// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct AppUpdateSettingsSection: View {
    @Bindable var updateChecker: AppUpdater
    let language: AppLanguage
    let showsBuildNumber: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section(language.t("Updates")) {
            LabeledContent(language.t("Current Version"), value: "V\(AppVersion.current.displayValue)")
            if showsBuildNumber, let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                LabeledContent(language.t("Build"), value: build)
            }

            Toggle(language.t("Check for updates on launch"), isOn: Binding(
                get: { updateChecker.automaticallyChecksForUpdates },
                set: { updateChecker.setAutomaticallyChecksForUpdates($0) }
            ))
            Toggle(language.t("Automatically download and install on quit"), isOn: Binding(
                get: { updateChecker.automaticallyDownloadsUpdates },
                set: { updateChecker.setAutomaticallyDownloadsUpdates($0) }
            ))
            .disabled(!updateChecker.automaticallyChecksForUpdates)

            HStack(spacing: 10) {
                Button {
                    updateChecker.checkNow()
                } label: {
                    Label(language.t("Check for Updates…"), systemImage: "arrow.clockwise")
                }
                .disabled(updateChecker.isStarted && !updateChecker.canCheckForUpdates)
                .fixedSize()

                if let lastChecked = updateChecker.lastCheckedAt {
                    let formattedDate = lastChecked.formatted(
                        .dateTime.year().month(.twoDigits).day(.twoDigits)
                            .hour().minute().locale(Locale(identifier: language.localeIdentifier))
                    )
                    Text("\(language.t("Last checked")): \(formattedDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(Text(lastChecked, format: .dateTime.year().month().day().hour().minute()))
                }

                Spacer(minLength: 4)

                Button(language.t("Open Releases")) {
                    openURL(GitHubReleaseService.releasesURL)
                }
                .fixedSize()
            }
            if language != updateChecker.nativeLanguage {
                Text(language.t("Restart Capricorn to apply this language to update windows."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            statusContent
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
        case .failed(let issue):
            Label(language.t(issue.rawValue), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .available(let version):
            Label(language.updateAvailableMessage(version: version), systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
                .fixedSize(horizontal: false, vertical: true)
        case .downloading:
            ProgressView(language.t("Downloading update…"), value: updateChecker.downloadProgress)
        case .extracting:
            Label(language.t("Preparing update…"), systemImage: "shippingbox")
        case .readyToInstall:
            Label(language.t("Update ready to install"), systemImage: "checkmark.circle")
        case .installing:
            Label(language.t("Installing update…"), systemImage: "arrow.triangle.2.circlepath")
        case .blocked(let conflicts):
            VStack(alignment: .leading, spacing: 6) {
                Label(language.t("Update blocked"), systemImage: "hand.raised")
                    .foregroundStyle(.orange)
                Text(conflicts.map { language.t($0.rawValue) }.joined(separator: ", "))
                    .font(.caption)
            }
        }
    }
}
