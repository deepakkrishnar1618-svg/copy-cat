import Defaults
import SwiftUI

// An NSPanel subclass that implements floating panel traits.
// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
  var isPresented: Bool = false
  /// When non-nil the panel is locked to this height (bottom-strip mode).
  /// windowWillResize will enforce it and skip persisting window size.
  private var fixedHeight: CGFloat?
  var statusBarButton: NSStatusBarButton?
  let onClose: () -> Void

  override var isMovable: Bool {
    get { false }
    set {}
  }

  init(
    contentRect: NSRect,
    identifier: String = "",
    statusBarButton: NSStatusBarButton? = nil,
    onClose: @escaping () -> Void,
    view: () -> Content
  ) {
    self.onClose = onClose

    super.init(
        contentRect: contentRect,
        styleMask: [.nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )

    self.statusBarButton = statusBarButton
    self.identifier = NSUserInterfaceItemIdentifier(identifier)

    Defaults[.windowSize] = contentRect.size
    delegate = self

    animationBehavior = .none
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    hidesOnDeactivate = false
    backgroundColor = .clear
    titlebarSeparatorStyle = .none

    // Hide all traffic light buttons
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    let hostingView = NSHostingView(
      rootView: view()
        // The safe area is ignored because the title bar still interferes with the geometry
        .ignoresSafeArea()
        .gesture(DragGesture()
          .onEnded { _ in
            self.saveWindowPosition()
        })
    )
    // Prevent the hosting view from resizing the window when SwiftUI content changes
    // (e.g. pinning items triggers layout recalculation that would collapse the panel)
    if #available(macOS 13.0, *) {
      hostingView.sizingOptions = []
    }
    contentView = hostingView
    contentView?.layer?.cornerRadius = 0
    contentView?.layer?.maskedCorners = []
  }

  func toggle(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    if isPresented {
      close()
    } else {
      open(height: height, at: popupPosition)
    }
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let panelHeight: CGFloat = 270
    fixedHeight = panelHeight
    setContentSize(NSSize(width: screen.frame.width, height: panelHeight))
    // Lock height so SwiftUI layout changes (e.g. pinning) cannot collapse the panel
    minSize = NSSize(width: 300, height: panelHeight)
    maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: panelHeight)
    setFrameOrigin(NSPoint(x: screen.frame.minX, y: screen.frame.minY))
    orderFrontRegardless()
    makeKey()
    isPresented = true
  }

  func verticallyResize(to newHeight: CGFloat) {
    return
  }

  func determinePreviewPlacement() {
    let preview = AppState.shared.preview
    guard !preview.state.isOpen else { return }
    let newSize = preview.computeSizeWithPreview(frame.size, state: .open)
    preview.placement = preview.computePlacement(window: self, for: newSize)
  }

  func saveWindowPosition() {
    if let screenFrame = screen?.visibleFrame {
      // Only store the size of the window without the preview
      let width = AppState.shared.preview.contentWidth

      let anchorX = frame.minX + width / 2 - screenFrame.minX
      let anchorY = frame.maxY - screenFrame.minY
      Defaults[.windowPosition] = NSPoint(x: anchorX / screenFrame.width, y: anchorY / screenFrame.height)
    }
  }

  func saveWindowFrame(frame: NSRect) {
    Defaults[.windowSize] = frame.size
    saveWindowPosition()
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    // Bottom-strip mode: height is locked. Return immediately without saving
    // to Defaults[.windowSize] — that would corrupt Popup.resize() calculations.
    if let fixedHeight {
      return NSSize(width: frameSize.width, height: fixedHeight)
    }

    let preview = AppState.shared.preview

    if inLiveResize && preview.resizingMode == .none {
      let screenPoint = NSEvent.mouseLocation
      let windowPoint = convertPoint(fromScreen: screenPoint)
      let location: SlideoutPlacement = windowPoint.x <= frame.width / 2 ? .left : .right
      if (location == preview.placement) && preview.state == .open {
        preview.startResize(mode: .slideout)
      } else {
        preview.startResize(mode: .content)
      }
    }

    var finalFrameSize = frameSize
    var minContent = preview.minimumContentWidth
    var minPreview = 0.0

    if inLiveResize && preview.resizingMode != .none {
      if preview.resizingMode == .content && preview.state == .open {
        minPreview = preview.slideoutWidth
      }
      if preview.resizingMode == .slideout {
        minPreview = preview.minimumSlideoutWidth
        minContent = preview.contentWidth
      }
    }
    finalFrameSize.width = max(finalFrameSize.width, minContent + minPreview)

    if !AppState.shared.preview.state.isAnimating {
      var size = frame.size
      // Only store the size of the window without the preview
      size.width = AppState.shared.preview.contentWidth
      saveWindowFrame(frame: NSRect(origin: frame.origin, size: size))
    }

    return finalFrameSize
  }

  func windowWillMove(_ notification: Notification) {
    determinePreviewPlacement()
  }

  func windowDidMove(_ notification: Notification) {
    determinePreviewPlacement()
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    AppState.shared.preview.cancelAutoOpen()
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    AppState.shared.preview.startAutoOpen()
    AppState.shared.preview.endResize()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    AppState.shared.preview.enableAutoOpen()

    if AppState.shared.navigator.leadHistoryItem != nil {
      AppState.shared.preview.startAutoOpen()
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    AppState.shared.preview.disableAutoOpen()
  }

  // Close automatically when out of focus, e.g. outside click.
  override func resignKey() {
    super.resignKey()
    // Don't hide if confirmation is shown.
    if NSApp.alertWindow == nil {
      close()
    }
  }

  override func close() {
    super.close()
    AppState.shared.preview.state = .closed
    isPresented = false
    statusBarButton?.isHighlighted = false
    onClose()
  }

  // Allow text inputs inside the panel can receive focus
  override var canBecomeKey: Bool {
    return true
  }
}
