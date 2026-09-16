import Foundation
import Libbox
import os
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

private let logger = Logger(category: "HangWatchdog")

@available(iOSApplicationExtension, unavailable)
@available(tvOSApplicationExtension, unavailable)
@available(macOSApplicationExtension, unavailable)
public final class HangWatchdog: @unchecked Sendable {
    private static let installLock = NSLock()
    private static var shared: HangWatchdog?

    private static let tickInterval: TimeInterval = 0.25
    private static let sampleInterval: TimeInterval = 1
    private static let metadataWriteInterval: TimeInterval = 5
    private static let monitoringGapThreshold: TimeInterval = 2
    private static let maxSamples = 120
    private static let snapshotOffsets: [TimeInterval] = [0, 0.5, 2, 8, 30]
    private static let goroutineDumpTimeout: DispatchTimeInterval = .seconds(1)
    #if DEBUG
        private static let reportThreshold: TimeInterval = 1
        private static let reportCooldown: TimeInterval = 5
        private static let maxReportsPerProcess = Int.max
    #else
        private static let reportThreshold: TimeInterval = 2
        private static let reportCooldown: TimeInterval = 5 * 60
        private static let maxReportsPerProcess = 3
    #endif

    private struct ThreadMeasurement {
        var uptime: UInt64
        var cpuTime: UInt64?
        var state: String?
        var error: kern_return_t?
        var duration: TimeInterval
    }

    private struct Completion {
        var measurement: ThreadMeasurement
        var outcome: String
        var applicationState: String
        var activity: String
        var mode: String?
    }

    private struct RunLoopState {
        var generation: UInt64 = 0
        var busy = true
        var checkpoint: ThreadMeasurement
        var startIsKnown = true
        var activity = "launch"
        var mode: String?
        var paused = false
        var applicationState: String
        var foregroundSince: UInt64
        var watchedGeneration: UInt64?
        var completion: Completion?
    }

    private struct ActiveReport {
        var artifactURL: URL?
        var generation: UInt64
        var baseline: ThreadMeasurement
        var detectedAt: UInt64
        var date: Date
        var lastSampleAt: UInt64
        var lastWriteAt: UInt64
        var contents = CrashReportArtifactContents()
        var metadata: CrashReportMetadata
        var diagnostics: HangReport
    }

    private let mainThread: thread_t
    private let processStartedAt: Date?
    private let processStartedUptime: UInt64
    private let stateLock = NSLock()
    private var state: RunLoopState
    private var reportCount = 0
    private var lastReportAt: UInt64?
    private var activeReport: ActiveReport?
    private var pendingGoDump: GoroutineDumpResult?

    @MainActor
    public static func installForCurrentProcess() {
        installLock.lock()
        defer { installLock.unlock() }
        guard shared == nil else { return }
        let processInfo = currentProcessInfo()
        if let processInfo, (processInfo.kp_proc.p_flag & P_TRACED) != 0 {
            logger.info("debugger attached, hang watchdog disabled")
            return
        }
        let watchdog = HangWatchdog(processInfo: processInfo)
        watchdog.installRunLoopObservers()
        watchdog.installLifecycleObservers()
        let thread = Thread { watchdog.run() }
        thread.name = "io.nekohasekai.sing-box.hang-watchdog"
        thread.qualityOfService = .userInitiated
        shared = watchdog
        thread.start()
    }

