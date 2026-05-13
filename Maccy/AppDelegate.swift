import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
  var panel: FloatingPanel<CopyCatPanel>!
  private var onboardingPanel: NSPanel?
  private var excludeAppsPanel: NSPanel?
  private weak var historyLimitField: NSTextField?
  private weak var historyLimitSaveBtn: NSButton?
  private var isShowingMinError = false

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.behavior = .removalAllowed
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.image = Defaults[.menuIcon].image
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    return statusItem
  }()

  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      SPUUpdater(hostBundle: Bundle.main,
                 applicationBundle: Bundle.main,
                 userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
                 delegate: nil)
      .automaticallyChecksForUpdates = false
    }
    #endif

    // Bridge FloatingPanel via AppDelegate.
    AppState.shared.appDelegate = self

    Clipboard.shared.onNewCopy { History.shared.add($0) }
    Clipboard.shared.start()

    Task {
      for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
        Clipboard.shared.restart()
      }
    }

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, Defaults[.showInStatusBar] != newValue {
        Defaults[.showInStatusBar] = newValue
      }
    }

    Task {
      for await value in Defaults.updates(.showInStatusBar) {
        statusItem.isVisible = value
      }
    }

    Task {
      for await value in Defaults.updates(.menuIcon, initial: false) {
        statusItem.button?.image = value.image
      }
    }

    synchronizeMenuIconText()
    Task {
      for await value in Defaults.updates(.showRecentCopyInMenuBar) {
        if value {
          statusItem.button?.title = AppState.shared.menuIconText
        } else {
          statusItem.button?.title = ""
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.ignoreEvents) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }

    Task {
      for await _ in Defaults.updates(.enabledPasteboardTypes) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    migrateUserDefaults()
    disableUnusedGlobalHotkeys()

    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      CopyCatPanel()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  private func migrateUserDefaults() {
    if Defaults[.migrations]["2024-07-01-version-2"] != true {
      // Start 2.x from scratch.
      Defaults.reset(.migrations)

      // Inverse hide* configuration keys.
      Defaults[.showFooter] = !UserDefaults.standard.bool(forKey: "hideFooter")
      Defaults[.showSearch] = !UserDefaults.standard.bool(forKey: "hideSearch")
      Defaults[.showTitle] = !UserDefaults.standard.bool(forKey: "hideTitle")
      UserDefaults.standard.removeObject(forKey: "hideFooter")
      UserDefaults.standard.removeObject(forKey: "hideSearch")
      UserDefaults.standard.removeObject(forKey: "hideTitle")

      Defaults[.migrations]["2024-07-01-version-2"] = true
    }

    if Defaults[.migrations]["2025-05-13-secure-ignore-apps"] != true {
      let secureApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7-osx",
        "com.apple.keychainaccess",
        "com.bitwarden.desktop"
      ]
      for app in secureApps where !Defaults[.ignoredApps].contains(app) {
        Defaults[.ignoredApps].append(app)
      }
      Defaults[.migrations]["2025-05-13-secure-ignore-apps"] = true
    }

    // The following defaults are not used in Maccy 2.x
    // and should be removed in 3.x.
    // - LaunchAtLogin__hasMigrated
    // - avoidTakingFocus
    // - saratovSeparator
    // - maxMenuItemLength
    // - maxMenuItems
  }

  @objc
  private func performStatusItemClick() {
    let menu = NSMenu()

    let openItem = NSMenuItem(title: "Open Clipboard", action: #selector(openPanel), keyEquivalent: "")
    openItem.target = self
    menu.addItem(openItem)
    menu.addItem(.separator())

    let limitItem = NSMenuItem()
    limitItem.view = makeHistoryLimitView()
    menu.addItem(limitItem)
    menu.addItem(.separator())

    let exportCSVItem = NSMenuItem(title: "Export CSV (.zip)...", action: #selector(exportCSV), keyEquivalent: "")
    exportCSVItem.target = self
    menu.addItem(exportCSVItem)

    let exportPDFItem = NSMenuItem(title: "Export PDF...", action: #selector(exportPDF), keyEquivalent: "")
    exportPDFItem.target = self
    menu.addItem(exportPDFItem)

    let excludeAppsItem = NSMenuItem(title: "Excluded Apps...", action: #selector(openExcludeApps), keyEquivalent: "")
    excludeAppsItem.target = self
    menu.addItem(excludeAppsItem)
    menu.addItem(.separator())

    let helpItem = NSMenuItem(title: "How to Use Copy Cat", action: #selector(showOnboarding), keyEquivalent: "")
    helpItem.target = self
    menu.addItem(helpItem)
    menu.addItem(.separator())

    let accessibilityItem = NSMenuItem(title: "Check Auto-Paste Permission", action: #selector(checkAccessibility), keyEquivalent: "")
    accessibilityItem.target = self
    menu.addItem(accessibilityItem)

    let uninstallItem = NSMenuItem(title: "Uninstall Copy Cat...", action: #selector(uninstallApp), keyEquivalent: "")
    uninstallItem.target = self
    menu.addItem(uninstallItem)
    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Quit Copy Cat", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quitItem)

    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  @objc private func uninstallApp() {
    let alert = NSAlert()
    alert.messageText = "Uninstall Copy Cat"
    alert.informativeText = "This will completely erase your clipboard history, pinboards, settings, and accessibility permissions.\n\nAfter clicking Uninstall, the app will quit. You can then safely drag it to the Trash."
    alert.addButton(withTitle: "Cancel")
    let uninstallButton = alert.addButton(withTitle: "Uninstall & Quit")
    uninstallButton.hasDestructiveAction = true

    NSApp.activate(ignoringOtherApps: true)

    if alert.runModal() == .alertSecondButtonReturn {
      let task = Process()
      task.launchPath = "/usr/bin/tccutil"
      task.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.copycat.app"]
      try? task.run()

      if let bundleID = Bundle.main.bundleIdentifier {
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
      }
      
      Task { @MainActor in
        AppState.shared.history.clear()
        NSApp.terminate(nil)
      }
    }
  }

  @objc private func checkAccessibility() {
    Accessibility.check()
  }

  @objc private func openPanel() {
    panel.toggle(height: AppState.shared.popup.height, at: .statusItem)
  }

  @objc private func setHistoryLimitFromField(_ sender: NSTextField) {
    let value = sender.integerValue
    if value >= 10 {
      Defaults[.size] = value
      Task { @MainActor in AppState.shared.history.enforceCurrentLimit() }
    }
  }

  func controlTextDidBeginEditing(_ obj: Notification) {
    guard let field = obj.object as? NSTextField,
          field.tag == 42,
          isShowingMinError,
          let btn = historyLimitSaveBtn else { return }
    isShowingMinError = false
    applySaveBtnStyle(btn, title: "Save", color: .secondaryLabelColor)
    btn.isEnabled = true
  }

  func controlTextDidChange(_ obj: Notification) {
    guard let field = obj.object as? NSTextField,
          field.tag == 42,
          let btn = historyLimitSaveBtn else { return }
    let isDirty = field.integerValue != Defaults[.size]
    let orange = NSColor(red: 0.94, green: 0.34, blue: 0.15, alpha: 1.0)
    applySaveBtnStyle(btn, title: "Save", color: isDirty ? orange : .secondaryLabelColor)
  }

  private func applySaveBtnStyle(_ btn: NSButton, title: String, color: NSColor) {
    let attrs: [NSAttributedString.Key: Any] = [
      .foregroundColor: color,
      .font: NSFont.systemFont(ofSize: 11, weight: .medium)
    ]
    btn.attributedTitle = NSAttributedString(string: title, attributes: attrs)
  }

  @objc private func exportCSV() {
    Task { @MainActor in
      do {
        let tempURL = try await ExportManager.shared.exportCSVZip()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CopyCatExport.zip"
        panel.allowedContentTypes = [UTType.zip]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if FileManager.default.fileExists(atPath: dest.path) {
          try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: tempURL, to: dest)
      } catch {}
    }
  }

  @objc private func exportPDF() {
    Task { @MainActor in
      do {
        let tempURL = try await ExportManager.shared.exportPDF()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CopyCatExport.pdf"
        panel.allowedContentTypes = [UTType.pdf]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if FileManager.default.fileExists(atPath: dest.path) {
          try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: tempURL, to: dest)
      } catch {}
    }
  }

  @objc private func openExcludeApps() {
    if excludeAppsPanel == nil {
      let p = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      p.title = "Excluded Apps"
      p.isReleasedWhenClosed = false
      p.level = .floating
      let hosting = NSHostingView(rootView: IgnoreApplicationsSettingsView())
      p.contentView = hosting
      excludeAppsPanel = p
    }
    excludeAppsPanel?.center()
    NSApp.activate(ignoringOtherApps: true)
    excludeAppsPanel?.makeKeyAndOrderFront(nil)
  }

  @objc private func showOnboarding() {
    if onboardingPanel == nil {
      let p = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      p.titleVisibility = .hidden
      p.titlebarAppearsTransparent = true
      p.isMovableByWindowBackground = true
      p.backgroundColor = .clear
      p.level = .floating
      p.isReleasedWhenClosed = false

      let hosting = NSHostingView(rootView: OnboardingView { [weak self] in
        self?.onboardingPanel?.close()
        self?.onboardingPanel = nil
      })
      hosting.wantsLayer = true
      p.contentView = hosting
      p.contentView?.layer?.cornerRadius = 16
      p.contentView?.layer?.masksToBounds = true
      onboardingPanel = p
    }
    onboardingPanel?.center()
    NSApp.activate(ignoringOtherApps: true)
    onboardingPanel?.makeKeyAndOrderFront(nil)
  }

  private func makeHistoryLimitView() -> NSView {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 34))

    let label = NSTextField(labelWithString: "History Limit:")
    label.font = .systemFont(ofSize: 13)
    label.frame = NSRect(x: 12, y: 9, width: 98, height: 16)
    label.textColor = .labelColor
    container.addSubview(label)

    let field = NSTextField(frame: NSRect(x: 116, y: 7, width: 60, height: 20))
    field.integerValue = Defaults[.size]
    field.alignment = .center
    field.font = .systemFont(ofSize: 13)
    field.tag = 42
    field.delegate = self
    field.target = self
    field.action = #selector(setHistoryLimitFromField(_:))
    container.addSubview(field)
    historyLimitField = field

    let unit = NSTextField(labelWithString: "items")
    unit.font = .systemFont(ofSize: 11)
    unit.textColor = .secondaryLabelColor
    unit.frame = NSRect(x: 182, y: 9, width: 34, height: 16)
    container.addSubview(unit)

    let saveBtn = NSButton(frame: NSRect(x: 220, y: 7, width: 90, height: 20))
    saveBtn.bezelStyle = .rounded
    saveBtn.controlSize = .small
    saveBtn.target = self
    saveBtn.action = #selector(saveHistoryLimitButtonTapped(_:))
    applySaveBtnStyle(saveBtn, title: "Save", color: .secondaryLabelColor)
    container.addSubview(saveBtn)
    historyLimitSaveBtn = saveBtn

    return container
  }

  @objc private func saveHistoryLimitButtonTapped(_ sender: NSButton) {
    guard let field = sender.superview?.viewWithTag(42) as? NSTextField else { return }
    let orange = NSColor(red: 0.94, green: 0.34, blue: 0.15, alpha: 1.0)
    let value = field.integerValue

    guard value >= 10 else {
      field.integerValue = Defaults[.size]
      applySaveBtnStyle(sender, title: "Minimum 10", color: orange)
      sender.isEnabled = false
      isShowingMinError = true
      return
    }

    applySaveBtnStyle(sender, title: "Saving...", color: orange)
    sender.isEnabled = false
    setHistoryLimitFromField(field)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      guard let self else { return }
      self.applySaveBtnStyle(sender, title: "Saved ✓", color: .secondaryLabelColor)
      sender.isEnabled = true
    }
  }


  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: {
      DispatchQueue.main.async {
        if Defaults[.showRecentCopyInMenuBar] {
          self.statusItem.button?.title = AppState.shared.menuIconText
        }
        self.synchronizeMenuIconText()
      }
    }
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin]
    KeyboardShortcuts.disable(names)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
}
