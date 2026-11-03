// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct AutomaticSNTSettingsControls: View {
    @Bindable var preferences: AppPreferences
    @State private var serviceManager: DeviceHelperServiceManager
    @State private var showsServiceWarning = false
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init(preferences: AppPreferences, serviceManager: DeviceHelperServiceManager? = nil) {
        self.preferences = preferences
        _serviceManager = State(initialValue: serviceManager ?? .shared)
    }

    var body: some View {
        HStack {
            Text(preferences.language.t("Read SNT automatically"))
                .foregroundStyle(serviceManager.availability == .available ? Color.primary : Color.secondary)
            Spacer(minLength: 8)
            Group {
                if let warning {
                    Button {
                        showsServiceWarning.toggle()
                    } label: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preferences.language.t(warning))
                    .accessibilityIdentifier("settings.automaticSNT.serviceWarning")
                    .popover(isPresented: $showsServiceWarning, arrowEdge: .bottom) {
                        Text(preferences.language.t(warning))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 280, alignment: .leading)
                            .padding(12)
                    }
                } else if serviceManager.availability == .checking {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel(preferences.language.t("Checking device service"))
                }
            }
            .frame(width: 22, height: 22)
            Toggle(preferences.language.t("Read SNT automatically"), isOn: $preferences.automaticSNT)
                .labelsHidden()
                .disabled(serviceManager.availability != .available)
                .accessibilityIdentifier("settings.automaticSNT")
                .help(preferences.language.t(
                    "When authorized, read idle USB disks when Capricorn opens or a disk connects, unless valid SNT data was captured within 48 hours."
                ))
        }
        .task { await serviceManager.monitorConnectionHealth() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { serviceManager.refresh() }
        }
        .onChange(of: serviceManager.availability) {
            if warning == nil { showsServiceWarning = false }
        }
    }

    private var warning: String? {
        switch serviceManager.availability {
        case .notEnabled:
            "Enable the device service in Settings before using automatic SNT reads."
        case .unhealthy:
            "The privileged device service is not working. Disable and re-enable it."
        case .checking, .available:
            nil
        }
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
        case .cached: "clock.arrow.circlepath"
        case .reading: "arrow.triangle.2.circlepath"
        case .recovery: "exclamationmark.triangle"
        case .authorization: "lock"
        case .stopped, .unsupported: "pause.circle"
        default: "clock"
        }
    }
}
