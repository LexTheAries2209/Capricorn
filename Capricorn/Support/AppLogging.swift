// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import OSLog

enum CapricornLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Capricorn"

    static let inventory = Logger(subsystem: subsystem, category: "Inventory")
    static let smart = Logger(subsystem: subsystem, category: "SMART")
    static let benchmark = Logger(subsystem: subsystem, category: "Benchmark")
    static let workload = Logger(subsystem: subsystem, category: "Workload")
    static let diskOperations = Logger(subsystem: subsystem, category: "DiskOperations")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")

    static let inventorySignposter = OSSignposter(subsystem: subsystem, category: "Inventory")
    static let benchmarkSignposter = OSSignposter(subsystem: subsystem, category: "Benchmark")
}
