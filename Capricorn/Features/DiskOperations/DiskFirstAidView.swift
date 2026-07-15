// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

private let diskUtilityURL = URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app")
private let appleFirstAidURL = URL(string: "https://support.apple.com/guide/disk-utility/repair-a-storage-device-dskutl1040/mac")!
private let windowsCHKDSKURL = URL(string: "https://learn.microsoft.com/windows-server/administration/windows-commands/chkdsk")!

struct DiskFirstAidSheet: View {
    var viewModel: AppModel
    var language: AppLanguage

    var body: some View {
        Group {
            switch viewModel.firstAidState {
            case .idle:
                EmptyView()
            case .preflighting:
                FirstAidPreparingView(language: language, close: viewModel.closeFirstAid)
            case .awaitingConfirmation:
                if !viewModel.firstAidOpenFileInspections.isEmpty {
                    FirstAidOpenFilesView(viewModel: viewModel, language: language)
                } else if let plan = viewModel.firstAidPlan {
                    FirstAidConfirmationView(viewModel: viewModel, plan: plan, language: language)
                } else {
                    FirstAidUnavailableView(
                        message: viewModel.firstAidError ?? language.t("First Aid preflight did not produce a repair plan."),
                        language: language,
                        close: viewModel.closeFirstAid
                    )
                }
            case .running, .stoppingAfterCurrent, .refreshing, .completed:
                FirstAidProgressView(viewModel: viewModel, language: language)
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .interactiveDismissDisabled(viewModel.firstAidState.isRepairing || viewModel.firstAidState == .refreshing)
    }
}

private struct FirstAidPreparingView: View {
    var language: AppLanguage
    var close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel(language.t("Preparing First Aid"))
            Text(language.t("Preparing First Aid"))
                .font(.title2.weight(.semibold))
            Text(language.t("Capricorn is verifying current volume identities, formats, and repair eligibility."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button(language.t("Cancel"), action: close)
        }
        .padding(32)
    }
}

private struct FirstAidConfirmationView: View {
    var viewModel: AppModel
    var plan: DiskFirstAidPlan
    var language: AppLanguage

    private var canStart: Bool {
        plan.blockedReason == nil
            && !viewModel.firstAidSelectedTargetIDs.isEmpty
            && viewModel.firstAidBackupConfirmed
            && viewModel.firstAidActivityConfirmed
            && (!plan.requiresHealthWarningConfirmation || viewModel.firstAidHealthWarningConfirmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let reason = plan.blockedReason {
                        blockedNotice(reason)
                    }
                    targetSection
                    if plan.blockedReason == nil {
                        riskSection
                    }
                    if let error = viewModel.firstAidError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)

            Divider()
            HStack {
                guidanceButtons
                Spacer()
                Button(language.t("Cancel")) {
                    viewModel.closeFirstAid()
                }
                Button(role: .destructive) {
                    Task { await viewModel.beginFirstAid() }
                } label: {
                    Label(language.t("Run First Aid"), systemImage: "cross.case.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
                .accessibilityHint(language.t("First Aid modifies filesystem metadata on the selected volumes."))
            }
        }
        .padding(22)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "cross.case.fill")
                .font(.title)
                .foregroundStyle(.red)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(language.t("Disk First Aid"))
                    .font(.title2.weight(.semibold))
                Text(plan.driveName)
                    .font(.headline)
                Text(language.t("First Aid can modify filesystem metadata. It is not data recovery and cannot repair physical media failure."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HealthBadge(status: plan.health, compact: true)
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.t("Select Volumes"))
                .font(.headline)
            Text(language.t("No volume is selected by default. Only external APFS and ExFAT volumes can run direct First Aid."))
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(plan.targets) { target in
                    FirstAidTargetRow(
                        target: target,
                        language: language,
                        isSelected: Binding(
                            get: { viewModel.firstAidSelectedTargetIDs.contains(target.id) },
                            set: { selected in
                                if selected {
                                    viewModel.firstAidSelectedTargetIDs.insert(target.id)
                                } else {
                                    viewModel.firstAidSelectedTargetIDs.remove(target.id)
                                }
                            }
                        )
                    )
                    if target.id != plan.targets.last?.id {
                        Divider()
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.8), lineWidth: 1)
            }
        }
    }

    private var riskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.t("Required Confirmations"))
                .font(.headline)
            Toggle(language.t("Important data is backed up, or I accept the risk of proceeding without a backup."), isOn: Binding(
                get: { viewModel.firstAidBackupConfirmed },
                set: { viewModel.firstAidBackupConfirmed = $0 }
            ))
            Toggle(language.t("All transfers, benchmarks, and disk writes are stopped, and power and cables are stable."), isOn: Binding(
                get: { viewModel.firstAidActivityConfirmed },
                set: { viewModel.firstAidActivityConfirmed = $0 }
            ))
            if plan.requiresHealthWarningConfirmation {
                Toggle(language.t("SMART shows a warning. I understand First Aid cannot repair physical media problems."), isOn: Binding(
                    get: { viewModel.firstAidHealthWarningConfirmed },
                    set: { viewModel.firstAidHealthWarningConfirmed = $0 }
                ))
                .foregroundStyle(.orange)
            }
        }
        .toggleStyle(.checkbox)
    }

    private func blockedNotice(_ reason: DiskFirstAidBlockReason) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.t("Direct First Aid Unavailable"))
                    .font(.headline)
                Text(language.t(reason.messageKey))
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: reason == .unhealthyMedia ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(reason == .unhealthyMedia ? .red : .orange)
        }
        .padding(14)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var guidanceButtons: some View {
        if plan.blockedReason == .systemDisk
            || plan.blockedReason == .internalDisk
            || plan.targets.contains(where: { $0.support == .preflightFailed }) {
            Button {
                openDiskUtility()
            } label: {
                Label(language.t("Open Disk Utility"), systemImage: "externaldrive.badge.timemachine")
            }
            Button {
                NSWorkspace.shared.open(appleFirstAidURL)
            } label: {
                Label(language.t("Recovery Instructions"), systemImage: "safari")
            }
        }
        if plan.targets.contains(where: { $0.support == .ntfsRequiresWindows }) {
            Button {
                copyCHKDSKExample()
            } label: {
                Label(language.t("Copy CHKDSK Example"), systemImage: "doc.on.doc")
            }
            Button {
                NSWorkspace.shared.open(windowsCHKDSKURL)
            } label: {
                Label(language.t("Windows CHKDSK Guide"), systemImage: "safari")
            }
        }
    }
}

