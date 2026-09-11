import CoreML
import Foundation
import Testing
@testable import T2SKokoro

/// `MLComputePlan` over the staged Core ML stages: for each compute-unit policy, where Core ML
/// would place every operation of a stage's MIL program, what each is estimated to cost, and how
/// long the plan took to build. Written for one question from the iPhone 17 Pro (docs/HANDOFF.md,
/// "The phone answered", 2026-09-10): why the A19 Pro's CPU plan compiler never finishes
/// `kokoro_decoder_har_post_15s`, a stage the A13 builds in about a minute. The per-op placement
/// under `.cpuAndGPU` says which operators the CPU cannot take at all and which carry the weight;
/// the `.cpu` row says whether the plan itself can be built for the CPU there, and how long that
/// takes (docs/research/2026-09-10-on-device-models-on-old-and-new-phones.md, item 9). The plan
/// load is the compiler's segmentation and cost estimate; `MLModel.load`, which the app pays, is
/// the same compile plus the backend's specialization, so a plan that takes minutes here is a
/// stage the app cannot warm up on that policy either.
///
/// Not a test of anything. It is `.enabled` only while it is asked for:
///
/// - **On this Mac**, by `spikes/findings/compute-plan-probe/` existing. `scripts/compute-plan-probe.sh`
///   creates it, writes the settings below into `probe.env` there, and runs this suite alone through
///   `xcodebuild` (`-only-testing:T2SKokoroTests/KokoroComputePlanProbe`). The environment does not
///   reach a macOS unit-test process (see `scripts/test-kokoro.sh`), which is why the settings travel
///   as a file. Needs the staged `.mlpackage`s (`scripts/fetch-kokoro-coreml.sh --app`); only the
///   stages asked for are compiled, into the `.build/compiled-stages-<revision>` directory the other
///   model-backed tests share, so nothing is compiled twice either way. Expect a couple of minutes
///   per stage for `cpuAndGPU` and `cpu`, and five to nine minutes for `all`, which spends them
///   failing the generator's Neural Engine compile before it falls back (`scripts/compute-probe.sh`,
///   2026-09-10) — `--policies cpuAndGPU,cpu` skips it.
///
/// - **On a phone** (Harsh's 17 Pro), by the environment variable `KOKORO_COMPUTE_PLAN_PROBE=1`.
///   From `Packages/T2SKokoro`, with the phone paired and on Wi-Fi:
///
///       xcodebuild test -scheme T2SKokoro -destination 'platform=iOS,id=<UDID>' \
///         -only-testing:T2SKokoroTests/KokoroComputePlanProbe \
///         -allowProvisioningUpdates DEVELOPMENT_TEAM=<team> CODE_SIGN_STYLE=Automatic \
///         -derivedDataPath .build/DerivedData-iOS \
///         TEST_RUNNER_KOKORO_COMPUTE_PLAN_PROBE=1 2>&1 | grep 'kokoro compute plan'
///
///   `xcodebuild` hands every `TEST_RUNNER_`-prefixed variable to the test runner it installs on the
///   device, so the other settings travel the same way (`TEST_RUNNER_KOKORO_COMPUTE_PLAN_STAGES=all`).
///   From Xcode instead: open `Packages/T2SKokoro/Package.swift`, choose the phone, Product → Scheme →
///   Edit Scheme → Test → Arguments → Environment Variables, add `KOKORO_COMPUTE_PLAN_PROBE` = `1`
///   (and any other setting), then run this suite alone from the test navigator. The phone has no
///   checkout, so the probe fetches the requested stage's three files from the pinned Hugging Face
///   revision (`KokoroCoreMLManifest`, through the installer's own Wi-Fi downloader; about 40 MB for
///   the generator, a weight file shared by another bucket copied rather than fetched again) into the
///   test runner's Caches, compiles them there, and keeps both for the next run. Neither recipe has
///   been run from this Mac: it has no phone, and the device test bundle — the app's own frameworks
///   plus MLX's Metal library staged for a test runner — has not been built here before.
///
/// Settings, as environment variables on a phone and as `KEY=VALUE` lines in `probe.env` on the Mac:
///
/// - `KOKORO_COMPUTE_PLAN_STAGES`: comma-separated stage names, or `all` for the fourteen; default
///   `kokoro_decoder_har_post_15s`.
/// - `KOKORO_COMPUTE_PLAN_POLICIES`: comma-separated `KokoroComputeUnits` raw values (`cpu`,
///   `cpuAndGPU`, `cpuAndNeuralEngine`, `all`); default `cpuAndGPU,cpu,all` in that order — the
///   phone's own policy first, then the one that never finished there, then the Neural Engine
///   attempt — because a plan that runs past the timeout keeps running in this process (see
///   ``plan(_:stage:policy:timeout:)``) and would skew whatever came after it.
/// - `KOKORO_COMPUTE_PLAN_TIMEOUT`: seconds one plan may take before the probe gives up on it and
///   moves on; default 900 — the A19's CPU compile of the generator was still running at twenty
///   minutes, so this bounds the run without hiding a compile that merely takes long.
/// - `KOKORO_COMPUTE_PLAN_MODELS`: a directory holding `<stage>.mlmodelc` (or `<stage>.mlpackage`,
///   compiled on the way) to read instead of the staging above.
///
/// Every line is printed with the prefix `kokoro compute plan`, so `grep` finds them in
/// `xcodebuild`'s output, through an unbuffered write, so a run stopped early still shows what it
/// had. The summary lines also go to `report.md` in the output directory, rewritten after every
/// plan, and each plan's per-operation listing to `ops-<stage>-<policy>.txt` beside it. The output
/// directory is `spikes/findings/compute-plan-probe/` on the Mac and the test runner's Caches on a
/// phone; its path is the first line printed.
@Suite(.serialized) struct KokoroComputePlanProbe {
    static let defaultStage = "kokoro_decoder_har_post_15s"
    static let defaultPolicies: [KokoroComputeUnits] = [.cpuAndGPU, .cpu, .all]
    static let defaultTimeoutSeconds = 900.0
    static let linePrefix = "kokoro compute plan"

