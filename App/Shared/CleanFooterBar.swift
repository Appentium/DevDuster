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

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedCount) selected")
                    .font(.headline)
                Text(ByteFormatter.string(selectedBytes))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                if isCleaning {
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
