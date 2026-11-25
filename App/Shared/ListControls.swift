import SwiftUI

struct SizeSortPicker: View {
    @Binding var order: SizeSortOrder
    var options: [SizeSortOrder] = [.size, .name]

    var body: some View {
        Picker("Sort", selection: $order) {
            ForEach(options) { order in
                Text(order.rawValue).tag(order)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

struct SelectAllButtons: View {
    let canSelectAll: Bool
    let canDeselectAll: Bool
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void

    var body: some View {
        Button("Select All", action: onSelectAll)
            .disabled(!canSelectAll)
        Button("Deselect All", action: onDeselectAll)
            .disabled(!canDeselectAll)
    }
}
