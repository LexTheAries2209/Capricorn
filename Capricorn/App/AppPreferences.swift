// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI

enum DiskAutomaticRefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case everyMinute = 1
    case every3Minutes = 3
    case every5Minutes = 5
    case every10Minutes = 10
    case every15Minutes = 15
    case every30Minutes = 30

    var id: Int { rawValue }

    var nanoseconds: UInt64? {
        guard self != .off else { return nil }
        return UInt64(rawValue) * 60 * 1_000_000_000
    }

    func title(language: AppLanguage) -> String {
        switch (language, self) {
        case (_, .off):
            language.t("Off")
        case (.english, .everyMinute):
            "Every minute"
        case (.simplifiedChinese, .everyMinute):
            "每 1 分钟"
        case (.english, _):
            "Every \(rawValue) minutes"
        case (.simplifiedChinese, _):
            "每 \(rawValue) 分钟"
        }
    }
}

@MainActor
@Observable
final class AppPreferences {
    enum Key {
        static let language = "appLanguage"
        static let showVirtualDisks = "showVirtualDisks"
        static let smartctlPath = "smartctlPath"
        static let usesPlainTabForFeatureSwitching = "usesPlainTabForFeatureSwitching"
        static let allowSystemDiskSelfTests = "allowSystemDiskSelfTests"
        static let showsSmartSelfTestInterface = "showsSmartSelfTestInterface"
        static let avoidWakingSleepingDisks = "avoidWakingSleepingDisks"
        static let redactSerialNumbers = "redactSerialNumbers"
        static let automaticRefreshIntervalMinutes = "automaticRefreshIntervalMinutes"
        static let showsCheckAndRepairActions = "showsCheckAndRepairActions"
        static let representativeVolumeStartupPreference = "representativeVolumeStartupPreference"
    }

    private let defaults: UserDefaults

    var languageRawValue: String {
        didSet { defaults.set(languageRawValue, forKey: Key.language) }
    }

    var showVirtualDisks: Bool {
        didSet { defaults.set(showVirtualDisks, forKey: Key.showVirtualDisks) }
    }

