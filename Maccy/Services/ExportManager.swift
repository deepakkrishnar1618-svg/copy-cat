import AppKit
import Foundation

final class ExportManager {
  static let shared = ExportManager()

  // MARK: - CSV zip export

  @MainActor
  func exportCSVZip() async throws -> URL {
    let clipboardCSV = buildClipboardCSV()
    var pinboardCSVs: [(String, String)] = []
    for board in PinboardStore.shared.pinboards {
      let entries = PinboardStore.shared.entries(for: board)
      let csv = buildPinboardCSV(entries: entries)
      let safeName = board.name
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: "\\", with: "-")
      pinboardCSVs.append(("\(safeName).csv", csv))
    }

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("CopyCatExport_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    try clipboardCSV.write(to: tempDir.appendingPathComponent("Clipboard.csv"), atomically: true, encoding: .utf8)
    for (name, content) in pinboardCSVs {
      try content.write(to: tempDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("CopyCatExport.zip")
    try? FileManager.default.removeItem(at: zipURL)

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
      process.arguments = ["-r", zipURL.path, "."]
      process.currentDirectoryURL = tempDir
      process.terminationHandler = { p in
        p.terminationStatus == 0 ? cont.resume() : cont.resume(throwing: ExportError.zipFailed)
      }
      do { try process.run() } catch { cont.resume(throwing: error) }
    }

    return zipURL
  }

  // MARK: - PDF export (HTML → NSTextView → dataWithPDF)

  @MainActor
  func exportPDF() async throws -> URL {
    let html = buildHTML()
    guard let data = html.data(using: .utf8) else { throw ExportError.encodingFailed }

    var docAttribs: NSDictionary? = nil
    let attrStr = try NSAttributedString(
      data: data,
      options: [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
      ],
      documentAttributes: &docAttribs
    )

    // Render into an off-screen NSTextView then capture as PDF
    let pageWidth: CGFloat = 600
    let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 10))
    tv.isVerticallyResizable = true
    tv.maxSize = NSSize(width: pageWidth, height: 1_000_000)
    tv.textContainer?.containerSize = NSSize(width: pageWidth, height: CGFloat.greatestFiniteMagnitude)
    tv.textContainer?.widthTracksTextView = true
    tv.textStorage?.setAttributedString(attrStr)
    tv.sizeToFit()

