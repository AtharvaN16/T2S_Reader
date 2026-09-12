import SwiftUI
import T2SApp
import T2SCore
import UIKit

/// The page's text (spec 2026-09-07 §4): one `UITextView` on TextKit 2 showing the whole document,
/// taps mapped to utterances, and following that keeps the spoken word in the middle third. Takes
/// plain values — SwiftUI re-runs `updateUIView` when any of them changes, which is what makes the
/// Appearance sheet work live. Never touch `layoutManager`: reading it downgrades the view to TextKit 1.
///
/// The read-along is a boundary, not a tint (owner, 2026-09-12): everything up to the word being
/// spoken is `ink`, everything after it `inkUnread`, so the page reads as done above and coming
/// below. It is drawn with TextKit 2 *rendering attributes*, which override colour at paint time
/// without touching the text storage — so a word landing costs one fragment's repaint, where the
/// tint it replaced rebuilt two `CAShapeLayer` paths, and no edit ever invalidates layout.
struct ReaderTextView: UIViewRepresentable {
    enum Tap: Equatable {
        case word(utteranceIndex: Int, sourceOffset: Int)
        case elsewhere
    }

    let text: ReaderText
    let textScale: Double
    let lineHeight: Double
    let highlight: HighlightRange?
    let highlightTheme: HighlightTheme
    let isFollowing: Bool
    let onTap: (Tap) -> Void
    let onUserScroll: () -> Void
    /// A passage the reader picked out by hand, to keep: its flattened range and its words.
    var onSaveSelection: ((Range<Int>, String) -> Void)? = nil

