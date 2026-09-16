// App/T2SReader/Design/MockIslandCenter.swift
import SwiftUI
import T2SApp
import UIKit

/// The one message the capsule is showing, and what its Play button does.
///
/// Four seconds, restarted by a second message — the same timing as `ToastCenter`, so an
/// announcement reads the same wherever it is drawn.
@MainActor
@Observable
final class MockIslandCenter {
    private(set) var message: ChapterReadyMessage?
    private(set) var cover: ToastContent.Cover?
    /// What the Play button does; nil when the message carries none (a failure).
    private(set) var action: (() -> Void)?
    private var dismissal: Task<Void, Never>?

    func show(_ message: ChapterReadyMessage, cover: ToastContent.Cover?,
              action: (() -> Void)?) {
        dismissal?.cancel()
        self.cover = cover
        self.action = action
        withAnimation(.spring(duration: 0.4)) { self.message = message }
        UIAccessibility.post(notification: .announcement, argument: message.title)
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissal?.cancel()
        action = nil
        withAnimation(.spring(duration: 0.35)) { message = nil }
    }
}
