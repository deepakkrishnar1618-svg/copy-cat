import SwiftUI

private struct CardData {
  let icon: String
  let gradient: [Color]
  let title: String
  let body: String
}

private let cards: [CardData] = [
  CardData(icon: "keyboard",
           gradient: [Color(red:0.23,green:0.51,blue:0.96), Color(red:0.44,green:0.27,blue:0.97)],
           title: "Your Clipboard, Always Ready",
           body: "Press ⇧⌘C (Shift + Command + C) to open Copy Cat's strip instantly from any app."),
  CardData(icon: "cursorarrow.click.2",
           gradient: [Color(red:0.55,green:0.27,blue:0.97), Color(red:0.94,green:0.27,blue:0.27)],
           title: "Paste in One Click",
           body: "Tap any card to instantly paste its content into your active app."),
  CardData(icon: "pin.fill",
           gradient: [Color(red:0.96,green:0.62,blue:0.04), Color(red:0.94,green:0.27,blue:0.27)],
           title: "Pin What Matters",
           body: "Hover a card and click the pin button to keep important clips front and center."),
  CardData(icon: "magnifyingglass",
           gradient: [Color(red:0.20,green:0.78,blue:0.35), Color(red:0.23,green:0.51,blue:0.96)],
           title: "Search Everything",
           body: "The always-visible search bar filters your entire clipboard history instantly."),
  CardData(icon: "folder.badge.plus",
           gradient: [Color(red:0.94,green:0.27,blue:0.27), Color(red:0.96,green:0.62,blue:0.04)],
           title: "Organize with Pinboards",
           body: "Create color-coded pinboards to save clips forever — no expiry, right-click any card to move it.")
]

struct OnboardingView: View {
  var onDismiss: () -> Void
  @State private var index = 0

  var body: some View {
    let card = cards[index]
    ZStack {
      LinearGradient(colors: card.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: index)

      VStack(spacing: 0) {
        Spacer()

        Image(systemName: card.icon)
          .font(.system(size: 64, weight: .thin))
          .foregroundStyle(.white)
          .frame(width: 120, height: 120)
          .background(.white.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 30))
          .shadow(color: .black.opacity(0.2), radius: 20)
          .padding(.bottom, 28)
          .transition(.scale.combined(with: .opacity))
          .id(index)

        Text(card.title)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
          .padding(.bottom, 12)

        Text(card.body)
          .font(.system(size: 14))
          .foregroundStyle(.white.opacity(0.85))
          .multilineTextAlignment(.center)
          .lineSpacing(2)
          .padding(.horizontal, 40)

        Spacer()

        HStack(spacing: 7) {
          ForEach(0..<cards.count, id: \.self) { i in
            Capsule()
              .fill(.white.opacity(i == index ? 1.0 : 0.4))
              .frame(width: i == index ? 18 : 6, height: 6)
              .animation(.spring(duration: 0.25), value: index)
          }
        }
        .padding(.bottom, 20)

        HStack(spacing: 12) {
          if index > 0 {
            Button(action: { withAnimation(.easeInOut(duration: 0.3)) { index -= 1 } }) {
              Text("Back")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(.white.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
          }
          Button(action: {
            if index == cards.count - 1 { onDismiss() }
            else { withAnimation(.easeInOut(duration: 0.3)) { index += 1 } }
          }) {
            Text(index == cards.count - 1 ? "Get Started" : "Next")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.black)
              .padding(.horizontal, 32).padding(.vertical, 10)
              .background(.white)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .focusable(false)
        }
        .padding(.bottom, 36)
      }
    }
    .frame(width: 440, height: 360)
  }
}
