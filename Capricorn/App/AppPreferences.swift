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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        languageRawValue = defaults.string(forKey: Key.language) ?? AppLanguage.english.rawValue
        showVirtualDisks = defaults.bool(forKey: Key.showVirtualDisks)
        smartctlPath = defaults.string(forKey: Key.smartctlPath) ?? ""
        includeSerialsInReports = defaults.bool(forKey: Key.includeSerialsInReports)
        usesPlainTabForFeatureSwitching = defaults.object(forKey: Key.usesPlainTabForFeatureSwitching) as? Bool ?? true
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

    var body: some View {
        Form {
            Picker("Language", selection: $preferences.languageRawValue) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.shortTitle).tag(language.rawValue)
                }
            }

            Toggle("Show virtual disks", isOn: $preferences.showVirtualDisks)
            Toggle("Include serials in reports", isOn: $preferences.includeSerialsInReports)
            Toggle("Use Tab to switch feature pages", isOn: $preferences.usesPlainTabForFeatureSwitching)

            LabeledContent("smartctl") {
                HStack {
                    TextField("Automatic detection", text: $preferences.smartctlPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…", action: chooseSmartctl)
                    Button("Automatic") {
                        preferences.restoreAutomaticSmartctlDetection()
                    }
                }
            }

            if !preferences.smartctlPathIsValid {
                Label("The selected smartctl path is not executable.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text("Control-Tab and Control-Shift-Tab always switch feature pages. Disable plain Tab switching to restore standard keyboard focus traversal.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 620)
    }

    private func chooseSmartctl() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the smartctl executable."
        if panel.runModal() == .OK, let url = panel.url {
            preferences.smartctlPath = url.path
        }
    }
}