    var smartctlPath: String {
        didSet {
            let trimmed = smartctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaults.removeObject(forKey: Key.smartctlPath)
            } else {
                defaults.set(trimmed, forKey: Key.smartctlPath)
            }
        }
    }

    var usesPlainTabForFeatureSwitching: Bool {
        didSet { defaults.set(usesPlainTabForFeatureSwitching, forKey: Key.usesPlainTabForFeatureSwitching) }
    }

    var allowSystemDiskSelfTests: Bool {
        didSet { defaults.set(allowSystemDiskSelfTests, forKey: Key.allowSystemDiskSelfTests) }
    }

    /// Self-tests can put sustained load on a disk. Keep their status and
    /// controls out of the main views until the user explicitly opts in.
    var showsSmartSelfTestInterface: Bool {
        didSet { defaults.set(showsSmartSelfTestInterface, forKey: Key.showsSmartSelfTestInterface) }
    }

    var avoidWakingSleepingDisks: Bool {
        didSet { defaults.set(avoidWakingSleepingDisks, forKey: Key.avoidWakingSleepingDisks) }
    }

    /// Controls only user-facing serial-number rendering. Internal identity,
    /// history matching, and persistence continue to use the full value.
    var redactSerialNumbers: Bool {
        didSet { defaults.set(redactSerialNumbers, forKey: Key.redactSerialNumbers) }
    }

    var automaticRefreshInterval: DiskAutomaticRefreshInterval {
        didSet { defaults.set(automaticRefreshInterval.rawValue, forKey: Key.automaticRefreshIntervalMinutes) }
    }

    /// Check and repair commands can modify filesystem metadata, so their
    /// sidebar entry is opt-in rather than exposed in every disk menu by default.
    var showsCheckAndRepairActions: Bool {
        didSet { defaults.set(showsCheckAndRepairActions, forKey: Key.showsCheckAndRepairActions) }
    }

    /// Controls the initial representative volume for each non-system drive.
    /// Manual sidebar changes remain active for the current application session.
    var representativeVolumeStartupPreference: RepresentativeVolumeStartupPreference {
        didSet { defaults.set(representativeVolumeStartupPreference.rawValue, forKey: Key.representativeVolumeStartupPreference) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        languageRawValue = defaults.string(forKey: Key.language) ?? AppLanguage.english.rawValue
        showVirtualDisks = defaults.bool(forKey: Key.showVirtualDisks)
        smartctlPath = defaults.string(forKey: Key.smartctlPath) ?? ""
        usesPlainTabForFeatureSwitching = defaults.object(forKey: Key.usesPlainTabForFeatureSwitching) as? Bool ?? true
        allowSystemDiskSelfTests = defaults.bool(forKey: Key.allowSystemDiskSelfTests)
        showsSmartSelfTestInterface = defaults.bool(forKey: Key.showsSmartSelfTestInterface)
        avoidWakingSleepingDisks = defaults.object(forKey: Key.avoidWakingSleepingDisks) as? Bool ?? true
        redactSerialNumbers = defaults.bool(forKey: Key.redactSerialNumbers)
        automaticRefreshInterval = DiskAutomaticRefreshInterval(
            rawValue: defaults.integer(forKey: Key.automaticRefreshIntervalMinutes)
        ) ?? .off
        showsCheckAndRepairActions = defaults.bool(forKey: Key.showsCheckAndRepairActions)
        representativeVolumeStartupPreference = RepresentativeVolumeStartupPreference(
            rawValue: defaults.string(forKey: Key.representativeVolumeStartupPreference) ?? ""
        ) ?? .largestCapacity
    }

    var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .english
    }

    var smartctlPathIsValid: Bool {
        smartctlPath.isEmpty || FileManager.default.isExecutableFile(atPath: smartctlPath)
    }

    func useBundledSmartctl() {
        smartctlPath = ""
    }

    func restoreAutomaticSmartctlDetection() {
        useBundledSmartctl()
    }
}

