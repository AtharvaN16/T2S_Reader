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
    let onError: (String) -> Void
    let onTearDown: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        do {
            let navigator = try PDFNavigatorViewController(
                publication: publication, initialLocation: nil, delegate: context.coordinator
            )
            context.coordinator.navigator = navigator
            context.coordinator.beginFollowingNavigation()
            return navigator
        } catch {
            context.coordinator.report(error)
            return UIViewController()
        }
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        guard let navigator = viewController as? PDFNavigatorViewController else { return }
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
            context.coordinator.go(navigator, to: locator)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(reader: reader, onTap: onTap, onError: onError, onTearDown: onTearDown)
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.tearDown()
    }

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
        let reader: ReaderModel
        let onTap: (SourceHit?) -> Void
        let onError: (String) -> Void
        let onTearDown: () -> Void
        weak var navigator: PDFNavigatorViewController?
        var lastPage: Int?
        private var programmaticNavigationUntil = Date.distantPast
        private var hasTornDown = false

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

        /// Cache ownership ends when the hosted navigator leaves the SwiftUI hierarchy. The
        /// navigator retains its publication independently until it finishes deallocating.
        func tearDown() {
            guard !hasTornDown else { return }
            hasTornDown = true
            navigator?.delegate = nil
            navigator = nil
            onTearDown()
        }

        func beginFollowingNavigation() {
            programmaticNavigationUntil = Date().addingTimeInterval(1)
        }

        func go(_ navigator: PDFNavigatorViewController, to locator: Locator) {
            beginFollowingNavigation()
            Task { _ = await navigator.go(to: locator, options: NavigatorGoOptions(animated: true)) }
        }

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

        /// A page turn outside the automatic-following window is user navigation. Clearing the
        /// cached target lets Back to current re-send the active audio page even when it is the
        /// same page we previously followed.
        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            if Date() > programmaticNavigationUntil, reader.isFollowing {
                reader.suspendFollowing()
                lastPage = nil
            }
        }
        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}
    }
}
