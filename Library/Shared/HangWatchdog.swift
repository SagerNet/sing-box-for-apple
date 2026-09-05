import Foundation
import Libbox
import os
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

private let logger = Logger(category: "HangWatchdog")

public final class HangWatchdog {
    private static let installLock = NSLock()
    private static var shared: HangWatchdog?

    private static let tickInterval: TimeInterval = 0.25
    #if DEBUG
        private static let reportThreshold: TimeInterval = 1
        private static let reportCooldown: TimeInterval = 5
        private static let maxReportsPerProcess = Int.max
    #else
        private static let reportThreshold: TimeInterval = 2
        private static let reportCooldown: TimeInterval = 5 * 60
        private static let maxReportsPerProcess = 3
    #endif
    private static let secondSnapshotDelay: TimeInterval = 10
    private static let goroutineDumpTimeout: DispatchTimeInterval = .seconds(1)

    private struct RunLoopState {
        var busy = true
        var generation: UInt64 = 0
        var busySince: UInt64
        var watchedGeneration: UInt64?
        var watchedDuration: UInt64?
        var paused = false
        var applicationState: String
        var foregroundSince: UInt64
    }

    private struct ActiveReport {
        let artifactURL: URL
        let generation: UInt64
        let busySince: UInt64
        var contents: CrashReportArtifactContents
        var metadata: CrashReportMetadata
        var secondSnapshotTaken = false
    }

    private let mainThread: thread_t
    private let processStartedAt: Date?
    private let installedAt: UInt64
    private let stateLock = NSLock()
    private var state: RunLoopState
    private var reportCount = 0
    private var lastReportAt: UInt64?
    private var activeReport: ActiveReport?

    public static func installForCurrentProcess() {
        precondition(Thread.isMainThread)
        installLock.lock()
        defer {
            installLock.unlock()
        }
        guard shared == nil else {
            return
        }
        let processInfo = currentProcessInfo()
        if let processInfo, (processInfo.kp_proc.p_flag & P_TRACED) != 0 {
            logger.info("debugger attached, hang watchdog disabled")
            return
        }
        let watchdog = HangWatchdog(processInfo: processInfo)
        watchdog.installRunLoopObservers()
        watchdog.installLifecycleObservers()
        let thread = Thread {
            watchdog.run()
        }
        thread.name = "io.nekohasekai.sing-box.hang-watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
        shared = watchdog
    }

    private init(processInfo: kinfo_proc?) {
        mainThread = pthread_mach_thread_np(pthread_self())
        let now = Self.uptime()
        installedAt = now
        if let processInfo {
            let startTime = processInfo.kp_proc.p_starttime
            processStartedAt = Date(timeIntervalSince1970: TimeInterval(startTime.tv_sec) + TimeInterval(startTime.tv_usec) / 1_000_000)
        } else {
            processStartedAt = nil
        }
        state = RunLoopState(busySince: now, applicationState: Self.initialApplicationState, foregroundSince: now)
    }

