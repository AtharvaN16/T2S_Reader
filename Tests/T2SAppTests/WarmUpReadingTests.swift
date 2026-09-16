import Foundation
import Testing
@testable import T2SApp

/// What the warm-up line says, in every state it can be asked about. The three `endsBadly` cases
/// are regressions: until 2026-09-12 a failed download, a failed stage load and a model the reader
/// had deleted all ended on the green "Voice ready", because the status model began its ready beat
/// on any exit from a warming state.
@Suite struct WarmUpReadingTests {

    // MARK: the wait, ending badly

    @Test func aFailedWarmUpDoesNotClaimTheVoiceIsReady() {
        let reading = WarmUpReading(phase: .failed(.warmUp), progress: 0.8)
        #expect(reading.title == "Voice unavailable")
        #expect(reading.tone == .failed)
    }

    @Test func aFailedWarmUpSaysWhatHappensToTheBookInstead() {
        let reading = WarmUpReading(phase: .failed(.warmUp), progress: 0.8)
        #expect(reading.messages == ["reading in the system voice instead"])
    }

    @Test func aFailedDownloadSaysItWillTryAgain() {
        let reading = WarmUpReading(phase: .failed(.install), progress: 0.3)
        #expect(reading.title == "Download failed")
        #expect(reading.messages == ["it will try again next time"])
        #expect(reading.tone == .failed)
    }

    @Test func nothingCountsOnAFailureSoThereIsNoValue() {
        #expect(WarmUpReading(phase: .failed(.warmUp), progress: 0.8).value == nil)
        #expect(WarmUpReading(phase: .failed(.install), progress: 0.3).value == nil)
    }

    @Test func aFailedWaitHoldsTheBarWhereItReached() {
        #expect(WarmUpReading(phase: .failed(.install), progress: 0.34).progress == 0.34)
    }

    // MARK: the wait, ending well

    @Test func aReadyWaitIsGreenAndSaysSo() {
        let reading = WarmUpReading(phase: .ready(buildingBackgroundSet: false), progress: 1)
        #expect(reading.title == "Voice ready")
        #expect(reading.tone == .ready)
        #expect(reading.progress == 1)
    }

    @Test func aReadyWaitHasNothingLeftToSaySoItsRowCollapses() {
        let reading = WarmUpReading(phase: .ready(buildingBackgroundSet: false), progress: 1)
        #expect(reading.messages.isEmpty)
        #expect(reading.value == nil)
        #expect(reading.collapsesSubtext)
    }

    @Test func aReadyWaitStillBuildingInTheBackgroundKeepsItsRow() {
        let reading = WarmUpReading(phase: .ready(buildingBackgroundSet: true), progress: 1)
        #expect(reading.title == "Voice ready")
        #expect(reading.messages == ["finishing up in the background"])
        #expect(!reading.collapsesSubtext)
    }

    // MARK: the download

    @Test func theDownloadCyclesItsOwnThreeMessages() {
        let reading = WarmUpReading(phase: .downloading(received: 120, total: 350), progress: 0.34)
        #expect(reading.messages == ["one-time install", "it might take some time", "almost done"])
    }

    @Test func theDownloadPutsMegabytesInTheValueSlot() {
        let reading = WarmUpReading(phase: .downloading(received: 120, total: 350), progress: 0.34)
        #expect(reading.value == "120 of 350 MB")
    }

    @Test func waitingForWiFiIsNotCountingAnything() {
        let reading = WarmUpReading(phase: .waitingForNetwork, progress: 0)
        #expect(reading.title == "Waiting for Wi-Fi")
        #expect(reading.messages == ["one-time install"])
        #expect(reading.value == nil)
    }

    @Test func aRetryCountsDownForRealAndKeepsThePlace() {
        let reading = WarmUpReading(phase: .retrying(secondsLeft: 6), progress: 0.34)
        #expect(reading.title == "Download interrupted")
        #expect(reading.messages == ["your place is kept"])
        #expect(reading.value == "6s")
    }

    // MARK: the warm-up

    @Test func theWarmUpCyclesItsOwnThreeMessages() {
        let reading = WarmUpReading(phase: .warming(secondsLeft: 90, stalled: false), progress: 0.5)
        #expect(reading.messages == ["it might take some time", "will be faster next time", "almost done"])
    }

    @Test func aShortWarmUpHasNothingWorthCyclingAndShowsOnlyItsClock() {
        let reading = WarmUpReading(phase: .warming(secondsLeft: 8, stalled: false), progress: 0.5)
        #expect(reading.messages.isEmpty)
        #expect(reading.value == "8s")
    }

    @Test func aStalledWarmUpAdmitsItIsStillGoingAndDropsTheClock() {
        let reading = WarmUpReading(phase: .warming(secondsLeft: nil, stalled: true), progress: 0.9)
        #expect(reading.title == "Still warming up")
        #expect(reading.value == nil)
    }

    @Test func checkingHasItsOwnTitleSoAStaleEstimateCannotLeakIn() {
        let reading = WarmUpReading(phase: .checking, progress: 0)
        #expect(reading.title == "Checking the voice")
        #expect(reading.messages.isEmpty)
        #expect(reading.value == nil)
    }