    /// `<repo>/spikes/findings/compute-plan-probe` on the Mac; the test runner's Caches on a phone,
    /// which has no checkout. This file is
    /// `<repo>/Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroComputePlanProbe.swift`.
    static let outputDirectory: URL = {
        #if os(iOS)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appending(path: "compute-plan-probe", directoryHint: .isDirectory)
        #else
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "spikes/findings/compute-plan-probe", directoryHint: .isDirectory)
        #endif
    }()

    /// Where a compiled stage is kept between runs. On the Mac it is the directory
    /// `KokoroTestSupport.compiledCoreMLResources()` fills, under the same names, so a stage compiled
    /// by either is found by the other.
    static let compiledDirectory: URL = {
        #if os(iOS)
        return outputDirectory.appending(path: "compiled", directoryHint: .isDirectory)
        #else
        var package = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { package.deleteLastPathComponent() }
        return package.appending(path: ".build/compiled-stages-\(KokoroCoreMLResources.revisionPrefix)", directoryHint: .isDirectory)
        #endif
    }()

    static var isRequested: Bool {
        if ProcessInfo.processInfo.environment["KOKORO_COMPUTE_PLAN_PROBE"] != nil { return true }
        #if os(iOS)
        return false
        #else
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue && KokoroTestSupport.haveCoreMLFiles
        #endif
    }

    /// `KEY=VALUE` lines of `probe.env` in the output directory; `#` starts a comment.
    static let fileSettings: [String: String] = {
        let url = outputDirectory.appending(path: "probe.env")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var settings: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { settings[String(trimmed[..<equals])] = value }
        }
        return settings
    }()

    /// A setting: the environment first, then `probe.env`.
    static func setting(_ key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty { return value }
        return fileSettings[key]
    }

    static var requestedStages: [String] {
        guard let raw = setting("KOKORO_COMPUTE_PLAN_STAGES") else { return [defaultStage] }
        if raw.lowercased() == "all" { return KokoroCoreMLResources.stageNames() }
        let names = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return names.isEmpty ? [defaultStage] : names
    }

    static var requestedPolicies: [KokoroComputeUnits] {
        guard let raw = setting("KOKORO_COMPUTE_PLAN_POLICIES") else { return defaultPolicies }
        let policies = raw.split(separator: ",").compactMap { KokoroComputeUnits(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        return policies.isEmpty ? defaultPolicies : policies
    }

    static var timeoutSeconds: Double {
        setting("KOKORO_COMPUTE_PLAN_TIMEOUT").flatMap(Double.init).map { max(1, $0) } ?? defaultTimeoutSeconds
    }

    /// `MLComputePlan` needs macOS 14.4 or iOS 17.4. The package's floors are macOS 15 and iOS 18
    /// (`Package.swift`), so the API is available wherever this compiles and no runtime check is
    /// made — one would be flagged as redundant. Lower the floors and this needs an `#available`.
    @Test(.enabled(if: KokoroComputePlanProbe.isRequested))
    func planEveryRequestedStageUnderEveryPolicy() async throws {
        let out = Self.outputDirectory
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let log = ProbeLog(directory: out)
        let info = ProcessInfo.processInfo
        log.line("output directory \(out.path(percentEncoded: false))")
        log.line("device \(KokoroComputeUnits.hardwareModel()), \(info.physicalMemory / 1_000_000) MB, "
            + "\(info.operatingSystemVersionString), \(info.activeProcessorCount) cores, thermal \(Self.thermalName)")
        log.line("compute devices: \(MLComputeDevice.allComputeDevices.map(Self.name(of:)).joined(separator: ", "))")
        let stages = Self.requestedStages, policies = Self.requestedPolicies, timeout = Self.timeoutSeconds
        log.line("stages \(stages.joined(separator: ", ")); policies \(policies.map(\.rawValue).joined(separator: ", ")); "
            + "timeout \(Int(timeout)) s per plan")
        log.write()

        for stage in stages {
            let compiled: URL
            do {
                compiled = try await Self.compiledStage(named: stage, log: log)
            } catch {
                log.line("\(stage): no compiled model — \(error)")
                log.row("| \(stage) | — | no model: \(error) | | | | | |")
                log.write()
                continue
            }
            for policy in policies {
                log.line("\(stage) under \(policy.runtimeName): loading the compute plan")
                do {
                    guard let report = try await Self.plan(compiled, stage: stage, policy: policy, timeout: timeout) else {
                        log.line("\(stage) under \(policy.runtimeName): no plan after \(Int(timeout)) s — the build keeps running "
                            + "in this process, so the next policy's time is contaminated")
                        log.row("| \(stage) | \(policy.runtimeName) | timed out after \(Int(timeout)) s | | | | | |")
                        log.write()
                        continue
                    }
                    let operations = Self.operationLines(report)
                    for line in operations { Self.emit(line) }
                    try? (operations.joined(separator: "\n") + "\n")
                        .write(to: out.appending(path: "ops-\(stage)-\(policy.rawValue).txt"), atomically: true, encoding: .utf8)
                    for line in Self.summaryLines(report) { log.line(line) }
                    log.row(Self.summaryRow(report))
                } catch {
                    log.line("\(stage) under \(policy.runtimeName): the plan failed to load — \(error)")
                    log.row("| \(stage) | \(policy.runtimeName) | failed: \(error) | | | | | |")
                }
                log.write()
            }
        }
        log.line("done")
        log.write()
    }

    // MARK: The models

    /// The compiled `<name>.mlmodelc`: from `KOKORO_COMPUTE_PLAN_MODELS` when it is set, else the
    /// copy kept in ``compiledDirectory`` from an earlier run, else compiled once from the staged
    /// `.mlpackage` — the checkout's staging on the Mac, a download on a phone — and kept there.
    static func compiledStage(named name: String, log: ProbeLog) async throws -> URL {
        let fileManager = FileManager.default
        if let override = setting("KOKORO_COMPUTE_PLAN_MODELS") {
            let directory = URL(fileURLWithPath: override, isDirectory: true)
            let compiled = directory.appending(path: "\(name).mlmodelc", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: compiled.path(percentEncoded: false)) {
                log.line("\(name): compiled stage at \(compiled.path(percentEncoded: false))")
                return compiled
            }
            let package = directory.appending(path: "\(name).mlpackage", directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: package.path(percentEncoded: false)) else {
                throw ProbeFailure.missing(name, under: directory)
            }
            return try await compile(package, name: name, log: log)
        }
        let compiled = compiledDirectory.appending(path: "\(name).mlmodelc", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: compiled.path(percentEncoded: false)) {
            log.line("\(name): compiled stage kept from an earlier run at \(compiled.path(percentEncoded: false))")
            return compiled
        }
        let package = try await stagedPackage(named: name, log: log)
        return try await compile(package, name: name, log: log)
    }

    /// `MLModel.compileModel` writes to the per-user temporary directory, which every checkout and
    /// session on a Mac shares (`KokoroTestSupport.compiledCoreMLResources()` has the history), so
    /// the result is moved into ``compiledDirectory`` at once.
    static func compile(_ package: URL, name: String, log: ProbeLog) async throws -> URL {
        try FileManager.default.createDirectory(at: compiledDirectory, withIntermediateDirectories: true)
        let clock = ContinuousClock()
        let started = clock.now
        let temporary = try await MLModel.compileModel(at: package)
        let destination = compiledDirectory.appending(path: "\(name).mlmodelc", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try FileManager.default.copyItem(at: temporary, to: destination)
            try? FileManager.default.removeItem(at: temporary)
        }
        log.line("\(name): compiled from \(package.lastPathComponent) in \(KokoroCoreMLEngine.fixed(KokoroCoreMLEngine.seconds(clock.now - started), 1)) s")
        return destination
    }

    /// The stage's `.mlpackage`: the checkout's staging on the Mac, a download on a phone.
    static func stagedPackage(named name: String, log: ProbeLog) async throws -> URL {
        #if os(iOS)
        return try await downloadedPackage(named: name, log: log)
        #else
        let coreml = KokoroCoreMLResources.developmentDirectory.appending(path: "coreml", directoryHint: .isDirectory)
        let package = coreml.appending(path: "\(name).mlpackage", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: package.path(percentEncoded: false)) else {
            throw ProbeFailure.missing(name, under: coreml)
        }
        return package
        #endif
    }

    #if os(iOS)
    /// The stage's `.mlpackage` fetched from the pinned revision into the runner's Caches: the three
    /// files the manifest lists for it, each checked against its digest, one already staged for
    /// another bucket with the same bytes copied rather than fetched again, and nothing fetched twice.
    static func downloadedPackage(named name: String, log: ProbeLog) async throws -> URL {
        let staging = outputDirectory.appending(path: "staging", directoryHint: .isDirectory)
        let files = KokoroCoreMLManifest.files.filter { $0.path.hasPrefix("coreml/\(name).mlpackage/") }
        guard !files.isEmpty else { throw ProbeFailure.missing(name, under: KokoroCoreMLManifest.repositoryURL) }
        let fileManager = FileManager.default
        for file in files {
            let destination = staging.appending(path: file.path)
            if try KokoroCoreMLInstall.matches(destination, file) { continue }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let part = destination.appendingPathExtension("part")
            try? fileManager.removeItem(at: part)
            let twin = KokoroCoreMLManifest.files.first { candidate in
                candidate.sha256 == file.sha256 && candidate.path != file.path
                    && ((try? KokoroCoreMLInstall.matches(staging.appending(path: candidate.path), candidate)) ?? false)
            }
            if let twin {
                log.line("\(name): \(file.path) copied from \(twin.path)")
                try fileManager.copyItem(at: staging.appending(path: twin.path), to: part)
            } else {
                log.line("\(name): downloading \(file.path) (\(file.byteCount) bytes) from \(file.url.absoluteString)")
                try await KokoroCoreMLInstall.wifiDownloader(file.url, part, { _ in }, { Self.emit("\(name): waiting for Wi-Fi") })
            }
            guard try KokoroCoreMLInstall.matches(part, file) else {
                try? fileManager.removeItem(at: part)
                throw ProbeFailure.checksum(file.path)
            }
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: part, to: destination)
        }
        return staging.appending(path: "coreml/\(name).mlpackage", directoryHint: .isDirectory)
    }
    #endif

    // MARK: The plan

    /// One operation of the program's entry function, as the plan places and prices it.
    struct OperationRow: Sendable {
        /// The operation's index in its block, with the enclosing operation's path and block index
        /// before it for a nested block: `12`, `12.b0.3`.
        let path: String
        let operatorName: String
        /// The operation's first output name — how a MIL program names an operation.
        let name: String
        let weight: Double?
        let preferred: String?
        let supported: [String]
    }

    struct PolicyReport: Sendable {
        let stage: String
        let policy: KokoroComputeUnits
        let loadSeconds: Double
        let functionNames: [String]
        let inputNames: [String]
        /// Every operation but `const`, in program order.
        let rows: [OperationRow]
        let constCount: Int
    }

    /// One policy's plan over one compiled stage, or nil once `timeout` seconds have passed without
    /// it. `MLComputePlan.load` cannot be cancelled: the detached task that runs it is left to
    /// finish on its own, still burning a core, which is why ``defaultPolicies`` puts the CPU
    /// policy — the one that never finished on the A19 — after the phone's own.
    static func plan(_ compiled: URL, stage: String, policy: KokoroComputeUnits, timeout: Double) async throws -> PolicyReport? {
        let finished = OSAllocatedUnfairLockBox(false)
        let work = Task.detached(priority: .userInitiated) { () async throws -> PolicyReport in
            defer { finished.value = true }
            return try await Self.analyze(compiled, stage: stage, policy: policy)
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(timeout)
        while !finished.value {
            if clock.now >= deadline { return nil }
            try await Task.sleep(for: .seconds(1))
        }
        return try await work.value
    }

    /// Loads the plan and walks the entry function's block — `main`, else the first by name —
    /// and every block nested in an operation, reading each operation's estimated cost and device
    /// usage. The plan never leaves this function: `MLComputePlan` is not `Sendable`.
    static func analyze(_ compiled: URL, stage: String, policy: KokoroComputeUnits) async throws -> PolicyReport {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = policy.mlComputeUnits
        let clock = ContinuousClock()
        let started = clock.now
        let plan = try await MLComputePlan.load(contentsOf: compiled, configuration: configuration)
        let loadSeconds = KokoroCoreMLEngine.seconds(clock.now - started)
        guard case .program(let program) = plan.modelStructure else { throw ProbeFailure.notAProgram(stage) }
        let functionNames = program.functions.keys.sorted()
        guard let entry = program.functions["main"] ?? functionNames.first.flatMap({ program.functions[$0] }) else {
            throw ProbeFailure.noFunction(stage)
        }
        var rows: [OperationRow] = []
        var constCount = 0
        func walk(_ block: MLModelStructure.Program.Block, path: String) {
            for (index, operation) in block.operations.enumerated() {
                let here = path.isEmpty ? String(index) : "\(path).\(index)"
                if operation.operatorName == "const" {
                    constCount += 1
                    continue
                }
                let usage = plan.deviceUsage(for: operation)
                rows.append(OperationRow(
                    path: here,
                    operatorName: operation.operatorName,
                    name: operation.outputs.first?.name ?? "-",
                    weight: plan.estimatedCost(of: operation)?.weight,
                    preferred: usage.map { Self.name(of: $0.preferred) },
                    supported: usage?.supported.map(Self.name(of:)) ?? []
                ))
                for (blockIndex, nested) in operation.blocks.enumerated() {
                    walk(nested, path: "\(here).b\(blockIndex)")
                }
            }
        }
        walk(entry.block, path: "")
        return PolicyReport(stage: stage, policy: policy, loadSeconds: loadSeconds, functionNames: functionNames,
                            inputNames: entry.inputs.map(\.name), rows: rows, constCount: constCount)
    }

    static func name(of device: MLComputeDevice) -> String {
        switch device {
        case .cpu: "cpu"
        case .gpu: "gpu"
        case .neuralEngine: "ane"
        @unknown default: "other"
        }
    }

    /// Whether the CPU is absent from an operation's supported devices — the operations a CPU-only
    /// plan has no home for.
    static func lacksCPU(_ row: OperationRow) -> Bool {
        !row.supported.isEmpty && !row.supported.contains("cpu")
    }

    static func operationLines(_ report: PolicyReport) -> [String] {
        report.rows.map { row in
            "op \(report.stage) \(report.policy.rawValue) \(row.path) \(row.operatorName) \(row.name) "
                + "cost \(row.weight.map { KokoroCoreMLEngine.fixed($0, 6) } ?? "-") preferred \(row.preferred ?? "-") "
                + "supported [\(row.supported.joined(separator: ","))]"
        }
    }

    static func summaryLines(_ report: PolicyReport) -> [String] {
        let label = "\(report.stage) under \(report.policy.runtimeName)"
        let weights = report.rows.compactMap(\.weight)
        let total = weights.reduce(0, +)
        let placed = report.rows.filter { $0.preferred != nil }.count
        let cpuOnly = report.rows.filter { $0.supported == ["cpu"] }.count
        let notCPU = report.rows.filter(lacksCPU).count
        var byPreferred: [String: Int] = [:]
        for row in report.rows { byPreferred[row.preferred ?? "none", default: 0] += 1 }

        var lines: [String] = []
        lines.append("\(label): plan loaded in \(KokoroCoreMLEngine.fixed(report.loadSeconds, 2)) s; "
            + "functions \(report.functionNames.joined(separator: ", ")); inputs \(report.inputNames.joined(separator: ", "))")
        lines.append("\(label): \(report.rows.count) operations (+ \(report.constCount) const), \(placed) with a device, "
            + "\(weights.count) with a cost, total estimated cost \(KokoroCoreMLEngine.fixed(total, 4))")
        lines.append("\(label): preferred "
            + byPreferred.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            + "; \(cpuOnly) supported by the CPU only; \(notCPU) not supported by the CPU")
        let notCPUOperators = Dictionary(grouping: report.rows.filter(lacksCPU), by: \.operatorName)
        if !notCPUOperators.isEmpty {
            lines.append("\(label): operators the CPU cannot take: "
                + notCPUOperators.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value.count)" }.joined(separator: ", "))
        }

        lines.append("\(label): the ten heaviest operations")
        let heaviest = report.rows.filter { $0.weight != nil }.sorted { ($0.weight ?? 0) > ($1.weight ?? 0) }.prefix(10)
        for row in heaviest {
            lines.append("  \(row.path) \(row.operatorName) \(row.name): cost \(KokoroCoreMLEngine.fixed(row.weight ?? 0, 4)), "
                + "preferred \(row.preferred ?? "none"), supported [\(row.supported.joined(separator: ","))]")
        }

        var byOperator: [String: (count: Int, weight: Double, cpu: Int, gpu: Int, ane: Int, notCPU: Int)] = [:]
        for row in report.rows {
            var entry = byOperator[row.operatorName] ?? (0, 0, 0, 0, 0, 0)
            entry.count += 1
            entry.weight += row.weight ?? 0
            switch row.preferred ?? "" {
            case "cpu": entry.cpu += 1
            case "gpu": entry.gpu += 1
            case "ane": entry.ane += 1
            default: break
            }
            if lacksCPU(row) { entry.notCPU += 1 }
            byOperator[row.operatorName] = entry
        }
        lines.append("\(label): by operator, the ten heaviest — count, cost, preferred cpu/gpu/ane, not supported by the CPU")
        for (operatorName, entry) in byOperator.sorted(by: { $0.value.weight > $1.value.weight }).prefix(10) {
            lines.append("  \(operatorName): ×\(entry.count), cost \(KokoroCoreMLEngine.fixed(entry.weight, 4)), "
                + "\(entry.cpu)/\(entry.gpu)/\(entry.ane), \(entry.notCPU) not on the CPU")
        }
        return lines
    }

    static let summaryHeader = [
        "| stage | policy | plan load | ops (+const) | preferred cpu/gpu/ane | CPU-only | not CPU | total cost |",
        "|---|---|---|---|---|---|---|---|",
    ]

    static func summaryRow(_ report: PolicyReport) -> String {
        var byPreferred: [String: Int] = [:]
        for row in report.rows { byPreferred[row.preferred ?? "none", default: 0] += 1 }
        let total = report.rows.compactMap(\.weight).reduce(0, +)
        return "| \(report.stage) | \(report.policy.runtimeName) | \(KokoroCoreMLEngine.fixed(report.loadSeconds, 2)) s "
            + "| \(report.rows.count) (+\(report.constCount)) "
            + "| \(byPreferred["cpu", default: 0])/\(byPreferred["gpu", default: 0])/\(byPreferred["ane", default: 0]) "
            + "| \(report.rows.filter { $0.supported == ["cpu"] }.count) | \(report.rows.filter(lacksCPU).count) "
            + "| \(KokoroCoreMLEngine.fixed(total, 4)) |"
    }

    // MARK: Output

    /// The report as it grows: every line printed as it comes and kept, and `report.md` rewritten
    /// on `write()`, so a run stopped early still leaves what it had.
    final class ProbeLog {
        let directory: URL
        private var lines: [String] = []
        private var rows: [String] = []

        init(directory: URL) {
            self.directory = directory
        }

        func line(_ text: String) {
            KokoroComputePlanProbe.emit(text)
            lines.append(text)
        }

        func row(_ text: String) {
            KokoroComputePlanProbe.emit(text)
            rows.append(text)
        }

        func write() {
            let text = (["# Compute-plan probe — \(Date().ISO8601Format())", ""]
                + KokoroComputePlanProbe.summaryHeader + rows + [""] + lines).joined(separator: "\n") + "\n"
            try? text.write(to: directory.appending(path: "report.md"), atomically: true, encoding: .utf8)
        }
    }

    /// One line to stdout, prefixed, through a POSIX write rather than `print`: `print` buffers when
    /// stdout is a pipe, as it is under `xcodebuild`, and a run stopped early would lose the buffer.
    static func emit(_ text: String) {
        let bytes = Array((linePrefix + " " + text + "\n").utf8)
        bytes.withUnsafeBufferPointer { buffer in _ = Darwin.write(STDOUT_FILENO, buffer.baseAddress, buffer.count) }
    }

    static var thermalName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    enum ProbeFailure: Error, CustomStringConvertible {
        case missing(String, under: URL)
        case checksum(String)
        case notAProgram(String)
        case noFunction(String)

        var description: String {
            switch self {
            case .missing(let name, let directory): "\(name) is not under \(directory.absoluteString)"
            case .checksum(let path): "\(path) did not match its digest after the download"
            case .notAProgram(let stage): "\(stage) is not an ML program"
            case .noFunction(let stage): "\(stage) has no function"
            }
        }
    }
}
