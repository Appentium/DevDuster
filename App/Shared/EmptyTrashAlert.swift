import SweepCore
import SwiftUI

struct EmptyTrashAlertModifier: ViewModifier {
    @Binding var volume: Volume?
    @Binding var error: String?
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "Empty Trash on \(volume?.name ?? "")?",
                isPresented: Binding(get: { volume != nil }, set: { if !$0 { volume = nil } })
            ) {
                Button("Empty Trash", role: .destructive, action: onConfirm)
                Button("Cancel", role: .cancel) { volume = nil }
            } message: {
                Text("Items in this volume's Trash will be permanently deleted. This can't be undone.")
            }
            .alert(
                "Failed to Empty Trash",
                isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
            ) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
    }
}

extension View {
    func emptyTrashAlerts(volume: Binding<Volume?>, error: Binding<String?>, onConfirm: @escaping () -> Void) -> some View {
        modifier(EmptyTrashAlertModifier(volume: volume, error: error, onConfirm: onConfirm))
    }
}
