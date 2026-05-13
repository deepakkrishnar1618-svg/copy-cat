import Foundation
import SwiftUI
import Observation

struct PinboardModel: Codable, Identifiable, Hashable {
  let id: UUID
  var name: String
  var colorHex: String

  init(name: String, colorHex: String) {
    self.id = UUID()
    self.name = name
    self.colorHex = colorHex
  }

  var uiColor: Color { Color(hex: colorHex) ?? .blue }
}

struct PinboardEntry: Codable, Identifiable {
  let id: UUID
  let pinboardId: UUID
  var text: String?
  var applicationName: String?
  var bundleIdentifier: String?
  var imageData: Data?
  var fileURLStrings: [String]?
  var copiedAt: Date
  var isPinned: Bool

  var fileURLs: [URL] {
    (fileURLStrings ?? []).compactMap { URL(string: $0) }
  }

  init(pinboardId: UUID, text: String?, applicationName: String?, bundleIdentifier: String? = nil, imageData: Data? = nil, fileURLStrings: [String]? = nil) {
    self.id = UUID()
    self.pinboardId = pinboardId
    self.text = text
    self.applicationName = applicationName
    self.bundleIdentifier = bundleIdentifier
    self.imageData = imageData
    self.fileURLStrings = fileURLStrings
    self.copiedAt = Date()
    self.isPinned = false
  }

  // Backward-compatible decode: new fields default gracefully for old entries
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    pinboardId = try c.decode(UUID.self, forKey: .pinboardId)
    text = try c.decodeIfPresent(String.self, forKey: .text)
    applicationName = try c.decodeIfPresent(String.self, forKey: .applicationName)
    bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
    imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
    fileURLStrings = try c.decodeIfPresent([String].self, forKey: .fileURLStrings)
    copiedAt = try c.decode(Date.self, forKey: .copiedAt)
    isPinned = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
  }
}

@Observable
final class PinboardStore {
  static let shared = PinboardStore()

  var pinboards: [PinboardModel] = []
  private var entriesByPinboard: [UUID: [PinboardEntry]] = [:]

  private let pinboardsKey = "CopyCatPinboards"
  private let entriesKey   = "CopyCatPinboardEntries"
  private var saveWorkItem: DispatchWorkItem?

  init() { load() }

  func entries(for pinboard: PinboardModel) -> [PinboardEntry] {
    let all = entriesByPinboard[pinboard.id] ?? []
    let pinned = all.filter { $0.isPinned }
    let unpinned = all.filter { !$0.isPinned }
    return pinned + unpinned
  }

  func createPinboard(name: String, colorHex: String) {
    let p = PinboardModel(name: name, colorHex: colorHex)
    pinboards.append(p)
    entriesByPinboard[p.id] = []
    save()
  }

  @MainActor func move(_ decorator: HistoryItemDecorator, to pinboard: PinboardModel) {
    let entry = PinboardEntry(
      pinboardId: pinboard.id,
      text: decorator.item.text,
      applicationName: decorator.application,
      bundleIdentifier: decorator.item.application,
      imageData: decorator.item.imageData,
      fileURLStrings: decorator.item.fileURLs.isEmpty ? nil : decorator.item.fileURLs.map { $0.absoluteString }
    )
    entriesByPinboard[pinboard.id, default: []].append(entry)
    AppState.shared.history.delete(decorator)
    save()
  }

  /// Move a pinboard entry back to the main clipboard history.
  /// Writes to NSPasteboard so the clipboard monitor picks it up and records it.
  @MainActor func moveBack(_ entry: PinboardEntry, from pinboard: PinboardModel) {
    let pb = NSPasteboard.general
    pb.clearContents()
    if let imageData = entry.imageData {
      pb.setData(imageData, forType: .tiff)
    } else if let fileURLStrings = entry.fileURLStrings, !fileURLStrings.isEmpty {
      let items: [NSPasteboardItem] = fileURLStrings.compactMap { str -> NSPasteboardItem? in
        guard let url = URL(string: str),
              let data = url.dataRepresentation as Data? else { return nil }
        let item = NSPasteboardItem()
        item.setData(data, forType: .fileURL)
        return item
      }
      pb.writeObjects(items)
    } else if let text = entry.text {
      pb.setString(text, forType: .string)
    }
    delete(entry, from: pinboard)
    Clipboard.shared.checkForChangesInPasteboard()
  }

  /// Move a pinboard entry from one pinboard to another.
  @MainActor func moveEntry(_ entry: PinboardEntry, from source: PinboardModel, to destination: PinboardModel) {
    let transferred = PinboardEntry(
      pinboardId: destination.id,
      text: entry.text,
      applicationName: entry.applicationName,
      imageData: entry.imageData,
      fileURLStrings: entry.fileURLStrings
    )
    entriesByPinboard[destination.id, default: []].append(transferred)
    delete(entry, from: source)
    save()
  }

  func togglePin(_ entry: PinboardEntry, in pinboard: PinboardModel) {
    guard let idx = entriesByPinboard[pinboard.id]?.firstIndex(where: { $0.id == entry.id }) else { return }
    entriesByPinboard[pinboard.id]?[idx].isPinned.toggle()
    save()
  }

  func delete(_ entry: PinboardEntry, from pinboard: PinboardModel) {
    entriesByPinboard[pinboard.id]?.removeAll { $0.id == entry.id }
    save()
  }

  func deletePinboard(_ pinboard: PinboardModel) {
    entriesByPinboard.removeValue(forKey: pinboard.id)
    pinboards.removeAll { $0.id == pinboard.id }
    save()
  }

  private func load() {
    if let data = UserDefaults.standard.data(forKey: pinboardsKey),
       let decoded = try? JSONDecoder().decode([PinboardModel].self, from: data) {
      pinboards = decoded
    }
    if let data = UserDefaults.standard.data(forKey: entriesKey),
       let decoded = try? JSONDecoder().decode([UUID: [PinboardEntry]].self, from: data) {
      entriesByPinboard = decoded
    }
  }

  private func save() {
    saveWorkItem?.cancel()
    let pinboards = self.pinboards
    let entries = self.entriesByPinboard
    let pKey = pinboardsKey
    let eKey = entriesKey
    let work = DispatchWorkItem {
      if let d = try? JSONEncoder().encode(pinboards) {
        UserDefaults.standard.set(d, forKey: pKey)
      }
      if let d = try? JSONEncoder().encode(entries) {
        UserDefaults.standard.set(d, forKey: eKey)
      }
    }
    saveWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
  }
}
