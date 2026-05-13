import AppKit
import Defaults
import SwiftUI

// MARK: - Constants
private enum Layout {
  static let toolbarHeight: CGFloat = 40
  static let cardStripHeight: CGFloat = 180   // card 180 + padding for hover scale
  static let cardWidth: CGFloat = 160
  static let cardHeight: CGFloat = 180
}

// MARK: - TabChip
private struct TabChip: View {
  let label: String
  let color: Color
  let isSelected: Bool
  var isDropTarget: Bool = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Circle().fill(color).frame(width: 8, height: 8)
        Text(label)
          .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
          .foregroundStyle(isSelected
            ? Color(red: 0.90, green: 0.89, blue: 0.88) // on-surface
            : Color(red: 0.90, green: 0.89, blue: 0.88).opacity(0.6))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        isDropTarget ? color.opacity(0.25) :
        (isSelected ? color.opacity(0.15) : Color.clear)
      )
      .clipShape(Capsule())
      .overlay(
        Capsule().stroke(
          isDropTarget ? Color(red: 0.94, green: 0.34, blue: 0.15).opacity(0.8) :
          (isSelected ? color.opacity(0.3) : Color.clear),
          lineWidth: isDropTarget ? 1.5 : 1
        )
      )
    }
    .buttonStyle(.plain)
    .scaleEffect(isDropTarget ? 1.08 : 1.0)
    .animation(.spring(duration: 0.15), value: isDropTarget)
  }
}

// MARK: - PinboardSeparator
private struct PinboardSeparator: View {
  let label: String
  var body: some View {
    VStack(spacing: 4) {
      Spacer()
      Rectangle()
        .fill(Color(red: 0.35, green: 0.25, blue: 0.23).opacity(0.4)) // outline-variant
        .frame(width: 1, height: 140)
      Text(label)
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88).opacity(0.4))
    }
    .frame(width: 18, height: Layout.cardHeight)
  }
}

// Helper for global search result grouping
private struct PinboardSearchResult: Identifiable {
  let board: PinboardModel
  let entries: [PinboardEntry]
  var id: UUID { board.id }
}

// MARK: - CopyCatPanel
struct CopyCatPanel: View {
  let appState = AppState.shared
  let pinboardStore = PinboardStore.shared
  @State private var selectedPinboard: PinboardModel? = nil
  @State private var searchText = ""
  @State private var showNewPinboard = false
  @State private var dropTargetPinboard: PinboardModel? = nil
  @Default(.ignoredApps) private var ignoredApps

  private var visibleHistory: [HistoryItemDecorator] {
    guard !ignoredApps.isEmpty else { return appState.history.items }
    return appState.history.items.filter { dec in
      guard let bundleID = dec.item.application else { return true }
      return !ignoredApps.contains(bundleID)
    }
  }
  private var pinnedItems: [HistoryItemDecorator] {
    visibleHistory.filter { $0.isPinned }
  }
  private var recentItems: [HistoryItemDecorator] {
    visibleHistory.filter { !$0.isPinned }
  }
  private var filteredPinned: [HistoryItemDecorator] {
    searchText.isEmpty ? pinnedItems : pinnedItems.filter { matches($0) }
  }
  private var filteredRecent: [HistoryItemDecorator] {
    searchText.isEmpty ? recentItems : recentItems.filter { matches($0) }
  }
  private func matches(_ d: HistoryItemDecorator) -> Bool {
    (d.item.text ?? "").localizedCaseInsensitiveContains(searchText) ||
    (d.application ?? "").localizedCaseInsensitiveContains(searchText) ||
    (d.title).localizedCaseInsensitiveContains(searchText)
  }
  private func matchesPinboardEntry(_ entry: PinboardEntry) -> Bool {
    let parsedSite = HistoryItemDecorator.AppNameParser.parse(text: entry.text) ?? ""
    return (entry.text ?? "").localizedCaseInsensitiveContains(searchText) ||
           (entry.applicationName ?? "").localizedCaseInsensitiveContains(searchText) ||
           parsedSite.localizedCaseInsensitiveContains(searchText) ||
           (entry.fileURLStrings ?? []).joined(separator: " ").localizedCaseInsensitiveContains(searchText)
  }

