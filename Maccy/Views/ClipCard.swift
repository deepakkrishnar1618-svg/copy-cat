import Defaults
import SwiftUI

enum ClipCardType {
  case image, text, link, file

  var label: String {
    switch self {
    case .image: return "IMAGE"
    case .text:  return "TEXT"
    case .link:  return "LINK"
    case .file:  return "FILE"
    }
  }

  // Legacy per-type color (kept for compatibility)
  var color: Color {
    switch self {
    case .image: return Color(red: 0.94, green: 0.27, blue: 0.27)
    case .text:  return Color(red: 0.96, green: 0.62, blue: 0.04)
    case .link:  return Color(red: 0.23, green: 0.51, blue: 0.96)
    case .file:  return Color(red: 0.42, green: 0.45, blue: 0.50)
    }
  }

  // Header background for unknown-app cards (not in AppDesign known-app list)
  var unknownAppColor: Color {
    switch self {
    case .text:  return Color(red: 0.09, green: 0.52, blue: 0.52)   // teal
    case .link:  return Color(red: 0.07, green: 0.50, blue: 0.38)   // emerald
    case .image: return Color(red: 0.96, green: 0.92, blue: 0.83)   // cream
    case .file:  return Color(red: 0.40, green: 0.43, blue: 0.48)   // steel grey
    }
  }

  // Text / icon foreground color that reads well on unknownAppColor
  var headerTextOnUnknown: Color {
    // Cream is light — needs dark text; all others are dark and take white
    self == .image ? Color(red: 0.13, green: 0.13, blue: 0.13) : .white
  }
}

struct ClipCard: View {
  let decorator: HistoryItemDecorator
  @State private var ogMeta: OGMetadata? = nil
  @State private var ogImage: NSImage? = nil
  @State private var fetchTask: Task<Void, Never>? = nil
  @State private var isHovered = false

  private var cardType: ClipCardType {
    if decorator.hasImage { return .image }
    if let t = decorator.item.text,
       (t.hasPrefix("http://") || t.hasPrefix("https://")) { return .link }
    if !decorator.item.fileURLs.isEmpty { return .file }
    return .text
  }

  private var hasThumbnail: Bool {
    if decorator.hasImage && decorator.thumbnailImage != nil { return true }
    if ogImage != nil { return true }
    return false
  }

  // Only show footer when there's content to display beneath the thumbnail
  private var showFooter: Bool {
    guard hasThumbnail else { return false }
    if cardType == .image { return false }  // images fill the full content area
    if cardType == .link { return true }
    return true
  }

  // Resolved header colors: brand color for known apps, content-type color for unknown
  private var headerBackground: Color {
    let appName = decorator.application ?? "Unknown"
    let design = HistoryItemDecorator.AppDesign.design(for: appName)
    return design.useSystemIcon ? cardType.unknownAppColor : design.color
  }
  private var headerForeground: Color {
    let appName = decorator.application ?? "Unknown"
    let design = HistoryItemDecorator.AppDesign.design(for: appName)
    return design.useSystemIcon ? cardType.headerTextOnUnknown : .white
  }

