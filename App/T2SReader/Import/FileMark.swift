// App/T2SReader/Import/FileMark.swift
import SwiftUI

/// The file flow's one object: a grey, unlit document wearing a badge that says where the file has
/// got to — a plus while there is nothing yet, the app's green tick once one is in (owner,
/// 2026-09-17: "when the file is uploaded, we have the green tick. Otherwise … the plus icon"). It
/// is the share extension's picture brought into the app, so a book shared in from another app and
/// a book chosen from Files land on the same image.
///
/// Both badges are drawn as a disc of our own rather than as an SF Symbol badge: `document.badge.plus`
/// has no checkmark sibling to swap to, and one disc that only changes glyph and colour can be
/// animated between the two states, where swapping whole symbols could not. The inner leaf is
/// `ground`, so either mark reads as punched through the disc in both themes.
struct FileMark: View {
    /// Where the file has got to. `waiting` is the bare document — nothing has been chosen yet.
    enum Stage { case waiting, working, ready }

    var stage: Stage
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            if stage == .working {
                ProgressView().controlSize(.large).tint(Tokens.ink2)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(Tokens.ink2)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: stage == .ready ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: size * 0.44, weight: .semibold))
                            .foregroundStyle(Tokens.ground, stage == .ready ? Tokens.positive : Tokens.ink2)
                            .offset(x: size * 0.20, y: size * 0.08)
                    }
            }
        }
        // A ceiling rather than a height, so a short sheet squeezes the picture instead of pushing
        // the key off the foot — the share sheet's own rule, kept.
        .frame(maxHeight: size * 1.6)
        .animation(.snappy, value: stage)
        .accessibilityHidden(true)
    }
}
