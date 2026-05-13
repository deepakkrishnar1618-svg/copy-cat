import SwiftUI

struct NewPinboardSheet: View {
  let onCreate: (String, String) -> Void
  let onCancel: () -> Void
  @State private var name = ""
  @State private var selectedHex = "0088FF"

  private let presets: [(String, Color)] = [
    ("0088FF", .blue),
    ("8B5CF6", Color(red: 0.55, green: 0.36, blue: 0.96)),
    ("EF4444", Color(red: 0.94, green: 0.27, blue: 0.27)),
    ("F59E0B", Color(red: 0.96, green: 0.62, blue: 0.04)),
    ("10B981", Color(red: 0.06, green: 0.73, blue: 0.51)),
    ("6B7280", Color(red: 0.42, green: 0.45, blue: 0.50))
  ]

  var body: some View {
    VStack(spacing: 20) {
      Text("New Pinboard")
        .font(.system(size: 16, weight: .semibold))

      TextField("Name (e.g. Work, Design)", text: $name)
        .textFieldStyle(.roundedBorder)
        .frame(width: 240)

      HStack(spacing: 10) {
        ForEach(presets, id: \.0) { hex, color in
          Circle()
            .fill(color)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.white, lineWidth: selectedHex == hex ? 2.5 : 0))
            .scaleEffect(selectedHex == hex ? 1.15 : 1.0)
            .onTapGesture { withAnimation(.spring(duration: 0.15)) { selectedHex = hex } }
        }
      }

      HStack(spacing: 10) {
        Button("Cancel") { onCancel() }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
        Button("Create") {
          let t = name.trimmingCharacters(in: .whitespaces)
          guard !t.isEmpty else { return }
          onCreate(t, selectedHex)
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(24)
    .frame(width: 300, height: 180)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1))
  }
}
