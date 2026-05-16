import Foundation

struct OGMetadata: Sendable {
  var title: String?
  var domain: String?
  var ogImageURL: URL?
}

actor OGFetcher {
  static let shared = OGFetcher()

  // V2 format: [urlString: [title, domain, ogImageURL]] — persists ogImageURL so thumbnails
  // survive app restarts without a network re-fetch. Old "CopyCatOGCache" entries are not
  // migrated; they will re-fetch once and populate the new format automatically.
  private let defaultsKey = "CopyCatOGMetaV2"
  private var cache: [String: OGMetadata] = [:]

  init() {
    if let saved = UserDefaults.standard.dictionary(forKey: "CopyCatOGMetaV2") as? [String: [String: String]] {
      for (urlString, info) in saved {
        let title = info["title"]
        let domain = info["domain"] ?? URL(string: urlString)?.host
        let ogImageURL = info["ogImageURL"].flatMap { URL(string: $0) }
        cache[urlString] = OGMetadata(title: title, domain: domain, ogImageURL: ogImageURL)
      }
    }
  }

  func fetch(urlString: String) async -> OGMetadata {
    // Return cached result immediately
    if let cached = cache[urlString] {
      return cached
    }

    // Extract domain as a baseline for partial metadata
    let domain = URL(string: urlString)?.host

    guard let url = URL(string: urlString) else {
      let meta = OGMetadata(title: nil, domain: domain, ogImageURL: nil)
      cache[urlString] = meta
      return meta
    }

    // Block non-HTTPS fetches to prevent leaking clipboard content over plain HTTP
    guard url.scheme == "https" else {
      let meta = OGMetadata(title: nil, domain: domain, ogImageURL: nil)
      cache[urlString] = meta
      return meta
    }

    // Browser-like headers — needed for sites with bot detection (LinkedIn, Spotify, etc.)
    var request = URLRequest(url: url, timeoutInterval: 5)
    request.setValue(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
    request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
    request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")

    let html: String
    do {
      // 1.5s debounce: cards that disappear (scroll/close) cancel this task before the fetch fires
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      let (data, _) = try await URLSession.shared.data(for: request)
      html = String(data: data, encoding: .utf8) ?? ""
    } catch {
      let meta = OGMetadata(title: nil, domain: domain, ogImageURL: nil)
      cache[urlString] = meta
      return meta
    }

    // og:title, falling back to twitter:title, then <title> tag
    let title = parseOGProperty("og:title", from: html)
      ?? parseMetaName("twitter:title", from: html)
      ?? parseTitleTag(from: html)

    // og:image, falling back to twitter:image
    let ogImageString = parseOGProperty("og:image", from: html)
      ?? parseMetaName("twitter:image", from: html)
    let ogImageURL = ogImageString.flatMap { URL(string: $0) }

    let meta = OGMetadata(title: title, domain: domain, ogImageURL: ogImageURL)
    cache[urlString] = meta
    var dict = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String: String]]) ?? [:]
    var info: [String: String] = [:]
    if let t = meta.title { info["title"] = t }
    if let d = meta.domain { info["domain"] = d }
    if let u = meta.ogImageURL?.absoluteString { info["ogImageURL"] = u }
    if !info.isEmpty { dict[urlString] = info }
    UserDefaults.standard.set(dict, forKey: defaultsKey)
    return meta
  }

  // Tries both attribute orderings for og: properties
  private func parseOGProperty(_ property: String, from html: String) -> String? {
    let patterns = [
      "property=\"\(property)\"[^>]*content=\"([^\"]+)\"",
      "content=\"([^\"]+)\"[^>]*property=\"\(property)\""
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
      let range = NSRange(html.startIndex..., in: html)
      if let match = regex.firstMatch(in: html, options: [], range: range),
         let captureRange = Range(match.range(at: 1), in: html) {
        return String(html[captureRange])
      }
    }
    return nil
  }

  // Parses <meta name="twitter:X" content="VALUE"> tags
  private func parseMetaName(_ name: String, from html: String) -> String? {
    let patterns = [
      "name=\"\(name)\"[^>]*content=\"([^\"]+)\"",
      "content=\"([^\"]+)\"[^>]*name=\"\(name)\""
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
      let range = NSRange(html.startIndex..., in: html)
      if let match = regex.firstMatch(in: html, options: [], range: range),
         let captureRange = Range(match.range(at: 1), in: html) {
        return String(html[captureRange])
      }
    }
    return nil
  }

  // Falls back to the plain HTML <title> tag when no OG/Twitter title exists
  private func parseTitleTag(from html: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>([^<]+)</title>", options: .caseInsensitive) else { return nil }
    let range = NSRange(html.startIndex..., in: html)
    if let match = regex.firstMatch(in: html, options: [], range: range),
       let captureRange = Range(match.range(at: 1), in: html) {
      let raw = String(html[captureRange])
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&quot;", with: "\"")
      return raw.isEmpty ? nil : raw
    }
    return nil
  }
}
