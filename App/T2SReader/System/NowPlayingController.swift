import Foundation
import MediaPlayer
import T2SApp
import T2SCore
import T2SLibrary
import UIKit

/// The app-target boundary for Lock Screen and Control Center integration. Playback state remains
/// owned by `PlaybackCoordinator`; this class only translates it to and from MediaPlayer.
@MainActor
final class NowPlayingController {
    private let player: PlayerModel
    private let libraryModel: LibraryModel
    private let preferences: ReaderPreferences
    private let paths: LibraryPaths
    private let center = MPNowPlayingInfoCenter.default()
    private let commands = MPRemoteCommandCenter.shared()
    private var commandTargets: [(command: MPRemoteCommand, token: Any)] = []
    private var artworkCache: [UUID: MPMediaItemArtwork] = [:]
    /// Artwork handlers are formed off the main actor (`NowPlayingArtwork`): MediaPlayer calls them
    /// on its own queue, and a main-actor-isolated handler traps there.
    private lazy var fallbackArtwork: MPMediaItemArtwork = {
        let image = UIImage(systemName: "book.closed.fill")!
        return NowPlayingArtwork.make(image)
    }()
    /// MediaPlayer extrapolates elapsed time from the value and playback rate, so only a new
    /// playing second merits a ticker-driven update.
    private var lastPublishedPlayingSecond: Int?
    private var lastPublishedSnapshot: NowPlayingSnapshot?
    /// A deleted document can remain in the coordinator while it winds down. Keep it off the Lock
    /// Screen until a different document is loaded instead of letting the ticker republish stale
    /// metadata.
    private var clearedDocumentID: UUID?
    private var started = false

    init(player: PlayerModel, libraryModel: LibraryModel, preferences: ReaderPreferences, paths: LibraryPaths) {
        self.player = player
        self.libraryModel = libraryModel
        self.preferences = preferences
        self.paths = paths
    }

