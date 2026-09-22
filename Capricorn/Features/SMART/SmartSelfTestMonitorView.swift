// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct SmartSelfTestPresentationSheet: View {
    let viewModel: AppModel
    let language: AppLanguage

    var body: some View {
        Group {
            switch viewModel.smartSelfTestPresentation {
            case let .confirmation(request):
                SmartSelfTestConfirmationView(
                    request: request,
                    language: language,
                    start: { viewModel.confirmSmartSelfTest(request) },
                    cancel: { viewModel.hideSmartSelfTestMonitor() }
                )
            case .monitor:
                SmartSelfTestMonitorView(viewModel: viewModel, language: language)
            case nil:
                EmptyView()
            }
        }
    }
}

private struct SmartSelfTestConfirmationView: View {
    let request: SmartSelfTestStartRequest
    let language: AppLanguage
    let start: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: request.kind == .short ? "hare.fill" : "tortoise.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(language.t("Start SMART Self-Test?"))
                        .font(.title3.weight(.semibold))
                    Text(request.drive.displayName)
                        .font(.headline)
                    Text("\(request.drive.bsdName) · \(request.drive.protocolName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 12) {
                confirmationRow(
                    title: language.t("Test Type"),
                    value: selfTestName(request.kind),
                    symbol: request.kind == .short ? "hare" : "tortoise"
                )
                confirmationRow(
                    title: language.t("Estimated Duration"),
                    value: estimatedDurationText(request.estimatedDurationSeconds),
                    symbol: "clock"
                )
            }

            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.t("Do not disconnect or power off this drive while the self-test is running."))
                        .font(.callout.weight(.semibold))
                    Text(language.t("You can hide the progress monitor and continue using Capricorn. Hiding it does not stop the self-test."))
                        .font(.caption)
                }
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.title3)
            }
            .foregroundStyle(.orange)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Spacer()
                Button(language.t("Cancel")) {
                    cancel()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    start()
                } label: {
                    Label(language.t("Start Self-Test"), systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private func confirmationRow(title: String, value: String, symbol: String) -> some View {
        GridRow {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 22, alignment: .center)
                Text(title)
            }
            .frame(width: 146, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .gridColumnAlignment(.leading)
        }
    }

    private func selfTestName(_ kind: SmartSelfTestKind) -> String {
        language.t(kind == .short ? "Quick Self-Test" : "Full Self-Test")
    }

    private func estimatedDurationText(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return language.t("Not reported by drive") }
        let minutes = max(1, Int(ceil(Double(seconds) / 60)))
        if language == .simplifiedChinese {
            return minutes >= 60
                ? "约 \(minutes / 60) 小时 \(minutes % 60) 分钟"
                : "约 \(minutes) 分钟"
        }
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "About \(hours) hr" : "About \(hours) hr \(remainder) min"
        }
        return "About \(minutes) min"
    }
}

private struct SmartSelfTestMonitorView: View {
    let viewModel: AppModel
    let language: AppLanguage
    @State private var isConfirmingAbort = false

    private var drive: DriveDevice? {
        viewModel.smartSelfTestDrive ?? viewModel.completedSmartSelfTest?.drive
    }

    private var isActive: Bool {
        viewModel.isSmartSelfTestActive
    }

