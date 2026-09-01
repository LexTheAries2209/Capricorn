// SPDX-License-Identifier: GPL-3.0-only
import SwiftData
import SwiftUI

@main
struct CapricornApp: App {
    @State private var viewModel: AppModel
    @State private var preferences: AppPreferences
    @State private var updateChecker: AppUpdateChecker
    @Environment(\.openSettings) private var openSettings
    private let modelContainer: ModelContainer

    init() {
        let preferences = AppPreferences()
        let viewModel = AppModel()
        let updateChecker = AppUpdateChecker()
        viewModel.showVirtualDisks = preferences.showVirtualDisks
        _preferences = State(initialValue: preferences)
        _viewModel = State(initialValue: viewModel)
        _updateChecker = State(initialValue: updateChecker)
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
                .task {
                    await updateChecker.checkQuietlyAtLaunch()
                }
        }
        .defaultSize(width: 1433, height: 732)
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(language.t("Check for Updates…")) {
                    openSettings()
                    Task { await updateChecker.checkNow() }
                }
                .disabled(updateChecker.state == .checking)

                SettingsLink()
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
                    Text(drive.catalogDisplayName)
                        .font(.caption)
                        .lineLimit(2)
                        .help(drive.catalogDisplayHelp(language: language))
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
            CapricornSettingsView(
                preferences: preferences,
                updateChecker: updateChecker,
                viewModel: viewModel
            )
        }
        .defaultSize(width: 620, height: 680)
        .windowResizability(.contentSize)
        .modelContainer(modelContainer)
        .commandsRemoved()
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
