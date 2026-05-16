import AppKit
import SwiftUI
import Defaults
import Foundation
import Observation
import Sauce

@Observable
class HistoryItemDecorator: Identifiable, Hashable, HasVisibility {
  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  static var previewImageSize: NSSize { NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536) }
  static var thumbnailImageSize: NSSize { NSSize(width: 340, height: Defaults[.imageMaxHeight]) }

  let id = UUID()

  var title: String = ""
  var attributedTitle: AttributedString?

  var isVisible: Bool = true
  var selectionIndex: Int = -1
  var isSelected: Bool {
    return selectionIndex != -1
  }
  var shortcuts: [KeyShortcut] = []

  struct AppDesign {
    let color: SwiftUI.Color
    let iconName: String
    let useSystemIcon: Bool // true = render the real macOS app icon instead of SF Symbol
    
    static func design(for appName: String?) -> AppDesign {
      switch (appName ?? "").lowercased() {
      case "youtube": return AppDesign(color: SwiftUI.Color(red: 1.0, green: 0.0, blue: 0.0), iconName: "play.rectangle.fill", useSystemIcon: false)
      case "google maps": return AppDesign(color: SwiftUI.Color(red: 0.2, green: 0.65, blue: 0.33), iconName: "map.fill", useSystemIcon: false)
      case "gmail": return AppDesign(color: SwiftUI.Color(red: 0.91, green: 0.26, blue: 0.21), iconName: "envelope.fill", useSystemIcon: false)
      case "google drive": return AppDesign(color: SwiftUI.Color(red: 0.2, green: 0.65, blue: 0.33), iconName: "externaldrive.fill", useSystemIcon: false)
      case "google docs": return AppDesign(color: SwiftUI.Color(red: 0.26, green: 0.52, blue: 0.96), iconName: "doc.text.fill", useSystemIcon: false)
      case "github": return AppDesign(color: SwiftUI.Color(red: 0.14, green: 0.16, blue: 0.18), iconName: "curlybraces.square.fill", useSystemIcon: false)
      case "x (twitter)", "x": return AppDesign(color: SwiftUI.Color(white: 0.1), iconName: "xmark", useSystemIcon: false)
      case "linkedin": return AppDesign(color: SwiftUI.Color(red: 0.0, green: 0.46, blue: 0.71), iconName: "person.crop.circle.fill", useSystemIcon: false)
      case "notion": return AppDesign(color: SwiftUI.Color(white: 0.2), iconName: "note.text", useSystemIcon: false)
      case "figma": return AppDesign(color: SwiftUI.Color(red: 0.95, green: 0.3, blue: 0.1), iconName: "f.circle.fill", useSystemIcon: false)
      case "slack": return AppDesign(color: SwiftUI.Color(red: 0.29, green: 0.1, blue: 0.29), iconName: "number", useSystemIcon: false)
      case "linear": return AppDesign(color: SwiftUI.Color(red: 0.36, green: 0.38, blue: 0.96), iconName: "arrow.up.right.circle.fill", useSystemIcon: false)
      case "chatgpt": return AppDesign(color: SwiftUI.Color(red: 0.06, green: 0.65, blue: 0.5), iconName: "waveform.circle.fill", useSystemIcon: false)
      case "claude": return AppDesign(color: SwiftUI.Color(red: 0.84, green: 0.61, blue: 0.48), iconName: "sparkles", useSystemIcon: false)
      case "reddit": return AppDesign(color: SwiftUI.Color(red: 1.0, green: 0.27, blue: 0.0), iconName: "bubble.left.and.bubble.right.fill", useSystemIcon: false)
      case "netflix": return AppDesign(color: SwiftUI.Color(red: 0.89, green: 0.04, blue: 0.08), iconName: "play.tv.fill", useSystemIcon: false)
      case "amazon": return AppDesign(color: SwiftUI.Color(red: 1.0, green: 0.6, blue: 0.0), iconName: "cart.fill", useSystemIcon: false)
      case "spotify": return AppDesign(color: SwiftUI.Color(red: 0.12, green: 0.84, blue: 0.38), iconName: "music.note", useSystemIcon: false)
      case "instagram": return AppDesign(color: SwiftUI.Color(red: 0.89, green: 0.26, blue: 0.4), iconName: "camera.fill", useSystemIcon: false)
      case "facebook": return AppDesign(color: SwiftUI.Color(red: 0.09, green: 0.46, blue: 0.95), iconName: "f.square.fill", useSystemIcon: false)
      case "tiktok": return AppDesign(color: SwiftUI.Color.black, iconName: "music.note", useSystemIcon: false)
      default: return AppDesign(color: SwiftUI.Color(red: 0.22, green: 0.22, blue: 0.22), iconName: "app.fill", useSystemIcon: true)
      }
    }
  }

  struct AppNameParser {
    static func parse(text: String?) -> String? {
      guard let rawText = text else { return nil }
      let textToParse = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
      
      guard textToParse.hasPrefix("http://") || textToParse.hasPrefix("https://"),
            let url = URL(string: textToParse),
            let host = url.host?.lowercased() else {
        return nil
      }
      
      let knownDomains: [String: String] = [
        "youtube.com": "YouTube",
        "youtu.be": "YouTube",
        "maps.google.com": "Google Maps",
        "goo.gl": "Google Maps", // mostly used for maps nowadays
        "mail.google.com": "Gmail",
        "drive.google.com": "Google Drive",
        "docs.google.com": "Google Docs",
        "github.com": "GitHub",
        "twitter.com": "X (Twitter)",
        "x.com": "X (Twitter)",
        "t.co": "X (Twitter)",
        "linkedin.com": "LinkedIn",
        "notion.so": "Notion",
        "notion.site": "Notion",
        "figma.com": "Figma",
        "slack.com": "Slack",
        "linear.app": "Linear",
        "chatgpt.com": "ChatGPT",
        "chat.openai.com": "ChatGPT",
        "claude.ai": "Claude",
        "reddit.com": "Reddit",
        "netflix.com": "Netflix",
        "amazon.com": "Amazon",
        "amzn.to": "Amazon",
        "open.spotify.com": "Spotify",
        "spotify.link": "Spotify",
        "instagram.com": "Instagram",
        "ig.me": "Instagram",
        "facebook.com": "Facebook",
        "fb.me": "Facebook",
        "tiktok.com": "TikTok"
      ]
      
      for (domain, appName) in knownDomains {
        if host == domain || host.hasSuffix("." + domain) {
          return appName
        }
      }
      
      var domainParts = host.replacingOccurrences(of: "www.", with: "").split(separator: ".")
      if domainParts.count >= 2 {
        domainParts.removeLast() // remove TLD
        if let last = domainParts.last, (last == "co" || last == "com" || last == "org" || last == "net" || last == "gov" || last == "edu"), domainParts.count >= 2 {
            domainParts.removeLast()
        }
        if let name = domainParts.last, name.count > 1 {
            return String(name).capitalized
        }
      }
      return nil
    }
  }

  @ObservationIgnored private var _applicationName: String? = nil
  @ObservationIgnored private var _applicationNameCached = false

  var application: String? {
    if _applicationNameCached { return _applicationName }
    _applicationName = resolveApplicationName()
    _applicationNameCached = true
    return _applicationName
  }

  private func resolveApplicationName() -> String? {
    if let parsedName = AppNameParser.parse(text: item.text) {
      return parsedName
    }
    if let sourceURL = item.sourceURL, let parsedName = AppNameParser.parse(text: sourceURL) {
      return parsedName
    }
    if item.universalClipboard {
      return "iCloud"
    }
    guard let bundle = item.application,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
    else {
      return nil
    }
    return url.deletingPathExtension().lastPathComponent
  }

  var hasImage: Bool { item.image != nil }

  var previewImageGenerationTask: Task<(), Error>?
  var thumbnailImageGenerationTask: Task<(), Error>?
  var previewImage: NSImage?
  var thumbnailImage: NSImage?
  var applicationImage: ApplicationImage

  // 10k characters seems to be more than enough on large displays
  var text: String { item.previewableText.shortened(to: 10_000) }

  var searchableText: String {
    if let customTitle = item.customTitle {
      return title + " " + customTitle
    }
    return title
  }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  var isSensitive: Bool {
    guard let text = item.text else { return false }
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.count > 8, !t.hasPrefix("http://"), !t.hasPrefix("https://") else { return false }
    return t.hasPrefix("Bearer ") || t.hasPrefix("bearer ") ||
           t.hasPrefix("sk-") || t.hasPrefix("ghp_") || t.hasPrefix("ghs_") || t.hasPrefix("gho_") ||
           t.hasPrefix("xoxb-") || t.hasPrefix("xoxp-") || t.hasPrefix("xoxa-") ||
           t.hasPrefix("AKIA") || t.hasPrefix("AIza") ||
           t.hasPrefix("-----BEGIN ") || t.hasPrefix("eyJ")
  }

  func hash(into hasher: inout Hasher) {
    // We need to hash title and attributedTitle, so SwiftUI knows it needs to update the view if they chage
    hasher.combine(id)
    hasher.combine(title)
    hasher.combine(attributedTitle)
  }

  private(set) var item: HistoryItem

  init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
    self.item = item
    self.shortcuts = shortcuts
    self.title = item.title
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)

    synchronizeItemPin()
    synchronizeItemTitle()
  }

  @MainActor
  func ensureThumbnailImage() {
    guard item.image != nil else {
      return
    }
    guard thumbnailImage == nil else {
      return
    }
    guard thumbnailImageGenerationTask == nil else {
      return
    }
    thumbnailImageGenerationTask = Task { [weak self] in
      self?.generateThumbnailImage()
    }
  }

  @MainActor
  func ensurePreviewImage() {
    guard item.image != nil else {
      return
    }
    guard previewImage == nil else {
      return
    }
    guard previewImageGenerationTask == nil else {
      return
    }
    previewImageGenerationTask = Task { [weak self] in
      self?.generatePreviewImage()
    }
  }

  @MainActor
  func asyncGetPreviewImage() async -> NSImage? {
    if let image = previewImage {
      return image
    }
    ensurePreviewImage()
    _ = await previewImageGenerationTask?.result
    return previewImage
  }

  @MainActor
  func cleanupImages() {
    thumbnailImageGenerationTask?.cancel()
    previewImageGenerationTask?.cancel()
    thumbnailImage?.recache()
    previewImage?.recache()
    thumbnailImage = nil
    previewImage = nil
  }

  @MainActor
  private func generateThumbnailImage() {
    guard let image = item.image else {
      return
    }
    thumbnailImage = image.resized(to: HistoryItemDecorator.thumbnailImageSize)
  }

  @MainActor
  private func generatePreviewImage() {
    guard let image = item.image else {
      return
    }
    previewImage = image.resized(to: HistoryItemDecorator.previewImageSize)
  }

  @MainActor
  func sizeImages() {
    generatePreviewImage()
    generateThumbnailImage()
  }

  func highlight(_ query: String, _ ranges: [Range<String.Index>]) {
    guard !query.isEmpty, !title.isEmpty else {
      attributedTitle = nil
      return
    }

    var attributedString = AttributedString(title.shortened(to: 500))
    for range in ranges {
      if let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString),
         let upperBound = AttributedString.Index(range.upperBound, within: attributedString) {
        switch Defaults[.highlightMatch] {
        case .bold:
          attributedString[lowerBound..<upperBound].font = .bold(.body)()
        case .italic:
          attributedString[lowerBound..<upperBound].font = .italic(.body)()
        case .underline:
          attributedString[lowerBound..<upperBound].underlineStyle = .single
        default:
          attributedString[lowerBound..<upperBound].backgroundColor = .findHighlightColor
          attributedString[lowerBound..<upperBound].foregroundColor = .black
        }
      }
    }

    attributedTitle = attributedString
  }

  @MainActor
  func togglePin() {
    if item.pin != nil {
      item.pin = nil
    } else {
      let pin = HistoryItem.randomAvailablePin
      item.pin = pin
    }
  }

  private func synchronizeItemPin() {
    _ = withObservationTracking {
      item.pin
    } onChange: {
      DispatchQueue.main.async {
        if let pin = self.item.pin {
          self.shortcuts = KeyShortcut.create(character: pin)
        }
        self.synchronizeItemPin()
      }
    }
  }

  private func synchronizeItemTitle() {
    _ = withObservationTracking {
      item.title
    } onChange: {
      DispatchQueue.main.async {
        self.title = self.item.title
        self.synchronizeItemTitle()
      }
    }
  }
}
