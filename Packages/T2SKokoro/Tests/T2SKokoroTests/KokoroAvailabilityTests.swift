import Foundation
import Testing
@testable import T2SKokoro

/// Serialized: the two tests that use the real files hash 340 MB each, and running them beside the
/// model-backed engine tests would measure disk contention rather than the probe.
@Suite(.serialized) struct KokoroAvailabilityTests {
    // MARK: The cheap checks, in order

    @Test func theSimulatorIsUnavailableWhateverElseTheProbeSees() async {
        let probe = KokoroAvailability.Probe(
            isSimulator: true,
            supportsRequiredGPUFamily: { false },
            resourcesDirectory: Self.nonexistentDirectory(),
            decision: try? KokoroRuntimeDecisionTests.decision()
        )
        #expect(await KokoroAvailability.check(probe) == .unavailable(.simulator))
    }

    @Test func aMachineWithNoMetalDeviceIsUnavailable() async {
        let probe = KokoroAvailability.Probe(
            isSimulator: false,
            supportsRequiredGPUFamily: { nil },
            resourcesDirectory: Self.nonexistentDirectory(),
            decision: try? KokoroRuntimeDecisionTests.decision()
        )
        #expect(await KokoroAvailability.check(probe) == .unavailable(.noMetalDevice))
    }

    @Test func aGPUBelowAppleFamily7IsUnavailable() async {
        let probe = KokoroAvailability.Probe(
            isSimulator: false,
            supportsRequiredGPUFamily: { false },
            resourcesDirectory: Self.nonexistentDirectory(),
            decision: try? KokoroRuntimeDecisionTests.decision()
        )
        #expect(await KokoroAvailability.check(probe) == .unavailable(.gpuFamilyUnsupported))
    }

    /// With no resource directory at all, reaching `.noRuntimeDecision` proves the decision is
    /// checked before anything looks at the files.
    @Test func aMissingRuntimeDecisionIsCheckedBeforeTheFiles() async {
        let probe = KokoroAvailability.Probe(
            isSimulator: false,
            supportsRequiredGPUFamily: { true },
            resourcesDirectory: nil,
            decision: nil
        )
        #expect(await KokoroAvailability.check(probe) == .unavailable(.noRuntimeDecision))
    }

    @Test func aDirectoryWithoutTheModelReportsTheFileThatIsMissing() async throws {
        let directory = Self.nonexistentDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let probe = KokoroAvailability.Probe(
            isSimulator: false,
            supportsRequiredGPUFamily: { true },
            resourcesDirectory: directory,
            decision: try KokoroRuntimeDecisionTests.decision()
        )
        #expect(await KokoroAvailability.check(probe)
            == .unavailable(.resources(.missing("kokoro-v1_0.safetensors"))))
    }

    /// The app's own inputs. `Bundle.main` here is the `xctest` tool, which carries no model, so the
    /// live probe finds no resource directory — the check that the bundle lookup is wired up at all.
    @Test func theLiveProbeReadsThisMachine() {
        let probe = KokoroAvailability.Probe.live()
        #expect(probe.isSimulator == false)
        #expect(probe.supportsRequiredGPUFamily() == true)
        #expect(probe.resourcesDirectory == nil)
    }

    // MARK: The installed files

    @Test(.enabled(if: KokoroTestSupport.haveRealFiles))
    func theInstalledFilesAndACompleteDecisionAreAvailable() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let decision = try KokoroRuntimeDecisionTests.decision()
        let probe = KokoroAvailability.Probe(
            isSimulator: false,
            supportsRequiredGPUFamily: { true },
            resourcesDirectory: KokoroResources.developmentDirectory,
            decision: decision
        )
        let located = try KokoroResources.locate(in: KokoroResources.developmentDirectory).get()
        #expect(await KokoroAvailability.check(probe) == .available(decision: decision, resources: located))
    }

    @Test(.enabled(if: KokoroTestSupport.haveRealFiles))
    func aDamagedVoiceTableOfTheRightSizeIsCaughtByTheChecksum() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let directory = Self.nonexistentDirectory()
        try Self.makeDirectoryWithADamagedVoiceTable(at: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let probe = KokoroAvailability.Probe(
            isSimulator: false,
            supportsRequiredGPUFamily: { true },
            resourcesDirectory: directory,
            decision: try KokoroRuntimeDecisionTests.decision()
        )
        #expect(await KokoroAvailability.check(probe)
            == .unavailable(.resources(.checksumMismatch("voices.npz"))))
    }

    // MARK: Helpers

    /// A path under the system temporary directory that nothing has created.
    private static func nonexistentDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appending(path: "KokoroAvailabilityTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// A directory holding the real model — hard-linked, so 327 MB is not copied — beside a copy of
    /// `voices.npz` with one byte changed. The copy keeps its size, so `locate` passes and only the
    /// hash catches it.
    private static func makeDirectoryWithADamagedVoiceTable(at directory: URL) throws {
        let fileManager = FileManager.default
        let real = try KokoroResources.locate(in: KokoroResources.developmentDirectory).get()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let model = directory.appending(path: KokoroResources.modelFileName)
        do { try fileManager.linkItem(at: real.model, to: model) }
        catch { try fileManager.copyItem(at: real.model, to: model) }

        let voices = directory.appending(path: KokoroResources.voicesFileName)
        try fileManager.copyItem(at: real.voices, to: voices)
        let handle = try FileHandle(forUpdating: voices)
        defer { try? handle.close() }
        try handle.seek(toOffset: 1024)
        guard let original = try handle.read(upToCount: 1)?.first else {
            throw KokoroResources.Failure.missing(KokoroResources.voicesFileName)
        }
        try handle.seek(toOffset: 1024)
        try handle.write(contentsOf: Data([original ^ 0xFF]))
    }
}