    @Test func theHostedVoiceExplainsWhyTheGlowIsUpOverAudio() {
        let reading = WarmUpReading(phase: .hostedVoiceSpeaking(secondsLeft: 120), progress: 0.5)
        #expect(reading.title == "Reading in the cloud voice")
        #expect(reading.value == "2:00")
    }

    // MARK: the clock's own manners

    @Test func aLongClockCountsInMinutesRatherThanAHundredSeconds() {
        #expect(WarmUpReading(phase: .warming(secondsLeft: 220, stalled: false), progress: 0.2).value == "3:40")
    }

    @Test func aShortClockCountsInSeconds() {
        #expect(WarmUpReading(phase: .warming(secondsLeft: 15, stalled: false), progress: 0.5).value == "15s")
    }

    @Test func aSpentClockGoesRatherThanCountingIntoTheNegative() {
        #expect(WarmUpReading(phase: .warming(secondsLeft: 0, stalled: false), progress: 0.95).value == nil)
    }

    // MARK: cycling

    @Test func aMessageIsHeldForItsWholeDwellBeforeTheNextOne() {
        let reading = WarmUpReading(phase: .downloading(received: 10, total: 350), progress: 0.1)
        #expect(reading.message(elapsed: 0) == "one-time install")
        #expect(reading.message(elapsed: 3.1) == "one-time install")
        #expect(reading.message(elapsed: 3.3) == "it might take some time")
        #expect(reading.message(elapsed: 6.5) == "almost done")
    }

    @Test func theCycleWrapsBackToTheStartWhileThereIsPlentyLeft() {
        let reading = WarmUpReading(phase: .downloading(received: 10, total: 350), progress: 0.1)
        #expect(reading.message(elapsed: 9.7) == "one-time install")
    }

    /// The owner, 2026-09-12: "when we get to almost done, don't cycle away from it."
    @Test func almostDoneIsTheLastThingSaidAndIsNotCycledAwayFrom() {
        let reading = WarmUpReading(phase: .downloading(received: 340, total: 350), progress: 0.97)
        #expect(reading.message(elapsed: 0) == "almost done")
        #expect(reading.message(elapsed: 3.3) == "almost done")
        #expect(reading.message(elapsed: 30) == "almost done")
    }

    @Test func theWarmUpAlsoSticksOnAlmostDone() {
        let reading = WarmUpReading(phase: .warming(secondsLeft: 2, stalled: false), progress: 0.96)
        #expect(reading.message(elapsed: 12) == "almost done")
    }

    @Test func aSingleMessageNeverMoves() {
        let reading = WarmUpReading(phase: .waitingForNetwork, progress: 0)
        #expect(reading.message(elapsed: 0) == "one-time install")
        #expect(reading.message(elapsed: 40) == "one-time install")
    }

    @Test func anEmptyMessageListSaysNothingAtAnyMoment() {
        #expect(WarmUpReading(phase: .checking, progress: 0).message(elapsed: 5) == nil)
    }

    // MARK: the bar

    @Test func aLaunchWithoutAnInstallIsOnePlainBar() {
        let reading = WarmUpReading(phase: .warming(secondsLeft: 15, stalled: false), progress: 0.5)
        #expect(reading.segments == [1])
    }

    @Test func aDownloadIsStillOnePlainBarBecauseItIsOneContinuousCount() {
        let reading = WarmUpReading(phase: .downloading(received: 120, total: 350), progress: 0.34)
        #expect(reading.segments == [1])
    }

    @Test func thePhasesAfterADownloadDivideTheBarInThree() {
        let reading = WarmUpReading(phase: .preparing(step: 3, of: 8, secondsLeft: 40), progress: 0.7)
        #expect(reading.segments.count == 3)
    }

    @Test func preparingNamesTheStepAndKeepsItsClock() {
        let reading = WarmUpReading(phase: .preparing(step: 3, of: 8, secondsLeft: 40), progress: 0.7)
        #expect(reading.title == "Preparing the voice")
        #expect(reading.value == "40s")
    }

    // MARK: the bridge to the band

    @Test func theBandReadingCarriesTheSameWordsAndShape() {
        let warm = WarmUpReading(phase: .downloading(received: 123, total: 350), progress: 0.4)
        let reading = warm.reading
        #expect(reading.kind == .voice)
        #expect(reading.title == warm.title)
        #expect(reading.messages == warm.messages)
        #expect(reading.value == warm.value)
        #expect(reading.segments == warm.segments)
        #expect(reading.tone == .waiting)
        #expect(reading.message(elapsed: 0) == warm.message(elapsed: 0))
        #expect(reading.message(elapsed: 4) == warm.message(elapsed: 4))
    }

    @Test func aFailedWaitCrossesOverAsFailed() {
        #expect(WarmUpReading(phase: .failed(.warmUp), progress: 0.8).reading.tone == .failed)
        #expect(WarmUpReading(phase: .ready(buildingBackgroundSet: false), progress: 1).reading.tone == .ready)
    }
}
