import Foundation
import IOKit
import IOKit.storage

struct DiskActivityCounters: Equatable, Sendable {
    var timestamp: Date
    var readBytes: UInt64
    var writeBytes: UInt64
}

struct DiskActivitySample: Identifiable, Codable, Equatable, Sendable {
    var timestamp: Date
    var readMegabytesPerSecond: Double
    var writeMegabytesPerSecond: Double

    var id: TimeInterval { timestamp.timeIntervalSinceReferenceDate }
}

enum DiskActivitySampleInterval: Double, CaseIterable, Codable, Identifiable, Sendable {
    case tenth = 0.1
    case fifth = 0.2
    case half = 0.5
    case one = 1.0

    static let `default` = DiskActivitySampleInterval.half

    var id: Double { rawValue }
    var seconds: TimeInterval { rawValue }
    var nanoseconds: UInt64 { UInt64(rawValue * 1_000_000_000) }

    var title: String {
        rawValue == 1 ? "1s" : String(format: "%.1fs", rawValue)
    }
}

protocol DiskActivityCounterReading: Sendable {
    func counters() -> DiskActivityCounters?
}

protocol DiskActivityProviding: Sendable {
    func reader(forBSDName bsdName: String) -> DiskActivityCounterReading?
    func counters(forBSDName bsdName: String) -> DiskActivityCounters?
}

enum DiskActivityRateCalculator {
    static func sample(previous: DiskActivityCounters?, current: DiskActivityCounters) -> DiskActivitySample {
        guard let previous else {
            return DiskActivitySample(timestamp: current.timestamp, readMegabytesPerSecond: 0, writeMegabytesPerSecond: 0)
        }

        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else {
            return DiskActivitySample(timestamp: current.timestamp, readMegabytesPerSecond: 0, writeMegabytesPerSecond: 0)
        }

        let readDelta = current.readBytes >= previous.readBytes ? current.readBytes - previous.readBytes : 0
        let writeDelta = current.writeBytes >= previous.writeBytes ? current.writeBytes - previous.writeBytes : 0
        return DiskActivitySample(
            timestamp: current.timestamp,
            readMegabytesPerSecond: Double(readDelta) / elapsed / 1_000_000,
            writeMegabytesPerSecond: Double(writeDelta) / elapsed / 1_000_000
        )
    }
}

enum DiskActivitySeries {
    static let defaultLimit = 120

    static func appending(_ sample: DiskActivitySample, to samples: [DiskActivitySample], limit: Int? = nil) -> [DiskActivitySample] {
        var next = samples
        next.append(sample)
        if let limit, next.count > limit {
            next.removeFirst(next.count - limit)
        }
        return next
    }
}

struct DiskActivitySummary: Equatable {
    var durationSeconds: TimeInterval
    var peakReadMegabytesPerSecond: Double
    var peakWriteMegabytesPerSecond: Double
    var averageReadMegabytesPerSecond: Double
    var averageWriteMegabytesPerSecond: Double
    var sampleCount: Int
}

enum DiskActivityStatistics {
    static func summarize(samples: [DiskActivitySample], startedAt: Date? = nil, endedAt: Date? = nil) -> DiskActivitySummary {
        let duration: TimeInterval
        if let startedAt, let endedAt {
            duration = max(0, endedAt.timeIntervalSince(startedAt))
        } else if let first = samples.first?.timestamp, let last = samples.last?.timestamp {
            duration = max(0, last.timeIntervalSince(first))
        } else {
            duration = 0
        }

        let peakRead = samples.map(\.readMegabytesPerSecond).max() ?? 0
        let peakWrite = samples.map(\.writeMegabytesPerSecond).max() ?? 0
        let divisor = max(samples.count, 1)
        let averageRead = samples.reduce(0) { $0 + $1.readMegabytesPerSecond } / Double(divisor)
        let averageWrite = samples.reduce(0) { $0 + $1.writeMegabytesPerSecond } / Double(divisor)

        return DiskActivitySummary(
            durationSeconds: duration,
            peakReadMegabytesPerSecond: peakRead,
            peakWriteMegabytesPerSecond: peakWrite,
            averageReadMegabytesPerSecond: averageRead,
            averageWriteMegabytesPerSecond: averageWrite,
            sampleCount: samples.count
        )
    }
}

struct DiskActivityChartTick: Equatable {
    var value: Double
    var label: String
}

enum DiskActivityChartScale {
    static func durationSeconds(for samples: [DiskActivitySample]) -> TimeInterval {
        guard let first = samples.first?.timestamp,
              let last = samples.last?.timestamp else {
            return 0
        }
        return max(0, last.timeIntervalSince(first))
    }

    static func xTicks(for samples: [DiskActivitySample]) -> [DiskActivityChartTick] {
        let duration = durationSeconds(for: samples)
        guard duration > 0 else {
            return [DiskActivityChartTick(value: 0, label: formatDuration(0))]
        }
        return [
            DiskActivityChartTick(value: 0, label: formatDuration(0)),
            DiskActivityChartTick(value: duration / 2, label: formatDuration(duration / 2)),
            DiskActivityChartTick(value: duration, label: formatDuration(duration))
        ]
    }

