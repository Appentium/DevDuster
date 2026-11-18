import DusterCore
import SwiftUI

struct CleanFlowModifier: ViewModifier {
    @Bindable var session: CleanSessionModel
    let selectedCount: Int
    let selectedBytes: Int64
    let onConfirmClean: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $session.isConfirming) {
                CleanConfirmationSheet(
                    itemCount: selectedCount,
                    totalBytes: selectedBytes,
                    moveToTrash: session.moveToTrash,
                    onConfirm: onConfirmClean,
                    onCancel: { session.isConfirming = false }
                )
            }
            .emptyTrashAlerts(model: session.emptyTrash) { volume in
                session.markEmptied(volume)
            }
    }
}

extension View {
    func cleanFlowModals(
        session: CleanSessionModel,
        selectedCount: Int,
        selectedBytes: Int64,
        onConfirmClean: @escaping () -> Void
    ) -> some View {
        modifier(
            CleanFlowModifier(
                session: session,
                selectedCount: selectedCount,
                selectedBytes: selectedBytes,
                onConfirmClean: onConfirmClean
            )
        )
    }
}
