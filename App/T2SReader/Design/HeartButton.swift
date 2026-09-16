// App/T2SReader/Design/HeartButton.swift
import SwiftUI

/// The favorite heart (owner, 2026-09-10): red and a little glossy — a top-lit gradient
/// (`Tokens.heartTop` → `heartBottom`, a shade lighter in the dark), a soft highlight, a shadow
/// under it — and it pops when it fills. Empty, it is the outline in `ink2`.
/// Sized to the row's radio so the two trailing marks read as one set.
///
/// It shared `GenderMark.swift` until that file went (2026-09-16, with the gender signs it was
/// named for); the heart is still the voice row's favorite control, so it lives on its own now.
struct HeartButton: View {
    var isOn: Bool
    var label: String
    var action: () -> Void
    @State private var pop = false

    var body: some View {
        Button {
            action()
            if !isOn {                                                                  // filling is what pops; emptying just empties
                pop = true
                Task { try? await Task.sleep(for: .milliseconds(180)); pop = false }
            }
        } label: {
            ZStack {
                if isOn {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(colors: [Tokens.heartTop, Tokens.heartBottom],
                                           startPoint: .top, endPoint: .bottom))
                        .overlay {
                            // The gloss: a soft white ellipse over the top lobes.
                            Ellipse()
                                .fill(Tokens.gloss.opacity(0.45))
                                .frame(width: 11, height: 5)
                                .blur(radius: 1.2)
                                .offset(x: -3, y: -6)
                        }
                        .shadow(color: Tokens.heartShade.opacity(0.35), radius: 2, x: 0, y: 1.5)
                } else {
                    Image(systemName: "heart")
                        .font(.system(size: 24))
                        .foregroundStyle(Tokens.ink2)
                }
            }
            .frame(width: 40, height: 40)
            .scaleEffect(pop ? 1.3 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.45), value: pop)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
