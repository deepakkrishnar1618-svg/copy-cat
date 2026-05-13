import AppKit
import Foundation

actor OGImageCache {
  static let shared = OGImageCache()

  private var memCache: [String: NSImage] = [:]
  private let memCacheLimit = 150
  private let cacheDir: URL?

  init() {
    if let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
      let dir = base.appendingPathComponent("CopyCatOGImages", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      cacheDir = dir
    } else {
      cacheDir = nil
    }
  }

  func image(for url: URL) -> NSImage? {
    let key = cacheKey(for: url)
    if let img = memCache[key] { return img }
    guard let dir = cacheDir else { return nil }
    let file = dir.appendingPathComponent(key + ".png")
    guard let data = try? Data(contentsOf: file),
          let img = NSImage(data: data) else { return nil }
    memCache[key] = img
    return img
  }

  func store(_ image: NSImage, for url: URL) {
    let key = cacheKey(for: url)
    if memCache.count >= memCacheLimit {
      memCache.removeValue(forKey: memCache.keys.first ?? "")
    }
    memCache[key] = image
    guard let dir = cacheDir,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    let file = dir.appendingPathComponent(key + ".png")
    try? png.write(to: file)
  }

  // FNV-1a hash of the URL string — deterministic, collision-resistant enough for a file key
  private func cacheKey(for url: URL) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in url.absoluteString.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 1099511628211
    }
    return String(format: "%016llx", hash)
  }
}