struct CapricornSettingsView: View {
    @Bindable var preferences: AppPreferences
    @Bindable var updateChecker: AppUpdateChecker
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SmartHistoryRecord.capturedAt, order: .reverse) private var smartHistoryRecords: [SmartHistoryRecord]
    @Query(sort: \BenchmarkHistoryRecord.measuredAt, order: .reverse) private var benchmarkHistoryRecords: [BenchmarkHistoryRecord]
    @Query(sort: \DiskActivityHistoryRecord.endedAt, order: .reverse) private var activityHistoryRecords: [DiskActivityHistoryRecord]
    @State private var historyDatabaseLocationError: String?
    @State private var historyDatabaseClearError: String?
    @State private var historyDatabaseClearResult: String?
    @State private var isConfirmingHistoryDatabaseClear = false
    @State private var historyDatabaseSizeBytes: Int64?
    @State private var pendingHistoryDatabaseStatistics: HistoryDatabaseStatistics?
    @State private var smartctlExecutableInfo: SmartctlExecutableInfo?

    private var language: AppLanguage {
        preferences.language
    }

    var body: some View {
        Form {
            AppUpdateSettingsSection(updateChecker: updateChecker, language: language)

            Picker(language.t("Language"), selection: $preferences.languageRawValue) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.shortTitle).tag(language.rawValue)
                }
            }

            Toggle(language.t("Show virtual disks"), isOn: $preferences.showVirtualDisks)
            Toggle(language.t("Use Tab to switch feature pages"), isOn: $preferences.usesPlainTabForFeatureSwitching)
            Text(language.t("Control-Tab and Control-Shift-Tab always switch feature pages. Disable plain Tab switching to restore standard keyboard focus traversal."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(language.t("Redact serial numbers"), isOn: $preferences.redactSerialNumbers)
            Text(language.t("When enabled, serial numbers show the first four characters followed by asterisks. Internal matching and history continue to use the full value."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Section(language.t("Disk Actions")) {
                Toggle(language.t("Show Check and Repair in Disk Actions"), isOn: $preferences.showsCheckAndRepairActions)
                Text(language.t("When disabled, Check and Repair is hidden from the disk action menu."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    language.t("Volume selected when Capricorn opens"),
                    selection: $preferences.representativeVolumeStartupPreference
                ) {
                    ForEach(RepresentativeVolumeStartupPreference.allCases) { preference in
                        Text(preference.title(language: language)).tag(preference)
                    }
                }
                Text(language.t("This applies only when Capricorn starts. Switching a volume from Disk Actions takes effect immediately."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(language.t("SMART Self-Tests")) {
                Toggle(language.t("Show SMART self-test status and controls"), isOn: $preferences.showsSmartSelfTestInterface)
                Text(language.t("When disabled, self-test status, records, and controls are hidden in Overview and SMART."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if preferences.showsSmartSelfTestInterface {
                    Toggle(language.t("Allow self-tests on the system disk"), isOn: $preferences.allowSystemDiskSelfTests)
                    Text(language.t("System-disk self-tests may reduce performance and increase sustained storage load. Keep a current backup before enabling this option."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(language.t("Disk Refresh")) {
                Picker(
                    language.t("Automatic disk refresh"),
                    selection: $preferences.automaticRefreshInterval
                ) {
                    ForEach(DiskAutomaticRefreshInterval.allCases) { interval in
                        Text(interval.title(language: language)).tag(interval)
                    }
                }
                Text(language.t("Periodically rescans connected disks and refreshes SMART data. Disk connection and removal events always refresh automatically."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(language.t("Do not wake sleeping disks for SMART refresh"), isOn: $preferences.avoidWakingSleepingDisks)
                Text(language.t("When an ATA or SCSI disk is in standby or sleep mode, Capricorn keeps its previous SMART data instead of spinning it up. Active disks continue to refresh normally."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(language.t("History Database")) {
                LabeledContent(language.t("Location")) {
                    Text(historyDatabaseDirectoryURL?.path ?? language.t("Unavailable"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                LabeledContent(language.t("Database Usage")) {
                    Text("\(historyDatabaseSizeText) · \(historyRecordCount) \(language.t("Records"))")
                        .monospacedDigit()
                }

                HStack {
                    Button {
                        openHistoryDatabaseLocation()
                    } label: {
                        Label(language.t("Open History Database Location"), systemImage: "folder")
                    }
                    .disabled(historyDatabaseDirectoryURL == nil)

                    Spacer(minLength: 12)

                    Button(role: .destructive) {
                        historyDatabaseClearResult = nil
                        historyDatabaseClearError = nil
                        pendingHistoryDatabaseStatistics = currentHistoryDatabaseStatistics
                        isConfirmingHistoryDatabaseClear = true
                    } label: {
                        Label(language.t("Clear History Database"), systemImage: "trash")
                    }
                    .foregroundStyle(.red)
                }

                if let historyDatabaseLocationError {
                    Label(historyDatabaseLocationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let historyDatabaseClearError {
                    Label(historyDatabaseClearError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let historyDatabaseClearResult {
                    Label(historyDatabaseClearResult, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(language.t("SMART Tool")) {
                LabeledContent("smartctl") {
                    HStack {
                        TextField(language.t("External smartctl path (optional)"), text: $preferences.smartctlPath)
                            .textFieldStyle(.roundedBorder)
                        Button(language.t("Choose…"), action: chooseSmartctl)
                        Button(language.t("Use Bundled")) {
                            preferences.useBundledSmartctl()
                        }
                    }
                }

                Text(language.t("Capricorn uses its bundled smartctl unless you select an executable here."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let smartctlExecutableInfo {
                    LabeledContent(language.t("Effective smartctl")) {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(language.t(smartctlExecutableInfo.origin == .external ? "External override" : "Bundled"))
                            Text(smartctlExecutableInfo.path ?? language.t("Unavailable"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            if let version = smartctlExecutableInfo.version {
                                Text("\(language.t("smartctl Version")): \(version)")
                            }
                            if let driveDatabaseVersion = smartctlExecutableInfo.driveDatabaseVersion {
                                Text("\(language.t("Drive Database")): \(driveDatabaseVersion)")
                            }
                            if let isCompatible = smartctlExecutableInfo.isCompatible {
                                Text(language.t(isCompatible ? "Compatible" : "Incompatible"))
                                    .foregroundStyle(isCompatible ? Color.secondary : Color.orange)
                            }
                        }
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                    }
                    if let error = smartctlExecutableInfo.error {
                        Label(language.statusMessage(error), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if smartctlExecutableInfo.isCompatible == nil {
                        Label(language.t("Compatibility could not be verified."), systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if !preferences.smartctlPathIsValid {
                    Label(language.t("The selected smartctl path is not executable."), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 620)
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
        .task {
            refreshHistoryDatabaseSize()
        }
        .task(id: preferences.smartctlPath) {
            smartctlExecutableInfo = await SmartctlSmartProvider().executableInfo()
        }
        .alert(language.t("Clear History Database"), isPresented: $isConfirmingHistoryDatabaseClear) {
            Button(language.t("Clear History Database"), role: .destructive) {
                clearHistoryDatabase()
            }
            Button(language.t("Cancel"), role: .cancel) {}
        } message: {
            let statistics = pendingHistoryDatabaseStatistics ?? currentHistoryDatabaseStatistics
            Text(
                "\(language.t("Database Size")): \(formattedByteCount(statistics.sizeBytes))\n" +
                "\(language.t("History Record Count")): \(statistics.recordCount)\n\n" +
                language.t("This permanently removes all SMART, benchmark, and live-activity history from the current database. It cannot be undone.")
            )
        }
    }

    private func chooseSmartctl() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = language.t("Choose")
        panel.message = language.t("Choose the smartctl executable.")
        if panel.runModal() == .OK, let url = panel.url {
            preferences.smartctlPath = url.path
        }
    }

    private var historyDatabaseDirectoryURL: URL? {
        try? ModelContainerFactory.applicationHistoryDirectoryURL()
    }

    private var historyRecordCount: Int {
        smartHistoryRecords.count + benchmarkHistoryRecords.count + activityHistoryRecords.count
    }

    private var historyDatabaseSizeText: String {
        guard let historyDatabaseSizeBytes else { return language.t("Unavailable") }
        return formattedByteCount(historyDatabaseSizeBytes)
    }

    private var currentHistoryDatabaseStatistics: HistoryDatabaseStatistics {
        HistoryDatabaseStatistics(
            sizeBytes: historyDatabaseSizeBytes ?? 0,
            recordCount: historyRecordCount
        )
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }

    private func refreshHistoryDatabaseSize() {
        guard let directory = historyDatabaseDirectoryURL else {
            historyDatabaseSizeBytes = nil
            return
        }

        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let size = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )?.reduce(into: Int64(0)) { total, item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return }
            total += Int64(values.fileSize ?? 0)
        }
        historyDatabaseSizeBytes = size ?? 0
    }

    private func openHistoryDatabaseLocation() {
        do {
            let directory = try ModelContainerFactory.applicationHistoryDirectoryURL()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            historyDatabaseLocationError = nil
            NSWorkspace.shared.open(directory)
        } catch {
            historyDatabaseLocationError = UserFacingError.message(
                language.t("Unable to open the history database location."),
                error: error
            )
        }
    }

    private func clearHistoryDatabase() {
        do {
            let removedCount = try HistoryRepository(modelContext: modelContext).clearAllHistory()
            historyDatabaseClearError = nil
            historyDatabaseClearResult = "\(language.t("History database cleared.")) \(removedCount) \(language.t("records removed."))"
            pendingHistoryDatabaseStatistics = nil
            refreshHistoryDatabaseSize()
        } catch {
            historyDatabaseClearResult = nil
            historyDatabaseClearError = UserFacingError.message(
                language.t("Unable to clear the history database."),
                error: error
            )
        }
    }
}

private struct HistoryDatabaseStatistics {
    let sizeBytes: Int64
    let recordCount: Int
}