private struct FirstAidTargetRow: View {
    var target: DiskFirstAidTarget
    var language: AppLanguage
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!target.isEligible)
                .accessibilityLabel("\(language.t("Select")) \(target.volumeName) \(language.t("for First Aid"))")
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(target.volumeName)
                        .font(.headline)
                    Text(target.fileSystemType ?? language.t("Unknown"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                    Text(formatByteCount(target.sizeBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text([target.deviceIdentifier, target.mountPoint].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Label(language.t(target.support.messageKey), systemImage: target.isEligible ? "checkmark.circle" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(target.isEligible ? .green : .secondary)
            }
            Spacer()
        }
        .padding(12)
    }
}

private struct FirstAidOpenFilesView: View {
    var viewModel: AppModel
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(language.t("Open Files Found"), systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
            Text(language.t("Close these applications before First Aid. Capricorn will not terminate processes or force-unmount the disk."))
                .foregroundStyle(.secondary)

            List {
                ForEach(viewModel.firstAidOpenFileInspections) { inspection in
                    Section(inspection.mountPoint) {
                        ForEach(inspection.processes) { process in
                            HStack(spacing: 12) {
                                Text(process.command)
                                    .fontWeight(.semibold)
                                    .frame(width: 150, alignment: .leading)
                                Text("PID \(process.pid)")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text(process.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                Button(language.t("Back")) {
                    viewModel.dismissFirstAidOpenFiles()
                }
                Spacer()
                Button {
                    Task { await viewModel.beginFirstAid() }
                } label: {
                    Label(language.t("Check Again"), systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    viewModel.continueFirstAidAfterOpenFiles()
                } label: {
                    Text(language.t("Try Anyway"))
                }
            }
        }
        .padding(22)
    }
}

private struct FirstAidProgressView: View {
    var viewModel: AppModel
    var language: AppLanguage

    private var isRunning: Bool {
        viewModel.firstAidState.isRepairing
    }

    private var currentTarget: DiskFirstAidTarget? {
        guard let id = viewModel.firstAidCurrentTargetID else { return nil }
        return viewModel.firstAidPlan?.targets.first(where: { $0.id == id })
    }

    private var completedCount: Int {
        viewModel.firstAidReport?.results.count ?? 0
    }

    private var progressFraction: Double {
        guard viewModel.firstAidTotalTargetCount > 0 else { return 0 }
        return min(1, Double(completedCount) / Double(viewModel.firstAidTotalTargetCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusSection
            resultsAndLog
            Divider()
            footer
        }
        .padding(22)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(language.t("Disk First Aid"))
                    .font(.title2.weight(.semibold))
                Text(viewModel.firstAidPlan?.driveName ?? viewModel.firstAidReport?.driveName ?? "")
                    .font(.headline)
                Text(language.t(statusMessageKey))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.firstAidState == .refreshing {
                ProgressView()
                    .accessibilityLabel(language.t("Refreshing disk and SMART information after First Aid."))
            } else {
                ProgressView(value: progressFraction)
                    .accessibilityLabel(language.t("First Aid Progress"))
                    .accessibilityValue("\(completedCount) / \(viewModel.firstAidTotalTargetCount)")
            }
            HStack {
                Text("\(language.t("Completed")) \(completedCount) / \(viewModel.firstAidTotalTargetCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let currentTarget, isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(language.t("Running"))
                    Text(currentTarget.volumeName)
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var resultsAndLog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.firstAidReport?.results ?? []) { result in
                    FirstAidResultRow(result: result, language: language)
                }

                if isRunning || viewModel.firstAidState == .refreshing {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(currentTarget?.volumeName ?? language.t("System Output"), systemImage: "terminal")
                            .font(.headline)
                        Text(viewModel.firstAidLiveOutput.isEmpty ? language.t("Waiting for command output...") : viewModel.firstAidLiveOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                            .padding(12)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityLabel(language.t("System Output"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
    }

    private var footer: some View {
        HStack {
            if viewModel.firstAidState == .completed,
               viewModel.firstAidReport?.hasFailures == true {
                Button {
                    openDiskUtility()
                } label: {
                    Label(language.t("Open Disk Utility"), systemImage: "externaldrive.badge.timemachine")
                }
            }
            Spacer()
            if viewModel.firstAidState == .running {
                Button {
                    Task { await viewModel.requestFirstAidStopAfterCurrent() }
                } label: {
                    Label(language.t("Stop After Current Volume"), systemImage: "stop.circle")
                }
            } else if viewModel.firstAidState == .stoppingAfterCurrent {
                Label(language.t("Stopping after the current volume finishes…"), systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }
            if viewModel.firstAidState == .completed {
                Button(language.t("Close")) {
                    viewModel.closeFirstAid()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var statusMessageKey: String {
        switch viewModel.firstAidState {
        case .running:
            return "First Aid is running. Do not disconnect the disk or quit Capricorn."
        case .stoppingAfterCurrent:
            return "The current volume will finish safely; remaining volumes will be skipped."
        case .refreshing:
            return "Refreshing disk and SMART information after First Aid."
        case .completed:
            if let error = viewModel.firstAidError, !error.isEmpty { return error }
            return viewModel.firstAidReport?.hasFailures == true ? "First Aid completed with issues." : "First Aid completed."
        case .idle, .preflighting, .awaitingConfirmation:
            return "Preparing First Aid"
        }
    }

    private var statusIcon: String {
        switch viewModel.firstAidState {
        case .completed:
            return viewModel.firstAidReport?.hasFailures == true || viewModel.firstAidError != nil ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
        case .running, .stoppingAfterCurrent, .refreshing:
            return "cross.case.fill"
        case .idle, .preflighting, .awaitingConfirmation:
            return "hourglass"
        }
    }

    private var statusColor: Color {
        viewModel.firstAidState == .completed
            ? (viewModel.firstAidReport?.hasFailures == true || viewModel.firstAidError != nil ? .orange : .green)
            : .blue
    }
}

private struct FirstAidResultRow: View {
    var result: DiskFirstAidTargetResult
    var language: AppLanguage

    var body: some View {
        DisclosureGroup {
            Text(output)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.target.volumeName)
                        .font(.headline)
                    Text("\(result.target.fileSystemType ?? language.t("Unknown")) · \(result.target.deviceIdentifier)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(language.t(statusKey))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(12)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusKey: String {
        switch result.outcome {
        case .succeeded: "First Aid Succeeded"
        case .failed: "First Aid Failed"
        case .skipped: "Skipped"
        }
    }

    private var icon: String {
        switch result.outcome {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .skipped: "minus.circle"
        }
    }

    private var color: Color {
        switch result.outcome {
        case .succeeded: .green
        case .failed: .orange
        case .skipped: .secondary
        }
    }

    private var output: String {
        let text = [result.stdout, result.stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return text.isEmpty ? language.t("No output.") : text
    }
}

private struct FirstAidUnavailableView: View {
    var message: String
    var language: AppLanguage
    var close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                language.t("First Aid Unavailable"),
                systemImage: "exclamationmark.triangle",
                description: Text(language.t(message))
            )
            Button(language.t("Close"), action: close)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }
}

private func openDiskUtility() {
    NSWorkspace.shared.open(diskUtilityURL)
}

private func copyCHKDSKExample() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("chkdsk <drive-letter>: /f", forType: .string)
}
