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
            ? Color(red: 0.90, green: 0.89, blue: 0.88)
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

// MARK: - CustomDragState
struct CustomDragState {
  var id: UUID
  var decorator: HistoryItemDecorator?
  var entry: PinboardEntry?
  var pinboard: PinboardModel?
  var location: CGPoint = .zero      // current cursor position (global)
  var startCursor: CGPoint = .zero   // cursor position at drag start (global)
  var grabOffset: CGSize = .zero     // card center - startCursor (constant after init)
}

// MARK: - CopyCatPanel
struct CopyCatPanel: View {
  let appState = AppState.shared
  let pinboardStore = PinboardStore.shared
  @State private var selectedPinboard: PinboardModel? = nil
  @State private var searchText = ""
  @State private var showNewPinboard = false
  @State private var dropTargetPinboard: PinboardModel? = nil
  @State private var isClipboardDropTarget = false
  @State private var showRenamePinboard = false
  @State private var dragState: CustomDragState?
  @State private var reorderDropIndex: Int? = nil
  @State private var shiftedCardIDs: Set<UUID> = []
  @State private var showPinnedEndGap: Bool = false
  @State private var ghostSnapX: CGFloat? = nil
  @State private var isPinToggleDrop = false
  @State private var tabChipFrames: [String: CGRect] = [:]
  @State private var cardFrames: [UUID: CGRect] = [:]
  @State private var separatorFrames: [String: CGRect] = [:]
  @State private var pinboardToRename: PinboardModel? = nil
  @State private var newPinboardName = ""
  @State private var showDeletePinboardConfirmation = false
  @State private var pinboardToDelete: PinboardModel? = nil
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
    (d.item.customTitle ?? "").localizedCaseInsensitiveContains(searchText) ||
    (d.item.text ?? "").localizedCaseInsensitiveContains(searchText) ||
    (d.application ?? "").localizedCaseInsensitiveContains(searchText) ||
    (d.title).localizedCaseInsensitiveContains(searchText)
  }
  private func matchesPinboardEntry(_ entry: PinboardEntry) -> Bool {
    let parsedSite = HistoryItemDecorator.AppNameParser.parse(text: entry.text) ?? ""
    return (entry.customTitle ?? "").localizedCaseInsensitiveContains(searchText) ||
           (entry.text ?? "").localizedCaseInsensitiveContains(searchText) ||
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
    // Drag overlay — position derived from cursor directly, no dictionary reads during drag
    .overlay {
      if let state = dragState {
        let ghostX = state.location.x + state.grabOffset.width
        let ghostY = state.location.y + state.grabOffset.height
        let tilt = Double(state.location.x - state.startCursor.x) / 25

        Group {
          if let dec = state.decorator {
            ClipCard(decorator: dec)
          } else if let entry = state.entry, let pb = state.pinboard {
            PinboardEntryCard(entry: entry, pinboard: pb)
          }
        }
        .frame(width: 160, height: 180)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(Color(red: 0.94, green: 0.34, blue: 0.15), lineWidth: 1.5)
        )
        .position(x: ghostX, y: ghostY)
        .allowsHitTesting(false)
        .shadow(color: .black.opacity(0.6), radius: 20, y: 15)
        .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(1.05)
      }
    }
    // Drop target label — floats above ghost card, animates in/out when target changes
    .overlay {
      if let state = dragState {
        let ghostX = state.location.x + state.grabOffset.width
        let ghostY = state.location.y + state.grabOffset.height
        let targetName: String? = dropTargetPinboard.map(\.name) ?? (isClipboardDropTarget ? "Clipboard" : nil)

        Group {
          if let name = targetName {
            Text(name == "Clipboard" ? "Move to Clipboard" : "Add to \(name)")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(Color(red: 0.94, green: 0.34, blue: 0.15))
              .clipShape(Capsule())
              .shadow(color: Color(red: 0.94, green: 0.34, blue: 0.15).opacity(0.4), radius: 8)
              .position(x: ghostX, y: max(20, ghostY - 110))
              .allowsHitTesting(false)
              .transition(.scale(scale: 0.85).combined(with: .opacity))
          }
        }
        .animation(.spring(duration: 0.15), value: targetName)
      }
    }
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
    .alert("Rename Pinboard", isPresented: $showRenamePinboard) {
      TextField("New name", text: $newPinboardName)
      Button("Save") {
        if let p = pinboardToRename, !newPinboardName.trimmingCharacters(in: .whitespaces).isEmpty {
          pinboardStore.renamePinboard(p, to: newPinboardName)
        }
      }
      Button("Cancel", role: .cancel) {}
    }
    .alert("Delete Pinboard", isPresented: $showDeletePinboardConfirmation) {
      Button("Delete", role: .destructive) {
        if let p = pinboardToDelete {
          pinboardStore.deletePinboard(p)
          if selectedPinboard?.id == p.id {
            withAnimation { selectedPinboard = nil }
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Are you sure you want to delete this pinboard? This action cannot be undone.")
    }
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
            TabChip(
              label: "Clipboard",
              color: Color(red: 0.94, green: 0.34, blue: 0.15),
              isSelected: selectedPinboard == nil,
              isDropTarget: isClipboardDropTarget
            ) {
              withAnimation(.easeInOut(duration: 0.15)) { selectedPinboard = nil }
            }
            .background(tabChipGeometry("clipboard"))
            ForEach(pinboardStore.pinboards) { pinboard in
              TabChip(
                label: pinboard.name,
                color: pinboard.uiColor,
                isSelected: selectedPinboard?.id == pinboard.id,
                isDropTarget: dropTargetPinboard?.id == pinboard.id
              ) {
                withAnimation(.easeInOut(duration: 0.15)) { selectedPinboard = pinboard }
              }
              .background(tabChipGeometry(pinboard.id.uuidString))
              .contextMenu {
                Button("Rename Pinboard") {
                  pinboardToRename = pinboard
                  newPinboardName = pinboard.name
                  showRenamePinboard = true
                }
                Button("Delete Pinboard", role: .destructive) {
                  pinboardToDelete = pinboard
                  showDeletePinboardConfirmation = true
                }
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
          .background(cardGeometry(dec.id))
          .opacity(dragState?.id == dec.id ? 0 : 1)
          .gesture(dragGesture(for: dec))
          .onTapGesture { tapCard(dec) }
      }
      ForEach(matchedRecent) { dec in
        ClipCard(decorator: dec)
          .background(cardGeometry(dec.id))
          .opacity(dragState?.id == dec.id ? 0 : 1)
          .gesture(dragGesture(for: dec))
          .onTapGesture { tapCard(dec) }
      }
      ForEach(boardResults) { result in
        PinboardSeparator(label: String(result.board.name.prefix(3)).uppercased())
        ForEach(result.entries) { entry in
          PinboardEntryCard(entry: entry, pinboard: result.board)
            .background(cardGeometry(entry.id))
            .opacity(dragState?.id == entry.id ? 0 : 1)
            .gesture(dragGesture(for: entry, in: result.board))
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
            .background(cardGeometry(decorator.id))
            .opacity(dragState?.id == decorator.id ? 0 : 1)
            .offset(x: shiftedCardIDs.contains(decorator.id) ? Layout.cardWidth + 12 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: shiftedCardIDs.contains(decorator.id))
            .gesture(dragGesture(for: decorator))
            .onTapGesture { tapCard(decorator) }
        }
        Color.clear
          .frame(width: showPinnedEndGap ? Layout.cardWidth : 0, height: 1)
          .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showPinnedEndGap)
        PinboardSeparator(label: "PIN")
          .background(separatorGeometry("clipboard_pin"))
      }
      ForEach(filteredRecent) { decorator in
        ClipCard(decorator: decorator)
          .background(cardGeometry(decorator.id))
          .opacity(dragState?.id == decorator.id ? 0 : 1)
          .offset(x: shiftedCardIDs.contains(decorator.id) ? Layout.cardWidth + 12 : 0)
          .animation(.spring(response: 0.25, dampingFraction: 0.8), value: shiftedCardIDs.contains(decorator.id))
          .gesture(dragGesture(for: decorator))
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
      return (entry.customTitle ?? "").localizedCaseInsensitiveContains(searchText) ||
             (entry.text ?? "").localizedCaseInsensitiveContains(searchText) ||
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
            .background(cardGeometry(entry.id))
            .opacity(dragState?.id == entry.id ? 0 : 1)
            .offset(x: shiftedCardIDs.contains(entry.id) ? Layout.cardWidth + 12 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: shiftedCardIDs.contains(entry.id))
            .gesture(dragGesture(for: entry, in: pinboard))
        }
        Color.clear
          .frame(width: showPinnedEndGap ? Layout.cardWidth : 0, height: 1)
          .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showPinnedEndGap)
        PinboardSeparator(label: "PIN")
          .background(separatorGeometry("pinboard_pin"))
      }
      ForEach(unpinnedEntries) { entry in
        PinboardEntryCard(entry: entry, pinboard: pinboard)
          .background(cardGeometry(entry.id))
          .opacity(dragState?.id == entry.id ? 0 : 1)
          .offset(x: shiftedCardIDs.contains(entry.id) ? Layout.cardWidth + 12 : 0)
          .animation(.spring(response: 0.25, dampingFraction: 0.8), value: shiftedCardIDs.contains(entry.id))
          .gesture(dragGesture(for: entry, in: pinboard))
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

  // MARK: - Custom Drag Handlers

  private func tabChipGeometry(_ key: String) -> some View {
    GeometryReader { geo in
      Color.clear
        .onAppear { tabChipFrames[key] = geo.frame(in: .global) }
        .onChange(of: geo.frame(in: .global)) { _, newFrame in
          tabChipFrames[key] = newFrame
        }
    }
  }

  private func cardGeometry(_ id: UUID) -> some View {
    GeometryReader { geo in
      Color.clear
        .onAppear { cardFrames[id] = geo.frame(in: .global) }
        .onChange(of: geo.frame(in: .global)) { _, newFrame in
          cardFrames[id] = newFrame
        }
    }
  }

  private func dragGesture(for decorator: HistoryItemDecorator) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .global)
      .onChanged { value in
        if dragState == nil {
          let frame = cardFrames[decorator.id] ?? .zero
          dragState = CustomDragState(
            id: decorator.id,
            decorator: decorator,
            location: value.location,
            startCursor: value.startLocation,
            grabOffset: CGSize(
              width: frame.midX - value.startLocation.x,
              height: frame.midY - value.startLocation.y
            )
          )
        }
        dragState?.location = value.location
        updateDropTarget(at: value.location)
      }
      .onEnded { value in
        let dropped = executeDrop(at: value.location)
        if dropped {
          dragState = nil
        } else {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragState?.location = dragState?.startCursor ?? .zero
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dragState = nil
          }
        }
        dropTargetPinboard = nil
        isClipboardDropTarget = false
        reorderDropIndex = nil
        isPinToggleDrop = false
        ghostSnapX = nil
        showPinnedEndGap = false
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { shiftedCardIDs = [] }
      }
  }

  private func dragGesture(for entry: PinboardEntry, in pinboard: PinboardModel) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .global)
      .onChanged { value in
        if dragState == nil {
          let frame = cardFrames[entry.id] ?? .zero
          dragState = CustomDragState(
            id: entry.id,
            entry: entry,
            pinboard: pinboard,
            location: value.location,
            startCursor: value.startLocation,
            grabOffset: CGSize(
              width: frame.midX - value.startLocation.x,
              height: frame.midY - value.startLocation.y
            )
          )
        }
        dragState?.location = value.location
        updateDropTarget(at: value.location)
      }
      .onEnded { value in
        let dropped = executeDrop(at: value.location)
        if dropped {
          dragState = nil
        } else {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragState?.location = dragState?.startCursor ?? .zero
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dragState = nil
          }
        }
        dropTargetPinboard = nil
        isClipboardDropTarget = false
        reorderDropIndex = nil
        isPinToggleDrop = false
        ghostSnapX = nil
        showPinnedEndGap = false
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { shiftedCardIDs = [] }
      }
  }

  private func updateDropTarget(at location: CGPoint) {
    // 1a. Toolbar-zone detection: when cursor is above the card strip, snap to the
    //     nearest tab chip by X so users don't need pinpoint accuracy on tiny chips.
    if dragState != nil, let minCardY = cardFrames.values.map(\.minY).min(),
       location.y < minCardY {
      let nearest = tabChipFrames.min(by: {
        abs($0.value.midX - location.x) < abs($1.value.midX - location.x)
      })
      if let key = nearest?.key {
        reorderDropIndex = nil
        ghostSnapX = nil
        isPinToggleDrop = false
        shiftedCardIDs = []
        showPinnedEndGap = false
        if key == "clipboard" {
          isClipboardDropTarget = true
          dropTargetPinboard = nil
        } else if let pb = pinboardStore.pinboards.first(where: { $0.id.uuidString == key }) {
          dropTargetPinboard = pb
          isClipboardDropTarget = false
        }
        return
      }
    }

    // 1b. Precise tab chip hit test (handles cursor-on-chip cases not caught above)
    var foundTabKey: String? = nil
    for (key, frame) in tabChipFrames {
      if frame.insetBy(dx: -10, dy: -10).contains(location) { foundTabKey = key; break }
    }
    if let key = foundTabKey {
      reorderDropIndex = nil
      ghostSnapX = nil
      isPinToggleDrop = false
      shiftedCardIDs = []
      showPinnedEndGap = false
      if key == "clipboard" { isClipboardDropTarget = true; dropTargetPinboard = nil }
      else if let pb = pinboardStore.pinboards.first(where: { $0.id.uuidString == key }) {
        dropTargetPinboard = pb; isClipboardDropTarget = false
      }
      return
    }
    isClipboardDropTarget = false
    dropTargetPinboard = nil

    guard let state = dragState else { return }

    // 2. Detect pin-separator crossing — show gaps in the TARGET section
    if detectPinCrossing(state: state, location: location) {
      isPinToggleDrop = true
      ghostSnapX = nil
      if let crossIDs = crossSectionTargetIDs(for: state) {
        let idx = insertionIndex(at: location, in: crossIDs)
        reorderDropIndex = idx
        shiftedCardIDs = Set(crossIDs.dropFirst(idx))
        let targetIsPinned: Bool
        if let dec = state.decorator { targetIsPinned = !dec.isPinned }
        else if let entry = state.entry { targetIsPinned = !entry.isPinned }
        else { targetIsPinned = false }
        showPinnedEndGap = targetIsPinned
      } else {
        reorderDropIndex = nil
        shiftedCardIDs = []
        showPinnedEndGap = false
      }
      return
    }
    isPinToggleDrop = false

    // 3. Reorder: open a gap, ghost follows cursor freely
    if let ids = currentSectionReorderIDs(for: state) {
      let idx = insertionIndex(at: location, in: ids)
      reorderDropIndex = idx
      ghostSnapX = nil
      shiftedCardIDs = Set(ids.dropFirst(idx))
      // Shift the separator right whenever reordering a pinned section so the last
      // card can't crash into it and the end-slot is visually reachable.
      let isPinnedReorder = state.decorator?.isPinned == true || state.entry?.isPinned == true
      showPinnedEndGap = isPinnedReorder
    } else {
      reorderDropIndex = nil
      ghostSnapX = nil
      shiftedCardIDs = []
      showPinnedEndGap = false
    }
  }

  private func executeDrop(at location: CGPoint) -> Bool {
    updateDropTarget(at: location)
    guard let state = dragState else { return false }

    if isPinToggleDrop {
      if let dec = state.decorator {
        let wasUnpinned = dec.isUnpinned
        appState.history.togglePin(dec)
        // After pinning, reorder to the gap position within the pinned section
        if wasUnpinned, let insertIdx = reorderDropIndex,
           let fromIdx = filteredPinned.firstIndex(of: dec) {
          appState.history.reorderPinnedItems(fromDisplayIndex: fromIdx, toDisplayIndex: insertIdx)
        }
        return true
      } else if let entry = state.entry, let pb = state.pinboard {
        pinboardStore.togglePin(entry, in: pb)
        // After toggling, reorder to the gap position within the target section
        if let insertIdx = reorderDropIndex {
          let allEntries = pinboardStore.entries(for: pb)
          if let fromIdx = allEntries.firstIndex(where: { $0.id == entry.id }) {
            pinboardStore.reorderEntries(in: pb, from: fromIdx, to: insertIdx)
          }
        }
        return true
      }
    } else if isClipboardDropTarget {
      if let entry = state.entry, let pb = state.pinboard {
        pinboardStore.moveBack(entry, from: pb)
        return true
      }
    } else if let targetPb = dropTargetPinboard {
      if let dec = state.decorator {
        pinboardStore.move(dec, to: targetPb)
        return true
      } else if let entry = state.entry, let pb = state.pinboard, pb.id != targetPb.id {
        pinboardStore.moveEntry(entry, from: pb, to: targetPb)
        return true
      }
    } else if let insertIdx = reorderDropIndex {
      if let dec = state.decorator, dec.isPinned {
        if let fromIdx = filteredPinned.firstIndex(of: dec) {
          appState.history.reorderPinnedItems(fromDisplayIndex: fromIdx, toDisplayIndex: insertIdx)
          return true
        }
      } else if let entry = state.entry, let pb = state.pinboard,
                selectedPinboard?.id == pb.id {
        let entries = pinboardStore.entries(for: pb)
        if let fromIdx = entries.firstIndex(where: { $0.id == entry.id }) {
          pinboardStore.reorderEntries(in: pb, from: fromIdx, to: insertIdx)
          return true
        }
      }
    }
    return false
  }

  // MARK: - Reorder helpers

  private func currentSectionReorderIDs(for state: CustomDragState) -> [UUID]? {
    if let dec = state.decorator, dec.isPinned {
      return filteredPinned.filter { $0.id != dec.id }.map(\.id)
    } else if let entry = state.entry, let pb = state.pinboard,
              selectedPinboard?.id == pb.id {
      let entries = pinboardStore.entries(for: pb)
      if entry.isPinned {
        return entries.filter { $0.isPinned && $0.id != entry.id }.map(\.id)
      } else {
        return entries.filter { !$0.isPinned && $0.id != entry.id }.map(\.id)
      }
    }
    return nil
  }

  private func crossSectionTargetIDs(for state: CustomDragState) -> [UUID]? {
    if let dec = state.decorator, selectedPinboard == nil {
      return dec.isPinned ? filteredRecent.map(\.id) : filteredPinned.map(\.id)
    } else if let entry = state.entry, let pb = state.pinboard,
              selectedPinboard?.id == pb.id {
      let entries = pinboardStore.entries(for: pb)
      if entry.isPinned {
        return entries.filter { !$0.isPinned }.map(\.id)
      } else {
        return entries.filter { $0.isPinned }.map(\.id)
      }
    }
    return nil
  }

  private func insertionIndex(at location: CGPoint, in ids: [UUID]) -> Int {
    for (i, id) in ids.enumerated() {
      guard let frame = cardFrames[id] else { continue }
      if location.x < frame.midX { return i }
    }
    return ids.count
  }

  private func gapSnapX(at index: Int, in ids: [UUID]) -> CGFloat? {
    let frames = ids.compactMap { cardFrames[$0] }
    guard !frames.isEmpty else { return nil }
    let half = Layout.cardWidth / 2
    if index == 0 { return frames[0].minX - 6 - half }
    if index >= frames.count { return frames[frames.count - 1].maxX + 6 + half }
    return frames[index - 1].maxX + 6 + half
  }

  private func detectPinCrossing(state: CustomDragState, location: CGPoint) -> Bool {
    if let dec = state.decorator, selectedPinboard == nil {
      if dec.isPinned, let sep = separatorFrames["clipboard_pin"] {
        return location.x > sep.maxX
      } else if !dec.isPinned, let sep = separatorFrames["clipboard_pin"] {
        return location.x < sep.minX
      }
    } else if let entry = state.entry, let pb = state.pinboard,
              selectedPinboard?.id == pb.id {
      if entry.isPinned, let sep = separatorFrames["pinboard_pin"] {
        return location.x > sep.maxX
      } else if !entry.isPinned, let sep = separatorFrames["pinboard_pin"] {
        return location.x < sep.minX
      }
    }
    return false
  }

  private func separatorGeometry(_ key: String) -> some View {
    GeometryReader { geo in
      Color.clear
        .onAppear { separatorFrames[key] = geo.frame(in: .global) }
        .onChange(of: geo.frame(in: .global)) { _, f in separatorFrames[key] = f }
    }
  }

}

