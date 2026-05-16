import SwiftUI
import AppKit

struct PinboardEntryCard: View {
  let entry: PinboardEntry
  let pinboard: PinboardModel
  @State private var isHovered = false
  @State private var ogMeta: OGMetadata? = nil
  @State private var ogImage: NSImage? = nil
  @State private var fetchTask: Task<Void, Never>? = nil
  @State private var showRenameTitle = false
  @State private var newTitle = ""

  // MARK: - Derived card properties

  private var cardType: ClipCardType {
    if entry.imageData != nil { return .image }
    if !(entry.fileURLStrings ?? []).isEmpty { return .file }
    if let t = entry.text, t.hasPrefix("http://") || t.hasPrefix("https://") { return .link }
    return .text
  }

  private var hasThumbnail: Bool {
    if entry.imageData != nil { return true }
    if ogImage != nil { return true }
    return false
  }

  // Only show footer beneath thumbnail when there is content to display
  private var showFooter: Bool {
    guard hasThumbnail else { return false }
    if cardType == .image { return false }  // images fill the full content area
    if cardType == .link { return true }
    return true
  }

  private var appName: String {
    HistoryItemDecorator.AppNameParser.parse(text: entry.text) ?? entry.applicationName ?? "Unknown"
  }

  private var design: HistoryItemDecorator.AppDesign {
    HistoryItemDecorator.AppDesign.design(for: appName)
  }

