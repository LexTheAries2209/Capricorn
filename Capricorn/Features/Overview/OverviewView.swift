// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

struct OverviewView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    @Environment(\.appLanguage) private var language
    @State private var showsSelfTestLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DrivePageHeaderView(drive: drive, snapshot: snapshot)

                if let snapshot {
                    Text(language.statusMessage(snapshot.summary))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    StatTile(title: language.t("Capacity"), value: formatByteCount(drive.sizeBytes), symbol: "square.stack.3d.down.right")
                    StatTile(title: language.t("Format"), value: drive.fileSystemSummary ?? language.t("Unavailable"), symbol: "doc.richtext")
                    StatTile(title: language.t("Temperature"), value: snapshot?.temperatureCelsius.map { String(format: "%.1f C", $0) } ?? language.t("Unavailable"), symbol: "thermometer.medium")
                    StatTile(title: language.t("Life Remaining"), value: snapshot?.lifeRemainingPercent.map { "\($0)%" } ?? language.t("Unavailable"), symbol: "battery.75percent")
                    StatTile(title: language.t("Power-On Hours"), value: snapshot?.powerOnHours.map(String.init) ?? language.t("Unavailable"), symbol: "timer")
                    StatTile(title: language.t("Media Errors"), value: snapshot?.mediaErrors.map(String.init) ?? language.t("Unavailable"), symbol: "exclamationmark.triangle")
                    StatTile(title: "SMART", value: language.statusMessage(snapshot?.smartStatusRaw ?? drive.smartStatusRaw) ?? language.t("Unavailable"), symbol: "checklist.checked")
                }

                InfoPanel(title: language.t("Volumes"), symbol: "opticaldiscdrive") {
                    if drive.volumes.isEmpty {
                        Text(language.t("No mounted volumes are mapped to this physical disk."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(drive.volumes) { volume in
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
                }

                SelfTestSummaryView(snapshot: snapshot, isExpanded: $showsSelfTestLog)
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
}
