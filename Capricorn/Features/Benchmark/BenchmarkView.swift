// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

struct BenchmarkView: View {
    let drive: DriveDevice
    var viewModel: AppModel
    let saveResults: ([BenchmarkResult], [DiskActivitySample]) -> Void
    @Environment(\.appLanguage) private var language

    @AppStorage("benchmarkTargetFolder") private var targetFolderPath = ""
    @AppStorage("benchmarkRunCount") private var selectedRunCount = BenchmarkProfile.defaultRuns
    @AppStorage("benchmarkFileSizeBytes") private var selectedFileSizeBytes = Int(BenchmarkProfile.defaultTestSize)
    @AppStorage("benchmarkDataPattern") private var selectedDataPatternRaw = BenchmarkProfile.defaultDataPattern.rawValue
    @AppStorage("benchmarkUsesTrimmedAverage") private var usesTrimmedAverage = BenchmarkProfile.defaultUsesTrimmedAverage
    @AppStorage("benchmarkCustomRowsJSON") private var customRowsJSON = ""
    @AppStorage("benchmarkDefaultEngine") private var defaultEngineRaw = BenchmarkProfile.default.engine.rawValue
    @AppStorage("benchmarkPeakNVMeEngine") private var peakNVMeEngineRaw = BenchmarkProfile.peakNVMe.engine.rawValue
    @AppStorage("benchmarkRealWorldEngine") private var realWorldEngineRaw = BenchmarkProfile.realWorld.engine.rawValue
    @AppStorage("benchmarkDemoEngine") private var demoEngineRaw = BenchmarkProfile.demoLight.engine.rawValue
    @AppStorage("benchmarkCustomEngine") private var customEngineRaw = BenchmarkEngine.synchronous.rawValue
    @AppStorage("benchmarkCustomExecutionMode") private var customExecutionModeRaw = BenchmarkExecutionMode.finite.rawValue
    @State private var selectedProfileID = BenchmarkProfile.default.id
    @State private var confirmWrite = false
    private let progressContentLeadingInset: CGFloat = 6

    private var baseProfile: BenchmarkProfile {
        let preset = BenchmarkProfile.presets.first(where: { $0.id == selectedProfileID }) ?? .default
        if preset.baseProfileID == "custom" {
            return BenchmarkProfile.custom(
                rows: customRows,
                engine: selectedEngine,
                executionMode: selectedCustomExecutionMode
            )
        }
        return preset.applying(engine: selectedEngine)
    }

    private var profile: BenchmarkProfile {
        baseProfile.configured(
            runs: selectedRunCount,
            fileSizeBytes: selectedBenchmarkFileSizeBytes,
            dataPattern: selectedDataPattern,
            usesTrimmedAverage: usesTrimmedAverage
        )
    }

    private var selectedProfileIsLooping: Bool {
        baseProfile.executionMode == .loopUntilCancelled
    }

    private var selectedProfileIsCustom: Bool {
        selectedProfileID == BenchmarkProfile.custom.id
    }

    private var selectedBenchmarkFileSizeBytes: Int64 {
        Int64(selectedFileSizeBytes)
    }

    private var selectedDataPattern: BenchmarkDataPattern {
        BenchmarkDataPattern(rawValue: selectedDataPatternRaw) ?? BenchmarkProfile.defaultDataPattern
    }

    private var selectedCustomExecutionMode: BenchmarkExecutionMode {
        get {
            BenchmarkExecutionMode(rawValue: customExecutionModeRaw) ?? .finite
        }
        nonmutating set {
            customExecutionModeRaw = newValue.rawValue
        }
    }

    private var customRows: [BenchmarkCustomRow] {
        get {
            BenchmarkCustomRow.decodeList(from: customRowsJSON)
        }
        nonmutating set {
            customRowsJSON = BenchmarkCustomRow.encodeList(newValue)
        }
    }

    private var customRowsBinding: Binding<[BenchmarkCustomRow]> {
        Binding {
            customRows
        } set: { nextRows in
            customRows = nextRows
        }
    }

    private var selectedEngine: BenchmarkEngine {
        get {
            storedEngine(for: selectedProfileID)
        }
        nonmutating set {
            storeEngine(newValue, for: selectedProfileID)
        }
    }

    private var selectedEngineBinding: Binding<BenchmarkEngine> {
        Binding {
            selectedEngine
        } set: { nextEngine in
            selectedEngine = nextEngine
        }
    }

    private var customExecutionModeBinding: Binding<BenchmarkExecutionMode> {
        Binding {
            selectedCustomExecutionMode
        } set: { nextMode in
            selectedCustomExecutionMode = nextMode
        }
    }

