// App/T2SReader/Design/MockIsland.swift
import SwiftUI
import T2SApp
import UIKit

/// A black capsule that begins as the Dynamic Island and grows downward.
///
/// **It is not a Live Activity and could not be one.** iOS never shows an app's own Live
/// Activity in the Dynamic Island while that app is in the foreground, so the in-app effect has
/// to be drawn by hand. This is that drawing.
///
/// On a phone with no island there is nothing to grow out of, so the same content is drawn as a
/// plain rounded card below the status bar. No pretending to be hardware that is not there.
struct MockIsland: View {
    @Environment(AppEnvironment.self) private var env
    var message: ChapterReadyMessage
    var cover: ToastContent.Cover?
    var action: (() -> Void)?
    var onDismiss: () -> Void
    /// The capsule's frame in window coordinates, published as it lays out and `.zero` on the way
    /// out. `IslandWindow` has no other way to know where it may accept a touch — SwiftUI hands a
    /// `hitTest` caller the hosting view and nothing under it (`MockIslandWindow.swift`).
    var onCapsuleFrame: (CGRect) -> Void = { _ in }

    /// Collapsed, the capsule is exactly the cutout. Expanded it keeps the cutout's width as its
    /// corner radius so the two silhouettes are continuous.
    private var hasIsland: Bool { IslandGeometry.deviceHasIsland }

    /// The safe-area top inset on every Dynamic Island device: a 54 pt status bar plus 5 pt.
    /// The system draws its clock and glyphs somewhere in here, on top of every window
    /// including this capsule's, so the capsule's own words must start no higher than this.
    private static let statusBarInset: CGFloat = 59

    /// Space between the capsule's background top (anchored at `IslandGeometry.cutoutTop`, so
    /// the capsule reads as a continuation of the real cutout) and the content's top. On an
    /// island device this is padded out so the content clears the status bar; the background
    /// itself does not move, so the capsule simply grows taller. On a device with no island the
    /// content already sits below the status bar via the outer top padding, so this stays the
    /// original, tighter inset.
    private var contentTopInset: CGFloat {
        hasIsland ? Self.statusBarInset - IslandGeometry.cutoutTop : 14
    }

    /// The real safe-area top inset, read from the key window rather than from a `GeometryReader`
    /// here: this capsule's window ignores the safe area on purpose (`MockIslandWindow.swift`), so
    /// the island's background can sit above it and merge with the real cutout — and a proxy
    /// inside a window that ignores it reports the inset it now covers as zero — the same
    /// measurement `StatusRows` and `PageTopEdge` hit and solve the same way. UIKit's own value is
    /// untouched by what this window's content ignores: it is a property of the screen, not of
    /// what is drawn over it, so it is also correct on the notch devices `statusBarInset` above
    /// was never measured against. `nil` only when there is no key window yet to ask.
    private var deviceSafeAreaTop: CGFloat? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top
    }

    /// Where the whole card — background included — sits on a device with no island: below
    /// whatever the real safe area is on this phone, plus the card's own margin, rather than
    /// below a Dynamic Island phone's specific 59 pt. Falls back to `statusBarInset` only if no
    /// key window can be asked yet, which keeps the card off the status bar rather than under it.
    private var nonIslandTopPadding: CGFloat {
        (deviceSafeAreaTop ?? Self.statusBarInset) + 8
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, contentTopInset)
            .padding(.bottom, 14)
            .background(
                RoundedRectangle(cornerRadius: hasIsland ? IslandGeometry.cutoutHeight : 22,
                                 style: .continuous)
                    .fill(.black)
            )
            // Tap-to-dismiss over the black rectangle and nothing else. This used to sit above the
            // full-screen frame below, where it covered the whole screen — unnoticed only because
            // the window was refusing every touch anyway, and it would have swallowed the app
            // whole the moment the window started answering.
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            // Measured at exactly the same place, so every point the window accepts is a point
            // this capsule can use, and the margins around it stay the app's.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onCapsuleFrame($0) }
            .onDisappear { onCapsuleFrame(.zero) }
            .padding(.horizontal, hasIsland ? 10 : Spacing.margin)
            .padding(.top, hasIsland ? IslandGeometry.cutoutTop : nonIslandTopPadding)
            .frame(maxHeight: .infinity, alignment: .top)
            .transition(.scale(scale: 0.4, anchor: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(message.title), \(message.detail)")
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            if let cover {
                BookCover(relativePath: cover.relativePath, paths: env.paths, height: 40,
                          title: cover.title, isPDF: cover.isPDF)
                    .accessibilityHidden(true)
            } else {
                CircleGlyph(systemName: message.isFailure ? "exclamationmark" : "checkmark",
                            tint: .black, fill: .white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(message.title).typeRole(.pill).foregroundStyle(.white)
                Text(message.detail).typeRole(.meta).foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Spacer(minLength: 8)
                Button(action: action) {
                    CircleGlyph(systemName: "play.fill", tint: .black, fill: .white)
                }
                .accessibilityLabel("Play")
            }
        }
    }
}
