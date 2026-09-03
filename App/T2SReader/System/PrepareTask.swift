import BackgroundTasks
import Foundation
import os
import T2SApp

/// The opportunistic, external-power-only Prepare request. This is deliberately a thin app
/// boundary: all policy and rendering work stays in the independently tested `PrepareRunner`.
@MainActor
enum PrepareTask {
    static let identifier = "com.t2s.reader.prepare"
    private static let log = Logger(subsystem: "com.t2s.reader", category: "prepare")
    /// Scene activation and launch can arrive back-to-back; the scheduler accepts one pending
    /// request per identifier, so coalesce those callbacks in the current process.
    private static var hasScheduledRequest = false

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            Task { @MainActor in
                guard let processingTask = task as? BGProcessingTask else {
                    task.setTaskCompleted(success: false)
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
