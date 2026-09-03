import ReadiumNavigator
import ReadiumShared
import SwiftUI
import T2SApp
import T2SCore
import T2SLibrary
import UIKit

/// PDF is audio-first with page-level sync (spec §6.1): the navigator follows the active
/// utterance's page; a tap reports the visible page.
struct PDFReaderView: UIViewControllerRepresentable {
    let publication: Publication
    let reader: ReaderModel
    let timeline: Timeline
    let onTap: (SourceHit?) -> Void

    func makeUIViewController(context: Context) -> PDFNavigatorViewController {
        let navigator = try! PDFNavigatorViewController(
            publication: publication, initialLocation: nil, delegate: context.coordinator
        )
        context.coordinator.navigator = navigator
        return navigator
    }

    func updateUIViewController(_ navigator: PDFNavigatorViewController, context: Context) {
        let page = reader.activeHighlight.map { Self.pageIndex(for: $0.position.progression, in: timeline) }
        if reader.isFollowing, let page, page != context.coordinator.lastPage,
           let link = publication.readingOrder.first {
            context.coordinator.lastPage = page
            let count = Self.pageCount(in: timeline)
            let locator = Locator(
                href: link.url(), mediaType: .pdf,
                locations: Locator.Locations(
                    progression: Double(page) / Double(max(1, count)), position: page + 1
                )
            )
            Task { _ = await navigator.go(to: locator, options: NavigatorGoOptions(animated: true)) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    static func pageCount(in timeline: Timeline) -> Int {
        var progressions: Set<Double> = []
        for chapter in timeline.chapters {
            for utterance in chapter.utterances {
                progressions.insert(utterance.position.progression)
            }
        }
        let sorted = progressions.sorted()
        guard sorted.count > 1 else { return 1 }
        let step = zip(sorted, sorted.dropFirst()).map { $1 - $0 }.min() ?? 1
        return step > 0 ? Int((1 / step).rounded()) : 1
    }

    static func pageIndex(for progression: Double, in timeline: Timeline) -> Int {
        Int((progression * Double(pageCount(in: timeline))).rounded())
    }

    @MainActor
    final class Coordinator: NSObject, PDFNavigatorDelegate {
        let onTap: (SourceHit?) -> Void
        weak var navigator: PDFNavigatorViewController?
        var lastPage: Int?

        init(onTap: @escaping (SourceHit?) -> Void) { self.onTap = onTap }

        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            guard let position = self.navigator?.currentLocation?.locations.position else {
                onTap(nil)
                return
            }
            onTap(SourceHit(
                resourceHref: PDFDocumentReader.resourceHref,
                blockText: "",
                offsetInBlock: 0,
                pageIndex: position - 1
            ))
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {}
        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}
    }
}
