// App/T2SReader/Design/MockIsland.swift
import SwiftUI
import T2SApp

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

    /// Collapsed, the capsule is exactly the cutout. Expanded it keeps the cutout's width as its
    /// corner radius so the two silhouettes are continuous.
    private var hasIsland: Bool { IslandGeometry.deviceHasIsland }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: hasIsland ? IslandGeometry.cutoutHeight : 22,
                                 style: .continuous)
                    .fill(.black)
            )
            .padding(.horizontal, hasIsland ? 10 : Spacing.margin)
            .padding(.top, hasIsland ? IslandGeometry.cutoutTop : 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
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
