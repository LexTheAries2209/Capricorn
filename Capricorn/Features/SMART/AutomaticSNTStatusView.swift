// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct AutomaticSNTSettingsControls: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        Toggle(preferences.language.t("Read SNT automatically"), isOn: $preferences.automaticSNT)
            .accessibilityIdentifier("settings.automaticSNT")
        Text(preferences.language.t(
            "When authorized, read idle USB disks once when Capricorn opens or a disk connects. Volumes are temporarily unmounted and restored without a confirmation window. Three read failures pause automatic attempts; manual success enables them again."
        ))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct AutomaticSNTStatusView: View {
    let drive: DriveDevice
    let viewModel: AppModel
    @Environment(\.appLanguage) private var language

    var body: some View {
        if let status = viewModel.automaticSNTStatus(for: drive) {
            VStack(alignment: .leading, spacing: 4) {
                Label(language.t(status.rawValue), systemImage: symbol(for: status))
                    .font(.caption)
                    .foregroundStyle(status == .recovery ? Color.orange : Color.secondary)
                    .accessibilityIdentifier("smart.automaticSNT.status")
                if let diagnostic = viewModel.automaticSNTDiagnostic(for: drive), !diagnostic.isEmpty {
                    DisclosureGroup(language.t("Diagnostic Output")) {
                        ScrollView {
                            Text(diagnostic)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 140)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func symbol(for status: AutomaticSNTStatus) -> String {
        switch status {
        case .updated: "checkmark.circle"
        case .reading: "arrow.triangle.2.circlepath"
        case .recovery: "exclamationmark.triangle"
        case .authorization: "lock"
        case .stopped, .unsupported: "pause.circle"
        default: "clock"
        }
    }
}
