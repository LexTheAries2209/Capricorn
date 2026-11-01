// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import ServiceManagement

struct DeviceHelperSettingsSection: View {
    let language: AppLanguage
    @State private var manager = DeviceHelperServiceManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section(language.t("Privileged Device Service")) {
            LabeledContent(language.t("Status"), value: language.t(statusTitle))
            HStack {
                Button {
                    manager.enable()
                } label: {
                    Label(language.t(manager.status == .requiresApproval ? "Review System Approval" : "Enable Device Service"),
                          systemImage: "lock.shield")
                }
                .disabled(manager.isChanging || manager.status == .enabled)
                Button {
                    Task { await manager.disable() }
                } label: {
                    Label(language.t("Disable Device Service"), systemImage: "stop.circle")
                }
                .disabled(manager.isChanging || manager.status == .notRegistered || manager.status == .notFound)
                Spacer()
                Button {
                    manager.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(language.t("Refresh Service Status"))
            }
            if let error = manager.error {
                Text(language.t(error)).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
        }
        .task { manager.refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active { manager.refresh() } }
    }

    private var statusTitle: String {
        switch manager.status {
        case .enabled: "Device Service Enabled"
        case .requiresApproval: "Device Service Awaiting System Approval"
        case .notRegistered: "Device Service Not Enabled"
        case .notFound: "Device Service Not Found"
        @unknown default: "Device Service Unavailable"
        }
    }
}
