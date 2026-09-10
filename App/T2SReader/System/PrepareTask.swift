import BackgroundTasks
import Foundation
import os
import T2SApp

/// The opportunistic, external-power-only Prepare request. This is deliberately a thin app
/// boundary: all policy and rendering work stays in the independently tested `PrepareRunner`.
@MainActor
enum PrepareTask {
    static let identifier = "com.t2s.reader.prepare"
    static let log = Logger(subsystem: "com.t2s.reader", category: "prepare")
    /// Scene activation and launch can arrive back-to-back; the scheduler accepts one pending
    /// request per identifier, so coalesce those callbacks in the current process.
    private static var hasScheduledRequest = false

    static func register() {
        // `@Sendable`, and so not main-actor isolated: `BGTaskScheduler`'s handler parameter is not
        // `@Sendable`, so a closure formed inside this `@MainActor` enum inherits its isolation, and
        // the scheduler calls it on its own queue — which trapped in `swift_task_checkIsolated` on
        // every overnight launch (iPhone 17 Pro, 2026-09-09 03:33, `EXC_BREAKPOINT` on
        // `com.apple.BGTaskScheduler (com.t2s.reader.prepare)`). The hop to the main actor is the
        // `Task` below, as it always was.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { @Sendable task in
            // `BGTask` is not `Sendable` and belongs to the scheduler's region; it crosses to the
            // main actor in this box, which is sound because nothing on the scheduler's side reads
            // it again — the handler's only job is to hand it over.
            let handed = HandedTask(task: task)
            Task { @MainActor in
                guard let processingTask = handed.task as? BGProcessingTask else {
                    handed.task.setTaskCompleted(success: false)
                    return
                }
                hasScheduledRequest = false
                PrepareTaskOperation(task: processingTask).start()
            }
        }
    }

    static func schedule() {
        guard !hasScheduledRequest else { return }
        hasScheduledRequest = true
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("Prepare scheduling failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// A `BGTask` on its way from the scheduler's queue to the main actor (see `PrepareTask.register`).
private struct HandedTask: @unchecked Sendable {
    let task: BGTask
}

/// Retained by its running task until it reports one and only one background-task completion.
@MainActor
private final class PrepareTaskOperation {
    private let task: BGProcessingTask
    private var runner: PrepareRunner?
    private var work: Task<Void, Never>?
    private var completed = false

    init(task: BGProcessingTask) {
        self.task = task
    }

    func start() {
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.expire() }
        }
        work = Task { @MainActor [self] in
            await run()
        }
    }

    private func run() async {
        guard !completed else { return }
        guard let environment = try? AppEnvironment.live() else {
            PrepareTask.schedule()
            complete(success: false)
            return
        }
        guard !completed else { return }
        // A background launch never builds Core ML's compute plans: that is a minute of a core per
        // stage on a first launch, and iOS kills a background process for it. Until a foreground
        // warm-up has built them for this install (`KokoroWarmUpRecord`), Prepare waits for the
        // next night.
        guard environment.kokoroStatus.warmedInstall else {
            PrepareTask.log.notice("Prepare skipped: the Kokoro voice has not been warmed up in the foreground on this install")
            PrepareTask.schedule()
            complete(success: false)
            return
        }

        let runner = environment.prepareRunner
        self.runner = runner
        let device = await environment.deviceMonitor.refreshNow()
        let result = await runner.run(reason: .backgroundProcessing, device: device)
        guard !completed else { return }

        if let recordedAt = result.recordedAt {
            environment.storage.recordPrepareRun(recordedAt)
        }
        await environment.storage.refresh()
        await environment.libraryModel.refresh()
        PrepareTask.schedule()
        complete(success: result.completedSuccessfully)
    }

    private func expire() {
        guard !completed else { return }
        runner?.cancel()
        work?.cancel()
        PrepareTask.schedule()
        complete(success: false)
    }

    private func complete(success: Bool) {
        guard !completed else { return }
        completed = true
        task.setTaskCompleted(success: success)
        work = nil
    }
}
