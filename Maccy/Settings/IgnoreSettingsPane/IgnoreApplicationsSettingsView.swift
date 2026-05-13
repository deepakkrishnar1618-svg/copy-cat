import AppKit
import Defaults
import SwiftUI

struct IgnoreApplicationsSettingsView: View {
  @Default(.ignoredApps) private var ignoredApps
  @State private var apps: [AppEntry] = []
  @State private var searchText = ""

  struct AppEntry: Identifiable {
    let id: String  // bundle ID
    let name: String
    let icon: NSImage
  }

  private var filteredApps: [AppEntry] {
    searchText.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.system(size: 12))
        TextField("Search apps...", text: $searchText)
          .textFieldStyle(.plain)
          .font(.system(size: 12))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(Color(nsColor: .controlBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

      List {
        ForEach(filteredApps) { app in
          HStack(spacing: 10) {
            Image(nsImage: app.icon)
              .resizable()
              .frame(width: 22, height: 22)
            Text(app.name)
              .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: Binding(
              get: { !ignoredApps.contains(app.id) },
              set: { isEnabled in
                if isEnabled {
                  ignoredApps.removeAll { $0 == app.id }
                } else {
                  if !ignoredApps.contains(app.id) {
                    ignoredApps.append(app.id)
                  }
                }
              }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
          }
          .padding(.vertical, 2)
        }
      }
      .listStyle(.plain)
      .frame(minHeight: 240)

      Text("Apps toggled off won't be recorded. Existing clipboard items from excluded apps are hidden.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding()
    .onAppear { loadApps() }
  }

  private func loadApps() {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(
      at: URL(fileURLWithPath: "/Applications"),
      includingPropertiesForKeys: nil,
      options: .skipsHiddenFiles
    ) else { return }

    var result: [AppEntry] = []
    for url in contents where url.pathExtension == "app" {
      guard let bundle = Bundle(url: url),
            let bundleID = bundle.bundleIdentifier else { continue }
      let name = url.deletingPathExtension().lastPathComponent
      let icon = NSWorkspace.shared.icon(forFile: url.path)
      result.append(AppEntry(id: bundleID, name: name, icon: icon))
    }
    apps = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}

#Preview {
  IgnoreApplicationsSettingsView()
    .environment(\.locale, .init(identifier: "en"))
}
