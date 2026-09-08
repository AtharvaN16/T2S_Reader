import SwiftUI
import T2SApp
import T2SCore
import UIKit

/// The page's text (spec 2026-09-07 §4): one `UITextView` on TextKit 2 showing the whole document,
/// the paragraph and word tints drawn as rounded rectangles under the glyphs, taps mapped to
/// utterances, and following that keeps the spoken word in the middle third. Takes plain values —
/// SwiftUI re-runs `updateUIView` when any of them changes, which is what makes the Appearance
/// sheet work live. Never touch `layoutManager`: reading it downgrades the view to TextKit 1.
struct ReaderTextView: UIViewRepresentable {
    enum Tap: Equatable {
        case word(utteranceIndex: Int, sourceOffset: Int)
        case elsewhere
    }

    let text: ReaderText
    let textScale: Double
    let lineHeight: Double
    let highlight: HighlightRange?
    let isFollowing: Bool
    let onTap: (Tap) -> Void
    let onUserScroll: () -> Void

    /// Room for the floating top circles and the three-row bottom block. The page gives the view
    /// `.ignoresSafeArea(edges: .bottom)`, so the top is measured from the safe-area top and the
    /// bottom from the window's: 96 (12 × 8) clears the top band's 150 pt on an iPhone 16 Pro
    /// (59 + 96) and leaves only the last few points of its fade over the first line on an
    /// iPhone 11 Pro (44 + 96); 240 clears the scrubber, times, transport and tool rows.
    static let insets = UIEdgeInsets(top: 96, left: Spacing.margin, bottom: 240, right: Spacing.margin)
    static let cornerRadius: CGFloat = 4

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textContainerInset = Self.insets
        view.textContainer.lineFragmentPadding = 0
        // The default before any text arrives; the typeset string then carries `ink` per run, since
        // `textColor` applies to the whole string and would flatten the byline's `ink2`.
        view.textColor = UIColor(Tokens.ink)
        view.contentInsetAdjustmentBehavior = .never
        view.verticalScrollIndicatorInsets = UIEdgeInsets(top: Self.insets.top, left: 0, bottom: Self.insets.bottom, right: 0)
        view.delegate = context.coordinator
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:))))
        _ = view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak coordinator = context.coordinator] (_: UITextView, _: UITraitCollection) in
            coordinator?.redrawHighlight()
        }
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        coordinator.onUserScroll = onUserScroll
        coordinator.setText(text, scale: textScale, lineHeight: lineHeight, following: isFollowing)
        coordinator.setHighlight(highlight, following: isFollowing)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onUserScroll: onUserScroll)
    }

    /// Crosses from the build task to the main actor: the string is immutable once built and
    /// nothing else holds it.
    private struct Typeset: @unchecked Sendable {
        let string: NSAttributedString
    }

    private struct StyleKey: Equatable {
        var documentID: UUID
        var scale: Double
        var lineHeight: Double
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var onTap: (Tap) -> Void
        var onUserScroll: () -> Void
        private weak var view: UITextView?
        private var text: ReaderText?
        private var styleKey: StyleKey?
        private var buildTask: Task<Void, Never>?
        private var highlight: HighlightRange?
        private var wasFollowing = true
        private var wordRange: Range<Int>?
        private var tintRange: Range<Int>?
        /// Centre the word without animation as soon as content exists: the initial build for a
        /// document, or a settings rebuild made while following. A settings rebuild made while
        /// following is suspended never sets this — the page stays where the reader left it.
        private var pendingCentre = true
        /// Sits under the text canvas (subview index 0); its bounds origin tracks the content offset so
        /// paths in content coordinates draw in place with no transforms.
        private let overlay = UIView()
        private let tintLayer = CAShapeLayer()
        private let wordLayer = CAShapeLayer()

        init(onTap: @escaping (Tap) -> Void, onUserScroll: @escaping () -> Void) {
            self.onTap = onTap
            self.onUserScroll = onUserScroll
        }

        /// The page went away mid-typeset: stop it rather than finish a book nobody will read.
        deinit {
            buildTask?.cancel()
        }

        func attach(_ view: UITextView) {
            self.view = view
            overlay.isUserInteractionEnabled = false
            overlay.backgroundColor = .clear
            overlay.layer.addSublayer(tintLayer)
            overlay.layer.addSublayer(wordLayer)
            view.insertSubview(overlay, at: 0)
            syncOverlay()
        }

        // MARK: Text

        /// Builds the attributed text for a new document or for a text-setting change. The
        /// **initial** build for a document — the coordinator had no text before, or the document
        /// id changed — always centres the active word once content lands, as does a **rebuild**
        /// made while `following`. A rebuild made while following is suspended (the `Back to
        /// current` pill showing) leaves `pendingCentre` and the content offset alone, so a
        /// text-size or line-height change does not yank the page back to the spoken word; the
        /// tints still track the new layout because `recomputeRanges()`/`redrawHighlight()` always run.
        func setText(_ text: ReaderText, scale: Double, lineHeight: Double, following: Bool) {
            let key = StyleKey(documentID: text.documentID, scale: scale, lineHeight: lineHeight)
            guard key != styleKey else { return }
            let isInitial = self.text == nil || styleKey?.documentID != key.documentID
            styleKey = key
            buildTask?.cancel()
            let inkColor = UIColor(Tokens.ink)
            let bylineColor = UIColor(Tokens.ink2)
            buildTask = Task.detached(priority: .userInitiated) { [text] in
                guard let string = ReaderTypesetter.attributedString(
                    for: text, scale: scale, lineHeight: lineHeight, inkColor: inkColor, bylineColor: bylineColor)
                else { return }
                let typeset = Typeset(string: string)
                await MainActor.run { [weak self] in
                    guard let self, self.styleKey == key, let view = self.view else { return }
                    self.text = text
                    view.attributedText = typeset.string
                    self.recomputeRanges()
                    self.redrawHighlight()
                    guard isInitial || following else { return }
                    self.pendingCentre = true
                    self.centreIfNeeded(animated: false)
                    // TextKit 2 estimates the height of text it has not laid out; the first answer can be off.
                    Task { @MainActor [weak self] in
                        self?.redrawHighlight()
                        self?.centreIfNeeded(animated: false)
                    }
                }
            }
        }

        // MARK: Highlight

        func setHighlight(_ highlight: HighlightRange?, following: Bool) {
            let changed = highlight != self.highlight
            self.highlight = highlight
            if changed {
                recomputeRanges()
                redrawHighlight()
            }
            if following, changed || !wasFollowing {
                // A centre still pending from the rebuild is the opening one: land on the word
                // rather than flinging to it from the top.
                centreIfNeeded(animated: !pendingCentre)
            }
            wasFollowing = following
        }

        private func recomputeRanges() {
            guard let text, let highlight else {
                wordRange = nil
                tintRange = nil
                return
            }
            wordRange = text.wordRange(for: highlight)
            tintRange = text.tintRange(forUtterance: highlight.utteranceIndex)
        }

        func redrawHighlight() {
            guard let view else { return }
            let traits = view.traitCollection
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tintLayer.fillColor = UIColor(Tokens.accentFaint).resolvedColor(with: traits).cgColor
            wordLayer.fillColor = UIColor(Tokens.accentSoft).resolvedColor(with: traits).cgColor
            tintLayer.path = tintRange.flatMap { path(for: rects(for: $0), padding: 0) }
            wordLayer.path = wordRange.flatMap { path(for: rects(for: $0), padding: 1) }
            syncOverlay()
            CATransaction.commit()
        }

        private func path(for rects: [CGRect], padding: CGFloat) -> CGPath? {
            guard !rects.isEmpty else { return nil }
            let path = UIBezierPath()
            for rect in rects {
                path.append(UIBezierPath(roundedRect: rect.insetBy(dx: -padding, dy: 0), cornerRadius: ReaderTextView.cornerRadius))
            }
            return path.cgPath
        }

        /// Per-line rectangles of a flattened-string range, in content coordinates.
        private func rects(for range: Range<Int>) -> [CGRect] {
            guard let view, let layoutManager = view.textLayoutManager,
                  let contentManager = layoutManager.textContentManager,
                  let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.lowerBound),
                  let end = contentManager.location(contentManager.documentRange.location, offsetBy: range.upperBound),
                  let textRange = NSTextRange(location: start, end: end)
            else { return [] }
            layoutManager.ensureLayout(for: textRange)
            let inset = view.textContainerInset
            var rects: [CGRect] = []
            layoutManager.enumerateTextSegments(in: textRange, type: .highlight, options: [.rangeNotRequired]) { _, frame, _, _ in
                rects.append(frame.offsetBy(dx: inset.left, dy: inset.top))
                return true
            }
            return rects
        }

        private func syncOverlay() {
            guard let view else { return }
            overlay.frame = view.bounds
            overlay.bounds = CGRect(origin: view.contentOffset, size: view.bounds.size)
        }

        // MARK: Following

        private func centreIfNeeded(animated: Bool) {
            guard let view, let wordRange else { return }
            let rects = rects(for: wordRange)
            guard let first = rects.first else { return }
            let word = rects.dropFirst().reduce(first) { $0.union($1) }
            let insets = ReaderTextView.insets
            let visibleHeight = max(1, view.bounds.height - insets.top - insets.bottom)
            let visibleTop = view.contentOffset.y + insets.top
            let mid = word.midY
            if !pendingCentre, mid >= visibleTop + visibleHeight / 3, mid <= visibleTop + 2 * visibleHeight / 3 { return }
            pendingCentre = false
            let maxOffset = max(0, view.contentSize.height - view.bounds.height)
            let target = min(maxOffset, max(0, mid - insets.top - visibleHeight / 2))
            view.setContentOffset(CGPoint(x: 0, y: target), animated: animated)
        }

        // MARK: Taps

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view, let text, let layoutManager = view.textLayoutManager,
                  let contentManager = layoutManager.textContentManager
            else { onTap(.elsewhere); return }
            var point = gesture.location(in: view)
            point.x -= view.textContainerInset.left
            point.y -= view.textContainerInset.top
            guard let fragment = layoutManager.textLayoutFragment(for: point),
                  let element = fragment.textElement, let elementRange = element.elementRange
            else { onTap(.elsewhere); return }
            let local = CGPoint(x: point.x - fragment.layoutFragmentFrame.minX, y: point.y - fragment.layoutFragmentFrame.minY)
            guard let line = fragment.textLineFragments.first(where: { $0.typographicBounds.insetBy(dx: -8, dy: -8).contains(local) })
            else { onTap(.elsewhere); return }
            // Line-fragment indices are relative to the text element (the paragraph).
            let elementStart = contentManager.offset(from: contentManager.documentRange.location, to: elementRange.location)
            let index = line.characterIndex(for: CGPoint(x: local.x - line.typographicBounds.minX, y: local.y - line.typographicBounds.minY))
            let clamped = min(max(index, line.characterRange.location), line.characterRange.location + max(0, line.characterRange.length - 1))
            if let hit = text.hit(at: elementStart + clamped) {
                onTap(.word(utteranceIndex: hit.utteranceIndex, sourceOffset: hit.sourceOffset))
            } else {
                onTap(.elsewhere)
            }
        }

        // MARK: UIScrollViewDelegate

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            onUserScroll()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncOverlay()
        }
    }
}