    func start() {
        guard !started else { return }
        started = true
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: preferences.skipBackSeconds)]
        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: preferences.skipForwardSeconds)]
        commands.changePlaybackRateCommand.supportedPlaybackRates = player.coordinator.availableRates.map { NSNumber(value: $0) }

        addTarget(to: commands.playCommand) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.player.current != nil else { return .commandFailed }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.player.coordinator.play()
                    self.update()
                }
                return .success
            }
        }
        addTarget(to: commands.pauseCommand) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.player.current != nil else { return .commandFailed }
                self.player.coordinator.pause()
                self.update()
                return .success
            }
        }
        addTarget(to: commands.togglePlayPauseCommand) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.player.current != nil else { return .commandFailed }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.player.togglePlay()
                    self.update()
                }
                return .success
            }
        }
        addTarget(to: commands.skipBackwardCommand) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.player.current != nil,
                      let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.player.skip(by: -event.interval)
                    self.update()
                }
                return .success
            }
        }
        addTarget(to: commands.skipForwardCommand) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.player.current != nil,
                      let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.player.skip(by: event.interval)
                    self.update()
                }
                return .success
            }
        }
        addTarget(to: commands.changePlaybackRateCommand) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.player.current != nil,
                      let event = event as? MPChangePlaybackRateCommandEvent,
                      let rate = NowPlayingSnapshot.acceptedRate(Double(event.playbackRate),
                                                                 available: self.player.coordinator.availableRates) else {
                    return .commandFailed
                }
                self.player.setRate(rate)
                self.update()
                return .success
            }
        }
        addTarget(to: commands.changePlaybackPositionCommand) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.player.current != nil,
                      let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                let position = NowPlayingSnapshot.clampedSeek(event.positionTime, duration: self.player.total)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.player.coordinator.seek(toTime: position)
                    self.update()
                }
                return .success
            }
        }
        addTarget(to: commands.seekBackwardCommand) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.player.current != nil,
                      let event = event as? MPSeekCommandEvent else { return .commandFailed }
                guard event.type == .endSeeking else { return .success }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.player.skip(by: -Double(self.preferences.skipBackSeconds))
                    self.update()
                }
                return .success
            }
        }
        addTarget(to: commands.seekForwardCommand) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.player.current != nil,
                      let event = event as? MPSeekCommandEvent else { return .commandFailed }
                guard event.type == .endSeeking else { return .success }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.player.skip(by: Double(self.preferences.skipForwardSeconds))
                    self.update()
                }
                return .success
            }
        }

        commands.previousTrackCommand.isEnabled = false
        commands.nextTrackCommand.isEnabled = false
        commands.changeRepeatModeCommand.isEnabled = false
        commands.changeShuffleModeCommand.isEnabled = false
        commands.ratingCommand.isEnabled = false
        commands.likeCommand.isEnabled = false
        commands.dislikeCommand.isEnabled = false
        commands.bookmarkCommand.isEnabled = false
    }

    /// Publishes the one current document, or clears an item no longer present in the player.
    func update() {
        guard let current = player.current else {
            clear()
            return
        }
        guard clearedDocumentID != current.id else { return }
        clearedDocumentID = nil
        let timeline = player.coordinator.timeline
        let queue = libraryModel.queue
        let snapshot = NowPlayingSnapshot(
            title: current.document.title,
            author: current.document.author ?? "",
            duration: player.total,
            elapsed: player.elapsed,
            rate: player.coordinator.rate,
            isPlaying: player.isPlaying,
            chapterIndex: player.chapterIndex,
            chapterCount: timeline?.chapters.count ?? current.chapterCount,
            queueIndex: queue.firstIndex(where: { $0.id == current.id }),
            queueCount: queue.count
        )
        update(snapshot, artwork: artwork(for: current.document))
    }

    func update(_ snapshot: NowPlayingSnapshot, artwork: MPMediaItemArtwork?) {
        let playingSecond = Int(snapshot.elapsed.rounded(.down))
        if let last = lastPublishedSnapshot {
            var withoutElapsed = snapshot
            var lastWithoutElapsed = last
            withoutElapsed.elapsed = 0
            lastWithoutElapsed.elapsed = 0
            if snapshot.isPlaying, last.isPlaying, withoutElapsed == lastWithoutElapsed,
               lastPublishedPlayingSecond == playingSecond {
                return
            }
            if !snapshot.isPlaying, last == snapshot { return }
        }
        lastPublishedPlayingSecond = playingSecond
        lastPublishedSnapshot = snapshot

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: snapshot.author,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: snapshot.defaultPlaybackRate,
            MPNowPlayingInfoPropertyChapterCount: snapshot.chapterCount,
            MPNowPlayingInfoPropertyPlaybackQueueCount: snapshot.queueCount,
        ]
        if let chapter = snapshot.chapterNumber { info[MPNowPlayingInfoPropertyChapterNumber] = chapter }
        if let index = snapshot.queueIndex { info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = snapshot.isPlaying ? .playing : .paused
    }

    func clear() {
        center.nowPlayingInfo = nil
        lastPublishedPlayingSecond = nil
        lastPublishedSnapshot = nil
        clearedDocumentID = player.current?.id
    }

    deinit {
        MainActor.assumeIsolated {
            for target in commandTargets { target.command.removeTarget(target.token) }
        }
    }

    private func addTarget(to command: MPRemoteCommand,
                           handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        commandTargets.append((command, command.addTarget(handler: handler)))
    }

    private func artwork(for document: Document) -> MPMediaItemArtwork {
        if let cached = artworkCache[document.id] { return cached }
        let path = document.coverImagePath.map(paths.url(forRelativePath:)) ?? paths.coverURL(document.id)
        guard let image = UIImage(contentsOfFile: path.path) else { return fallbackArtwork }
        let artwork = NowPlayingArtwork.make(image)
        artworkCache[document.id] = artwork
        return artwork
    }
}
