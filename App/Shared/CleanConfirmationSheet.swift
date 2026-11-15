import SwiftUI

struct CleanConfirmationSheet: View {
    let itemCount: Int
    let totalBytes: Int64?
    let moveToTrash: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: moveToTrash ? "trash" : "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(moveToTrash ? Color.accentColor : Color.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(moveToTrash ? "Move \(itemCount) items to Trash?" : "Permanently delete \(itemCount) items?")
                        .font(.headline)
                    if let totalBytes {
                        Text("Total size: \(ByteFormatter.string(totalBytes))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if moveToTrash {
                Text("Selected items will be moved to the Trash. You can restore them from Trash until it is emptied.")
                    .font(.body)
            } else {
                Text("Selected items will be permanently deleted and can't be undone.")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(moveToTrash ? "Move to Trash" : "Delete Permanently", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(moveToTrash ? .accentColor : .red)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