    private static func currentProcessInfo() -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&name, UInt32(name.count), &info, &size, nil, 0)
        guard result == 0 else {
            return nil
        }
        return info
    }

    private static func uptime() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    private static func seconds(_ nanoseconds: UInt64) -> TimeInterval {
        TimeInterval(nanoseconds) / 1_000_000_000
    }

    private func installRunLoopObservers() {
        let afterWaiting = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { [unowned self] _, _ in
            let now = Self.uptime()
            stateLock.lock()
            state.busy = true
            state.generation += 1
            state.busySince = now
            stateLock.unlock()
        }
        let beforeWaiting = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [unowned self] _, _ in
            let now = Self.uptime()
            stateLock.lock()
            state.busy = false
            if state.watchedGeneration == state.generation {
                state.watchedGeneration = nil
                state.watchedDuration = now - state.busySince
            }
            stateLock.unlock()
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), afterWaiting, CFRunLoopMode.commonModes)
        CFRunLoopAddObserver(CFRunLoopGetMain(), beforeWaiting, CFRunLoopMode.commonModes)
    }

    #if canImport(UIKit)
        private static let initialApplicationState = "active"

        private func installLifecycleObservers() {
            let center = NotificationCenter.default
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [unowned self] _ in
                updateLifecycle(applicationState: "background", paused: true, enteredForeground: false)
            }
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [unowned self] _ in
                updateLifecycle(applicationState: "inactive", paused: false, enteredForeground: true)
            }
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [unowned self] _ in
                updateLifecycle(applicationState: "active", paused: false, enteredForeground: false)
            }
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [unowned self] _ in
                updateLifecycle(applicationState: "inactive", paused: false, enteredForeground: false)
            }
        }
    #else
        private static let initialApplicationState = "inactive"

        private func installLifecycleObservers() {
            let center = NotificationCenter.default
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { [unowned self] _ in
                updateLifecycle(applicationState: "active", paused: false, enteredForeground: true)
            }
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: nil) { [unowned self] _ in
                updateLifecycle(applicationState: "inactive", paused: false, enteredForeground: false)
            }
        }
    #endif

    private func updateLifecycle(applicationState: String, paused: Bool, enteredForeground: Bool) {
        let now = Self.uptime()
        stateLock.lock()
        state.applicationState = applicationState
        state.paused = paused
        if enteredForeground {
            state.foregroundSince = now
        }
        stateLock.unlock()
    }

    private func run() {
        var lastGeneration: UInt64 = 0
        var stalledTicks = 0
        while true {
            Thread.sleep(forTimeInterval: Self.tickInterval)
            stateLock.lock()
            let snapshot = state
            stateLock.unlock()
            if snapshot.paused {
                stalledTicks = 0
                lastGeneration = snapshot.generation
                finalizeActiveReport(snapshot: snapshot)
                continue
            }
            if snapshot.busy, snapshot.generation == lastGeneration {
                stalledTicks += 1
            } else {
                stalledTicks = 0
            }
            lastGeneration = snapshot.generation
            let stalledFor = TimeInterval(stalledTicks) * Self.tickInterval
            if let activeReport {
                if activeReport.generation != snapshot.generation || !snapshot.busy {
                    finalizeActiveReport(snapshot: snapshot)
                } else if !activeReport.secondSnapshotTaken, Self.seconds(Self.uptime() - activeReport.busySince) >= Self.secondSnapshotDelay {
                    takeSecondSnapshot()
                }
                continue
            }
            if stalledFor >= Self.reportThreshold {
                beginReport(snapshot: snapshot)
            }
        }
    }

    private func beginReport(snapshot: RunLoopState) {
        let now = Self.uptime()
        guard reportCount < Self.maxReportsPerProcess else {
            return
        }
        if let lastReportAt, Self.seconds(now - lastReportAt) < Self.reportCooldown {
            return
        }
        reportCount += 1
        lastReportAt = now
        stateLock.lock()
        state.watchedGeneration = snapshot.generation
        state.watchedDuration = nil
        stateLock.unlock()

        let nativeLog = NativeCrashReporter.liveReportText(thread: mainThread)
        let goLog = goroutineDump()
        let contents = CrashReportArtifactContents(goLog: goLog, nativeLog: nativeLog)
        let metadata = buildMetadata(snapshot: snapshot, capturedAt: now, duration: now - snapshot.busySince, resolved: false)
        do {
            let artifactURL = try CrashReportArchive.writeArchivedReport(contents: contents, date: Date(), metadata: metadata)
            activeReport = ActiveReport(
                artifactURL: artifactURL,
                generation: snapshot.generation,
                busySince: snapshot.busySince,
                contents: contents,
                metadata: metadata
            )
            logger.warning("main thread unresponsive, hang report written to \(artifactURL.lastPathComponent)")
        } catch {
            logger.warning("failed to write hang report: \(error.localizedDescription)")
        }
    }

    private func takeSecondSnapshot() {
        guard var activeReport else {
            return
        }
        activeReport.secondSnapshotTaken = true
        let elapsed = Self.seconds(Self.uptime() - activeReport.busySince)
        let separator = "\n\n===== Snapshot 2 (after \(String(format: "%.1f", elapsed))s) =====\n\n"
        if let nativeLog = NativeCrashReporter.liveReportText(thread: mainThread) {
            activeReport.contents.nativeLog = (activeReport.contents.nativeLog ?? "") + separator + nativeLog
        }
        if let goLog = goroutineDump() {
            activeReport.contents.goLog = (activeReport.contents.goLog ?? "") + separator + goLog
        }
        self.activeReport = activeReport
        rewriteActiveReport(activeReport)
    }

    private func finalizeActiveReport(snapshot: RunLoopState) {
        guard var activeReport else {
            return
        }
        self.activeReport = nil
        let duration: UInt64
        if let watchedDuration = snapshot.watchedDuration {
            duration = watchedDuration
        } else {
            duration = Self.uptime() - activeReport.busySince
        }
        stateLock.lock()
        state.watchedGeneration = nil
        state.watchedDuration = nil
        stateLock.unlock()
        activeReport.metadata.hangDuration = Self.formatDuration(duration)
        activeReport.metadata.hangResolved = "true"
        rewriteActiveReport(activeReport)
    }

    private func rewriteActiveReport(_ activeReport: ActiveReport) {
        do {
            try CrashReportArchive.rewriteArchivedReport(at: activeReport.artifactURL, contents: activeReport.contents, metadata: activeReport.metadata)
        } catch {
            logger.warning("failed to update hang report: \(error.localizedDescription)")
        }
    }

    private func buildMetadata(snapshot: RunLoopState, capturedAt: UInt64, duration: UInt64, resolved: Bool) -> CrashReportMetadata {
        let threadInfo = mainThreadInfo()
        return CrashReportMetadataBuilder.normalized(
            CrashReportMetadata(
                source: "Application",
                bundleIdentifier: Bundle.main.bundleIdentifier,
                startedAt: processStartedAt.map(CrashReportArchive.iso8601String(from:)),
                crashedAt: CrashReportArchive.iso8601String(from: Date()),
                kind: CrashReportMetadata.hangKind,
                hangDuration: Self.formatDuration(duration),
                hangResolved: resolved ? "true" : "false",
                applicationState: snapshot.applicationState,
                mainThreadState: threadInfo?.state,
                mainThreadCPUUsage: threadInfo?.cpuUsage,
                sinceLaunch: Self.formatDuration(capturedAt - installedAt),
                sinceForeground: Self.formatDuration(capturedAt - snapshot.foregroundSince)
            )
        )
    }

    private static func formatDuration(_ nanoseconds: UInt64) -> String {
        String(format: "%.2fs", seconds(nanoseconds))
    }

    private func mainThreadInfo() -> (state: String, cpuUsage: String)? {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                thread_info(mainThread, thread_flavor_t(THREAD_BASIC_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        let state: String
        switch info.run_state {
        case TH_STATE_RUNNING:
            state = "running"
        case TH_STATE_STOPPED:
            state = "stopped"
        case TH_STATE_WAITING:
            state = "waiting"
        case TH_STATE_UNINTERRUPTIBLE:
            state = "uninterruptible"
        case TH_STATE_HALTED:
            state = "halted"
        default:
            state = "unknown"
        }
        let cpuUsage = String(format: "%.1f%%", Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100)
        return (state, cpuUsage)
    }

    private final class GoroutineDumpResult: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?

        func set(_ newValue: String) {
            lock.lock()
            value = newValue
            lock.unlock()
        }

        func get() -> String? {
            lock.lock()
            defer {
                lock.unlock()
            }
            return value
        }
    }

    private func goroutineDump() -> String? {
        let result = GoroutineDumpResult()
        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread {
            result.set(LibboxGoroutineDump())
            semaphore.signal()
        }
        thread.name = "io.nekohasekai.sing-box.hang-goroutine-dump"
        thread.qualityOfService = .userInteractive
        thread.start()
        guard semaphore.wait(timeout: .now() + Self.goroutineDumpTimeout) == .success else {
            logger.warning("goroutine dump timed out")
            return nil
        }
        return result.get()
    }
}
