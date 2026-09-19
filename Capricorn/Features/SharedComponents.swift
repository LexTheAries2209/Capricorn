// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct InfoPanel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    var valueTint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(valueTint ?? Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

/// Maps health bands to the battery glyphs available in the system symbol set.
enum LifeRemainingBatterySymbol {
    static func symbol(for percent: Int?) -> String {
        guard let percent else { return "battery.50percent" }

        switch min(max(percent, 0), 100) {
        case 100:
            return "battery.100percent"
        case 60..<100:
            return "battery.75percent"
        case 40..<60:
            return "battery.50percent"
        case 20..<40:
            return "battery.25percent"
        default:
            return "battery.0percent"
        }
    }
}

struct HealthBadge: View {
    let status: HealthStatus
    var compact = false
    @Environment(\.appLanguage) private var language

    var body: some View {
        Label(language.healthBadgeTitle(status, compact: compact), systemImage: status.symbolName)
            .font(compact ? .caption.bold() : .headline)
            .foregroundStyle(status.tint)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 8)
            .background(status.tint.opacity(0.12), in: Capsule())
    }
}

struct StatusLine: View {
    let title: String
    let isOn: Bool
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack {
            Image(systemName: isOn ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isOn ? .green : .secondary)
            Text(title)
            Spacer()
            Text(isOn ? language.t("Detected") : language.t("Not detected"))
                .foregroundStyle(.secondary)
        }
    }
}

struct SATSMARTDriverGuidanceView: View {
    let guidance: SATSMARTDriverGuidance
    let openSettings: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(alignment: .center) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.t(guidance.titleKey))
                        .font(.headline)
                    Text(language.t(guidance.messageKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if guidance.showsSATSettingsAction {
                Spacer(minLength: 12)

                Button(action: openSettings) {
                    Label(language.t("Open SAT SMART Drive Settings"), systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }
}

struct SATSMARTDriverGuidanceUnavailableView: View {
    let guidance: SATSMARTDriverGuidance
    let openSettings: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(language.t(guidance.titleKey))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } description: {
            VStack(spacing: 2) {
                ForEach(guidance.smartMessageLineKeys, id: \.self) { lineKey in
                    Text(language.t(lineKey))
                }
            }
            .multilineTextAlignment(.center)
        } actions: {
            if guidance.showsSATSettingsAction {
                Button(action: openSettings) {
                    Label(language.t("Open SAT SMART Drive Settings"), systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }
}

extension SATSMARTDriverGuidance {
    var titleKey: String {
        switch self {
        case .installationSuggested:
            "SAT SMART Drive May Be Required"
        case .activationRequired:
            "SAT SMART Drive Needs Attention"
        case .samsungT5DriverConflict:
            "Driver Conflict May Block SMART"
        case .usbNVMeSMARTUnavailable:
            "USB-NVMe SMART May Be Unavailable"
        }
    }

    var messageKey: String {
        switch self {
        case .installationSuggested:
            "This USB storage device did not return SMART data. Installing SAT SMART Drive may provide more health information; support depends on the drive and enclosure."
        case .activationRequired:
            "SAT SMART Drive files are installed, but the driver is not active. Check macOS approval or restart, then recheck it in Settings."
        case .samsungT5DriverConflict:
            "SAT SMART Drive is installed, but this Samsung Portable SSD T5 still did not return SMART data. Samsung's driver may conflict with SAT SMART Drive; removing the Samsung driver may restore SMART access."
        case .usbNVMeSMARTUnavailable:
            "SAT SMART Drive is installed, but this USB-NVMe drive still did not return SMART data. SAT SMART Drive targets SATA bridges; some USB-NVMe bridges cannot expose SMART data on macOS."
        }
    }

    var smartMessageLineKeys: [String] {
        switch self {
        case .installationSuggested:
            [
                "This USB storage device did not return SMART data",
                "Installing SAT SMART Drive may provide more health information",
                "Support depends on the drive and enclosure"
            ]
        case .activationRequired:
            [
                "SAT SMART Drive files are installed",
                "The driver is not active",
                "Check macOS approval or restart",
                "Then recheck it in Settings"
            ]
        case .samsungT5DriverConflict:
            [
                "SAT SMART Drive is installed",
                "This Samsung Portable SSD T5 still did not return SMART data",
                "Samsung's driver may conflict with SAT SMART Drive",
                "Removing the Samsung driver may restore SMART access"
            ]
        case .usbNVMeSMARTUnavailable:
            [
                "SAT SMART Drive is installed",
                "This USB-NVMe drive still did not return SMART data",
                "SAT SMART Drive targets SATA bridges",
                "Some USB-NVMe bridges cannot expose SMART data on macOS"
            ]
        }
    }

    var showsSATSettingsAction: Bool {
        switch self {
        case .installationSuggested, .activationRequired:
            true
        case .samsungT5DriverConflict, .usbNVMeSMARTUnavailable:
            false
        }
    }
}

extension HealthStatus {
    var tint: Color {
        switch self {
        case .good: .green
        case .warning: .yellow
        case .preFail: .orange
        case .failed: .red
        case .unavailable: .secondary
        }
    }
}

extension ProviderState {
    var tint: Color {
        switch self {
        case .available: .green
        case .limited: .yellow
        case .unavailable: .secondary
        case .failed: .red
        }
    }

    var symbolName: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .limited: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }
}