    private var monitorHeight: CGFloat {
        if isActive {
            return 380
        }
        if viewModel.completedSmartSelfTest != nil {
            return 330
        }
        return 350
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 20) {
                monitorHeader

                if isActive, let progress = viewModel.smartSelfTestProgress {
                    activeProgress(progress, now: timeline.date)
                } else if let completion = viewModel.completedSmartSelfTest {
                    completionResult(completion)
                } else {
                    unavailableResult
                }

                HStack {
                    if isActive {
                        Text(language.t("The self-test continues on the drive when this monitor is hidden."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(language.t(isActive ? "Hide Window" : "Close")) {
                        viewModel.hideSmartSelfTestMonitor()
                    }
                    .keyboardShortcut(.cancelAction)

                    if isActive {
                        Button(role: .destructive) {
                            isConfirmingAbort = true
                        } label: {
                            Label(language.t("Abort Self-Test"), systemImage: "stop.fill")
                        }
                        .disabled(viewModel.smartSelfTestSession == .stopping)
                    }
                }
            }
            .padding(24)
            .frame(width: 620, height: monitorHeight, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: monitorHeight)
        }
        .alert(language.t("Abort SMART Self-Test?"), isPresented: $isConfirmingAbort) {
            Button(language.t("Abort Self-Test"), role: .destructive) {
                viewModel.abortSmartSelfTest()
            }
            Button(language.t("Keep Running"), role: .cancel) {}
        } message: {
            Text(language.t("Capricorn will ask the drive to stop its current self-test. Any progress made by this test will be lost."))
        }
    }

    private var monitorHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: headerSymbol)
                .font(.title2)
                .foregroundStyle(headerColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(drive?.displayName ?? language.t("SMART Self-Test Monitor"))
                    .font(.title3.weight(.semibold))
                if let drive {
                    Text("\(drive.bsdName) · \(drive.protocolName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(headerStatus)
                .font(.caption.weight(.semibold))
                .foregroundStyle(headerColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(headerColor.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func activeProgress(_ progress: SmartSelfTestProgress, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(language.t(progress.kind == .short ? "Quick SMART Self-Test" : "Full SMART Self-Test"))
                    .font(.headline)
                Spacer()
                if let completed = progress.completedPercent {
                    Text("\(completed)%")
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                }
            }

            if let completed = progress.completedPercent {
                ProgressView(value: Double(completed), total: 100)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            Text(activeStage(progress))
                .font(.callout)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                GridRow {
                    metric(
                        title: language.t("Elapsed"),
                        value: formattedDuration(now.timeIntervalSince(progress.startedAt)),
                        symbol: "timer"
                    )
                    metric(
                        title: language.t("Estimated Completion"),
                        value: estimatedCompletion(progress, now: now),
                        symbol: "calendar.badge.clock"
                    )
                }
                GridRow {
                    metric(
                        title: language.t("Last Status Update"),
                        value: progress.lastStatusUpdateAt.map(formattedTime) ?? language.t("Waiting for first update"),
                        symbol: "arrow.clockwise"
                    )
                    metric(
                        title: language.t("Current Stage"),
                        value: activeStage(progress),
                        symbol: "waveform.path.ecg"
                    )
                }
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func completionResult(_ completion: SmartSelfTestCompletion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(completionTitle(completion.state), systemImage: completionSymbol(completion.state))
                .font(.title3.weight(.semibold))
                .foregroundStyle(completionColor(completion.state))
            Text(language.statusMessage(completion.message))
                .foregroundStyle(.secondary)

            if let entry = completion.report?.latestEntry {
                Divider()
                HStack(alignment: .top) {
                    Text(language.t("Drive Report"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(language.statusMessage(entry.status))
                        .fontWeight(.medium)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }

            HStack {
                Text(language.t("Completed At"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedTime(completion.completedAt))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(completionColor(completion.state).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var unavailableResult: some View {
        ContentUnavailableView(
            language.t("Self-Test Status Unknown"),
            systemImage: "questionmark.circle",
            description: Text(language.statusMessage(viewModel.smartSelfTestMessage) ?? language.t("No self-test status is available."))
        )
    }

    private func metric(title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activeStage(_ progress: SmartSelfTestProgress) -> String {
        switch viewModel.smartSelfTestSession {
        case .starting:
            return language.t("Sending the self-test command to the drive.")
        case .running:
            if progress.completedPercent == nil {
                return language.t("The drive is running the self-test but has not reported percentage progress.")
            }
            return language.t(progress.kind == .short
                ? "The drive is running the quick self-test."
                : "The drive is running the full self-test.")
        case .stopping:
            return language.t("Waiting for the drive to stop the self-test.")
        case let .failed(message):
            return language.statusMessage(message)
        case .idle:
            return language.t("Self-Test Status Unknown")
        }
    }

    private var headerStatus: String {
        if isActive {
            switch viewModel.smartSelfTestSession {
            case .starting: return language.t("Starting")
            case .running: return language.t("Running")
            case .stopping: return language.t("Stopping")
            case .idle, .failed: break
            }
        }
        guard let state = viewModel.completedSmartSelfTest?.state else {
            return language.t("Self-Test Status Unknown")
        }
        return completionTitle(state)
    }

    private var headerSymbol: String {
        if isActive { return "waveform.path.ecg" }
        return completionSymbol(viewModel.completedSmartSelfTest?.state ?? .unknown)
    }

    private var headerColor: Color {
        if isActive { return .blue }
        return completionColor(viewModel.completedSmartSelfTest?.state ?? .unknown)
    }

    private func completionTitle(_ state: SmartSelfTestCompletionState) -> String {
        switch state {
        case .passed: language.t("Self-Test Passed")
        case .failed: language.t("Self-Test Failed")
        case .aborted: language.t("Self-Test Aborted")
        case .disconnected: language.t("Drive Disconnected")
        case .unknown: language.t("Self-Test Status Unknown")
        }
    }

    private func completionSymbol(_ state: SmartSelfTestCompletionState) -> String {
        switch state {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .aborted: "stop.circle.fill"
        case .disconnected: "externaldrive.badge.xmark"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private func completionColor(_ state: SmartSelfTestCompletionState) -> Color {
        switch state {
        case .passed: .green
        case .failed: .red
        case .aborted, .disconnected: .orange
        case .unknown: .secondary
        }
    }

    private func estimatedCompletion(_ progress: SmartSelfTestProgress, now: Date) -> String {
        guard let seconds = progress.estimatedDurationSeconds else {
            return language.t("Not reported by drive")
        }
        let completion = progress.startedAt.addingTimeInterval(TimeInterval(seconds))
        if now > completion, case .running = viewModel.smartSelfTestSession {
            return "\(formattedTime(completion)) · \(language.t("Waiting for drive"))"
        }
        return formattedTime(completion)
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
