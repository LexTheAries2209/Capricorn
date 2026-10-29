// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct USBRawSmartSheet: View {
    @Bindable var viewModel: AppModel
    let language: AppLanguage

    var body: some View {
        if let session = viewModel.usbRawSmartSession {
            VStack(alignment: .leading, spacing: 16) {
                Label(language.t("Try SNT"), systemImage: "externaldrive.badge.questionmark")
                    .font(.title2.bold())
                Text("\(session.drive.displayName) (\(session.drive.bsdName))")
                    .font(.headline)
                    .textSelection(.enabled)
                switch session.state {
                case .confirmation:
                    confirmation(session)
                case .running:
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(language.t("Running SNT..."))
                    }
                    Text(language.t("Volumes will be unmounted, the USB device captured, SMART read, and the device released before mount restoration is attempted."))
                        .foregroundStyle(.secondary)
                    Text(language.t("Keep the disk connected until this window shows the result."))
                        .foregroundStyle(.secondary)
                case .completed:
                    completion(session)
                }
                Divider()
                HStack {
                    Spacer()
                    if session.state == .confirmation {
                        Button(language.t("Cancel")) { viewModel.closeUSBRawSmart() }
                            .keyboardShortcut(.cancelAction)
                        Button(language.t("Unmount and Try SNT")) {
                            Task { await viewModel.beginUSBRawSmart() }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canBeginUSBRawSmart)
                    } else if session.state == .completed {
                        Button(language.t("Close")) { viewModel.closeUSBRawSmart() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(24)
            .frame(width: 580)
            .fixedSize(horizontal: false, vertical: true)
            .interactiveDismissDisabled(session.state == .running)
        }
    }

    private func confirmation(_ session: USBRawSmartSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(language.t("Experimental USB-NVMe SMART Read"), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(language.t("This will attempt to unmount all volumes on this USB device and take exclusive control of the device. Open files and disk operations must be closed first."))
            Text(language.t("After reading SMART, Capricorn will release the device and attempt to restore its previous mounts. Restoration may fail; reconnecting the disk or using Disk Utility may be necessary. Administrator authorization is required."))
                .foregroundStyle(.secondary)
            Text(language.t("If automatic identification fails, up to three SNT protocols will be tried. Volumes may be unmounted and restored more than once."))
                .foregroundStyle(.secondary)
            if session.drive.volumes.contains(where: { $0.mountPoint != nil }) {
                Text(language.t("Mounted Volumes")).font(.subheadline.bold())
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(session.drive.volumes.filter { $0.mountPoint != nil }) { volume in
                            Text("\(volume.name)  \(volume.mountPoint ?? "")")
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 110)
            }
        }
    }

    @ViewBuilder
    private func completion(_ session: USBRawSmartSession) -> some View {
        if let result = session.result {
            Label(
                language.t(result.message),
                systemImage: result.snapshot?.hasSMARTPayload == true && result.restorationConfirmed
                    ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .foregroundStyle(result.restorationConfirmed ? Color.primary : Color.orange)
            if !result.phases.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(result.phases.enumerated()), id: \.offset) { _, phase in
                        Label(language.t(phase.title),
                              systemImage: phase == .restoreFailed ? "exclamationmark.triangle"
                                : phase == .restored ? "checkmark" : "arrow.right")
                            .font(.callout)
                    }
                }
            }
            DisclosureGroup(language.t("Diagnostic Output")) {
                ScrollView {
                    Text(result.transcript)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 180)
            }
        }
        if let error = session.error {
            Text(language.t(error)).foregroundStyle(.orange).textSelection(.enabled)
        }
    }
}
