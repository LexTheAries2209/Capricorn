// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct SmartHistoryReportPayload: Codable, Hashable {
    let recordID: UUID
    let drive: DriveDevice
    let driveName: String
    let capturedAt: Date
    let health: HealthStatus
    let summary: String
    let snapshot: SmartSnapshot?

    init(record: SmartHistoryRecord, drive: DriveDevice) {
        recordID = record.id
        self.drive = drive
        driveName = record.driveName
        capturedAt = record.capturedAt
        health = record.health
        summary = record.summary
        snapshot = record.snapshot
    }
}

struct SmartHistoryReportWindow: View {
    let payload: SmartHistoryReportPayload
    @Environment(\.appLanguage) private var language
    @AppStorage(AppPreferences.Key.redactSerialNumbers) private var redactSerialNumbers = false
    @AppStorage("smartSnapshotExportFolder") private var snapshotExportFolderPath = ""
    @State private var saveMessage: String?

    private var saveMessageIsWarning: Bool {
        guard let saveMessage else { return false }
        return saveMessage.localizedCaseInsensitiveContains("failed")
            || saveMessage.localizedCaseInsensitiveContains("unavailable")
            || saveMessage.contains("失败")
            || saveMessage.contains("不可用")
    }

    var body: some View {
        VStack(spacing: 0) {
            reportHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let snapshot = payload.snapshot {
                        snapshotSummary(snapshot)
                        providerStatuses(snapshot.providerStatuses)
                        attributes(snapshot.attributes)
                    } else {
                        ContentUnavailableView(
                            language.t("SMART Snapshot Report"),
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(
                                "\(language.t("No saved SMART details are available for this snapshot."))\n\(language.statusMessage(payload.summary))"
                            )
                        )
                        .frame(maxWidth: .infinity, minHeight: 360)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .navigationTitle("\(payload.driveName) - \(language.t("SMART Snapshot Report"))")
    }

    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(payload.driveName)
                        .font(.title2.bold())
                    Label(
                        payload.capturedAt.formatted(
                            .dateTime
                                .year()
                                .month(.abbreviated)
                                .day()
                                .hour()
                                .minute()
                                .second()
                                .locale(Locale(identifier: language.localeIdentifier))
                        ),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                HealthBadge(status: payload.health, compact: true)
            }

            HStack(spacing: 8) {
                Button {
                    _ = chooseSnapshotExportFolder()
                } label: {
                    Label(language.t("Choose Folder"), systemImage: "folder.badge.gearshape")
                }
                .help(language.t(snapshotExportFolderPath.isEmpty ? "Choose Storage Folder" : "Change Storage Folder"))

                if !snapshotExportFolderPath.isEmpty {
                    Button {
                        snapshotExportFolderPath = ""
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .help(language.t("Clear Storage Folder"))
                }

                Button {
                    saveSnapshotCSV()
                } label: {
                    Label(language.t("Save CSV"), systemImage: "tray.and.arrow.down")
                }
                .disabled(payload.snapshot == nil)
                .help(language.t("Save SMART Snapshot CSV"))

                if let saveMessage {
                    Label(
                        saveMessage,
                        systemImage: saveMessageIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(saveMessageIsWarning ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                } else if !snapshotExportFolderPath.isEmpty {
                    Text(snapshotExportFolderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(20)
    }

    private func saveSnapshotCSV() {
        guard let snapshot = payload.snapshot else { return }

        let exportFolderPath: String
        if snapshotExportFolderPath.isEmpty {
            guard let selectedFolderPath = chooseSnapshotExportFolder() else { return }
            exportFolderPath = selectedFolderPath
        } else {
            exportFolderPath = snapshotExportFolderPath
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: exportFolderPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            saveMessage = language.t("The selected folder is unavailable.")
            return
        }

        let fileURL = URL(fileURLWithPath: exportFolderPath, isDirectory: true)
            .appendingPathComponent(
                ReportExporter.smartSnapshotFileName(
                    drive: payload.drive,
                    date: snapshot.capturedAt,
                    language: language
                )
            )

        do {
            let report = ReportExporter.smartSnapshotCSVReport(
                drive: payload.drive,
                snapshot: snapshot,
                language: language,
                redactSerialNumbers: redactSerialNumbers
            )
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            saveMessage = "\(language.t("CSV saved:")) \(fileURL.lastPathComponent)"
        } catch {
            saveMessage = "\(language.t("CSV export failed:")) \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func chooseSnapshotExportFolder() -> String? {
        let panel = NSOpenPanel()
        panel.title = language.t("Choose Storage Folder")
        panel.message = language.t("Choose an optional folder for exported SMART snapshot CSV files.")
        panel.prompt = language.t("Use Folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if !snapshotExportFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: snapshotExportFolderPath, isDirectory: true)
        } else if let fallback = payload.drive.benchmarkMountPoint {
            panel.directoryURL = URL(fileURLWithPath: fallback, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        snapshotExportFolderPath = url.path
        saveMessage = nil
        return url.path
    }

    private func snapshotSummary(_ snapshot: SmartSnapshot) -> some View {
        let historySummary = SmartHistorySummary(snapshot: snapshot)

        return InfoPanel(title: language.t("Snapshot Summary"), symbol: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.statusMessage(snapshot.summary))
                    .font(.subheadline)
                    .textSelection(.enabled)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    reportMetric(language.t("Health"), language.healthBadgeTitle(snapshot.health, compact: true), "heart.text.square")
                    if let temperature = snapshot.temperatureCelsius {
                        reportMetric(language.t("Temperature"), String(format: "%.1f °C", temperature), "thermometer.medium")
                    }
                    if let life = snapshot.lifeRemainingPercent {
                        reportMetric(language.t("Life Remaining"), "\(life)%", LifeRemainingBatterySymbol.symbol(for: life))
                    }
                    if let hours = snapshot.powerOnHours {
                        reportMetric(language.t("Power-On Hours"), hours.formatted(), "timer")
                    }
                    if let cycles = snapshot.powerCycleCount {
                        reportMetric(language.t("Power Cycles"), cycles.formatted(), "power")
                    }
                    if let errors = snapshot.mediaErrors {
                        reportMetric(language.t("Media Errors"), errors.formatted(), "exclamationmark.triangle")
                    }
                    if let dataRead = historySummary.dataRead {
                        reportMetric(language.t("Total Read"), dataRead, "arrow.down.circle")
                    }
                    if let dataWritten = historySummary.dataWritten {
                        reportMetric(language.t("Total Written"), dataWritten, "arrow.up.circle")
                    }
                }
            }
        }
    }

    private func reportMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func providerStatuses(_ statuses: [ProviderStatus]) -> some View {
        if !statuses.isEmpty {
            InfoPanel(title: language.t("Provider Status"), symbol: "externaldrive.connected.to.line.below") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(statuses.enumerated()), id: \.element.id) { index, status in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: status.state.symbolName)
                                .foregroundStyle(status.state.tint)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(status.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(providerStateTitle(status.state))
                                        .font(.caption)
                                        .foregroundStyle(status.state.tint)
                                }
                                Text(language.statusMessage(status.message))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)

                        if index < statuses.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func attributes(_ attributes: [SmartAttribute]) -> some View {
        InfoPanel(
            title: "\(language.t("SMART Attributes")) (\(attributes.count))",
            symbol: "list.bullet.rectangle"
        ) {
            if attributes.isEmpty {
                Text(language.t("No SMART Attributes"))
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(attributes.enumerated()), id: \.offset) { index, attribute in
                        SmartHistoryAttributeReportRow(attribute: attribute)
                            .padding(.vertical, 10)
                        if index < attributes.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func providerStateTitle(_ state: ProviderState) -> String {
        switch state {
        case .available: language.t("Available")
        case .limited: language.t("Limited")
        case .unavailable: language.t("Unavailable")
        case .failed: language.t("Failed")
        }
    }
}

private struct SmartHistoryAttributeReportRow: View {
    let attribute: SmartAttribute
    @Environment(\.appLanguage) private var language

    private var display: SmartAttributeDisplay {
        language.smartAttributeDisplay(attribute)
    }

    private var hasNormalizedValues: Bool {
        attribute.current != nil || attribute.worst != nil || attribute.threshold != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(display.title)
                    .font(.headline)
                Text(attribute.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                HealthBadge(status: attribute.status, compact: true)
            }

            Text(language == .simplifiedChinese ? "\(attribute.name) - \(display.subtitle)" : display.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent(language.t("Raw")) {
                Text(attribute.rawValue)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }

            if hasNormalizedValues {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 22) {
                        normalizedValue(language.t("Current"), attribute.current)
                        normalizedValue(language.t("Worst"), attribute.worst)
                        normalizedValue(language.t("Threshold"), attribute.threshold)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        normalizedValue(language.t("Current"), attribute.current)
                        normalizedValue(language.t("Worst"), attribute.worst)
                        normalizedValue(language.t("Threshold"), attribute.threshold)
                    }
                }
            }

            Label(attribute.source, systemImage: "shippingbox")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func normalizedValue(_ title: String, _ value: Int?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "-")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
    }
}