    let pdfData = tv.dataWithPDF(inside: tv.bounds)
    let pdfURL = FileManager.default.temporaryDirectory.appendingPathComponent("CopyCatExport.pdf")
    try pdfData.write(to: pdfURL)
    return pdfURL
  }

  // MARK: - CSV builders

  @MainActor
  private func buildClipboardCSV() -> String {
    let fmt = ISO8601DateFormatter()
    var rows = ["text,type,application,copied_at,is_pinned"]
    for dec in AppState.shared.history.items {
      let text = csvEscape(dec.item.text ?? "")
      let type = itemType(hasImage: dec.hasImage, text: dec.item.text, fileURLs: dec.item.fileURLs)
      let app = csvEscape(dec.application ?? "")
      let date = fmt.string(from: dec.item.firstCopiedAt)
      rows.append("\(text),\(type),\(app),\(date),\(dec.isPinned)")
    }
    return rows.joined(separator: "\n")
  }

  private func buildPinboardCSV(entries: [PinboardEntry]) -> String {
    let fmt = ISO8601DateFormatter()
    var rows = ["text,type,application,copied_at,is_pinned"]
    for entry in entries {
      let text = csvEscape(entry.text ?? "")
      let type = entryType(entry)
      let app = csvEscape(entry.applicationName ?? "")
      let date = fmt.string(from: entry.copiedAt)
      rows.append("\(text),\(type),\(app),\(date),\(entry.isPinned)")
    }
    return rows.joined(separator: "\n")
  }

  // MARK: - HTML builder for PDF

  @MainActor
  private func buildHTML() -> String {
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    fmt.timeStyle = .short

    let clipItems = AppState.shared.history.items
    let boards = PinboardStore.shared.pinboards
    let totalPinboard = boards.reduce(0) { $0 + PinboardStore.shared.entries(for: $1).count }

    var html = """
    <html><head><meta charset="utf-8">
    <style>
    body{font-family:-apple-system,Helvetica Neue,sans-serif;margin:48px;color:#222;background:#fff;}
    h1{font-size:22px;color:#111;margin:0 0 4px;}
    .sub{color:#888;font-size:12px;margin-bottom:36px;}
    h2{font-size:13px;font-weight:700;color:#333;border-bottom:1px solid #eee;padding-bottom:6px;margin:28px 0 10px;text-transform:uppercase;letter-spacing:.5px;}
    .item{padding:6px 0 8px;border-bottom:1px solid #f5f5f5;}
    .preview{font-size:12px;color:#333;word-break:break-word;}
    .meta{font-size:10px;color:#aaa;margin-top:3px;}
    .badge{display:inline-block;padding:1px 5px;border-radius:3px;font-size:10px;font-weight:700;margin-right:5px;}
    .TEXT{background:#e6f7e6;color:#256425;}
    .LINK{background:#e6eeff;color:#1a3a8a;}
    .IMAGE{background:#fff0e6;color:#a03010;}
    .FILE{background:#f0f0f0;color:#444;}
    .pin{color:#f05627;font-size:10px;margin-left:4px;}
    .empty{color:#bbb;font-size:12px;font-style:italic;}
    </style></head><body>
    <h1>Copy Cat Export</h1>
    <div class="sub">Generated \(fmt.string(from: Date())) &nbsp;&middot;&nbsp; \(clipItems.count) clipboard items &nbsp;&middot;&nbsp; \(boards.count) pinboards &nbsp;&middot;&nbsp; \(totalPinboard) pinboard items</div>
    """

    html += "<h2>Clipboard (\(clipItems.count))</h2>"
    if clipItems.isEmpty {
      html += "<p class='empty'>No items</p>"
    } else {
      for dec in clipItems {
        let type = itemType(hasImage: dec.hasImage, text: dec.item.text, fileURLs: dec.item.fileURLs)
        let preview = htmlEscape(String((dec.item.text ?? (dec.hasImage ? "[Image]" : "[File]")).prefix(300)))
        let app = htmlEscape(dec.application ?? "")
        let date = fmt.string(from: dec.item.lastCopiedAt)
        let pin = dec.isPinned ? "<span class='pin'>pinned</span>" : ""
        html += "<div class='item'><span class='badge \(type)'>\(type)</span><span class='preview'>\(preview)\(pin)</span><div class='meta'>\(app) · \(date)</div></div>"
      }
    }

    for board in boards {
      let entries = PinboardStore.shared.entries(for: board)
      html += "<h2>\(htmlEscape(board.name)) (\(entries.count))</h2>"
      if entries.isEmpty {
        html += "<p class='empty'>No items</p>"
      } else {
        for entry in entries {
          let type = entryType(entry)
          let preview = htmlEscape(String((entry.text ?? (entry.imageData != nil ? "[Image]" : "[File]")).prefix(300)))
          let app = htmlEscape(entry.applicationName ?? "")
          let date = fmt.string(from: entry.copiedAt)
          let pin = entry.isPinned ? "<span class='pin'>pinned</span>" : ""
          html += "<div class='item'><span class='badge \(type)'>\(type)</span><span class='preview'>\(preview)\(pin)</span><div class='meta'>\(app) · \(date)</div></div>"
        }
      }
    }

    html += "</body></html>"
    return html
  }

  // MARK: - Helpers

  private func itemType(hasImage: Bool, text: String?, fileURLs: [URL]) -> String {
    if hasImage { return "IMAGE" }
    if !fileURLs.isEmpty { return "FILE" }
    if let t = text, t.hasPrefix("https://") || t.hasPrefix("http://") { return "LINK" }
    return "TEXT"
  }

  private func entryType(_ entry: PinboardEntry) -> String {
    if entry.imageData != nil { return "IMAGE" }
    if !(entry.fileURLStrings ?? []).isEmpty { return "FILE" }
    if let t = entry.text, t.hasPrefix("https://") || t.hasPrefix("http://") { return "LINK" }
    return "TEXT"
  }

  private func csvEscape(_ str: String) -> String {
    let clean = str
      .replacingOccurrences(of: "\"", with: "\"\"")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
    return "\"\(clean)\""
  }

  private func htmlEscape(_ str: String) -> String {
    str
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  enum ExportError: Error {
    case encodingFailed
    case zipFailed
  }
}