    @MainActor
    private init(processInfo: kinfo_proc?) {
        let mainThread = pthread_mach_thread_np(pthread_self())
        self.mainThread = mainThread
        let measurement = Self.measureThread(mainThread)
        if let processInfo {
            let start = processInfo.kp_proc.p_starttime
            let date = Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
            processStartedAt = date
            let age = UInt64(max(0, Date().timeIntervalSince(date)) * 1_000_000_000)
            processStartedUptime = measurement.uptime > age ? measurement.uptime - age : 0
        } else {
            processStartedAt = nil
            processStartedUptime = measurement.uptime
        }
        #if canImport(UIKit)
            let applicationState: String
            switch UIApplication.shared.applicationState {
            case .active:
                applicationState = "active"
            case .background:
                applicationState = "background"
            default:
                applicationState = "inactive"
            }
        #else
            let applicationState = NSApp?.isActive == true ? "active" : "inactive"
        #endif
        state = RunLoopState(
            checkpoint: measurement,
            paused: applicationState == "background",
            applicationState: applicationState,
            foregroundSince: measurement.uptime
        )
    }

    private static func currentProcessInfo() -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else { return nil }
        return info
    }

    private static func uptime() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    private static func seconds(_ nanoseconds: UInt64) -> TimeInterval {
        TimeInterval(nanoseconds) / 1_000_000_000
    }

    private static func elapsed(from: UInt64, to: UInt64) -> UInt64 {
        to >= from ? to - from : 0
    }

    private func readState() -> RunLoopState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }

    private func installRunLoopObservers() {
        let activities = CFRunLoopActivity.entry.rawValue
            | CFRunLoopActivity.beforeTimers.rawValue
            | CFRunLoopActivity.beforeSources.rawValue
            | CFRunLoopActivity.afterWaiting.rawValue
            | CFRunLoopActivity.exit.rawValue
        let progress = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities, true, CFIndex.min) { [unowned self] _, activity in
            if activity == .beforeSources {
                stateLock.lock()
                state.activity = "beforeSources"
                stateLock.unlock()
            } else {
                recordProgress(activity: Self.activityName(activity), busy: true)
            }
        }
        let idle = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [unowned self] _, _ in
            recordProgress(activity: "beforeWaiting", busy: false)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), progress, CFRunLoopMode.commonModes)
        CFRunLoopAddObserver(CFRunLoopGetMain(), idle, CFRunLoopMode.commonModes)
    }

    private func recordProgress(activity: String, busy: Bool) {
        let measurement = Self.measureThread(mainThread)
        let mode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain()).map { $0.rawValue as String }
        stateLock.lock()
        if state.watchedGeneration == state.generation, state.completion == nil {
            state.completion = Completion(
                measurement: measurement, outcome: "recovered",
                applicationState: state.applicationState, activity: activity, mode: mode
            )
            state.watchedGeneration = nil
        }
        state.generation &+= 1
        state.checkpoint = measurement
        state.startIsKnown = true
        state.activity = activity
        state.mode = mode
        state.busy = busy
        stateLock.unlock()
    }

    private static func activityName(_ activity: CFRunLoopActivity) -> String {
        switch activity {
        case .entry: "entry"
        case .beforeTimers: "beforeTimers"
        case .beforeSources: "beforeSources"
        case .afterWaiting: "afterWaiting"
        case .exit: "exit"
        default: "unknown"
        }
    }

    private func installLifecycleObservers() {
        let center = NotificationCenter.default
        #if canImport(UIKit)
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
        #else
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { [unowned self] _ in
                updateLifecycle(applicationState: "active", paused: false, enteredForeground: true)
            }
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: nil) { [unowned self] _ in
                updateLifecycle(applicationState: "inactive", paused: false, enteredForeground: false)
            }
        #endif
    }

    private func updateLifecycle(applicationState: String, paused: Bool, enteredForeground: Bool) {
        let measurement = Self.measureThread(mainThread)
        stateLock.lock()
        if state.watchedGeneration == state.generation, state.completion == nil {
            state.completion = Completion(
                measurement: measurement, outcome: paused ? "backgrounded" : "recovered",
                applicationState: applicationState, activity: "lifecycle", mode: state.mode
            )
            state.watchedGeneration = nil
        }
        state.generation &+= 1
        state.checkpoint = measurement
        state.startIsKnown = true
        state.activity = "lifecycle"
        state.busy = !paused
        state.applicationState = applicationState
        state.paused = paused
        if enteredForeground {
            state.foregroundSince = measurement.uptime
        }
        stateLock.unlock()
    }

    private func run() {
        while true {
            let beforeSleepUptime = Self.uptime()
            let beforeSleep = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
            Thread.sleep(forTimeInterval: Self.tickInterval)
            let pollInterval = Self.seconds(Self.elapsed(from: beforeSleep, to: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)))
            let snapshot = readState()
            if let completion = snapshot.completion, activeReport != nil,
               pollInterval <= Self.monitoringGapThreshold || completion.measurement.uptime <= beforeSleepUptime
            {
                finishReport(completion: completion)
            }
            if pollInterval > Self.monitoringGapThreshold {
                if var report = activeReport {
                    report.diagnostics.outcome = "monitoring_gap"
                    report.diagnostics.monitoringGapSeconds = pollInterval
                    persist(&report, includeStacks: false)
                    activeReport = nil
                }
                let measurement = Self.measureThread(mainThread)
                stateLock.lock()
                if state.generation == snapshot.generation {
                    state.generation &+= 1
                    state.checkpoint = measurement
                    state.startIsKnown = false
                }
                state.watchedGeneration = nil
                state.completion = nil
                stateLock.unlock()
                continue
            }
            guard !snapshot.paused else { continue }
            if var report = activeReport {
                guard snapshot.generation == report.generation, snapshot.busy else { continue }
                let now = Self.uptime()
                if Self.seconds(Self.elapsed(from: report.lastSampleAt, to: now)) >= Self.sampleInterval {
                    let measurement = Self.measureThread(mainThread)
                    if readState().generation == report.generation {
                        appendSample(
                            to: &report, measurement: measurement, event: "sample",
                            applicationState: snapshot.applicationState, activity: snapshot.activity, mode: snapshot.mode
                        )
                    }
                }
                if report.diagnostics.snapshots.count < Self.snapshotOffsets.count,
                   Self.seconds(Self.elapsed(from: report.detectedAt, to: now)) >= Self.snapshotOffsets[report.diagnostics.snapshots.count]
                {
                    captureSnapshot(&report)
                    persist(&report, includeStacks: true)
                } else if Self.seconds(Self.elapsed(from: report.lastWriteAt, to: now)) >= Self.metadataWriteInterval {
                    persist(&report, includeStacks: false)
                }
                activeReport = report
            } else if snapshot.busy,
                      Self.seconds(Self.elapsed(from: snapshot.checkpoint.uptime, to: Self.uptime())) >= Self.reportThreshold
            {
                beginReport(snapshot: snapshot)
            }
        }
    }

    private func beginReport(snapshot: RunLoopState) {
        let measurement = Self.measureThread(mainThread)
        guard reportCount < Self.maxReportsPerProcess else { return }
        if let lastReportAt, Self.seconds(Self.elapsed(from: lastReportAt, to: measurement.uptime)) < Self.reportCooldown {
            return
        }
        stateLock.lock()
        guard state.generation == snapshot.generation, state.busy, !state.paused else {
            stateLock.unlock()
            return
        }
        state.watchedGeneration = snapshot.generation
        state.completion = nil
        stateLock.unlock()

        reportCount += 1
        lastReportAt = measurement.uptime
        let date = Date()
        let duration = Self.seconds(Self.elapsed(from: snapshot.checkpoint.uptime, to: measurement.uptime))
        var report = ActiveReport(
            generation: snapshot.generation, baseline: snapshot.checkpoint, detectedAt: measurement.uptime,
            date: date, lastSampleAt: measurement.uptime, lastWriteAt: measurement.uptime,
            metadata: CrashReportMetadataBuilder.normalized(CrashReportMetadata(
                source: "Application", bundleIdentifier: Bundle.main.bundleIdentifier,
                startedAt: processStartedAt.map(CrashReportArchive.iso8601String(from:)),
                crashedAt: CrashReportArchive.iso8601String(from: date), kind: CrashReportMetadata.hangKind,
                hangResolved: "false", applicationState: snapshot.applicationState,
                sinceLaunch: Self.formatDuration(Self.seconds(Self.elapsed(from: processStartedUptime, to: measurement.uptime))),
                sinceForeground: Self.formatDuration(Self.seconds(Self.elapsed(from: snapshot.foregroundSince, to: measurement.uptime)))
            )),
            diagnostics: HangReport(
                startedAt: CrashReportArchive.iso8601String(from: date.addingTimeInterval(-duration)),
                detectedAt: CrashReportArchive.iso8601String(from: date),
                startIsKnown: snapshot.startIsKnown,
                thresholdSeconds: Self.reportThreshold, pollIntervalSeconds: Self.tickInterval,
                sampleIntervalSeconds: Self.sampleInterval, stackSnapshotOffsetsSeconds: Self.snapshotOffsets,
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                hardwareModel: Self.hardwareModel, processorCount: ProcessInfo.processInfo.activeProcessorCount,
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
            )
        )
        appendSample(
            to: &report, measurement: measurement, event: "detected",
            applicationState: snapshot.applicationState, activity: snapshot.activity, mode: snapshot.mode
        )
        persist(&report, includeStacks: false)
        captureSnapshot(&report)
        persist(&report, includeStacks: true)
        activeReport = report
    }

    private func appendSample(
        to report: inout ActiveReport, measurement: ThreadMeasurement, event: String,
        applicationState: String, activity: String, mode: String?
    ) {
        let duration = Self.seconds(Self.elapsed(from: report.baseline.uptime, to: measurement.uptime))
        let cpuSeconds: Double?
        if let baseline = report.baseline.cpuTime, let cpuTime = measurement.cpuTime, cpuTime >= baseline {
            cpuSeconds = Self.seconds(cpuTime - baseline)
        } else {
            cpuSeconds = nil
        }
        let previous = report.diagnostics.samples.last
        let interval = previous.map { duration - $0.elapsedSeconds }
        let cpuPercent = Self.cpuPercent(current: cpuSeconds, previous: 0, interval: duration)
        var usage = rusage()
        let processStart = Self.uptime()
        let processResult = getrusage(RUSAGE_SELF, &usage)
        let processError = processResult == 0 ? nil : errno
        let processEnd = Self.uptime()
        let processElapsed = Self.seconds(Self.elapsed(from: report.baseline.uptime, to: processStart + (processEnd - processStart) / 2))
        let processCPU = processResult == 0
            ? Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            : nil
        var memory = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let memoryResult = withUnsafeMutablePointer(to: &memory) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let thermalState: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = "nominal"
        case .fair: thermalState = "fair"
        case .serious: thermalState = "serious"
        case .critical: thermalState = "critical"
        @unknown default: thermalState = "unknown"
        }
        #if os(tvOS)
            let lowPowerMode: Bool? = nil
        #else
            let lowPowerMode: Bool? = ProcessInfo.processInfo.isLowPowerModeEnabled
        #endif
        report.diagnostics.samples.append(HangReport.Sample(
            event: event, elapsedSeconds: duration, mainThreadCPUSeconds: cpuSeconds, mainThreadCPUPercent: cpuPercent,
            intervalSeconds: interval,
            intervalMainThreadCPUPercent: Self.cpuPercent(current: cpuSeconds, previous: previous?.mainThreadCPUSeconds, interval: interval),
            mainThreadState: measurement.state, threadInfoError: measurement.error, threadMeasurementSeconds: measurement.duration,
            processElapsedSeconds: processElapsed, processCPUSeconds: processCPU,
            intervalProcessCPUPercent: Self.cpuPercent(
                current: processCPU, previous: previous?.processCPUSeconds,
                interval: previous.map { processElapsed - $0.processElapsedSeconds }
            ),
            processInfoError: processError,
            residentMemoryBytes: memoryResult == KERN_SUCCESS ? memory.resident_size : nil,
            physicalFootprintBytes: memoryResult == KERN_SUCCESS ? memory.phys_footprint : nil,
            memoryInfoError: memoryResult == KERN_SUCCESS ? nil : memoryResult,
            applicationState: applicationState, runLoopActivity: activity, runLoopMode: mode,
            thermalState: thermalState, lowPowerMode: lowPowerMode
        ))
        if report.diagnostics.samples.count > Self.maxSamples {
            report.diagnostics.samples.remove(at: 1)
            report.diagnostics.droppedSampleCount += 1
        }
        report.lastSampleAt = measurement.uptime
        report.diagnostics.durationSeconds = duration
        report.metadata.hangDuration = Self.formatDuration(duration)
        report.metadata.mainThreadCPUTime = cpuSeconds.map(Self.formatDuration)
        report.metadata.mainThreadCPURatio = cpuPercent.map { String(format: "%.1f%%", $0) }
        report.metadata.mainThreadState = measurement.state
    }

    private func captureSnapshot(_ report: inout ActiveReport) {
        let measurement = Self.measureThread(mainThread)
        let snapshot = readState()
        guard snapshot.generation == report.generation, snapshot.busy, !snapshot.paused else { return }
        appendSample(
            to: &report, measurement: measurement, event: "snapshot",
            applicationState: snapshot.applicationState, activity: snapshot.activity, mode: snapshot.mode
        )
        guard let sample = report.diagnostics.samples.last else { return }
        let number = report.diagnostics.snapshots.count + 1
        let heading = "\n\n===== Snapshot \(number) (after \(Self.formatDuration(sample.elapsedSeconds))) =====\n\n"
        let nativeStart = Self.uptime()
        var nativeStatus = "captured"
        var nativeError: String?
        do {
            let text = try NativeCrashReporter.liveReportText(thread: mainThread)
            report.contents.nativeLog = (report.contents.nativeLog ?? "") + heading + text
        } catch {
            nativeStatus = "failed"
            nativeError = error.localizedDescription
        }
        let native = HangReport.Capture(
            startedAfterSeconds: Self.seconds(Self.elapsed(from: report.baseline.uptime, to: nativeStart)),
            durationSeconds: Self.seconds(Self.elapsed(from: nativeStart, to: Self.uptime())),
            status: nativeStatus, error: nativeError
        )
        let goStart = Self.uptime()
        let go: (text: String?, status: String)
        if readState().generation == report.generation {
            go = goroutineDump()
        } else {
            go = (nil, "skipped_after_progress")
        }
        if let text = go.text {
            report.contents.goLog = (report.contents.goLog ?? "") + heading + text
        }
        report.diagnostics.snapshots.append(HangReport.StackSnapshot(
            number: number, sample: sample, native: native,
            go: HangReport.Capture(
                startedAfterSeconds: Self.seconds(Self.elapsed(from: report.baseline.uptime, to: goStart)),
                durationSeconds: Self.seconds(Self.elapsed(from: goStart, to: Self.uptime())), status: go.status
            ),
            mainThreadProgressedDuringCapture: readState().generation != report.generation
        ))
    }

    private func finishReport(completion: Completion) {
        guard var report = activeReport else { return }
        appendSample(
            to: &report, measurement: completion.measurement, event: completion.outcome,
            applicationState: completion.applicationState, activity: completion.activity, mode: completion.mode
        )
        report.diagnostics.outcome = completion.outcome
        report.diagnostics.durationIsLowerBound = !report.diagnostics.startIsKnown
        report.diagnostics.endedAt = CrashReportArchive.iso8601String(from:
            report.date.addingTimeInterval(Self.seconds(Self.elapsed(from: report.detectedAt, to: completion.measurement.uptime))))
        report.metadata.hangResolved = completion.outcome == "recovered" ? "true" : "false"
        persist(&report, includeStacks: false)
        activeReport = nil
        stateLock.lock()
        state.watchedGeneration = nil
        state.completion = nil
        stateLock.unlock()
    }

    private func persist(_ report: inout ActiveReport, includeStacks: Bool) {
        report.metadata.hangOutcome = report.diagnostics.outcome
        report.contents.hangReport = report.diagnostics
        do {
            if let url = report.artifactURL {
                if includeStacks {
                    try CrashReportArchive.rewriteArchivedReport(at: url, contents: report.contents, metadata: report.metadata)
                } else {
                    try CrashReportArchive.updateHangReport(at: url, report: report.diagnostics)
                    try CrashReportArchive.updateMetadata(at: url, metadata: report.metadata)
                }
            } else {
                let url = try CrashReportArchive.writeArchivedReport(contents: report.contents, date: report.date, metadata: report.metadata)
                report.artifactURL = url
                logger.warning("main thread unresponsive, hang report written to \(url.lastPathComponent)")
            }
        } catch {
            logger.warning("failed to write hang report: \(error.localizedDescription)")
        }
        report.lastWriteAt = Self.uptime()
    }

    private static func formatDuration(_ seconds: Double) -> String {
        String(format: "%.2fs", seconds)
    }

    private static func cpuPercent(current: Double?, previous: Double?, interval: Double?) -> Double? {
        guard let current, let previous, let interval, interval > 0, current >= previous else { return nil }
        return (current - previous) / interval * 100
    }

    private static func measureThread(_ thread: thread_t) -> ThreadMeasurement {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let start = uptime()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        let end = uptime()
        let state: String?
        if result != KERN_SUCCESS {
            state = nil
        } else {
            switch info.run_state {
            case TH_STATE_RUNNING: state = "running"
            case TH_STATE_STOPPED: state = "stopped"
            case TH_STATE_WAITING: state = "waiting"
            case TH_STATE_UNINTERRUPTIBLE: state = "uninterruptible"
            case TH_STATE_HALTED: state = "halted"
            default: state = "unknown"
            }
        }
        return ThreadMeasurement(
            uptime: start + (end - start) / 2,
            cpuTime: result == KERN_SUCCESS ? nanoseconds(info.user_time) + nanoseconds(info.system_time) : nil,
            state: state, error: result == KERN_SUCCESS ? nil : result, duration: seconds(end - start)
        )
    }

    private static func nanoseconds(_ time: time_value_t) -> UInt64 {
        UInt64(max(0, time.seconds)) * NSEC_PER_SEC + UInt64(max(0, time.microseconds)) * NSEC_PER_USEC
    }

    private static let hardwareModel: String? = {
        #if os(macOS)
            let key = "hw.model"
        #else
            let key = "hw.machine"
        #endif
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }()

    private final class GoroutineDumpResult: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var value: String?

        func set(_ newValue: String?) {
            lock.lock()
            value = newValue
            lock.unlock()
            semaphore.signal()
        }

        func get() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private func goroutineDump() -> (text: String?, status: String) {
        if let pendingGoDump {
            guard pendingGoDump.semaphore.wait(timeout: .now()) == .success else {
                return (nil, "previous_dump_still_running")
            }
            self.pendingGoDump = nil
        }
        let result = GoroutineDumpResult()
        pendingGoDump = result
        let thread = Thread { result.set(LibboxGoroutineDump()) }
        thread.name = "io.nekohasekai.sing-box.hang-goroutine-dump"
        thread.qualityOfService = .userInitiated
        thread.start()
        guard result.semaphore.wait(timeout: .now() + Self.goroutineDumpTimeout) == .success else {
            return (nil, "timed_out")
        }
        pendingGoDump = nil
        guard let text = result.get(), !text.isEmpty else { return (nil, "empty") }
        return (text, "captured")
    }
}
