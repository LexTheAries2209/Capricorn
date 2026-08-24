// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import Observation
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
        static let avoidWakingSleepingDisks = "avoidWakingSleepingDisks"
        static let redactSerialNumbers = "redactSerialNumbers"
        static let automaticRefreshIntervalMinutes = "automaticRefreshIntervalMinutes"
        static let showsCheckAndRepairActions = "showsCheckAndRepairActions"
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        languageRawValue = defaults.string(forKey: Key.language) ?? AppLanguage.english.rawValue
        showVirtualDisks = defaults.bool(forKey: Key.showVirtualDisks)
        smartctlPath = defaults.string(forKey: Key.smartctlPath) ?? ""
        usesPlainTabForFeatureSwitching = defaults.object(forKey: Key.usesPlainTabForFeatureSwitching) as? Bool ?? true
        allowSystemDiskSelfTests = defaults.bool(forKey: Key.allowSystemDiskSelfTests)
        avoidWakingSleepingDisks = defaults.object(forKey: Key.avoidWakingSleepingDisks) as? Bool ?? true
        redactSerialNumbers = defaults.bool(forKey: Key.redactSerialNumbers)
        automaticRefreshInterval = DiskAutomaticRefreshInterval(
            rawValue: defaults.integer(forKey: Key.automaticRefreshIntervalMinutes)
        ) ?? .off
        showsCheckAndRepairActions = defaults.bool(forKey: Key.showsCheckAndRepairActions)
    }

    var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .english
    }

    var smartctlPathIsValid: Bool {
        smartctlPath.isEmpty || FileManager.default.isExecutableFile(atPath: smartctlPath)
    }

    func restoreAutomaticSmartctlDetection() {
        smartctlPath = ""
    }
}

struct CapricornSettingsView: View {
    @Bindable var preferences: AppPreferences
    @Bindable var updateChecker: AppUpdateChecker
    @State private var historyDatabaseLocationError: String?

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
            Toggle(language.t("Redact serial numbers"), isOn: $preferences.redactSerialNumbers)
            Text(language.t("When enabled, serial numbers show the first four characters followed by asterisks. Internal matching and history continue to use the full value."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Section(language.t("Disk Actions")) {
                Toggle(language.t("Show Check and Repair in Disk Actions"), isOn: $preferences.showsCheckAndRepairActions)
                Text(language.t("When disabled, Check and Repair is hidden from the disk action menu."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(language.t("SMART Self-Tests")) {
                Toggle(language.t("Allow self-tests on the system disk"), isOn: $preferences.allowSystemDiskSelfTests)
                Text(language.t("System-disk self-tests may reduce performance and increase sustained storage load. Keep a current backup before enabling this option."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                Button {
                    openHistoryDatabaseLocation()
                } label: {
                    Label(language.t("Open History Database Location"), systemImage: "folder")
                }
                .disabled(historyDatabaseDirectoryURL == nil)

                if let historyDatabaseLocationError {
                    Label(historyDatabaseLocationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            LabeledContent("smartctl") {
                HStack {
                    TextField(language.t("Automatic detection"), text: $preferences.smartctlPath)
                        .textFieldStyle(.roundedBorder)
                    Button(language.t("Choose…"), action: chooseSmartctl)
                    Button(language.t("Automatic")) {
                        preferences.restoreAutomaticSmartctlDetection()
                    }
                }
            }

            if !preferences.smartctlPathIsValid {
                Label(language.t("The selected smartctl path is not executable."), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text(language.t("Control-Tab and Control-Shift-Tab always switch feature pages. Disable plain Tab switching to restore standard keyboard focus traversal."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 620)
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
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
}
