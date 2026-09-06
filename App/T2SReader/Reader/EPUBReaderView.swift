import ReadiumAdapterGCDWebServer
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import T2SApp
import T2SCore
import T2SReadium
import UIKit
import WebKit

/// Hosts Readium's EPUB navigator in scroll mode with Inter, decorates the active sentence with
/// `accentFaint` and the active word with `accentSoft`, auto-scrolls while following (on word
/// changes only), and reports taps as `SourceHit`s.
struct EPUBReaderView: UIViewControllerRepresentable {
    let publication: Publication
    let reader: ReaderModel
    let preferences: ReaderPreferences
    let timeline: Timeline
    let httpServer: GCDHTTPServer
    let onTap: (SourceHit?) -> Void
    let onError: (String) -> Void
    let onTearDown: () -> Void

    static let decorationGroup: DecorationGroup = "t2s"
    /// A custom style so the sentence tint gets its own opacity: `HTMLDecorationTemplate` bakes one
    /// fixed `alpha` per style into its stylesheet and applies it to every decoration of that style,
    /// discarding each `Decoration`'s own tint alpha — sharing `.highlight` with the word decoration
    /// would render both at the same opacity regardless of which `Tokens` color is passed.
    static let sentenceStyle: Decoration.Style.Id = "sentence"

