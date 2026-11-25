import SwiftUI

struct DiskMapFiltersView: View {
    @Bindable var model: DiskMapModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double?
    @State private var unit = SizeUnit.mb

    enum SizeUnit: Int64, CaseIterable, Identifiable {
        case kb = 1_000
        case mb = 1_000_000
        case gb = 1_000_000_000

        var id: Int64 { rawValue }

        var label: String {
            switch self {
            case .kb: "KB"
            case .mb: "MB"
            case .gb: "GB"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hide Smaller Than")
                .font(.headline)

            Picker("Preset", selection: presetBinding) {
                Text("Off").tag(Int64(0))
                ForEach(DiskMapModel.minimumSizeOptions.dropFirst(), id: \.self) { bytes in
                    Text(ByteFormatter.string(bytes)).tag(bytes)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                Text("Custom")
                TextField("Size", value: $amount, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit(applyAndClose)
                Picker("Unit", selection: $unit) {
                    ForEach(SizeUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Button("Apply", action: applyAndClose)
            }

            Divider()

            Text("Excluded from Scans")
                .font(.headline)
            if model.excludedPaths.isEmpty {
                Text("Right-click a folder on the map to exclude it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.excludedPaths, id: \.self) { path in
                HStack {
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 280, alignment: .leading)
                    Spacer()
                    Button("Include Again") { model.includeAgain(path) }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 420, alignment: .leading)
        .fixedSize()
        .onAppear { showInField(model.minimumBytes) }
    }

    private var fieldBytes: Int64 {
        guard let amount, amount > 0 else { return 0 }
        return Int64(amount * Double(unit.rawValue))
    }

    private var presetBinding: Binding<Int64> {
        Binding(get: { fieldBytes }, set: showInField)
    }

    private func applyAndClose() {
        model.minimumBytes = fieldBytes
        dismiss()
    }

    private func showInField(_ bytes: Int64) {
        guard bytes > 0 else {
            amount = nil
            return
        }
        unit = SizeUnit.allCases.last { bytes >= $0.rawValue } ?? .kb
        amount = Double(bytes) / Double(unit.rawValue)
    }
}
