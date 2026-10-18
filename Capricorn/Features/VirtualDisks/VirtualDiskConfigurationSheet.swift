// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct VirtualDiskConfigurationSheet: View {
    let language: AppLanguage
    private let isEditing: Bool
    let create: (VirtualDiskConfiguration) throws -> Void
    let cancel: () -> Void
    @State private var configuration: VirtualDiskConfiguration
    @State private var creationError: String?

    init(
        language: AppLanguage,
        configuration: VirtualDiskConfiguration? = nil,
        existingDiskNames: [String] = [],
        create: @escaping (VirtualDiskConfiguration) throws -> Void,
        cancel: @escaping () -> Void
    ) {
        self.language = language
        self.isEditing = configuration != nil
        self.create = create
        self.cancel = cancel
        _configuration = State(initialValue: configuration ?? .defaults(
            language: language, existingNames: existingDiskNames
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(language.t(isEditing ? "Edit Configuration" : "Add virtual disk"))
                    .font(.title2.bold())
                Spacer()
            }
            .padding(20)

            Form {
                Section(language.t("Disk Identity")) {
                    TextField(language.t("Name"), text: $configuration.name)
                    TextField(language.t("Model"), text: $configuration.model, prompt: Text(language.t("Optional")))
                    TextField(language.t("Serial Number"), text: $configuration.serialNumber, prompt: Text(language.t("Optional")))
                    LabeledContent(language.t("Capacity")) {
                        VirtualDiskCapacityInput(value: $configuration.capacity, unit: $configuration.unit)
                    }
                    Picker(language.t("Disk Type"), selection: $configuration.mediaType) {
                        ForEach(VirtualDiskMediaType.allCases) { type in
                            Text(language.t(type.rawValue)).tag(type)
                        }
                    }
                    Picker(language.t("Interface"), selection: $configuration.interface) {
                        ForEach(VirtualDiskInterface.allCases) { interface in
                            Text(language.t(interface.titleKey)).tag(interface)
                        }
                    }
                    Picker(language.t("Sector Size"), selection: $configuration.blockSize) {
                        Text("512B").tag(512)
                        Text("4KB").tag(4096)
                    }
                }

                Section(language.t("Partitions")) {
                    ForEach($configuration.partitions) { $partition in
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent(language.t("Partition Name")) {
                                HStack(spacing: 12) {
                                    TextField(language.t("Partition Name"), text: $partition.name)
                                        .labelsHidden()
                                        .multilineTextAlignment(.trailing)
                                    Button {
                                        configuration.partitions.removeAll { $0.id == partition.id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(language.t("Remove Partition"))
                                    .accessibilityLabel(language.t("Remove Partition"))
                                }
                            }
                            LabeledContent(language.t("Partition Type")) {
                                Picker(language.t("Partition Type"), selection: $partition.format) {
                                    ForEach(VirtualDiskFormat.allCases) { format in
                                        Text(language.t(format.rawValue)).tag(format)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize(horizontal: true, vertical: false)
                            }
                            LabeledContent(language.t("Capacity")) {
                                VirtualDiskCapacityInput(value: $partition.capacity, unit: $partition.unit)
                            }
                            LabeledContent(language.t("Used Capacity")) {
                                VirtualDiskCapacityInput(
                                    value: $partition.usedCapacity, unit: $partition.usedCapacityUnit,
                                    title: language.t("Used Capacity")
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    HStack {
                        Button {
                            var partition = VirtualDiskPartition()
                            partition.name = "\(language.t("Partition")) \(configuration.partitions.count + 1)"
                            partition.unit = .gb
                            let remainder = configuration.unallocatedBytes ?? 0
                            partition.capacity = String(format: "%.3f", Double(remainder) / 1_000_000_000)
                            configuration.partitions.append(partition)
                        } label: {
                            Label(language.t("Add Partition"), systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                        if let bytes = configuration.unallocatedBytes {
                            Text("\(language.t("Unallocated")): \(formatByteCount(bytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(language.t("Overview Values")) {
                    Picker(language.t("Health"), selection: $configuration.health) {
                        Text(language.t("Automatic")).tag(nil as HealthStatus?)
                        ForEach(HealthStatus.allCases) { status in
                            Text(language.healthTitle(status)).tag(Optional(status))
                        }
                    }
                    metricField("Temperature", unit: "C", value: $configuration.temperature)
                    metricField("Life Remaining", unit: "%", value: $configuration.lifeRemaining)
                    metricField("Power-On Hours", value: $configuration.powerOnHours)
                    metricField("Power Cycles", value: $configuration.powerCycleCount)
                    metricField("Media Errors", value: $configuration.mediaErrors)
                    metricField("Unsafe Shutdowns", value: $configuration.unsafeShutdowns)
                }
            }
            .formStyle(.grouped)
            .textFieldStyle(.roundedBorder)
            .environment(\.locale, Locale(identifier: language.localeIdentifier))

            Divider()
            HStack(alignment: .center, spacing: 16) {
                if let message = creationError ?? configuration.validationMessage {
                    Text(language.t(message))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                Button(language.t("Cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    do {
                        try create(configuration)
                    } catch {
                        creationError = error.localizedDescription
                    }
                } label: {
                    Label(language.t(isEditing ? "Save" : "Add"), systemImage: isEditing ? "checkmark" : "plus")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(configuration.validationMessage != nil)
                .accessibilityIdentifier(isEditing ? "saveVirtualDisk" : "createVirtualDisk")
            }
            .padding(20)
        }
        .frame(minWidth: 700, idealWidth: 700, maxWidth: 800, minHeight: 620, idealHeight: 760)
        .onChange(of: configuration.validationMessage) { creationError = nil }
    }

    private func metricField(_ title: String, unit: String? = nil, value: Binding<String>) -> some View {
        LabeledContent(language.t(title)) {
            HStack(spacing: 8) {
                TextField(language.t(title), text: value, prompt: Text(language.t("Optional")))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                if let unit {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                }
            }
        }
    }
}

private struct VirtualDiskCapacityInput: View {
    @Binding var value: String
    @Binding var unit: VirtualDiskCapacityUnit
    var title = "Capacity"

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $value)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Picker("Unit", selection: $unit) {
                ForEach(VirtualDiskCapacityUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .labelsHidden()
            .frame(width: 70)
        }
    }
}