  // Real macOS app icon resolved from the stored bundle identifier
  private var appIconImage: NSImage? {
    guard design.useSystemIcon,
          let bundleID = entry.bundleIdentifier,
          let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: appURL.path)
  }

  // Brand color for known apps; content-type color for unknown apps
  private var headerBackground: Color {
    design.useSystemIcon ? cardType.unknownAppColor : design.color
  }

  private var headerForeground: Color {
    design.useSystemIcon ? cardType.headerTextOnUnknown : .white
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      header
      content
      if showFooter { footer }
    }
    .frame(width: 160, height: 180)
    .background(Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.85))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          isHovered
            ? Color(red: 0.94, green: 0.34, blue: 0.15)
            : Color(red: 0.21, green: 0.21, blue: 0.20),
          lineWidth: isHovered ? 1.5 : 1
        )
    )
    .overlay(alignment: .topTrailing) { pinOverlay }
    .contextMenu { contextMenuItems }
    .onTapGesture { handleTap() }
    .scaleEffect(isHovered ? 1.04 : 1.0)
    .shadow(color: .black.opacity(isHovered ? 0.22 : 0.08), radius: isHovered ? 12 : 4)
    .animation(.spring(duration: 0.15), value: isHovered)
    .onHover { isHovered = $0 }
    .onAppear { startOGFetchIfNeeded() }
    .onDisappear {
      fetchTask?.cancel()
      fetchTask = nil
    }
    .alert("Rename Title", isPresented: $showRenameTitle) {
      TextField("Title", text: $newTitle)
      Button("Save") {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        PinboardStore.shared.setCustomTitle(t.isEmpty ? nil : t, for: entry, in: pinboard)
      }
      Button("Reset to Default") {
        PinboardStore.shared.setCustomTitle(nil, for: entry, in: pinboard)
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 8) {
      if design.useSystemIcon {
        if let icon = appIconImage {
          Image(nsImage: icon)
            .resizable()
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
          Image(systemName: "app.fill")
            .font(.system(size: 18))
            .foregroundStyle(headerForeground)
            .frame(width: 20, height: 20)
        }
      } else {
        Image(systemName: design.iconName)
          .font(.system(size: 18))
          .foregroundStyle(headerForeground)
          .frame(width: 20, height: 20)
      }

      VStack(alignment: .leading, spacing: 0) {
        Text(entry.customTitle ?? cardType.label)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(headerForeground)
          .lineLimit(1)
          .truncationMode(.tail)
          .help(entry.customTitle ?? cardType.label)
        Text(appName)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(headerForeground.opacity(0.9))
      }
      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(headerBackground)
  }

  // MARK: - Content area

  @ViewBuilder
  private var content: some View {
    Group {
      if let imageData = entry.imageData, let nsImage = NSImage(data: imageData) {
        Image(nsImage: nsImage)
          .resizable()
          .scaledToFill()
      } else if let ogImg = ogImage {
        Image(nsImage: ogImg)
          .resizable()
          .scaledToFill()
      } else {
        contentText
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: showFooter ? 96 : 140)
    .clipped()
  }

  @ViewBuilder
  private var contentText: some View {
    switch cardType {
    case .link:
      Text(String((entry.text ?? "").prefix(120)))
        .font(.system(size: 11))
        .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
    case .file:
      Text(entry.fileURLs.first?.lastPathComponent ?? entry.fileURLStrings?.first ?? "File")
        .font(.system(size: 11))
        .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
    default:
      Text(String((entry.text ?? "No preview").prefix(120)))
        .font(.system(size: 11))
        .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
    }
  }

  // MARK: - Footer (only when thumbnail is present and there is displayable text)

  private var footer: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(footerText)
        .font(.system(size: 11))
        .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .frame(height: 44)
    .background(Color(red: 0.13, green: 0.12, blue: 0.12))
  }

  private var footerText: String {
    if cardType == .link {
      return ogMeta?.title ?? ogMeta?.domain ?? URL(string: entry.text ?? "")?.host ?? "Link"
    }
    return entry.text ?? entry.fileURLs.first?.lastPathComponent ?? ""
  }

  // MARK: - Pin overlay (appears on hover)

  @ViewBuilder
  private var pinOverlay: some View {
    if isHovered {
      Button {
        isHovered = false
        Task { @MainActor in PinboardStore.shared.togglePin(entry, in: pinboard) }
      } label: {
        Image(systemName: entry.isPinned ? "pin.fill" : "pin")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 26, height: 26)
          .background(entry.isPinned ? Color(red: 0.94, green: 0.34, blue: 0.15).opacity(0.9) : Color.black.opacity(0.4))
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .padding(6)
      .transition(.scale(scale: 0.7).combined(with: .opacity))
    }
  }

  // MARK: - Context menu

  @ViewBuilder
  private var contextMenuItems: some View {
    Button("Rename Title") {
      newTitle = entry.customTitle ?? cardType.label
      showRenameTitle = true
    }
    Button(entry.isPinned ? "Unpin" : "Pin") {
      Task { @MainActor in PinboardStore.shared.togglePin(entry, in: pinboard) }
    }

    // Move to another pinboard
    let otherBoards = PinboardStore.shared.pinboards.filter { $0.id != pinboard.id }
    if !otherBoards.isEmpty {
      Menu("Move to Pinboard") {
        ForEach(otherBoards) { dest in
          Button {
            Task { @MainActor in PinboardStore.shared.moveEntry(entry, from: pinboard, to: dest) }
          } label: {
            Label {
              Text(dest.name)
            } icon: {
              Image(systemName: "circle.fill")
                .foregroundStyle(dest.uiColor)
            }
          }
        }
      }
    }

    Button("Move back to Clipboard") {
      Task { @MainActor in PinboardStore.shared.moveBack(entry, from: pinboard) }
    }

    Divider()

    Button("Delete", role: .destructive) {
      Task { @MainActor in PinboardStore.shared.delete(entry, from: pinboard) }
    }
  }

  // MARK: - Tap to paste

  private func handleTap() {
    Task { @MainActor in
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
      } else {
        return
      }

      // Record to clipboard history before pasting
      Clipboard.shared.checkForChangesInPasteboard()

      AppState.shared.popup.close()
      try? await Task.sleep(nanoseconds: 150_000_000)
      Clipboard.shared.paste()
    }
  }

  // MARK: - OG metadata fetch (links only)

  private func startOGFetchIfNeeded() {
    guard cardType == .link, let urlString = entry.text else { return }
    fetchTask = Task {
      let meta = await OGFetcher.shared.fetch(urlString: urlString)
      await MainActor.run { ogMeta = meta }
      guard let imageURL = meta.ogImageURL else { return }
      if let cached = await OGImageCache.shared.image(for: imageURL) {
        await MainActor.run { ogImage = cached }
        return
      }
      do {
        let (data, _) = try await URLSession.shared.data(from: imageURL)
        if let img = NSImage(data: data) {
          await OGImageCache.shared.store(img, for: imageURL)
          await MainActor.run { ogImage = img }
        }
      } catch {}
    }
  }
}
