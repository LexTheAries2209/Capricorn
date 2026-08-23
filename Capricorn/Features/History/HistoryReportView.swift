// SPDX-License-Identifier: GPL-3.0-only
import SwiftData
import SwiftUI

struct HistoryReportView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    let smartHistory: [SmartHistoryRecord]
    let benchmarkHistory: [BenchmarkHistoryRecord]
    let activityHistory: [DiskActivityHistoryRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var showHiddenHistory = false
    @State private var reportError: String?
    private let historyScrollThreshold = 10
    private let historyRowHeight: CGFloat = 58

    private var visibleSmartHistory: [SmartHistoryRecord] {
        HistoryVisibility.visible(smartHistory)
    }

    private var hiddenSmartHistory: [SmartHistoryRecord] {
        HistoryVisibility.hidden(smartHistory)
    }

    private var visibleBenchmarkHistory: [BenchmarkHistoryRecord] {
        HistoryVisibility.visible(benchmarkHistory)
    }

    private var hiddenBenchmarkHistory: [BenchmarkHistoryRecord] {
        HistoryVisibility.hidden(benchmarkHistory)
    }

    private var visibleActivityHistory: [DiskActivityHistoryRecord] {
        HistoryVisibility.visible(activityHistory)
    }

    private var hiddenActivityHistory: [DiskActivityHistoryRecord] {
        HistoryVisibility.hidden(activityHistory)
    }

    private var hasHiddenHistory: Bool {
        !hiddenSmartHistory.isEmpty || !hiddenBenchmarkHistory.isEmpty || !hiddenActivityHistory.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    DrivePageHeaderView(drive: drive, snapshot: snapshot, showsHealthBadge: false)
                    Spacer()
                }

                Text(language.t("History & Reports"))
                    .font(.title2.bold())

                if let reportError {
                    Label(reportError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(alignment: .top, spacing: 16) {
                    historyPanel(
                        title: language.t("SMART Snapshots"),
                        symbol: "clock",
                        count: visibleSmartHistory.count,
                        emptyText: hiddenSmartHistory.isEmpty ? language.t("No saved snapshots yet.") : language.t("No visible snapshots. Hidden snapshots can be restored below."),
                        hideAll: { hideAllHistory(visibleSmartHistory) }
                    ) {
                        historyRows(visibleSmartHistory) { item in
                            smartHistoryRow(item, isHidden: false)
                        }
                    }

                    historyPanel(
                        title: language.t("Benchmark Runs"),
                        symbol: "chart.xyaxis.line",
                        count: visibleBenchmarkHistory.count,
                        emptyText: hiddenBenchmarkHistory.isEmpty ? language.t("No saved benchmark results yet.") : language.t("No visible benchmark results. Hidden benchmark results can be restored below."),
                        hideAll: { hideAllHistory(visibleBenchmarkHistory) }
                    ) {
                        historyRows(visibleBenchmarkHistory) { item in
                            benchmarkHistoryRow(item, isHidden: false)
                        }
                    }

                    historyPanel(
                        title: language.t("Live Activity History"),
                        symbol: "waveform.path.ecg.rectangle",
                        count: visibleActivityHistory.count,
                        emptyText: hiddenActivityHistory.isEmpty ? language.t("No saved activity records yet.") : language.t("No visible activity records. Hidden activity records can be restored below."),
                        hideAll: { hideAllHistory(visibleActivityHistory) }
                    ) {
                        historyRows(visibleActivityHistory) { item in
                            activityHistoryRow(item, isHidden: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if hasHiddenHistory {
                    hiddenHistoryDisclosure
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var historyScrollHeight: CGFloat {
        CGFloat(historyScrollThreshold) * historyRowHeight
    }

    @ViewBuilder
    private func historyPanel<Rows: View>(
        title: String,
        symbol: String,
        count: Int,
        emptyText: String,
        hideAll: @escaping () -> Void,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Spacer(minLength: 8)
                Button(action: hideAll) {
                    Label(language.t("Hide All"), systemImage: "eye.slash")
                }
                .controlSize(.small)
                .disabled(count == 0)
                .help(language.t("Hide All"))
            }

            if count == 0 {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else if count > historyScrollThreshold {
                ScrollView(.vertical) {
                    rows()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: historyScrollHeight)
                .scrollIndicators(.visible)
            } else {
                rows()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)
    }

    private func historyRows<Record: Identifiable, Row: View>(
        _ items: [Record],
        @ViewBuilder row: @escaping (Record) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                    .padding(.vertical, 8)
                if index < items.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var hiddenHistoryDisclosure: some View {
        DisclosureGroup(isExpanded: $showHiddenHistory) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(language.t("Hidden records remain in the local database and can be restored here."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        restoreAllHiddenHistory()
                    } label: {
                        Label(language.t("Restore All"), systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                }

                if !hiddenSmartHistory.isEmpty {
                    Text(language.t("SMART Snapshots"))
                        .font(.subheadline.bold())
                    ForEach(hiddenSmartHistory) { item in
                        smartHistoryRow(item, isHidden: true)
                        Divider()
                    }
                }

                if !hiddenBenchmarkHistory.isEmpty {
                    Text(language.t("Benchmark Runs"))
                        .font(.subheadline.bold())
                    ForEach(hiddenBenchmarkHistory) { item in
                        benchmarkHistoryRow(item, isHidden: true)
                        Divider()
                    }
                }

                if !hiddenActivityHistory.isEmpty {
                    Text(language.t("Live Activity History"))
                        .font(.subheadline.bold())
                    ForEach(hiddenActivityHistory) { item in
                        activityHistoryRow(item, isHidden: true)
                        Divider()
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label(language.t("Manage Hidden Records"), systemImage: "eye.slash")
                .font(.headline)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

    private func smartHistoryRow(_ item: SmartHistoryRecord, isHidden: Bool) -> some View {
        HStack {
            HealthBadge(status: item.health, compact: true)
            VStack(alignment: .leading) {
                Text(item.capturedAt.formatted(date: .abbreviated, time: .standard))
                Text(language.statusMessage(item.summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            historyVisibilityButton(isHidden: isHidden) {
                if isHidden {
                    restoreHistory(item)
                } else {
                    hideHistory(item)
                }
            }
        }
    }

    private func benchmarkHistoryRow(_ item: BenchmarkHistoryRecord, isHidden: Bool) -> some View {
        let activitySamples = item.activitySamples
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(item.testLabel) \(language.operationTitle(item.operation))")
                    Text(item.measuredAt.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.2f MB/s", item.bestMegabytesPerSecond))
                    .monospacedDigit()
                historyVisibilityButton(isHidden: isHidden) {
                    if isHidden {
                        restoreHistory(item)
                    } else {
                        hideHistory(item)
                    }
                }
            }

            if !activitySamples.isEmpty {
                DiskActivityChartView(
                    title: language.t("Saved Benchmark Activity"),
                    samples: activitySamples,
                    current: activitySamples.last,
                    style: .mini
                )
            }
        }
    }

    private func activityHistoryRow(_ item: DiskActivityHistoryRecord, isHidden: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.endedAt.formatted(date: .abbreviated, time: .standard))
                Text("\(DiskActivityChartScale.formatDuration(item.durationSeconds)) · \(item.sampleCount) \(language.t("samples")) · \(item.sampleInterval.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(language.operationTitle(.read)) \(DiskActivityFormatter.speed(item.peakReadMegabytesPerSecond))")
                Text("\(language.operationTitle(.write)) \(DiskActivityFormatter.speed(item.peakWriteMegabytesPerSecond))")
            }
            .font(.caption.monospacedDigit())
            historyVisibilityButton(isHidden: isHidden) {
                if isHidden {
                    restoreHistory(item)
                } else {
                    hideHistory(item)
                }
            }
        }
    }

    private func historyVisibilityButton(isHidden: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isHidden ? "arrow.uturn.backward" : "eye.slash")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .help(language.t(isHidden ? "Restore" : "Hide from history"))
        .accessibilityLabel(language.t(isHidden ? "Restore" : "Hide from history"))
    }

    private func hideHistory<T: HistoryDisplayRecord>(_ item: T) {
        do {
            try HistoryRepository(modelContext: modelContext).hide(item)
        } catch {
            reportError = language.t("Could not update history.")
        }
    }

    private func restoreHistory<T: HistoryDisplayRecord>(_ item: T) {
        do {
            try HistoryRepository(modelContext: modelContext).restore(item)
        } catch {
            reportError = language.t("Could not update history.")
        }
    }

    private func hideAllHistory<T: HistoryDisplayRecord>(_ records: [T]) {
        do {
            try HistoryRepository(modelContext: modelContext).hideAll(records)
        } catch {
            reportError = language.t("Could not update history.")
        }
    }

    private func restoreAllHiddenHistory() {
        let repository = HistoryRepository(modelContext: modelContext)
        do {
            try repository.restoreAll(hiddenSmartHistory)
            try repository.restoreAll(hiddenBenchmarkHistory)
            try repository.restoreAll(hiddenActivityHistory)
        } catch {
            reportError = language.t("Could not update history.")
        }
    }

}
