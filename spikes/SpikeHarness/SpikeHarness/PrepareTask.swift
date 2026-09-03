// PrepareTask.swift — Plan 0 Task 3 (§7.7): a BGProcessingTask that runs the bench while the
// phone is idle on charge, logging bg.begin / bg.expired so the granted runtime can be measured.
import BackgroundTasks
import Foundation

enum PrepareTask {
    static let id = "com.t2s.spike.prepare"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            handle(task as! BGProcessingTask)
        }
    }

    static func schedule() {
        let req = BGProcessingTaskRequest(identifier: id)
        req.requiresExternalPower = true
        req.requiresNetworkConnectivity = false
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do { try BGTaskScheduler.shared.submit(req); SpikeLog.shared.record("bg.scheduled") }
        catch { SpikeLog.shared.record("bg.scheduleFailed", ["error": "\(error)"]) }
    }

    private static func handle(_ task: BGProcessingTask) {
        SpikeLog.shared.record("bg.begin")
        let bench = try? SynthBench()
        task.expirationHandler = {
            SpikeLog.shared.record("bg.expired")
            bench?.cancel()
            schedule()
        }
        DispatchQueue.global(qos: .utility).async {
            bench?.run(sentences: Corpus.sentences, cycle: .init(playbackRate: 0)) { _ in }
            task.setTaskCompleted(success: true)
        }
    }
}