    func makeUIViewController(context: Context) -> UIViewController {
        let initial = reader.activeHighlight.flatMap { LocatorMapping.locator(for: $0, in: timeline) }
        let padding = UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1)
        let templates: [Decoration.Style.Id: HTMLDecorationTemplate] = [
            .highlight: .highlight(defaultTint: UIColor(Tokens.accentSoft), padding: padding, lineWeight: 2, cornerRadius: 4, alpha: 0.2),
            Self.sentenceStyle: .highlight(defaultTint: UIColor(Tokens.accentFaint), padding: padding, lineWeight: 2, cornerRadius: 4, alpha: 0.08),
        ]
        let config = EPUBNavigatorViewController.Configuration(
            preferences: Self.preferences(from: preferences, colorScheme: context.environment.colorScheme),
            contentInset: [.compact: (top: Spacing.margin, bottom: 120), .regular: (top: Spacing.margin, bottom: 120)],
            decorationTemplates: templates,
            fontFamilyDeclarations: [Self.interDeclaration()]
        )
        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication, initialLocation: initial, config: config, httpServer: httpServer
            )
            navigator.delegate = context.coordinator
            context.coordinator.navigator = navigator
            return navigator
        } catch {
            context.coordinator.report(error)
            return UIViewController()
        }
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        guard let navigator = viewController as? EPUBNavigatorViewController else { return }
        let coordinator = context.coordinator
        let updatedPreferences = Self.preferences(from: preferences, colorScheme: context.environment.colorScheme)
        if updatedPreferences != coordinator.lastPreferences {
            coordinator.lastPreferences = updatedPreferences
            navigator.submitPreferences(updatedPreferences)
        }

        let highlight = reader.activeHighlight
        let sentence = reader.activeSentence
        let locator = highlight.flatMap { LocatorMapping.locator(for: $0, in: timeline) }
        let wordChanged = highlight != coordinator.lastHighlight
        let sentenceChanged = sentence != coordinator.lastSentence
        if wordChanged || sentenceChanged {
            coordinator.lastHighlight = highlight
            coordinator.lastSentence = sentence
            var decorations: [Decoration] = []
            if let sentence, let sentenceLocator = LocatorMapping.locator(for: sentence, in: timeline) {
                decorations.append(Decoration(
                    id: "sentence", locator: sentenceLocator,
                    style: .init(id: Self.sentenceStyle, config: Decoration.Style.HighlightConfig(tint: UIColor(Tokens.accentFaint), isActive: false))
                ))
            }
            if let locator {
                decorations.append(Decoration(
                    id: "word", locator: locator,
                    style: .highlight(tint: UIColor(Tokens.accentSoft), isActive: false)
                ))
            }
            navigator.apply(decorations: decorations, in: Self.decorationGroup)
            // Auto-scroll tracks the word; a sentence-only change (a new sentence starting on the
            // same word, or the reverse) must not re-trigger a scroll.
            if wordChanged, reader.isFollowing, let locator {
                coordinator.scrollToHighlight(locator)
            }
        } else if reader.isFollowing, !coordinator.wasFollowing, let locator {
            coordinator.scrollToHighlight(locator)
        }
        coordinator.wasFollowing = reader.isFollowing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(reader: reader, onTap: onTap, onError: onError, onTearDown: onTearDown)
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    /// Reader body: Inter 18pt × scale, line height 1.5 by default (spec §2.4.1); theme from
    /// preferences and colors from the design tokens. `fontSize` is a ratio to Readium's own base
    /// size (`CSSPercentLength`, 1.0 = 100%), so the spec's 18pt body is `18 / 16 = 1.125` at
    /// scale 1.0 — not `18 * scale`, which renders at 1800%. `publisherStyles` off lets the theme,
    /// font and alignment settings apply instead of the publisher's own CSS (many Readium settings
    /// require it, per its own docs); `paragraphSpacing` is a rem length, not a ratio, and 1.0 sits
    /// mid-way through Readium's 0…2 supported range.
    static func preferences(from preferences: ReaderPreferences, colorScheme: ColorScheme) -> EPUBPreferences {
        let dark = preferences.theme == .dark || (preferences.theme == .system && colorScheme == .dark)
        var result = EPUBPreferences()
        result.fontFamily = "Inter"
        result.fontSize = 1.125 * preferences.textScale
        result.lineHeight = preferences.lineHeight
        result.publisherStyles = false
        result.textAlign = .start
        result.hyphens = false
        result.paragraphSpacing = 1.0
        result.scroll = true
        result.theme = dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        result.backgroundColor = ReadiumNavigator.Color(uiColor: UIColor(Tokens.ground).resolvedColor(with: traits))
        result.textColor = ReadiumNavigator.Color(uiColor: UIColor(Tokens.ink).resolvedColor(with: traits))
        return result
    }

    /// The bundled Inter faces served to the navigator's web view.
    static func interDeclaration() -> AnyHTMLFontFamilyDeclaration {
        func face(_ name: String, weight: CSSStandardFontWeight) -> CSSFontFace? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf"),
                  let file = FileURL(url: url)
            else { return nil }
            return CSSFontFace(file: file, style: .normal, weight: .standard(weight))
        }
        let faces = [
            face("Inter-Regular", weight: .normal),
            face("Inter-Medium", weight: .medium),
            face("Inter-SemiBold", weight: .semiBold),
        ].compactMap { $0 }
        return CSSFontFamilyDeclaration(fontFamily: "Inter", alternates: [.sansSerif], fontFaces: faces)
            .eraseToAnyHTMLFontFamilyDeclaration()
    }

    @MainActor
    final class Coordinator: NSObject, EPUBNavigatorDelegate, WKScriptMessageHandler {
        let reader: ReaderModel
        let onTap: (SourceHit?) -> Void
        let onError: (String) -> Void
        let onTearDown: () -> Void
        weak var navigator: EPUBNavigatorViewController?
        var lastPreferences: EPUBPreferences?
        var lastHighlight: HighlightRange?
        var lastSentence: HighlightRange?
        var wasFollowing = true
        private var programmaticScrollUntil = Date.distantPast
        private var capturedTap: CapturedTap?
        private var hasTornDown = false

        private static let tapMessageName = "t2sReaderTap"

        private struct CapturedTap {
            let hit: SourceHit?
            let date: Date
        }

        init(
            reader: ReaderModel,
            onTap: @escaping (SourceHit?) -> Void,
            onError: @escaping (String) -> Void,
            onTearDown: @escaping () -> Void
        ) {
            self.reader = reader
            self.onTap = onTap
            self.onError = onError
            self.onTearDown = onTearDown
        }

        func report(_ error: Error) { onError("This document can't be displayed: \(error)") }

        /// Drop the cache's ownership only after SwiftUI has dismantled the navigator host. The
        /// navigator may finish deallocating after this point, but still keeps its own publication
        /// reference until then.
        func tearDown() {
            guard !hasTornDown else { return }
            hasTornDown = true
            navigator?.delegate = nil
            navigator = nil
            onTearDown()
        }

        func scrollToHighlight(_ locator: Locator) {
            guard let navigator else { return }
            guard let highlight = locator.text.highlight else { return }
            let selector: String?
            if case .string(let value)? = locator.locations.otherLocations["cssSelector"] {
                selector = value
            } else {
                selector = nil
            }
            programmaticScrollUntil = Date().addingTimeInterval(1)
            Task {
                _ = await navigator.evaluateJavaScript(ReaderScripts.scrollIntoMiddle(
                    selector: selector,
                    before: locator.text.before,
                    highlight: highlight,
                    after: locator.text.after
                ))
            }
        }

        /// A location change we did not cause is a manual scroll and suspends following.
        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            if Date() > programmaticScrollUntil, reader.isFollowing {
                reader.suspendFollowing()
            }
        }

        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            Task { [weak self] in
                // WebKit delivers the resource document's message on the same tap. Yielding gives
                // that message a turn before consuming it without ever treating navigator-space
                // coordinates as resource-local coordinates.
                await Task.yield()
                guard let self else { return }
                guard let capturedTap = self.capturedTap,
                      Date().timeIntervalSince(capturedTap.date) < 0.5
                else {
                    self.onTap(nil)
                    return
                }
                self.capturedTap = nil
                self.onTap(capturedTap.hit)
            }
        }

        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}

        func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
            userContentController.addUserScript(WKUserScript(
                source: ReaderScripts.captureTap,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
            userContentController.add(self, name: Self.tapMessageName)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.tapMessageName,
                  let body = message.body as? [String: Any],
                  let href = body["href"] as? String
            else { return }

            let hit: SourceHit?
            if let text = body["text"] as? String, let offset = body["offset"] as? Int {
                hit = SourceHit(
                    resourceHref: ReadiumDocumentReader.resourceKey(href),
                    blockText: text,
                    offsetInBlock: offset
                )
            } else {
                hit = nil
            }
            capturedTap = CapturedTap(hit: hit, date: Date())
        }
    }
}
