import SweepCore
import SwiftUI

struct EmptyTrashAlertModifier: ViewModifier {
    @Bindable var model: EmptyTrashModel
    let onEmptied: (Volume) async -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "Empty Trash on \(model.volumeToEmpty?.name ?? "")?",
                isPresented: Binding(get: { model.volumeToEmpty != nil }, set: { if !$0 { model.volumeToEmpty = nil } }),
                // Dismissal clears volumeToEmpty before the Task runs, so the volume must be captured here.
                presenting: model.volumeToEmpty
            ) { volume in
                Button("Empty Trash", role: .destructive) {
                    Task {
                        if let emptied = await model.empty(volume) {
                            await onEmptied(emptied)
                        }
                    }
                }
                Button("Cancel", role: .cancel) { model.volumeToEmpty = nil }
            } message: { _ in
                Text("Items in this volume's Trash will be permanently deleted. This can't be undone.")
            }
            .alert(
                "Failed to Empty Trash",
                isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
            ) {
                Button("OK", role: .cancel) { model.error = nil }
            } message: {
                Text(model.error ?? "")
            }
    }
}

extension View {
    func emptyTrashAlerts(model: EmptyTrashModel, onEmptied: @escaping (Volume) async -> Void) -> some View {
        modifier(EmptyTrashAlertModifier(model: model, onEmptied: onEmptied))
    }
}
