// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

struct OverviewView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    let diskCheckReport: DiskCheckReport?
    let isDiskChecking: Bool
    let allowSystemDiskSelfTests: Bool
    let canRunQuickCheck: Bool
    let runQuickCheck: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DrivePageHeaderView(drive: drive, snapshot: snapshot, showsSerialNumber: true)

                if let snapshot {
                    Text(language.statusMessage(snapshot.summary))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    StatTile(title: language.t("Capacity"), value: formatByteCount(drive.sizeBytes), symbol: "square.stack.3d.down.right")
                    if let capacityUsage = drive.capacityUsage {
                        StatTile(title: language.t("Used Capacity"), value: formatByteCount(capacityUsage.usedBytes), symbol: "chart.pie.fill")
                        StatTile(title: language.t("Available Capacity"), value: formatByteCount(capacityUsage.availableBytes), symbol: "internaldrive")
                    }
                    StatTile(title: language.t("Format"), value: drive.fileSystemSummary ?? language.t("Unavailable"), symbol: "doc.richtext")
                    StatTile(
                        title: language.t("Temperature"),
                        value: snapshot?.temperatureCelsius.map { String(format: "%.1f C", $0) } ?? language.t("Unavailable"),
                        symbol: "thermometer.medium",
                        valueTint: temperatureValueTint
                    )
                    StatTile(
                        title: language.t("Life Remaining"),
                        value: snapshot?.lifeRemainingPercent.map { "\($0)%" } ?? language.t("Unavailable"),
                        symbol: LifeRemainingBatterySymbol.symbol(for: snapshot?.lifeRemainingPercent)
                    )
                    StatTile(title: language.t("Power-On Hours"), value: snapshot?.powerOnHours.map(String.init) ?? language.t("Unavailable"), symbol: "timer")
                    StatTile(title: language.t("Media Errors"), value: snapshot?.mediaErrors.map(String.init) ?? language.t("Unavailable"), symbol: "exclamationmark.triangle")
                    StatTile(title: "SMART", value: language.statusMessage(snapshot?.smartStatusRaw ?? drive.smartStatusRaw) ?? language.t("Unavailable"), symbol: "checklist.checked")
                }

                InfoPanel(title: language.t("Volumes"), symbol: "opticaldiscdrive") {
                    if drive.displayableVolumes.isEmpty {
                        Text(language.t("No mounted volumes are mapped to this physical disk."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(drive.displayableVolumes) { volume in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(volume.name)
                                    Text(volumeSubtitle(volume))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(formatByteCount(volume.sizeBytes))
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                    }
                }

                InfoPanel(title: language.t("Providers"), symbol: "antenna.radiowaves.left.and.right") {
                    ForEach(snapshot?.providerStatuses ?? []) { status in
                        HStack(alignment: .top) {
                            Image(systemName: status.state.symbolName)
                                .foregroundStyle(status.state.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.name)
                                    .font(.headline)
                                Text(language.statusMessage(status.message))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }

                    if let passthrough = USBSmartCommandPassthroughStatus.resolve(for: drive, snapshot: snapshot) {
                        HStack(alignment: .top) {
                            Image(systemName: passthrough.state.symbolName)
                                .foregroundStyle(passthrough.state.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.t(passthrough.kind.titleKey))
                                    .font(.headline)
                                Text(language.statusMessage(passthrough.state.messageKey))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                DiskCheckOverviewSummary(
                    report: diskCheckReport,
                    isRunning: isDiskChecking,
                    requiresSystemDiskPermission: drive.isSystemDisk && !allowSystemDiskSelfTests,
                    canRunQuickCheck: canRunQuickCheck,
                    runQuickCheck: runQuickCheck
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func volumeSubtitle(_ volume: DriveDevice.Volume) -> String {
        let path = volume.mountPoint ?? volume.deviceIdentifier
        guard let format = FileSystemFormatResolver.normalized(volume.fileSystemType) else {
            return path
        }
        return "\(path) · \(format)"
    }

    private func temperatureTint(for celsius: Double) -> Color? {
        switch DriveTemperatureLevel(celsius: celsius) {
        case .normal: nil
        case .elevated: .yellow
        case .critical: .red
        }
    }

    private var temperatureValueTint: Color? {
        guard let celsius = snapshot?.temperatureCelsius else { return nil }
        return temperatureTint(for: celsius)
    }
}

private extension USBSmartCommandPassthroughKind {
    var titleKey: String {
        switch self {
        case .sata: "USB-SATA SMART Command Passthrough"
        case .nvme: "USB-NVMe SMART Command Passthrough"
        }
    }
}

private extension ProviderState {
    var messageKey: String {
        switch self {
        case .available: "SMART data was successfully read through this USB bridge."
        case .limited: "The USB bridge was identified, but SMART data is currently limited."
        case .unavailable, .failed: "The USB bridge was identified, but SMART commands could not be read."
        }
    }
}

private struct DiskCheckOverviewSummary: View {
    let report: DiskCheckReport?
    let isRunning: Bool
    let requiresSystemDiskPermission: Bool
    let canRunQuickCheck: Bool
    let runQuickCheck: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        InfoPanel(title: language.t("Quick Disk Check"), symbol: "doc.text.magnifyingglass") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusTint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                    if let report {
                        Text("\(language.t("Last checked")): \(formattedCheckDate(report.capturedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if requiresSystemDiskPermission {
                        Text(language.t("Enable system-disk checks in Settings before running Quick Disk Check."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    if requiresSystemDiskPermission {
                        SettingsLink {
                            Label(language.t("Settings"), systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Button(action: runQuickCheck) {
                        Label(language.t("Run Quick Disk Check"), systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canRunQuickCheck)
                }
            }
        }
    }

    private var statusTitle: String {
        if isRunning {
            return language.t("Disk Check In Progress")
        }
        guard let report else { return language.t("No Disk Check Record") }
        return report.hasIssues
            ? language.t("Disk Check Reported Issues")
            : language.t("Last Disk Check Passed")
    }

    private var statusSymbol: String {
        if isRunning { return "hourglass" }
        guard let report else { return "questionmark.circle" }
        return report.hasIssues ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusTint: Color {
        if isRunning { return .blue }
        guard let report else { return .secondary }
        return report.hasIssues ? .orange : .green
    }

    private func formattedCheckDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.timeZone = TimeZone(secondsFromGMT: language == .simplifiedChinese ? 8 * 60 * 60 : 0)
        formatter.dateFormat = language == .simplifiedChinese
            ? "yyyy年M月d日 HH:mm:ss 'UTC+8'"
            : "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }
}
