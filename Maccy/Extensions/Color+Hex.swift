import SwiftUI

extension Color {
  init?(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    guard Scanner(string: hex).scanHexInt64(&int), hex.count == 6 else { return nil }
    self.init(
      red:   Double((int >> 16) & 0xFF) / 255,
      green: Double((int >> 8)  & 0xFF) / 255,
      blue:  Double(int         & 0xFF) / 255
    )
  }
}
