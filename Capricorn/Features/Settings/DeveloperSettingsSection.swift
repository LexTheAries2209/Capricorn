// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct DeveloperSettingsSection: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        Section(preferences.language.t("Developer Options")) {
            Toggle(
                preferences.language.t("Enable developer options"),
                isOn: $preferences.enablesDeveloperOptions
            )

            if preferences.enablesDeveloperOptions {
                Toggle(
                    preferences.language.t("Allow adding virtual disks (Beta)"),
                    isOn: $preferences.enablesVirtualDisks
                )
                Toggle(
                    preferences.language.t("Show build number"),
                    isOn: $preferences.showsBuildNumber
                )
                Toggle(
                    preferences.language.t("Automatically download and install updates"),
                    isOn: $preferences.automaticallyDownloadsAndInstallsUpdates
                )
            }
        }
    }
}