    /// Room for the header and the bottom block. The page gives the view `.ignoresSafeArea(edges:
    /// .bottom)`, so the top is measured from the safe-area top and the bottom from the window's:
    /// 112 (14 × 8) clears the header's 68 pt band (16 + 36 + 16) and most of the 48 pt of fade it
    /// hangs below itself; 336 clears the bottom block (chapter row, scrubber, times, transport at
    /// 72, tool row, home-indicator inset ≈ 302) and the near-solid part of the 64 pt of fade it
    /// hangs above itself, so the last line can scroll up to where the ground is faint.
    static let insets = UIEdgeInsets(top: 112, left: Spacing.margin, bottom: 336, right: Spacing.margin)
    static let cornerRadius: CGFloat = 4

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        // Selectable so a press picks out a passage — the highlight is the reader's now, not the
        // read-along's (owner, 2026-09-12). UIKit's own press and double-tap install alongside our
        // tap-to-seek, which is why the coordinator is that recogniser's delegate.
        view.isSelectable = true
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textContainerInset = Self.insets
        view.textContainer.lineFragmentPadding = 0
        // The default before any text arrives; the typeset string then carries `ink` per run, since
        // `textColor` applies to the whole string and would flatten the byline's `ink2`.
        view.textColor = UIColor(Tokens.ink)
        // The selection wears the colour the read-along used to paint (owner, 2026-09-12), set
        // here as well as in `setHighlightTheme` — that one only fires on a *change*, so a reader
        // who never touches the Appearance sheet would have kept the system blue.
        view.tintColor = UIColor(Tokens.highlightWord(highlightTheme))
        view.contentInsetAdjustmentBehavior = .never
        view.verticalScrollIndicatorInsets = UIEdgeInsets(top: Self.insets.top, left: 0, bottom: Self.insets.bottom, right: 0)
        view.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        context.coordinator.tap = tap
        // Rides along with the system's own press, only to watch where it starts and ends.
        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handlePress(_:)))
        press.delegate = context.coordinator
        press.cancelsTouchesInView = false
        press.minimumPressDuration = 0.3
        view.addGestureRecognizer(press)
        _ = view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak coordinator = context.coordinator] (_: UITextView, _: UITraitCollection) in
            coordinator?.restateFade()
        }
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        coordinator.onUserScroll = onUserScroll
        coordinator.onSaveSelection = onSaveSelection
        coordinator.setHighlightTheme(highlightTheme)
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
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var onTap: (Tap) -> Void
        var onUserScroll: () -> Void
        var onSaveSelection: ((Range<Int>, String) -> Void)?
        /// Ours, kept so the text view's own single tap can be made to yield to it.
        weak var tap: UITapGestureRecognizer?
        private weak var view: UITextView?
        private var text: ReaderText?
        private var styleKey: StyleKey?
        private var buildTask: Task<Void, Never>?
        private var highlight: HighlightRange?
        private var highlightTheme: HighlightTheme = .amber
        private var wasFollowing = true
        private var wordRange: Range<Int>?
        /// Flattened offset of the word being spoken: everything before it has been read. Nil before
        /// the first word lands, when the whole document is still "coming".
        private var readBoundary: Int?
        /// The word crossing from unread to read, eased rather than snapped (owner, 2026-09-12).
        private var fade: (range: Range<Int>, from: UIColor, to: UIColor, start: CFTimeInterval)?
        /// Words waiting their turn. Each takes the same `fadeSeconds`, whatever the speech is
        /// doing, so the light travels at one speed instead of hurrying through short words and
        /// dawdling over long ones (owner, 2026-09-12).
        private var fadeQueue: [Range<Int>] = []
        private var fadeLink: CADisplayLink?
        private static let fadeSeconds: CFTimeInterval = 0.22
        /// Past this the reader is ahead of us — a seek, or speech faster than the light. The
        /// backlog lands at once rather than trailing further and further behind the voice.
        private static let fadeBacklog = 3
        /// Centre the word without animation as soon as content exists: the initial build for a
        /// document, or a settings rebuild made while following. A settings rebuild made while
        /// following is suspended never sets this — the page stays where the reader left it.
        private var pendingCentre = true

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
        }

        // MARK: The read/unread boundary

        /// Rendering attributes are set here rather than left to `renderingAttributesValidator`: the
        /// validator is asked once, as a fragment is first laid out, and `invalidateRenderingAttributes`
        /// does not ask it again — measured on the simulator, 744 calls, every one of them before the
        /// first word had landed, and none after (2026-09-12). Setting them directly paints at once.
        ///
        /// Ordinary reading moves the boundary one word: only that word is restated. A first word, a
        /// seek backwards or a rebuild restates the whole document, which is rare and still touches no
        /// layout — rendering attributes are a paint-time override.
        private func setReadBoundary(_ new: Int?) {
            let old = readBoundary
            readBoundary = new
            guard old != new else { return }
            if let old, let new, old < new {
                beginFade(old..<new)
            } else {
                endFade()
                restateFade()
                repaint()
            }
        }

        /// Setting rendering attributes marks them but does not redraw what is already on screen:
        /// measured, the page repainted twice in three and a half seconds of speech, so the boundary
        /// arrived a sentence at a time instead of a word (owner, 2026-09-12). Laying the viewport
        /// out again paints it now — the viewport only, which is the work a scroll already does.
        private func repaint(force: Bool = false) {
            guard let view else { return }
            guard force || (!view.isDragging && !view.isDecelerating) else { return }
            view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        }

        /// States both sides from scratch. Also the light/dark path: the dimmed colour is resolved
        /// when it is set, so a theme change has to set it again.
        // MARK: One word easing across

        /// The word just spoken lifts from `inkUnread` to its own colour over a quarter-second, on
        /// the display's own clock, so the boundary flows rather than stepping (owner, 2026-09-12).
        /// A word arriving while the last is still easing lands it first, so nothing is left part-lit.
        private func beginFade(_ range: Range<Int>) {
            fadeQueue.append(range)
            if fadeQueue.count > Self.fadeBacklog {
                let overdue = fadeQueue.prefix(fadeQueue.count - Self.fadeBacklog)
                overdue.forEach { markRead($0) }
                fadeQueue.removeFirst(overdue.count)
            }
            startNextFade()
        }

        private func startNextFade() {
            guard fade == nil, !fadeQueue.isEmpty else { return }
            let range = fadeQueue.removeFirst()
            guard let traits = view?.traitCollection else { markRead(range); repaint(); return }
            fade = (range,
                    UIColor(Tokens.inkUnread).resolvedColor(with: traits),
                    storageColour(at: range.lowerBound).resolvedColor(with: traits),
                    CACurrentMediaTime())
            if fadeLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(stepFade))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
                link.add(to: .main, forMode: .common)
                fadeLink = link
            }
        }

        @objc private func stepFade() {
            guard let current = fade else { endFade(); return }
            let t = min(1, (CACurrentMediaTime() - current.start) / Self.fadeSeconds)
            if t >= 1 {
                markRead(current.range)
                fade = nil
                startNextFade()
                if fade == nil { endFade(); return }
            } else {
                let eased = t * t * (3 - 2 * t)
                paint(current.from.mixed(with: current.to, by: eased), over: current.range)
            }
            repaint()
        }

        /// Everything read, stated as one run. A word is given a run of its own as it lands, and
        /// those pile up — TextKit consults that map for every fragment it lays out, so scrolling
        /// back over text already read grew slower the longer the book had been playing (owner,
        /// 2026-09-12). Collapsing them is done as a drag begins, not per word: restating the whole
        /// span on every word made the page flicker.
        private func collapseRead() {
            guard let boundary = readBoundary else { return }
            markRead(0..<boundary)
        }

        /// Lands everything outstanding at its final colour and stops the clock.
        private func endFade() {
            fade = nil
            fadeQueue.removeAll()
            collapseRead()
            fadeLink?.invalidate()
            fadeLink = nil
            repaint()
        }

        func restateFade() {
            guard let text else { return }
            guard let boundary = readBoundary else {
                markRead(0..<text.length)                      // nothing read yet reads as nothing dimmed
                return
            }
            markRead(0..<boundary)
            markUnread(boundary..<text.length)
        }

        /// Puts back the colour the run was typeset in. Not `invalidateRenderingAttributes`, which
        /// clears the override but does not repaint what is already on screen — that left a band of
        /// stale dimmed text behind the boundary (seen in dark mode, 2026-09-12). Not a blanket `ink`
        /// either: that would flatten the byline's `ink2`, so each colour run is restated as its own.
        private func markRead(_ range: Range<Int>) {
            guard let manager = view?.textLayoutManager,
                  let content = manager.textContentManager as? NSTextContentStorage,
                  let storage = content.textStorage,
                  range.lowerBound < range.upperBound
            else { return }
            let ns = NSRange(location: range.lowerBound, length: range.upperBound - range.lowerBound)
            guard ns.upperBound <= storage.length else { return }
            storage.enumerateAttribute(.foregroundColor, in: ns) { value, sub, _ in
                guard let textRange = self.textRange(sub.location ..< sub.location + sub.length) else { return }
                manager.setRenderingAttributes([.foregroundColor: (value as? UIColor) ?? UIColor(Tokens.ink)],
                                               for: textRange)
            }
        }

        /// One colour over a range.
        private func paint(_ colour: UIColor, over range: Range<Int>) {
            guard let manager = view?.textLayoutManager, let textRange = textRange(range) else { return }
            manager.setRenderingAttributes([.foregroundColor: colour], for: textRange)
        }

        /// What the run at `offset` was typeset in — `ink`, or the byline's `ink2`.
        private func storageColour(at offset: Int) -> UIColor {
            guard let content = view?.textLayoutManager?.textContentManager as? NSTextContentStorage,
                  let storage = content.textStorage, offset >= 0, offset < storage.length,
                  let colour = storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor
            else { return UIColor(Tokens.ink) }
            return colour
        }

        private func markUnread(_ range: Range<Int>) {
            guard let manager = view?.textLayoutManager, let range = textRange(range) else { return }
            manager.setRenderingAttributes([.foregroundColor: UIColor(Tokens.inkUnread)], for: range)
        }

        /// A flattened-offset range as TextKit's own, or nil if it is empty or out of bounds.
        private func textRange(_ range: Range<Int>) -> NSTextRange? {
            guard range.lowerBound < range.upperBound,
                  let manager = view?.textLayoutManager, let content = manager.textContentManager,
                  let start = content.location(content.documentRange.location, offsetBy: range.lowerBound),
                  let end = content.location(content.documentRange.location, offsetBy: range.upperBound)
            else { return nil }
            return NSTextRange(location: start, end: end)
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
                    // Assigning the string replaces the content storage, so both sides of the
                    // boundary are stated again over the rebuilt document.
                    self.recomputeRanges()
                    self.readBoundary = self.wordRange?.lowerBound ?? self.readBoundary
                    self.restateFade()
                    guard isInitial || following else { return }
                    self.pendingCentre = true
                    self.centreIfNeeded(animated: false)
                    // TextKit 2 estimates the height of text it has not laid out; the first answer can be off.
                    Task { @MainActor [weak self] in
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
                setReadBoundary(wordRange?.lowerBound ?? readBoundary)
            }
            if following, !wasFollowing, let view, view.selectedRange.length > 0 {
                view.selectedRange = NSRange(location: view.selectedRange.location, length: 0)
            }
            if following, changed || !wasFollowing {
                // A centre still pending from the rebuild is the opening one: land on the word
                // rather than flinging to it from the top.
                centreIfNeeded(animated: !pendingCentre)
            }
            wasFollowing = following
        }

        /// The theme now colours the reader's own selection rather than a read-along tint, so it is
        /// the text view's tint: UIKit paints the selection and its handles with it.
        func setHighlightTheme(_ theme: HighlightTheme) {
            guard theme != highlightTheme else { return }
            highlightTheme = theme
            view?.tintColor = UIColor(Tokens.highlightWord(theme))
        }

        private func recomputeRanges() {
            guard let text, let highlight else {
                wordRange = nil
                return
            }
            wordRange = text.wordRange(for: highlight)
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

        // MARK: Following

        private func centreIfNeeded(animated: Bool) {
            guard let view, let wordRange else { return }
            // Never against a finger: inside the stray distance the page is still following, and
            // re-centring mid-drag — or under a selection's handles — would pull it out from
            // under the reader.
            guard !view.isDragging, !view.isDecelerating, view.selectedRange.length == 0 else { return }
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

        /// Where a drag started, so following is only given up once the reader has actually gone
        /// somewhere. Any touch on the page used to hand it over, and "Back to current" appeared on
        /// the slightest nudge (owner, 2026-09-12).
        private var dragOrigin: CGFloat?
        /// Where a long press began. Selecting drags the page along, and once that has carried it a
        /// stray distance you have left your place — but the pill waits for the finger to lift,
        /// rather than appearing over the passage being held (owner, 2026-09-12).
        private var pressOrigin: CGFloat?
        private static let strayDistance: CGFloat = 140

        @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
            guard let view else { return }
            switch gesture.state {
            case .began:
                pressOrigin = view.contentOffset.y
            case .ended, .cancelled, .failed:
                if let origin = pressOrigin, abs(view.contentOffset.y - origin) > Self.strayDistance {
                    onUserScroll()
                }
                pressOrigin = nil
            default:
                break
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            dragOrigin = scrollView.contentOffset.y
            collapseRead()          // the one moment the accumulated runs cost anything
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if pressOrigin == nil, let origin = dragOrigin,
               abs(scrollView.contentOffset.y - origin) > Self.strayDistance {
                dragOrigin = nil
                onUserScroll()
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
            if !willDecelerate { dragOrigin = nil }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            dragOrigin = nil
        }

        // MARK: Selection

        /// Our tap-to-seek sits beside UIKit's own press and double-tap rather than fighting them:
        /// without this the selection recognisers swallow the tap and the page stops seeking.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// Every other single tap waits on ours failing, so tapping a word reaches us first. Asked
        /// this way round rather than by reaching into `view.gestureRecognizers`: a selectable
        /// `UITextView` keeps its text-interaction recognisers on a private subview, so that list
        /// never held them and our tap simply never fired (measured, 2026-09-12).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === tap, let other = other as? UITapGestureRecognizer else { return false }
            return other.numberOfTapsRequired == 1
        }

        /// Keeps the two gestures apart: while a selection is up, a tap is the system's to handle —
        /// ours would mark a word underneath the menu (owner, 2026-09-12).
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === tap else { return true }
            return view.map { $0.selectedRange.length == 0 } ?? true
        }

        /// Following would scroll the page out from under the selection handles.
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.selectedRange.length > 0 else { return }
            // Not `onUserScroll()`: holding a passage is not leaving your place, and giving up
            // following put "Back to current" up on every long press (owner, 2026-09-12).
            // `centreIfNeeded` stands down while a selection is up, which is all this needed.
        }

        /// "Save as bookmark" in front of Look Up, Translate and the rest, which UIKit supplies.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let onSaveSelection,
                  let passage = textView.attributedText?.attributedSubstring(from: range).string,
                  !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let save = UIAction(title: "Save as bookmark", image: UIImage(systemName: "bookmark")) { _ in
                onSaveSelection(range.location ..< range.location + range.length, passage)
                textView.selectedRange = NSRange(location: range.location, length: 0)
            }
            // Copy stays where the hand expects it, first; keeping a passage sits with Look Up,
            // Translate and Share, which are the other things you do with words (owner, 2026-09-12).
            return UIMenu(children: suggestedActions + [save])
        }
    }
}

private extension UIColor {
    /// Straight interpolation between two already-resolved colours, for the word easing across.
    func mixed(with other: UIColor, by t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}
