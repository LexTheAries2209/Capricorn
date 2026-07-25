// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppPreferences {
    enum Key {
        static let language = "appLanguage"
        static let showVirtualDisks = "showVirtualDisks"
        static let smartctlPath = "smartctlPath"
        static let includeSerialsInReports = "includeSerialsInReports"
        static let usesPlainTabForFeatureSwitching = "usesPlainTabForFeatureSwitching"
        static let allowSystemDiskSelfTests = "allowSystemDiskSelfTests"
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

    var includeSerialsInReports: Bool {
        didSet { defaults.set(includeSerialsInReports, forKey: Key.includeSerialsInReports) }
    }

    var usesPlainTabForFeatureSwitching: Bool {
        didSet { defaults.set(usesPlainTabForFeatureSwitching, forKey: Key.usesPlainTabForFeatureSwitching) }
    }

    var allowSystemDiskSelfTests: Bool {
        didSet { defaults.set(allowSystemDiskSelfTests, forKey: Key.allowSystemDiskSelfTests) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        languageRawValue = defaults.string(forKey: Key.language) ?? AppLanguage.english.rawValue
        showVirtualDisks = defaults.bool(forKey: Key.showVirtualDisks)
        smartctlPath = defaults.string(forKey: Key.smartctlPath) ?? ""
        includeSerialsInReports = defaults.bool(forKey: Key.includeSerialsInReports)
        usesPlainTabForFeatureSwitching = defaults.object(forKey: Key.usesPlainTabForFeatureSwitching) as? Bool ?? true
        allowSystemDiskSelfTests = defaults.bool(forKey: Key.allowSystemDiskSelfTests)
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

    private var language: AppLanguage {
        preferences.language
    }

    var body: some View {
        Form {
            Picker(language.t("Language"), selection: $preferences.languageRawValue) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.shortTitle).tag(language.rawValue)
                }
            }

            Toggle(language.t("Show virtual disks"), isOn: $preferences.showVirtualDisks)
            Toggle(language.t("Include serials in reports"), isOn: $preferences.includeSerialsInReports)
            Toggle(language.t("Use Tab to switch feature pages"), isOn: $preferences.usesPlainTabForFeatureSwitching)

            Section(language.t("SMART Self-Tests")) {
                Toggle(language.t("Allow self-tests on the system disk"), isOn: $preferences.allowSystemDiskSelfTests)
                Text(language.t("System-disk self-tests may reduce performance and increase sustained storage load. Keep a current backup before enabling this option."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}
