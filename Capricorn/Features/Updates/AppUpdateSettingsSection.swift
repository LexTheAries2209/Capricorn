// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct AppUpdateSettingsSection: View {
    @Bindable var updateChecker: AppUpdateChecker
    let language: AppLanguage
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section(language.t("Updates")) {
            LabeledContent(language.t("Current Version"), value: "V\(updateChecker.currentVersion.displayValue)")

            statusContent

            HStack {
                Button {
                    Task { await updateChecker.checkNow() }
                } label: {
                    Label(language.t("Check for Updates…"), systemImage: "arrow.clockwise")
                }
                .disabled(updateChecker.state == .checking)

                Spacer()

                Button(language.t("Open Releases")) {
                    openURL(GitHubReleaseService.releasesURL)
                }
            }
        }
        .task {
            await updateChecker.checkNow()
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch updateChecker.state {
        case .idle:
            Text(language.t("Not checked yet."))
                .foregroundStyle(.secondary)
        case .checking:
            Label(language.t("Checking for updates…"), systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .upToDate:
            Label(language.t("You are up to date."), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Label(language.t("Unable to connect to GitHub."), systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                Text(language.t("Check your connection, retry, or open the Releases page manually."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .updateAvailable(let release):
            VStack(alignment: .leading, spacing: 6) {
                Label("\(language.t("Update available")): \(release.name)", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                if !release.body.isEmpty {
                    Text(release.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                Link(language.t("Open Release Notes"), destination: release.htmlURL)
                    .font(.caption)
            }
        }
    }
}
