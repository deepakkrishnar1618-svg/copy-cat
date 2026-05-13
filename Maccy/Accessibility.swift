import AppKit

struct Accessibility {
  static var allowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  // Call on first launch to show the macOS accessibility permission dialog
  static func requestIfNeeded() {
    guard !allowed else { return }
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
  }

  // Called before paste — silently no-ops if already granted, prompts if not
  static func check() {
    guard !allowed else { return }
    
    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText = "To paste items automatically, Copy Cat needs Accessibility permission.\n\nIMPORTANT: If you are enabling this for the first time, or if macOS is stuck in a loop, you MUST Quit and Restart Copy Cat after toggling the switch in System Settings for the permission to take effect."
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Quit Copy Cat")
    alert.addButton(withTitle: "Cancel")
    
    // Ensure the app is active so the alert shows up in front
    NSApp.activate(ignoringOtherApps: true)
    
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        requestIfNeeded()
    } else if response == .alertSecondButtonReturn {
        NSApp.terminate(nil)
    }
  }
}