  // MARK: body
  var body: some View {
    ZStack {
      // Layer 1: macOS frosted-glass blur
      if #available(macOS 26.0, *) { GlassEffectView() } else {
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
      }
      // Layer 2: dark tint overlay for Obsidian Ember depth
      Color(red: 0.075, green: 0.075, blue: 0.075).opacity(0.53)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        toolbar
          .frame(height: Layout.toolbarHeight)

        Divider().opacity(0.15)

        Spacer().frame(height: 18)

        cardStrip
          .frame(height: Layout.cardStripHeight)
      }
    }
    // Exact fixed frame — matches panel height set in FloatingPanel.open()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // New pinboard overlay (in-panel, keeps panel as key window)
    .overlay {
      if showNewPinboard {
        ZStack {
          Color.black.opacity(0.35)
            .ignoresSafeArea()
            .onTapGesture {
              withAnimation(.spring(duration: 0.2)) { showNewPinboard = false }
            }
          NewPinboardSheet(
            onCreate: { name, colorHex in
              pinboardStore.createPinboard(name: name, colorHex: colorHex)
              withAnimation(.spring(duration: 0.2)) { showNewPinboard = false }
            },
            onCancel: {
              withAnimation(.spring(duration: 0.2)) { showNewPinboard = false }
            }
          )
          .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .transition(.opacity)
      }
    }
    .animation(.spring(duration: 0.2), value: showNewPinboard)
    .task { try? await appState.history.load() }
  }

  // MARK: - Toolbar (search + tab chips + export)
  private var toolbar: some View {
    HStack(spacing: 0) {
      // App logo — left-pinned branding mark
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.leading, 12)

      Spacer(minLength: 8)

      HStack(spacing: 12) {
        // Search field — fixed width pill
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 11))
            .foregroundStyle(Color(red: 0.94, green: 0.34, blue: 0.15)) // branding orange
          TextField("Search...", text: $searchText)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88))
            .tint(Color(red: 0.94, green: 0.34, blue: 0.15)) // orange caret
          if !searchText.isEmpty {
            Button { searchText = "" } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 140)
        .background(Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.8)) // surface-container-low
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.21, green: 0.21, blue: 0.20), lineWidth: 1))

        // Divider between search and tabs
        Rectangle()
          .fill(Color.secondary.opacity(0.15))
          .frame(width: 1, height: 18)
          .padding(.horizontal, 4)

        // Tab chips — scrollable but height-fixed
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            TabChip(label: "Clipboard", color: Color(red: 0.94, green: 0.34, blue: 0.15), isSelected: selectedPinboard == nil) { // branding orange #f05627
              withAnimation(.easeInOut(duration: 0.15)) { selectedPinboard = nil }
            }
            ForEach(pinboardStore.pinboards) { pinboard in
              TabChip(
                label: pinboard.name,
                color: pinboard.uiColor,
                isSelected: selectedPinboard?.id == pinboard.id,
                isDropTarget: dropTargetPinboard?.id == pinboard.id
              ) {
                withAnimation(.easeInOut(duration: 0.15)) { selectedPinboard = pinboard }
              }
              .contextMenu {
                Button("Delete Pinboard", role: .destructive) {
                  pinboardStore.deletePinboard(pinboard)
                  if selectedPinboard?.id == pinboard.id {
                    withAnimation { selectedPinboard = nil }
                  }
                }
              }
              .dropDestination(for: ClipItemTransfer.self) { items, _ in
                let ids = items.map { $0.itemID }
                Task { @MainActor in
                  for id in ids {
                    if let dec = AppState.shared.history.items.first(where: { $0.id == id }) {
                      PinboardStore.shared.move(dec, to: pinboard)
                    }
                  }
                }
                return true
              } isTargeted: { targeted in
                dropTargetPinboard = targeted ? pinboard : nil
              }
            }
            Button {
              withAnimation(.spring(duration: 0.2)) { showNewPinboard = true }
            } label: {
              Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color(red: 0.90, green: 0.89, blue: 0.88)) // tertiary neutral
            }
            .buttonStyle(.plain)
          }
          .padding(.vertical, 4)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
  }

  // MARK: - Card strip
  private var cardStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      // Use HStack (not Lazy) — avoids lazy sizing quirks that cause height
      // to be undefined during SwiftUI layout passes triggered by pin/unpin.
      HStack(alignment: .center, spacing: 12) {
        if !searchText.isEmpty {
          globalSearchContent
        } else if let pinboard = selectedPinboard {
          pinboardContent(for: pinboard)
        } else {
          clipboardContent
        }
      }
      .padding(.leading, 16)
      .padding(.trailing, 24)
      .padding(.vertical, 8)
      .frame(height: Layout.cardHeight + 16) // extra room for hover scale
    }
  }

  // MARK: - Global search (across clipboard + all pinboards)
  @ViewBuilder
  private var globalSearchContent: some View {
    let matchedPinned = filteredPinned
    let matchedRecent = filteredRecent
    let boardResults: [PinboardSearchResult] = pinboardStore.pinboards.compactMap { board in
      let matched = pinboardStore.entries(for: board).filter { matchesPinboardEntry($0) }
      return matched.isEmpty ? nil : PinboardSearchResult(board: board, entries: matched)
    }
    let hasClipboard = !matchedPinned.isEmpty || !matchedRecent.isEmpty

    if !hasClipboard && boardResults.isEmpty {
      VStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 30))
          .foregroundStyle(.tertiary)
        Text("No results for \"\(searchText)\"")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity)
    } else {
      ForEach(matchedPinned) { dec in
        ClipCard(decorator: dec)
          .draggable(ClipItemTransfer(itemID: dec.id))
          .onTapGesture { tapCard(dec) }
      }
      ForEach(matchedRecent) { dec in
        ClipCard(decorator: dec)
          .draggable(ClipItemTransfer(itemID: dec.id))
          .onTapGesture { tapCard(dec) }
      }
      ForEach(boardResults) { result in
        PinboardSeparator(label: String(result.board.name.prefix(4)).uppercased())
        ForEach(result.entries) { entry in
          PinboardEntryCard(entry: entry, pinboard: result.board)
        }
      }
    }
  }

  // MARK: - Clipboard tab content
  @ViewBuilder
  private var clipboardContent: some View {
    if filteredPinned.isEmpty && filteredRecent.isEmpty {
      VStack(spacing: 8) {
        Image(systemName: "clipboard")
          .font(.system(size: 30))
          .foregroundStyle(.tertiary)
        Text("No clipboard history")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity)
    } else {
      if !filteredPinned.isEmpty {
        ForEach(filteredPinned) { decorator in
          ClipCard(decorator: decorator)
            .draggable(ClipItemTransfer(itemID: decorator.id))
            .onTapGesture { tapCard(decorator) }
        }
        PinboardSeparator(label: "PIN")
      }
      ForEach(filteredRecent) { decorator in
        ClipCard(decorator: decorator)
          .draggable(ClipItemTransfer(itemID: decorator.id))
          .onTapGesture { tapCard(decorator) }
      }
    }
  }

  // MARK: - Pinboard tab content
  @ViewBuilder
  private func pinboardContent(for pinboard: PinboardModel) -> some View {
    let allEntries = pinboardStore.entries(for: pinboard)
    let filtered = searchText.isEmpty ? allEntries : allEntries.filter { entry in
      let parsedSite = HistoryItemDecorator.AppNameParser.parse(text: entry.text) ?? ""
      return (entry.text ?? "").localizedCaseInsensitiveContains(searchText) ||
             (entry.applicationName ?? "").localizedCaseInsensitiveContains(searchText) ||
             parsedSite.localizedCaseInsensitiveContains(searchText) ||
             (entry.fileURLStrings ?? []).joined(separator: " ").localizedCaseInsensitiveContains(searchText)
    }
    let pinnedEntries = filtered.filter { $0.isPinned }
    let unpinnedEntries = filtered.filter { !$0.isPinned }

    if filtered.isEmpty {
      VStack(spacing: 8) {
        Image(systemName: "tray")
          .font(.system(size: 30))
          .foregroundStyle(.tertiary)
        Text(searchText.isEmpty ? "No items in \"\(pinboard.name)\"" : "No results in \"\(pinboard.name)\"")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity)
    } else {
      if !pinnedEntries.isEmpty {
        ForEach(pinnedEntries) { entry in
          PinboardEntryCard(entry: entry, pinboard: pinboard)
        }
        PinboardSeparator(label: "PIN")
      }
      ForEach(unpinnedEntries) { entry in
        PinboardEntryCard(entry: entry, pinboard: pinboard)
      }
    }
  }

  // MARK: - Card tap action
  private func tapCard(_ decorator: HistoryItemDecorator) {
    Task { @MainActor in
      AppState.shared.popup.close()
      try? await Task.sleep(nanoseconds: 150_000_000)
      Clipboard.shared.copy(decorator.item, removeFormatting: Defaults[.removeFormattingByDefault])
      Clipboard.shared.paste()
    }
  }

}

