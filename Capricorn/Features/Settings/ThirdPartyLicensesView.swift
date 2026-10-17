// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct ThirdPartyLicensesView: View {
    static let windowID = "third-party-licenses"
    let language: AppLanguage
    @State private var selection = Component.sparkle

    private enum Component: String, CaseIterable, Identifiable {
        case sparkle = "Sparkle"
        case smartctl = "smartctl"

        var id: String { rawValue }

        var version: String {
            switch self {
            case .sparkle: "2.10.0"
            case .smartctl: "7.5"
            }
        }

        var license: String {
            switch self {
            case .sparkle: "MIT / BSD"
            case .smartctl: "GPL-2.0-or-later"
            }
        }

        var projectURL: URL {
            switch self {
            case .sparkle: URL(string: "https://github.com/sparkle-project/Sparkle")!
            case .smartctl: URL(string: "https://www.smartmontools.org/")!
            }
        }

        var licenseText: String? {
            // Xcode copies these synchronized resource groups into the resource root.
            let name = self == .sparkle ? "LICENSE" : "COPYING"
            guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker(language.t("Component"), selection: $selection) {
                ForEach(Component.allCases) { component in
                    Text(component.rawValue).tag(component)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Link(destination: selection.projectURL) {
                    Label("\(selection.rawValue) \(selection.version)", systemImage: "safari")
                }
                Spacer()
                Text(selection.license)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(verbatim: selection.licenseText ?? language.t("License text is unavailable."))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(.background)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 400)
        .navigationTitle(language.t("Third-Party Licenses"))
    }
}
