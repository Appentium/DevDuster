import SwiftUI

struct CleanFooterBar: View {
    let selectedCount: Int
    let selectedBytes: Int64
    @Binding var moveToTrash: Bool
    let isDisabled: Bool
    let isCleaning: Bool
    let onClean: () -> Void
    var actionTitle = "Clean"
    var showsTrashToggle = true
    /// While a clean runs, a progress bar takes the place of the selection summary.
    var progress: CleanProgress? = nil

    var body: some View {
        HStack(spacing: 16) {
            if let progress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 360)
                        .animation(.easeOut(duration: 0.2), value: progress.fraction)
                    Text(progress.label)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedCount) selected")
                        .font(.headline)
                    Text(ByteFormatter.string(selectedBytes))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if showsTrashToggle {
                Toggle("Move to Trash", isOn: $moveToTrash)
                    .toggleStyle(.checkbox)
                    .disabled(isCleaning)
            }
            Button {
                onClean()
            } label: {
                if isCleaning && progress == nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(actionTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(moveToTrash && showsTrashToggle ? .accentColor : .red)
            .disabled(isDisabled || isCleaning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// Shown on a list row while that item is being deleted.
struct DeletingBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Deleting…")
                .font(.callout)
                .foregroundStyle(.tint)
        }
        .transition(.opacity)
    }
}