    private var configurationDescription: BenchmarkConfigurationDescription {
        language.benchmarkConfigurationDescription(
            profile: baseProfile,
            runs: profile.runs,
            fileSizeBytes: profile.testFileSizeBytes,
            dataPattern: selectedDataPattern,
            usesTrimmedAverage: profile.usesTrimmedAverage
        )
    }

    private func storedEngine(for profileID: String) -> BenchmarkEngine {
        let fallback = BenchmarkProfile.presets.first(where: { $0.id == profileID })?.engine ?? BenchmarkEngine.synchronous
        let rawValue: String
        switch profileID {
        case BenchmarkProfile.default.id:
            rawValue = defaultEngineRaw
        case BenchmarkProfile.peakNVMe.id:
            rawValue = peakNVMeEngineRaw
        case BenchmarkProfile.realWorld.id:
            rawValue = realWorldEngineRaw
        case BenchmarkProfile.demoLight.id:
            rawValue = demoEngineRaw
        case BenchmarkProfile.custom.id:
            rawValue = customEngineRaw
        default:
            rawValue = fallback.rawValue
        }
        return BenchmarkEngine(rawValue: rawValue) ?? fallback
    }

    private func storeEngine(_ engine: BenchmarkEngine, for profileID: String) {
        switch profileID {
        case BenchmarkProfile.default.id:
            defaultEngineRaw = engine.rawValue
        case BenchmarkProfile.peakNVMe.id:
            peakNVMeEngineRaw = engine.rawValue
        case BenchmarkProfile.realWorld.id:
            realWorldEngineRaw = engine.rawValue
        case BenchmarkProfile.demoLight.id:
            demoEngineRaw = engine.rawValue
        case BenchmarkProfile.custom.id:
            customEngineRaw = engine.rawValue
        default:
            break
        }
    }

    private var driveResults: [BenchmarkResult] {
        viewModel.benchmarkResults.filter { $0.driveID == drive.id }
    }

    private var profileResults: [BenchmarkResult] {
        driveResults.filter { $0.profileID == profile.id }
    }

