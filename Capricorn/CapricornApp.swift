// SPDX-License-Identifier: GPL-3.0-only
import SwiftData
import SwiftUI

@main
struct CapricornApp: App {
    @StateObject private var viewModel = DITViewModel()
    @AppStorage("appLanguage") private var languageRawValue = AppLanguage.english.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .english
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1433, minHeight: 732)
        }
        .defaultSize(width: 1433, height: 732)
        .modelContainer(for: [SmartHistoryRecord.self, BenchmarkHistoryRecord.self, DiskActivityHistoryRecord.self, AppSettingsRecord.self])
        .commands {
            CommandGroup(after: .toolbar) {
                Button(language.t("Refresh Disks")) {
                    Task { await viewModel.refresh() }
                }
                .keyboardShortcut(AppCommandShortcut.refreshDisksKeyEquivalent, modifiers: AppCommandShortcut.refreshDisks.modifiers)
                .disabled(viewModel.isRefreshing)
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
            }
            .padding(8)
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