    static func yTicks(maxSpeed: Double, count: Int = 10) -> [Double] {
        let maximum = roundedMaximumSpeed(maxSpeed: maxSpeed)
        guard count > 1 else { return [maximum] }
        return (0..<count).map { index in
            maximum * Double(index) / Double(count - 1)
        }
    }

    static func roundedMaximumSpeed(maxSpeed: Double) -> Double {
        let speed = max(maxSpeed, 1)
        let magnitude = pow(10, floor(log10(speed)))
        let normalized = speed / magnitude
        let rounded: Double
        if normalized <= 1 {
            rounded = 1
        } else if normalized <= 2 {
            rounded = 2
        } else if normalized <= 5 {
            rounded = 5
        } else {
            rounded = 10
        }
        return rounded * magnitude
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes < 60 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m\(String(format: "%02d", seconds))s"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h\(remainingMinutes)m"
    }
}

enum DiskActivityFormatter {
    static func speed(_ speed: Double) -> String {
        if speed >= 1_000 {
            return String(format: "%.2f GB/s", speed / 1_000)
        }
        if speed >= 100 {
            return String(format: "%.0f MB/s", speed)
        }
        if speed >= 10 {
            return String(format: "%.1f MB/s", speed)
        }
        return String(format: "%.2f MB/s", max(0, speed))
    }
}

final class DiskActivityMonitor: @unchecked Sendable {
    typealias Sleeper = @Sendable (UInt64) async throws -> Void

    private let provider: DiskActivityProviding
    private let sleeper: Sleeper

    init(
        provider: DiskActivityProviding,
        sleeper: @escaping Sleeper = { nanoseconds in try await Task.sleep(nanoseconds: nanoseconds) }
    ) {
        self.provider = provider
        self.sleeper = sleeper
    }

    func run(
        bsdName: String,
        interval: DiskActivitySampleInterval,
        onSample: @Sendable @escaping (DiskActivitySample) async -> Void
    ) async {
        let reader = provider.reader(forBSDName: bsdName)
        var previousCounters: DiskActivityCounters?

        while !Task.isCancelled {
            let counters = reader?.counters() ?? provider.counters(forBSDName: bsdName)
            if Task.isCancelled { break }

            if let counters {
                let sample = DiskActivityRateCalculator.sample(previous: previousCounters, current: counters)
                previousCounters = counters
                await onSample(sample)
            }

            do {
                try await sleeper(interval.nanoseconds)
            } catch {
                break
            }
        }
    }
}

final class IOKitDiskActivityProvider: DiskActivityProviding, @unchecked Sendable {
    func counters(forBSDName bsdName: String) -> DiskActivityCounters? {
        reader(forBSDName: bsdName)?.counters()
    }

    func reader(forBSDName bsdName: String) -> DiskActivityCounterReading? {
        guard let media = copyWholeMedia(bsdName: bsdName) else { return nil }
        defer { IOObjectRelease(media) }

        guard let driver = copyBlockStorageDriverAncestor(from: media) else { return nil }
        return IOKitDiskActivityReader(driver: driver)
    }

    private func copyWholeMedia(bsdName: String) -> io_registry_entry_t? {
        guard let matching = IOServiceMatching(kIOMediaClass) else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let media = IOIteratorNext(iterator)
            guard media != 0 else { return nil }

            let mediaBSDName = copyStringProperty(media, key: kIOBSDNameKey)
            let isWhole = copyBoolProperty(media, key: kIOMediaWholeKey)
            if mediaBSDName == bsdName, isWhole == true {
                return media
            }

            IOObjectRelease(media)
        }
    }

    private func copyBlockStorageDriverAncestor(from entry: io_registry_entry_t) -> io_registry_entry_t? {
        var current = entry
        var currentIsOwned = false

        while true {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                if currentIsOwned {
                    IOObjectRelease(current)
                }
                return nil
            }

            if currentIsOwned {
                IOObjectRelease(current)
            }

            if IOObjectConformsTo(parent, kIOBlockStorageDriverClass) != 0 {
                return parent
            }

            current = parent
            currentIsOwned = true
        }
    }

    private func copyStringProperty(_ entry: io_registry_entry_t, key: String) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private func copyBoolProperty(_ entry: io_registry_entry_t, key: String) -> Bool? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    private func copyDictionaryProperty(_ entry: io_registry_entry_t, key: String) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }
}

private final class IOKitDiskActivityReader: DiskActivityCounterReading, @unchecked Sendable {
    private let driver: io_registry_entry_t

    init(driver: io_registry_entry_t) {
        self.driver = driver
    }

    deinit {
        IOObjectRelease(driver)
    }

    func counters() -> DiskActivityCounters? {
        guard let statistics = copyDictionaryProperty(driver, key: kIOBlockStorageDriverStatisticsKey),
              let readBytes = statistics[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber,
              let writeBytes = statistics[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber else {
            return nil
        }

        return DiskActivityCounters(
            timestamp: Date(),
            readBytes: readBytes.uint64Value,
            writeBytes: writeBytes.uint64Value
        )
    }

    private func copyDictionaryProperty(_ entry: io_registry_entry_t, key: String) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }
}
