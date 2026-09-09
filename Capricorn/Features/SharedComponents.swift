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
    private let symbol: String?
    private let customIcon: AnyView?
    var valueTint: Color? = nil

    init(title: String, value: String, symbol: String, valueTint: Color? = nil) {
        self.title = title
        self.value = value
        self.symbol = symbol
        self.customIcon = nil
        self.valueTint = valueTint
    }

    init<Icon: View>(
        title: String,
        value: String,
        valueTint: Color? = nil,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.value = value
        self.symbol = nil
        self.customIcon = AnyView(icon())
        self.valueTint = valueTint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let customIcon {
                customIcon
                    .foregroundStyle(.secondary)
            } else if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
            }
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

/// Uses native battery glyphs, with a custom near-full state because SF Symbols
/// does not provide a 90% battery glyph.
enum LifeRemainingBatterySymbol {
    static func symbol(for percent: Int?) -> String {
        guard let percent else { return "battery.50percent" }

        switch min(max(percent, 0), 100) {
        case 100:
            return "battery.100percent"
        case 90..<100:
            return "battery.100percent"
        case 70..<90:
            return "battery.75percent"
        case 45..<70:
            return "battery.50percent"
        case 20..<45:
            return "battery.25percent"
        case 1..<20:
            return "battery.0percent"
        default:
            return "battery.0percent"
        }
    }

    static func nearFullFillFraction(for percent: Int?) -> Double? {
        guard let percent, (90..<100).contains(percent) else { return nil }
        return Double(percent) / 100
    }
}

struct LifeRemainingBatteryIcon: View {
    let percent: Int?

    var body: some View {
        if let fillFraction = LifeRemainingBatterySymbol.nearFullFillFraction(for: percent) {
            NearlyFullBatteryIcon(fillFraction: fillFraction)
        } else {
            Image(systemName: LifeRemainingBatterySymbol.symbol(for: percent))
        }
    }
}

private struct NearlyFullBatteryIcon: View {
    let fillFraction: Double

    var body: some View {
        Canvas { context, size in
            let batteryRect = CGRect(
                x: 1.5,
                y: 4,
                width: size.width - 5,
                height: size.height - 8
            )
            let outline = Path(roundedRect: batteryRect, cornerRadius: 2)
            context.stroke(outline, with: .color(.secondary), lineWidth: 1.4)

            let inset: CGFloat = 2.5
            let fillWidth = max(0, batteryRect.width - inset * 2) * fillFraction
            let fillRect = CGRect(
                x: batteryRect.minX + inset,
                y: batteryRect.minY + inset,
                width: fillWidth,
                height: max(0, batteryRect.height - inset * 2)
            )
            if fillRect.width > 0 {
                let fill = Path(roundedRect: fillRect, cornerRadius: 1)
                context.fill(fill, with: .color(.secondary))
            }

            let terminal = CGRect(
                x: size.width - 3.5,
                y: size.height / 2 - 1.5,
                width: 2,
                height: 3
            )
            context.fill(Path(roundedRect: terminal, cornerRadius: 0.8), with: .color(.secondary))
        }
        .frame(width: 18, height: 18)
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
