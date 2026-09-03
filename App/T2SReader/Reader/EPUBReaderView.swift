import ReadiumAdapterGCDWebServer
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import T2SApp
import T2SCore
import T2SReadium
import UIKit
import WebKit

/// Hosts Readium's EPUB navigator in scroll mode with Inter, decorates the active word with
/// `accentSoft`, auto-scrolls while following, and reports taps as `SourceHit`s.
struct EPUBReaderView: UIViewControllerRepresentable {
    let publication: Publication
    let reader: ReaderModel
    let preferences: ReaderPreferences
    let timeline: Timeline
    let httpServer: GCDHTTPServer
    let onTap: (SourceHit?) -> Void

    static let decorationGroup: DecorationGroup = "t2s"

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        let initial = reader.activeHighlight.flatMap { LocatorMapping.locator(for: $0, in: timeline) }
        let templates = HTMLDecorationTemplate.defaultTemplates(
            defaultTint: UIColor(Tokens.accentSoft), cornerRadius: 4
        )
        let config = EPUBNavigatorViewController.Configuration(
            preferences: Self.preferences(from: preferences, colorScheme: context.environment.colorScheme),
            contentInset: [.compact: (top: Spacing.margin, bottom: 120), .regular: (top: Spacing.margin, bottom: 120)],
            decorationTemplates: templates,
            fontFamilyDeclarations: [Self.interDeclaration()]
        )
        // The ReaderPage presents an error if opening the publication itself fails.
        let navigator = try! EPUBNavigatorViewController(
            publication: publication, initialLocation: initial, config: config, httpServer: httpServer
        )
        navigator.delegate = context.coordinator
        context.coordinator.navigator = navigator
        return navigator
    }

    func updateUIViewController(_ navigator: EPUBNavigatorViewController, context: Context) {
        let coordinator = context.coordinator
        let updatedPreferences = Self.preferences(from: preferences, colorScheme: context.environment.colorScheme)
        if updatedPreferences != coordinator.lastPreferences {
            coordinator.lastPreferences = updatedPreferences
            navigator.submitPreferences(updatedPreferences)
        }

        let highlight = reader.activeHighlight
        if highlight != coordinator.lastHighlight {
            coordinator.lastHighlight = highlight
            var decorations: [Decoration] = []
            if let highlight, let locator = LocatorMapping.locator(for: highlight, in: timeline) {
                decorations.append(Decoration(
                    id: "active", locator: locator,
                    style: .highlight(tint: UIColor(Tokens.accentSoft), isActive: false)
                ))
            }
            navigator.apply(decorations: decorations, in: Self.decorationGroup)
            if reader.isFollowing, let selector = highlight?.position.cssSelector {
                coordinator.scrollToBlock(selector)
            }
        } else if reader.isFollowing, !coordinator.wasFollowing,
                  let selector = highlight?.position.cssSelector {
            coordinator.scrollToBlock(selector)
        }
        coordinator.wasFollowing = reader.isFollowing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(reader: reader, onTap: onTap)
    }

    /// Reader body: Inter 18 × scale, line height 1.5 by default (spec §2.4.1); theme from
    /// preferences and colors from the design tokens.
    static func preferences(from preferences: ReaderPreferences, colorScheme: ColorScheme) -> EPUBPreferences {
        let dark = preferences.theme == .dark || (preferences.theme == .system && colorScheme == .dark)
        var result = EPUBPreferences()
        result.fontFamily = "Inter"
        result.fontSize = 18 * preferences.textScale
        result.lineHeight = preferences.lineHeight
        result.scroll = true
        result.theme = dark ? .dark : .light
        result.backgroundColor = ReadiumNavigator.Color(rawValue: dark ? 0x101010 : 0xF8F8F7)
        result.textColor = ReadiumNavigator.Color(rawValue: dark ? 0xF2F2F2 : 0x111111)
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
    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        let reader: ReaderModel
        let onTap: (SourceHit?) -> Void
        weak var navigator: EPUBNavigatorViewController?
        var lastPreferences: EPUBPreferences?
        var lastHighlight: HighlightRange?
        var wasFollowing = true
        private var programmaticScrollUntil = Date.distantPast

        init(reader: ReaderModel, onTap: @escaping (SourceHit?) -> Void) {
            self.reader = reader
            self.onTap = onTap
        }

        func scrollToBlock(_ selector: String) {
            guard let navigator else { return }
            programmaticScrollUntil = Date().addingTimeInterval(1)
            Task { _ = await navigator.evaluateJavaScript(ReaderScripts.scrollIntoMiddle(selector: selector)) }
        }

        /// A location change we did not cause is a manual scroll and suspends following.
        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            if Date() > programmaticScrollUntil, reader.isFollowing {
                reader.suspendFollowing()
            }
        }

        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            guard let navigator = self.navigator, let href = navigator.currentLocation?.href.string else {
                onTap(nil)
                return
            }
            Task {
                let result = await navigator.evaluateJavaScript(ReaderScripts.hitTest(x: point.x, y: point.y))
                guard case .success(let value) = result,
                      let dictionary = value as? [String: Any],
                      let text = dictionary["text"] as? String,
                      let offset = dictionary["offset"] as? Int
                else {
                    onTap(nil)
                    return
                }
                onTap(SourceHit(
                    resourceHref: ReadiumDocumentReader.resourceKey(href),
                    blockText: text,
                    offsetInBlock: offset
                ))
            }
        }

        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}
        func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {}
    }
}
