// App/T2SReader/Design/ToastCenter.swift
import SwiftUI
import UIKit

/// A toast raised from outside the view that shows it.
///
/// The Reader owns its own toasts — a bookmark is saved there and answered there — but "the voice
/// model was deleted" belongs to a play tap, and a play tap happens on Home, in the Collection, in
/// the mini-player and in the Reader. One place holds the message, and whichever host is on screen
/// draws it (`ToastHost`).
@MainActor
@Observable
final class ToastCenter {
    private(set) var content: ToastContent?
    /// What the toast's one pill does; nil when it carries none.
    private(set) var action: (() -> Void)?
    private var dismissal: Task<Void, Never>?

    /// Four seconds, restarted by a second message — the Reader's own timing, so a toast reads the
    /// same wherever it comes from.
    func show(_ content: ToastContent, action: (() -> Void)? = nil) {
        dismissal?.cancel()
        self.action = action
        withAnimation(.spring(duration: 0.3)) { self.content = content }
        UIAccessibility.post(notification: .announcement, argument: content.title)
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissal?.cancel()
        action = nil
        withAnimation(.easeOut(duration: 0.2)) { content = nil }
    }
}

/// Draws whatever the center is holding. Placed by each surface that can be frontmost when a toast
/// is raised: the root pager, and the Reader over it.
struct ToastHost: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let content = env.toasts.content {
            Toast(content: content,
                  onAction: {
                      let action = env.toasts.action
                      env.toasts.dismiss()
                      action?()
                  },
                  onTap: { env.toasts.dismiss() })
                .padding(.horizontal, Spacing.margin)
        }
    }
}
