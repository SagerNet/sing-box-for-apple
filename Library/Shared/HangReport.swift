import Foundation

public struct HangReport: Codable, Sendable {
    var version = 1
    var detection = "main_run_loop_stall"
    var startedAt: String
    var detectedAt: String
    var startIsKnown: Bool
    var thresholdSeconds: Double
    var pollIntervalSeconds: Double
    var sampleIntervalSeconds: Double
    var stackSnapshotOffsetsSeconds: [Double]
    var operatingSystem: String
    var hardwareModel: String?
    var processorCount: Int
    var physicalMemoryBytes: UInt64
    var outcome = "unresponsive"
    var durationSeconds: Double = 0
    var durationIsLowerBound = true
    var endedAt: String?
    var monitoringGapSeconds: Double?
    var droppedSampleCount = 0
    var samples: [Sample] = []
    var snapshots: [StackSnapshot] = []

    struct Sample: Codable, Sendable {
        var event: String
        var elapsedSeconds: Double
        var mainThreadCPUSeconds: Double?
        var mainThreadCPUPercent: Double?
        var intervalSeconds: Double?
        var intervalMainThreadCPUPercent: Double?
        var mainThreadState: String?
        var threadInfoError: Int32?
        var threadMeasurementSeconds: Double
        var processElapsedSeconds: Double
        var processCPUSeconds: Double?
        var intervalProcessCPUPercent: Double?
        var processInfoError: Int32?
        var residentMemoryBytes: UInt64?
        var physicalFootprintBytes: UInt64?
        var memoryInfoError: Int32?
        var applicationState: String
        var runLoopActivity: String
        var runLoopMode: String?
        var thermalState: String
        var lowPowerMode: Bool?
    }

    struct StackSnapshot: Codable, Sendable {
        var number: Int
        var sample: Sample
        var native: Capture
        var go: Capture
        var mainThreadProgressedDuringCapture: Bool
    }

    struct Capture: Codable, Sendable {
        var startedAfterSeconds: Double
        var durationSeconds: Double
        var status: String
        var error: String?
    }
}
