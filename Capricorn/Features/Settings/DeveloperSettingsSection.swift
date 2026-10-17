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
                    preferences.language.t("Enable custom benchmark configuration"),
                    isOn: $preferences.enablesCustomBenchmarkConfiguration
                )
                Toggle(
                    preferences.language.t("Enable virtual disks"),
                    isOn: $preferences.enablesVirtualDisks
                )
                Toggle(
                    preferences.language.t("Show build number"),
                    isOn: $preferences.showsBuildNumber
                )
            }
        }
    }
}
