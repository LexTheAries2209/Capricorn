// SPDX-License-Identifier: GPL-3.0-only
import SwiftData
import SwiftUI

@main
struct CapricornApp: App {
    @State private var viewModel: AppModel
    @State private var preferences: AppPreferences
    private let modelContainer: ModelContainer

    init() {
        let preferences = AppPreferences()
        let viewModel = AppModel()
        viewModel.showVirtualDisks = preferences.showVirtualDisks
        _preferences = State(initialValue: preferences)
        _viewModel = State(initialValue: viewModel)
        do {
            modelContainer = try ModelContainerFactory.makeApplication()
        } catch {
            fatalError("Unable to open Capricorn history database: \(error.localizedDescription)")
        }
    }

    private var language: AppLanguage {
        preferences.language
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, preferences: preferences)
                .frame(minWidth: 1050, minHeight: 680)
        }
        .defaultSize(width: 1433, height: 732)
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(after: .appSettings) {
                SettingsLink {
                    Text(language.t("Settings"))
                }
                .keyboardShortcut(
                    AppCommandShortcut.settingsKeyEquivalent,
                    modifiers: AppCommandShortcut.settings.modifiers
                )
            }

            CommandGroup(after: .toolbar) {
                Button(language.t("Next Function")) {
                    viewModel.selectNextFeatureTab()
                }
                .keyboardShortcut(AppCommandShortcut.featureTabKeyEquivalent, modifiers: AppCommandShortcut.nextFeatureTab.modifiers)

                Button(language.t("Previous Function")) {
                    viewModel.selectPreviousFeatureTab()
                }
                .keyboardShortcut(AppCommandShortcut.featureTabKeyEquivalent, modifiers: AppCommandShortcut.previousFeatureTab.modifiers)

                Divider()

                Button(language.t("Refresh Disks")) {
                    Task { await viewModel.refresh() }
                }
                .keyboardShortcut(AppCommandShortcut.refreshDisksKeyEquivalent, modifiers: AppCommandShortcut.refreshDisks.modifiers)
                .disabled(viewModel.isRefreshing || viewModel.isFirstAidBlocking)
            }
        }

        MenuBarExtra("Capricorn", systemImage: menuBarSymbol) {
            VStack(alignment: .leading, spacing: 8) {
                Label(menuBarSummary, systemImage: menuBarSymbol)
                if let drive = viewModel.selectedDrive {
                    Text(drive.displayName)
                        .font(.caption)
                }
                Button(language.t("Refresh")) {
                    Task { await viewModel.refresh() }
                }
                .keyboardShortcut(AppCommandShortcut.refreshDisksKeyEquivalent, modifiers: AppCommandShortcut.refreshDisks.modifiers)
                .disabled(viewModel.isRefreshing || viewModel.isFirstAidBlocking)
            }
            .padding(8)
        }

        Settings {
            CapricornSettingsView(preferences: preferences)
        }
    }

    private var menuBarSummary: String {
        let warningCount = viewModel.snapshots.values.filter { $0.health.severity >= HealthStatus.warning.severity }.count
        return language.healthSummary(driveCount: viewModel.drives.count, warningCount: warningCount)
    }

    private var menuBarSymbol: String {
        switch viewModel.worstHealth {
        case .good: "checkmark.seal.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .preFail: "exclamationmark.octagon.fill"
        case .failed: "xmark.octagon.fill"
        case .unavailable: "internaldrive"
        }
    }
}
