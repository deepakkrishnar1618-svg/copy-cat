import AppKit
import Defaults
import Settings
import SwiftUI
import UniformTypeIdentifiers

struct StorageSettingsPane: View {
  @Observable
  class ViewModel {
    var saveFiles = false {
      didSet {
        Defaults.withoutPropagation {
          if saveFiles {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.files.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.files.types)
          }
        }
      }
    }

    var saveImages = false {
      didSet {
        Defaults.withoutPropagation {
          if saveImages {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.images.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.images.types)
          }
        }
      }
    }

    var saveText = false {
      didSet {
        Defaults.withoutPropagation {
          if saveText {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.text.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.text.types)
          }
        }
      }
    }

    private var observer: Defaults.Observation?

    init() {
      observer = Defaults.observe(.enabledPasteboardTypes) { change in
        self.saveFiles = change.newValue.isSuperset(of: StorageType.files.types)
        self.saveImages = change.newValue.isSuperset(of: StorageType.images.types)
        self.saveText = change.newValue.isSuperset(of: StorageType.text.types)
      }
    }

    deinit {
      observer?.invalidate()
    }
  }

  @Default(.size) private var size
  @Default(.sortBy) private var sortBy

  @State private var viewModel = ViewModel()
  @State private var storageSize = Storage.shared.size
  @State private var sizeText = ""

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        bottomDivider: true,
        label: { Text("Save", tableName: "StorageSettings") }
      ) {
        Toggle(
          isOn: $viewModel.saveFiles,
          label: { Text("Files", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $viewModel.saveImages,
          label: { Text("Images", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $viewModel.saveText,
          label: { Text("Text", tableName: "StorageSettings") }
        )
        Text("SaveDescription", tableName: "StorageSettings")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }

      Settings.Section(label: { Text("Size", tableName: "StorageSettings") }) {
        HStack {
          TextField("", text: $sizeText)
            .frame(width: 80)
            .help(Text("SizeTooltip", tableName: "StorageSettings"))
            .onAppear { sizeText = "\(size)" }
            .onSubmit { commitSize() }
          Stepper("", value: Binding(
            get: { size },
            set: { newVal in
              size = newVal
              sizeText = "\(newVal)"
              storageSize = Storage.shared.size
            }
          ), in: 1...999)
          .labelsHidden()
          Button(action: commitSize) {
            HStack(spacing: 4) {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
              Text("Save")
                .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.94, green: 0.34, blue: 0.15))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(red: 0.94, green: 0.34, blue: 0.15).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.94, green: 0.34, blue: 0.15).opacity(0.4), lineWidth: 1))
          }
          .buttonStyle(.plain)
          .help("Save history limit")
          Text(storageSize)
            .controlSize(.small)
            .foregroundStyle(.gray)
            .help(Text("CurrentSizeTooltip", tableName: "StorageSettings"))
        }
      }

      Settings.Section(label: { Text("SortBy", tableName: "StorageSettings") }) {
        Picker("", selection: $sortBy) {
          ForEach(Sorter.By.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .frame(width: 160, alignment: .leading)
        .help(Text("SortByTooltip", tableName: "StorageSettings"))
      }

      Settings.Section(
        bottomDivider: false,
        label: { Text("Export") }
      ) {
        HStack(spacing: 10) {
          Button {
            triggerExport(asPDF: false)
          } label: {
            HStack(spacing: 5) {
              Image(systemName: "doc.zipper")
                .font(.system(size: 13))
              Text("Export CSV (.zip)")
                .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.94, green: 0.34, blue: 0.15))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color(red: 0.94, green: 0.34, blue: 0.15).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.94, green: 0.34, blue: 0.15).opacity(0.4), lineWidth: 1))
          }
          .buttonStyle(.plain)
          .help("Export clipboard and pinboards as CSV files inside a zip archive")

          Button {
            triggerExport(asPDF: true)
          } label: {
            HStack(spacing: 5) {
              Image(systemName: "doc.richtext")
                .font(.system(size: 13))
              Text("Export PDF")
                .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.94, green: 0.34, blue: 0.15))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color(red: 0.94, green: 0.34, blue: 0.15).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.94, green: 0.34, blue: 0.15).opacity(0.4), lineWidth: 1))
          }
          .buttonStyle(.plain)
          .help("Export clipboard and pinboards as a formatted PDF")
        }
        Text("Exports all clipboard items and pinboards. Excluded apps are not included.")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }
    }
  }

  private func triggerExport(asPDF: Bool) {
    Task { @MainActor in
      do {
        let tempURL = asPDF
          ? try await ExportManager.shared.exportPDF()
          : try await ExportManager.shared.exportCSVZip()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = asPDF ? "CopyCatExport.pdf" : "CopyCatExport.zip"
        panel.allowedContentTypes = asPDF ? [UTType.pdf] : [UTType.zip]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if FileManager.default.fileExists(atPath: dest.path) {
          try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: tempURL, to: dest)
      } catch {}
    }
  }

  private func commitSize() {
    if let v = Int(sizeText), v >= 1, v <= 999 {
      size = v
      storageSize = Storage.shared.size
    } else {
      sizeText = "\(size)"
    }
  }
}

#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