    private var targetFolderURL: URL? {
        guard !targetFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: targetFolderPath, isDirectory: true)
    }

    private var targetFolderIsUsable: Bool {
        guard !targetFolderPath.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: targetFolderPath, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: targetFolderPath)
    }

    private var targetFolderAvailableCapacity: Int64 {
        guard targetFolderIsUsable, let targetFolderURL else { return 0 }
        return BenchmarkStorageValidator.availableCapacity(for: targetFolderURL)
    }

    private var selectedFileSizeHasSpace: Bool {
        guard targetFolderIsUsable else { return false }
        return BenchmarkStorageValidator.isRequiredSpaceAvailable(for: profile, availableCapacity: targetFolderAvailableCapacity)
    }

    private var hasAnyAvailableFileSize: Bool {
        guard targetFolderIsUsable else { return false }
        return BenchmarkProfile.fileSizeOptions.contains { isFileSizeSelectable($0) }
    }

    private var canRunBenchmark: Bool {
        targetFolderIsUsable && selectedFileSizeHasSpace && !viewModel.isBenchmarking
    }

    private var targetFolderStatusIsReady: Bool {
        targetFolderIsUsable && selectedFileSizeHasSpace
    }

    private var targetFolderDriveMismatch: Bool {
        guard targetFolderIsUsable else { return false }
        return !BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(targetFolderPath, drive: drive)
    }

    private var targetFolderStatusSymbol: String {
        targetFolderStatusIsReady && !targetFolderDriveMismatch ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var targetFolderStatusColor: Color {
        targetFolderStatusIsReady && !targetFolderDriveMismatch ? .green : .orange
    }

    private var benchmarkConfirmationMessage: String {
        var message = "\(language.t("Write tests can temporarily use free space and stress storage."))\n\(language.benchmarkConfirmationConfiguration(profile: profile, runs: profile.runs, fileSizeBytes: profile.testFileSizeBytes, dataPattern: selectedDataPattern, usesTrimmedAverage: profile.usesTrimmedAverage))\n\(language.t("Write target folder:"))\n\(targetFolderPath)"
        if targetFolderDriveMismatch {
            message += "\n\(language.t("Benchmark will measure the target folder volume, not the selected drive."))"
        }
        return message
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                benchmarkHeader
                benchmarkControls
                targetFolderControl
                if BenchmarkActivityPanelState.showsChart(isNetworkDrive: drive.isNetwork) {
                    benchmarkActivityPanel
                }
                if shouldShowProgressAndErrors {
                    progressAndErrors
                }
                BenchmarkResultMatrixView(profile: profile, results: profileResults)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            adjustSelectedFileSizeForTarget()
        }
        .onChange(of: targetFolderPath) { _, _ in
            adjustSelectedFileSizeForTarget()
        }
        .onChange(of: customExecutionModeRaw) { _, _ in
            adjustSelectedFileSizeForTarget()
        }
        .onChange(of: customRowsJSON) { _, _ in
            adjustSelectedFileSizeForTarget()
        }
        .confirmationDialog(language.t("Benchmark writes a complete temporary test file to the selected target folder."), isPresented: $confirmWrite) {
            Button(language.t("Run Benchmark"), role: .destructive) {
                viewModel.startBenchmark(profile: profile, volumePath: targetFolderPath)
            }
            Button(language.t("Cancel"), role: .cancel) {}
        } message: {
            Text(benchmarkConfirmationMessage)
        }
    }

    private var benchmarkHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.t("Benchmark"))
                    .font(.largeTitle.bold())
                Text(drive.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(language.benchmarkFooter(
                testCount: profile.tests.count,
                fileSize: profile.testFileSizeBytes,
                runs: profile.runs,
                dataPattern: selectedDataPattern,
                usesTrimmedAverage: profile.usesTrimmedAverage,
                executionMode: profile.executionMode,
                engine: profile.engine
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var benchmarkControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 10) {
                    benchmarkPickerControls
                    Spacer(minLength: 12)
                    benchmarkActionControls
                }

                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal) {
                        HStack(alignment: .bottom, spacing: 10) {
                            benchmarkPickerControls
                        }
                    }
                    .scrollIndicators(.visible)

                    HStack(spacing: 10) {
                        benchmarkActionControls
                    }
                }
            }

            BenchmarkConfigurationDescriptionView(description: configurationDescription)
            if selectedProfileIsCustom {
                CustomBenchmarkRowsEditor(
                    rows: customRowsBinding,
                    executionMode: customExecutionModeBinding,
                    isDisabled: viewModel.isBenchmarking
                )
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var benchmarkPickerControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.t("Profile"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 154, alignment: .leading)
            Picker("", selection: $selectedProfileID) {
                ForEach(BenchmarkProfile.presets) { profile in
                    Text(language.profileName(profile)).tag(profile.id)
                }
            }
            .labelsHidden()
            .frame(width: 154, alignment: .leading)
            .disabled(viewModel.isBenchmarking)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(language.t("Runs"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Picker("", selection: $selectedRunCount) {
                ForEach(BenchmarkProfile.runCountOptions, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .labelsHidden()
            .frame(width: 72, alignment: .leading)
            .disabled(viewModel.isBenchmarking || selectedProfileIsLooping)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(language.t("Engine"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .leading)
            Picker("", selection: selectedEngineBinding) {
                Text(language.t("Sync")).tag(BenchmarkEngine.synchronous)
                Text(language.t("Async")).tag(BenchmarkEngine.asyncQueue)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 116, height: 28, alignment: .leading)
            .help(language.t("Async uses POSIX AIO queue depth; Sync uses worker threads with blocking file I/O."))
            .disabled(viewModel.isBenchmarking)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(language.t("Test Size"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Picker("", selection: $selectedFileSizeBytes) {
                ForEach(BenchmarkProfile.fileSizeOptions, id: \.self) { size in
                    Text(formatBenchmarkFileSize(size))
                        .tag(Int(size))
                        .disabled(!isFileSizeSelectable(size))
                }
            }
            .labelsHidden()
            .frame(width: 112, alignment: .leading)
            .disabled(viewModel.isBenchmarking)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(language.t("Data Pattern"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 142, alignment: .leading)
            Picker("", selection: $selectedDataPatternRaw) {
                ForEach(BenchmarkDataPattern.allCases) { pattern in
                    Text(language.benchmarkDataPatternTitle(pattern)).tag(pattern.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 142, alignment: .leading)
            .disabled(viewModel.isBenchmarking)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(language.t("Trim Outliers"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .leading)
            Picker("", selection: $usesTrimmedAverage) {
                Text(language.t("Off")).tag(false)
                Text(language.t("On")).tag(true)
            }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 116, height: 28, alignment: .leading)
                .help(language.t("Run two extra measured passes, discard fastest and slowest, then average the rest."))
                .disabled(viewModel.isBenchmarking || selectedProfileIsLooping)
        }
    }

    @ViewBuilder
    private var benchmarkActionControls: some View {
        Button {
            requestBenchmarkStart()
        } label: {
            Label(language.t("Run"), systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canRunBenchmark)

        Button {
            viewModel.cancelBenchmark()
        } label: {
            Label(language.t("Cancel"), systemImage: "stop.fill")
        }
        .disabled(!viewModel.isBenchmarking)

        Button {
            saveResults(profileResults, viewModel.diskActivitySamples)
        } label: {
            Label(language.t("Save Results"), systemImage: "tray.and.arrow.down")
        }
        .disabled(profileResults.isEmpty)
    }

    private var targetFolderControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(language.t("Target Folder"), systemImage: "folder")
                    .font(.headline)

                Button {
                    chooseTargetFolder()
                } label: {
                    Label(targetFolderPath.isEmpty ? language.t("Choose Target Folder") : language.t("Change Folder"), systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)

                Label(targetFolderStatusText, systemImage: targetFolderStatusSymbol)
                    .font(.caption)
                    .foregroundStyle(targetFolderStatusColor)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

            Text(targetFolderPath.isEmpty ? language.t("No target folder selected") : targetFolderPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if targetFolderDriveMismatch {
                Label(language.t("Benchmark will measure the target folder volume, not the selected drive."), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

    private var targetFolderStatusText: String {
        if targetFolderPath.isEmpty {
            return language.t("Choose a writable target folder")
        }
        if targetFolderIsUsable, !hasAnyAvailableFileSize {
            return language.t("Not enough free space for the smallest test size")
        }
        if targetFolderIsUsable, !selectedFileSizeHasSpace {
            return language.t("Selected test size exceeds available free space")
        }
        if targetFolderDriveMismatch {
            return language.t("Target folder is writable but not on selected drive")
        }
        return targetFolderIsUsable ? language.t("Target folder is writable") : language.t("Target folder is not writable")
    }

    private var shouldShowProgressAndErrors: Bool {
        viewModel.isBenchmarking || viewModel.benchmarkError != nil || !canRunBenchmark
    }

    private var benchmarkActivityPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if drive.isNetwork {
                Label(language.t("Network drives do not provide per-disk IOKit activity counters."), systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
            } else {
                DiskActivityChartView(
                    title: language.t("Live Disk Activity"),
                    samples: viewModel.diskActivitySamples,
                    current: viewModel.currentDiskActivity,
                    style: .compact
                )
            }
        }
        .padding(.leading, progressContentLeadingInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressAndErrors: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = viewModel.benchmarkProgress,
               BenchmarkActivityPanelState.showsProgress(isBenchmarking: viewModel.isBenchmarking, hasProgress: true) {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress.fraction)
                    Text("\(language.progressLabel(progress.currentTestLabel)): \(progressStatusText(progress))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, progressContentLeadingInset)
            }

            if let error = viewModel.benchmarkError {
                Label(language.statusMessage(error), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if !targetFolderIsUsable {
                Label(language.t("Select a target folder before starting the speed test."), systemImage: "folder.badge.plus")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else if !hasAnyAvailableFileSize {
                Label(language.t("Not enough free space for the smallest test size"), systemImage: "internaldrive")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if !selectedFileSizeHasSpace {
                Label(language.t("Selected test size exceeds available free space"), systemImage: "internaldrive")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private func progressStatusText(_ progress: BenchmarkProgress) -> String {
        var text = language.statusMessage(progress.message)
        if progress.phaseTotalBytes > 0 {
            text += " · \(formatBenchmarkFileSize(progress.phaseCompletedBytes)) / \(formatBenchmarkFileSize(progress.phaseTotalBytes))"
        }
        return text
    }

    private func chooseTargetFolder() {
        let panel = NSOpenPanel()
        panel.title = language.t("Choose Target Folder")
        panel.message = language.t("Choose a writable folder where a temporary benchmark file can be created.")
        panel.prompt = language.t("Use Folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let targetFolderURL {
            panel.directoryURL = targetFolderURL
        } else if let fallback = drive.benchmarkMountPoint {
            panel.directoryURL = URL(fileURLWithPath: fallback, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        targetFolderPath = url.path
        viewModel.benchmarkError = nil
        adjustSelectedFileSizeForTarget()
    }

    private func requestBenchmarkStart() {
        guard validateTargetFolderForRun() else { return }
        confirmWrite = true
    }

    private func validateTargetFolderForRun() -> Bool {
        guard let targetFolderURL else {
            viewModel.benchmarkError = "Choose a writable target folder before starting."
            return false
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetFolderPath, isDirectory: &isDirectory) else {
            viewModel.benchmarkError = "Selected target folder no longer exists."
            return false
        }
        guard isDirectory.boolValue else {
            viewModel.benchmarkError = "The benchmark target must be a folder."
            return false
        }

        let probeURL = targetFolderURL.appendingPathComponent("Capricorn-write-check-\(UUID().uuidString)")
        do {
            try Data().write(to: probeURL, options: .atomic)
            try? FileManager.default.removeItem(at: probeURL)
        } catch {
            try? FileManager.default.removeItem(at: probeURL)
            viewModel.benchmarkError = "Selected target folder is not writable."
            return false
        }

        let available = BenchmarkStorageValidator.availableCapacity(for: targetFolderURL)
        let required = BenchmarkStorageValidator.requiredSpace(for: profile)
        guard BenchmarkStorageValidator.isRequiredSpaceAvailable(for: profile, availableCapacity: available) else {
            viewModel.benchmarkError = BenchmarkError.insufficientSpace(required: required, available: available).localizedDescription
            return false
        }

        viewModel.benchmarkError = nil
        return true
    }

    private func isFileSizeSelectable(_ fileSizeBytes: Int64) -> Bool {
        guard targetFolderIsUsable else { return true }
        let candidateProfile = baseProfile.configured(
            runs: selectedRunCount,
            fileSizeBytes: fileSizeBytes,
            dataPattern: selectedDataPattern,
            usesTrimmedAverage: usesTrimmedAverage
        )
        return BenchmarkStorageValidator.isRequiredSpaceAvailable(for: candidateProfile, availableCapacity: targetFolderAvailableCapacity)
    }

    private func adjustSelectedFileSizeForTarget() {
        if let minimumSize = BenchmarkProfile.fileSizeOptions.first, Int64(selectedFileSizeBytes) < minimumSize {
            selectedFileSizeBytes = Int(minimumSize)
        }
        guard targetFolderIsUsable else { return }
        let selectedSize = Int64(selectedFileSizeBytes)
        guard !isFileSizeSelectable(selectedSize) else { return }
        if let fallback = BenchmarkProfile.fileSizeOptions.last(where: { isFileSizeSelectable($0) }) {
            selectedFileSizeBytes = Int(fallback)
        }
    }
}

private struct CustomBenchmarkRowsEditor: View {
    @Binding var rows: [BenchmarkCustomRow]
    @Binding var executionMode: BenchmarkExecutionMode
    let isDisabled: Bool
    @Environment(\.appLanguage) private var language
    private let typeColumnWidth: CGFloat = 88
    private let blockSizeColumnWidth: CGFloat = 116
    private let queueColumnWidth: CGFloat = 62
    private let threadColumnWidth: CGFloat = 62
    private let mixedColumnWidth: CGFloat = 112
    private let deleteColumnWidth: CGFloat = 42
    private let columnSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.top, 2)

            HStack(alignment: .firstTextBaseline) {
                Label(language.t("Custom Test Groups"), systemImage: "slider.horizontal.3")
                    .font(.headline)
                Text(language.t("Each group creates read/write tests; mixed adds a 30% write / 70% read item."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addRow()
                } label: {
                    Label(language.t("Add Group"), systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(isDisabled || rows.count >= BenchmarkCustomRow.maxRows)
            }

            HStack(alignment: .bottom, spacing: columnSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.t("Loop"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: blockSizeColumnWidth, alignment: .leading)
                    Picker("", selection: $executionMode) {
                        Text(language.t("Off")).tag(BenchmarkExecutionMode.finite)
                        Text(language.t("On")).tag(BenchmarkExecutionMode.loopUntilCancelled)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: blockSizeColumnWidth, alignment: .leading)
                    .help(language.t("Loop repeats the custom groups until you stop it manually."))
                }

                Text(language.t("Loop mode ignores test count and extra trimmed testing."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(isDisabled)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: columnSpacing) {
                    Text(language.t("Type"))
                        .frame(width: typeColumnWidth, alignment: .leading)
                    Text(language.t("Block Size"))
                        .frame(width: blockSizeColumnWidth, alignment: .leading)
                    Text("Q")
                        .frame(width: queueColumnWidth, alignment: .leading)
                    Text("T")
                        .frame(width: threadColumnWidth, alignment: .leading)
                    Text(language.t("Mixed"))
                        .frame(width: mixedColumnWidth, alignment: .leading)
                    Spacer(minLength: 0)
                    Text(language.t("Delete"))
                        .frame(width: deleteColumnWidth, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: columnSpacing) {
                        Picker("", selection: $rows[index].accessPattern) {
                            Text("SEQ").tag(BenchmarkAccessPattern.sequential)
                            Text("RND").tag(BenchmarkAccessPattern.random)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: typeColumnWidth, alignment: .leading)

                        Picker("", selection: $rows[index].blockSizeBytes) {
                            ForEach(BenchmarkCustomRow.blockSizeOptions, id: \.self) { size in
                                Text(formatBytes(size)).tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: blockSizeColumnWidth, alignment: .leading)

                        Picker("", selection: $rows[index].queueDepth) {
                            ForEach(BenchmarkCustomRow.queueDepthOptions, id: \.self) { depth in
                                Text("\(depth)").tag(depth)
                            }
                        }
                        .labelsHidden()
                        .frame(width: queueColumnWidth, alignment: .leading)

                        Picker("", selection: $rows[index].threads) {
                            ForEach(BenchmarkCustomRow.threadOptions, id: \.self) { threadCount in
                                Text("\(threadCount)").tag(threadCount)
                            }
                        }
                        .labelsHidden()
                        .frame(width: threadColumnWidth, alignment: .leading)

                        Picker("", selection: $rows[index].includeMixed) {
                            Text(language.t("Off")).tag(false)
                            Text(language.t("On")).tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: mixedColumnWidth, alignment: .leading)

                        Text(rows[index].label.replacingOccurrences(of: "MiB", with: "M").replacingOccurrences(of: "KiB", with: "K"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            removeRow(at: index)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                        .help(language.t("Delete"))
                        .disabled(isDisabled || rows.count <= 1)
                    }
                    .disabled(isDisabled)
                }
            }

            Text(language.t("Maximum 4 groups."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addRow() {
        guard rows.count < BenchmarkCustomRow.maxRows else { return }
        rows.append(BenchmarkCustomRow.newRow(index: rows.count))
    }

    private func removeRow(at index: Int) {
        guard rows.count > 1, rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }
}

private struct BenchmarkConfigurationDescriptionView: View {
    let description: BenchmarkConfigurationDescription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(description.profileUse)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            BenchmarkConfigurationLine(text: description.runs)
            BenchmarkConfigurationLine(text: description.fileSize)
            BenchmarkConfigurationLine(text: description.dataPattern)
            BenchmarkConfigurationLine(text: description.testTerms)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BenchmarkConfigurationLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct DiskActivityChartView: View {
    enum Style {
        case compact
        case expanded
        case mini

        var chartHeight: CGFloat {
            switch self {
            case .compact: 92
            case .expanded: 220
            case .mini: 58
            }
        }

        var yAxisWidth: CGFloat {
            switch self {
            case .compact: 54
            case .expanded: 68
            case .mini: 48
            }
        }

        var font: Font {
            switch self {
            case .compact: .caption2
            case .expanded: .caption
            case .mini: .caption2
            }
        }

    }

    private struct ChartData {
        var samples: [DiskActivitySample]
        var graphMaximumSpeed: Double
        var yTicks: [Double]
        var xTicks: [DiskActivityChartTick]
        var durationSeconds: TimeInterval
    }

    let title: String
    let samples: [DiskActivitySample]
    let current: DiskActivitySample?
    let style: Style
    @Environment(\.appLanguage) private var language

    private var readSpeed: Double {
        current?.readMegabytesPerSecond ?? 0
    }

    private var writeSpeed: Double {
        current?.writeMegabytesPerSecond ?? 0
    }

    private var chartData: ChartData {
        let maximumSpeed = max(samples.flatMap { [$0.readMegabytesPerSecond, $0.writeMegabytesPerSecond] }.max() ?? 0, 1)
        return ChartData(
            samples: samples,
            graphMaximumSpeed: maximumSpeed,
            yTicks: DiskActivityChartScale.yTicks(maxSpeed: maximumSpeed),
            xTicks: DiskActivityChartScale.xTicks(for: samples),
            durationSeconds: DiskActivityChartScale.durationSeconds(for: samples)
        )
    }

    var body: some View {
        let preparedChartData = chartData
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.caption.bold())

                Spacer(minLength: 8)

                speedLegend(title: language.operationTitle(.read), value: readSpeed, color: .blue)
                speedLegend(title: language.operationTitle(.write), value: writeSpeed, color: .green)
            }

            HStack(alignment: .top, spacing: 6) {
                yAxisLabels(preparedChartData.yTicks)
                    .frame(width: style.yAxisWidth, height: style.chartHeight)

                VStack(spacing: 4) {
                    Canvas { context, size in
                        let rect = CGRect(origin: .zero, size: size)
                        let background = Path(roundedRect: rect, cornerRadius: 6)
                        context.fill(background, with: .color(Color(nsColor: .controlBackgroundColor)))
                        context.stroke(background, with: .color(Color(nsColor: .separatorColor).opacity(0.45)), lineWidth: 1)

                        let plotRect = rect.insetBy(dx: 8, dy: 7)
                        drawGrid(in: plotRect, context: context, chartData: preparedChartData)
                        drawSeries(\.readMegabytesPerSecond, color: .blue, in: plotRect, context: context, chartData: preparedChartData)
                        drawSeries(\.writeMegabytesPerSecond, color: .green, in: plotRect, context: context, chartData: preparedChartData)
                    }
                    .frame(height: style.chartHeight)

                    xAxisLabels(preparedChartData.xTicks)
                }
            }
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text("\(language.operationTitle(.read)) \(DiskActivityFormatter.speed(readSpeed)), \(language.operationTitle(.write)) \(DiskActivityFormatter.speed(writeSpeed))"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func yAxisLabels(_ yTicks: [Double]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(yTicks.reversed()), id: \.self) { tick in
                Text(DiskActivityFormatter.speed(tick))
                    .font(style.font.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func xAxisLabels(_ xTicks: [DiskActivityChartTick]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(xTicks.enumerated()), id: \.offset) { index, tick in
                Text(tick.label)
                    .font(style.font.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == xTicks.count - 1 ? .trailing : .center))
            }
        }
        .frame(height: 14)
    }

    private func speedLegend(title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(title) \(DiskActivityFormatter.speed(value))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func drawGrid(in rect: CGRect, context: GraphicsContext, chartData: ChartData) {
        var path = Path()
        let maxSpeed = chartData.yTicks.last ?? 1
        for tick in chartData.yTicks {
            let fraction = maxSpeed > 0 ? tick / maxSpeed : 0
            let y = rect.maxY - rect.height * CGFloat(fraction)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        if chartData.durationSeconds > 0 {
            for tick in chartData.xTicks {
                let fraction = tick.value / chartData.durationSeconds
                let x = rect.minX + rect.width * CGFloat(fraction)
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }
        context.stroke(path, with: .color(Color(nsColor: .separatorColor).opacity(0.78)), lineWidth: 0.8)
    }

    private func drawSeries(
        _ keyPath: KeyPath<DiskActivitySample, Double>,
        color: Color,
        in rect: CGRect,
        context: GraphicsContext,
        chartData: ChartData
    ) {
        guard chartData.samples.count >= 2 else {
            drawBaseline(color: color, in: rect, context: context)
            return
        }

        let maxSpeed = max(chartData.yTicks.last ?? chartData.graphMaximumSpeed, 1)
        let firstTimestamp = chartData.samples.first?.timestamp ?? Date()
        let duration = max(chartData.durationSeconds, 0.0001)
        var path = Path()

        for (index, sample) in chartData.samples.enumerated() {
            let value = max(0, sample[keyPath: keyPath])
            let fraction = min(1, value / maxSpeed)
            let elapsed = max(0, sample.timestamp.timeIntervalSince(firstTimestamp))
            let point = CGPoint(
                x: rect.minX + rect.width * CGFloat(min(1, elapsed / duration)),
                y: rect.maxY - rect.height * CGFloat(fraction)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    private func drawBaseline(color: Color, in rect: CGRect, context: GraphicsContext) {
        var path = Path()
        let y = rect.maxY
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: 1)
    }
}

private struct BenchmarkResultMatrixView: View {
    let profile: BenchmarkProfile
    let results: [BenchmarkResult]
    @Environment(\.appLanguage) private var language

    private var hasMixedColumn: Bool {
        profile.tests.contains { $0.operation == .mixed } || results.contains { $0.operation == .mixed }
    }

    private var rowLabels: [String] {
        var labels: [String] = []
        for test in profile.tests {
            let label = Self.normalizedLabel(test.label)
            if !labels.contains(label) {
                labels.append(label)
            }
        }
        return labels
    }

    private var maximumSpeed: Double {
        max(results.map(\.bestMegabytesPerSecond).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CrystalHeaderCell(title: language.t("Test"))
                    .frame(width: 146)
                CrystalHeaderCell(title: "\(language.operationTitle(.read)) MB/s")
                CrystalHeaderCell(title: "\(language.operationTitle(.write)) MB/s")
                if hasMixedColumn {
                    CrystalHeaderCell(title: "\(language.operationTitle(.mixed)) MB/s")
                }
            }

            ForEach(rowLabels, id: \.self) { label in
                HStack(spacing: 8) {
                    CrystalTestLabelCell(title: Self.displayLabel(label))
                        .frame(width: 146)
                    CrystalSpeedCell(result: result(for: label, operation: .read), maximumSpeed: maximumSpeed)
                    CrystalSpeedCell(result: result(for: label, operation: .write), maximumSpeed: maximumSpeed)
                    if hasMixedColumn {
                        CrystalSpeedCell(result: result(for: label, operation: .mixed), maximumSpeed: maximumSpeed)
                    }
                }
            }

            if results.isEmpty {
                Label(language.t("Run a benchmark profile to populate the read/write matrix."), systemImage: "speedometer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }

    private func result(for label: String, operation: BenchmarkOperation) -> BenchmarkResult? {
        results
            .filter { Self.normalizedLabel($0.testLabel) == label && $0.operation == operation }
            .max { $0.measuredAt < $1.measuredAt }
    }

    private static func normalizedLabel(_ label: String) -> String {
        label.hasSuffix(" Mix") ? String(label.dropLast(4)) : label
    }

    private static func displayLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "MiB", with: "M")
            .replacingOccurrences(of: "KiB", with: "K")
    }
}

private struct CrystalHeaderCell: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct CrystalTestLabelCell: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .monospaced()
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.horizontal, 8)
            .background(
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.92),
                        Color.green.opacity(0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .foregroundStyle(.black.opacity(0.82))
    }
}

private struct CrystalSpeedCell: View {
    let result: BenchmarkResult?
    let maximumSpeed: Double
    @Environment(\.appLanguage) private var language

    private var fillFraction: Double {
        guard let result else { return 0 }
        return min(1, max(0, result.bestMegabytesPerSecond / maximumSpeed))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.green.opacity(result == nil ? 0.05 : 0.2))
                    .frame(width: proxy.size.width * fillFraction)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .trailing, spacing: 4) {
                Text(speedText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                VStack(alignment: .trailing, spacing: 1) {
                    ForEach(Array(detailLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minWidth: 150, maxWidth: .infinity, minHeight: 76)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.separator.opacity(0.4), lineWidth: 1)
        }
    }

    private var speedText: String {
        guard let result else { return "--" }
        return String(format: "%.2f", result.bestMegabytesPerSecond)
    }

    private var detailLines: [String] {
        guard let result else { return ["MB/s"] }
        if result.transferMegabytesPerSecond != nil || result.flushMilliseconds != nil {
            var lines: [String] = []
            if let transfer = result.transferMegabytesPerSecond {
                lines.append(String(format: "%@ %.0f MB/s", transferLabel, transfer))
            }
            if let flush = result.flushMilliseconds {
                lines.append(String(format: "%@ %.0f ms", flushLabel, flush))
            }
            if !lines.isEmpty {
                return lines
            }
        }
        return [String(format: "MB/s   %.0f IOPS   %.0f us", result.iops, result.latencyMicroseconds)]
    }

    private var transferLabel: String {
        language == .simplifiedChinese ? "传输" : "transfer"
    }

    private var flushLabel: String {
        language == .simplifiedChinese ? "刷盘" : "fsync"
    }
}

struct SelfTestSummaryView: View {
    let snapshot: SmartSnapshot?
    @Binding var isExpanded: Bool
    @Environment(\.appLanguage) private var language

    private var selfTestStatus: String? {
        snapshot?.selfTestStatus?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSelfTestLog: Bool {
        guard let selfTestStatus else { return false }
        return !selfTestStatus.isEmpty
    }

    var body: some View {
        InfoPanel(title: language.t("Self-Tests"), symbol: "stethoscope") {
            if hasSelfTestLog, let selfTestStatus {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(language.statusMessage(selfTestStatus))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Label(language.t("Short and long self-test execution requires smartctl support for this drive. This version displays available logs and avoids starting destructive or vendor-specific tests automatically."), systemImage: "terminal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                } label: {
                    Label(language.t("Self-test log available"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Label(language.t("No self-test log is available from current providers."), systemImage: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ExternalSupportView: View {
    let status: ExternalSupportStatus
    let refresh: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(language.t("External Drive SMART"))
                    .font(.title2.bold())
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label(language.t("Verify"), systemImage: "arrow.clockwise")
                }
            }
            InfoPanel(title: language.t("Status"), symbol: "externaldrive.connected.to.line.below") {
                Label(language.t("Use this when SMART data is unavailable or limited for an external drive."), systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusLine(title: "smartctl", isOn: status.smartctlInstalled)
                StatusLine(title: "SAT SMART Driver", isOn: status.satDriverInstalled)
                Text(language.statusMessage(status.message))
                    .foregroundStyle(.secondary)
            }
            if !status.smartctlInstalled {
                InfoPanel(title: language.t("Install smartmontools"), symbol: "terminal") {
                    Text(language.t("Capricorn does not bundle smartctl. Install smartmontools to enable detailed SMART data when macOS native fields are limited."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("brew install smartmontools")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Text(language.t("After installation, refresh Capricorn. Apple Silicon Homebrew usually installs smartctl at /opt/homebrew/bin/smartctl; Intel Homebrew usually uses /usr/local/bin/smartctl."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://formulae.brew.sh/formula/smartmontools")!) {
                        Label(language.t("Open Homebrew smartmontools formula"), systemImage: "safari")
                    }
                }
            }
            InfoPanel(title: language.t("Driver Paths"), symbol: "shippingbox") {
                if status.driverPaths.isEmpty {
                    Text(language.t("No SAT SMART Driver bundle was detected in standard extension locations."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(status.driverPaths, id: \.self) { path in
                        Text(path).monospaced()
                    }
                }
            }
            Link(destination: URL(string: "https://github.com/kasbert/OS-X-SAT-SMART-Driver")!) {
                Label(language.t("Open SAT SMART Driver project"), systemImage: "safari")
            }
        }
    }
}
