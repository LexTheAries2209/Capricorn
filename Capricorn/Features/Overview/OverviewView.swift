// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

struct OverviewView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    @Environment(\.appLanguage) private var language
    @AppStorage(AppPreferences.Key.showsSmartSelfTestInterface) private var showsSmartSelfTestInterface = false

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
                    StatTile(title: language.t("Life Remaining"), value: snapshot?.lifeRemainingPercent.map { "\($0)%" } ?? language.t("Unavailable"), symbol: "battery.75percent")
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

                if showsSmartSelfTestInterface {
                    SelfTestOverviewSummary(snapshot: snapshot)
                }
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

private struct SelfTestOverviewSummary: View {
    let snapshot: SmartSnapshot?
    @Environment(\.appLanguage) private var language

    private var report: SmartSelfTestReport? { snapshot?.selfTestReport }

    var body: some View {
        InfoPanel(title: language.t("Self-Tests"), symbol: "stethoscope") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusTint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(language.t("Open SMART to view full self-test details and run tests."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let latest = report?.latestEntry {
                        Text("\(kindTitle(latest.kind)) · \(language.statusMessage(latest.status))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private var statusTitle: String {
        switch report?.state {
        case .running: language.t("Self-Test In Progress")
        case .passed: language.t("Last Self-Test Passed")
        case .failed: language.t("Last Self-Test Failed")
        case .aborted: language.t("Last Self-Test Aborted")
        case .unknown: language.t("Last Self-Test Status Unknown")
        default: language.t("No Self-Test Record")
        }
    }

    private var statusSymbol: String {
        switch report?.state {
        case .passed: "checkmark.circle.fill"
        case .failed, .aborted: "exclamationmark.triangle.fill"
        case .running: "hourglass"
        default: "questionmark.circle"
        }
    }

    private var statusTint: Color {
        switch report?.state {
        case .passed: .green
        case .failed, .aborted: .orange
        default: .secondary
        }
    }

    private func kindTitle(_ kind: SmartSelfTestKind) -> String {
        switch kind {
        case .short: language.t("Quick")
        case .long: language.t("Full")
        case .vendor: language.t("Vendor")
        case .unknown: language.t("Unknown")
        }
    }
}