  var body: some View {
    let appName = decorator.application ?? "Unknown"
    let design = HistoryItemDecorator.AppDesign.design(for: appName)

    VStack(spacing: 0) {
      // ── HEADER ──
      HStack(spacing: 8) {
        if design.useSystemIcon {
          Image(nsImage: decorator.applicationImage.nsImage)
            .resizable()
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
          Image(systemName: design.iconName)
            .font(.system(size: 18))
            .foregroundStyle(headerForeground)
            .frame(width: 20, height: 20)
        }

        VStack(alignment: .leading, spacing: 0) {
          Text(cardType.label)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(headerForeground)
          Text(appName)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(headerForeground.opacity(0.9))
        }
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(headerBackground)

      // ── CONTENT ──
      Group {
        if cardType == .image, let thumb = decorator.thumbnailImage {
          Image(nsImage: thumb)
            .resizable()
            .scaledToFill()
        } else if let ogImg = ogImage {
          // OG thumbnail fetched from the link
          Image(nsImage: ogImg)
            .resizable()
            .scaledToFill()
        } else {
          // Text/fallback preview
          switch cardType {
          case .link:
            Text(ogMeta?.title ?? String(decorator.text.prefix(120)))
              .font(.system(size: 11))
              .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88))
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .padding(8)
          case .file:
            Text(decorator.item.fileURLs.first?.lastPathComponent ?? "File")
              .font(.system(size: 11))
              .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88))
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .padding(8)
          default:
            Text(decorator.text.prefix(120))
              .font(.system(size: 11))
              .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88))
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .padding(8)
          }
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: showFooter ? 96 : 140)
      .clipped()

      // ── FOOTER — only shown when there is a thumbnail with displayable text ──
      if showFooter {
        VStack(alignment: .leading, spacing: 2) {
          if cardType == .link {
            Text(ogMeta?.title ?? ogMeta?.domain ?? URL(string: decorator.item.text ?? "")?.host ?? "Link")
              .font(.system(size: 11))
              .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88))
              .lineLimit(2)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            Text(decorator.text)
              .font(.system(size: 11))
              .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88))
              .lineLimit(2)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(10)
        .frame(height: 44)
        .background(Color(red: 0.13, green: 0.12, blue: 0.12)) // surface-container
      }
    }
    .frame(width: 160, height: 180)
    .background(Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.85))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          isHovered
            ? Color(red: 0.94, green: 0.34, blue: 0.15) // branding orange on hover
            : Color(red: 0.21, green: 0.21, blue: 0.20),
          lineWidth: isHovered ? 1.5 : 1
        )
    )
    .overlay(alignment: .topTrailing) {
      if isHovered {
        Button {
          isHovered = false
          Task { @MainActor in AppState.shared.history.togglePin(decorator) }
        } label: {
          Image(systemName: decorator.isPinned ? "pin.fill" : "pin")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(decorator.isPinned ? Color(red: 0.94, green: 0.34, blue: 0.15).opacity(0.9) : Color.black.opacity(0.4))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .transition(.scale(scale: 0.7).combined(with: .opacity))
      }
    }
    .contextMenu {
      Button(decorator.isPinned ? "Unpin" : "Pin") {
        Task { @MainActor in AppState.shared.history.togglePin(decorator) }
      }
      let pinboards = PinboardStore.shared.pinboards
      if !pinboards.isEmpty {
        Menu("Move to Pinboard") {
          ForEach(pinboards) { pinboard in
            Button {
              Task { @MainActor in PinboardStore.shared.move(decorator, to: pinboard) }
            } label: {
              Label {
                Text(pinboard.name)
              } icon: {
                Image(systemName: "circle.fill")
                  .foregroundStyle(pinboard.uiColor)
              }
            }
          }
        }
      }
      Divider()
      Button("Delete", role: .destructive) {
        Task { @MainActor in AppState.shared.history.delete(decorator) }
      }
    }
    .scaleEffect(isHovered ? 1.04 : 1.0)
    .shadow(color: .black.opacity(isHovered ? 0.22 : 0.08),
            radius: isHovered ? 12 : 4)
    .animation(.spring(duration: 0.15), value: isHovered)
    .onHover { isHovered = $0 }
    .onAppear {
      Task { @MainActor in
        if decorator.hasImage {
          decorator.ensureThumbnailImage()
        }
      }
      if cardType == .link, let urlString = decorator.item.text {
        fetchTask = Task {
          let meta = await OGFetcher.shared.fetch(urlString: urlString)
          await MainActor.run { ogMeta = meta }
          guard let imageURL = meta.ogImageURL else { return }
          // Serve from disk/memory cache when available — no network hit
          if let cached = await OGImageCache.shared.image(for: imageURL) {
            await MainActor.run { ogImage = cached }
            return
          }
          // First time: download, then persist to cache
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
    .onDisappear {
      fetchTask?.cancel()
      fetchTask = nil
    }
  }
}
