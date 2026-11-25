import DusterCore
import SwiftUI

struct ScanProgressBanner: View {
    let phase: ScanPhase
    let currentPath: String
    let onCancel: () -> Void

    private var phaseLabel: String {
        switch phase {
        case .rules: "Scanning rules..."
        case .projects: "Scanning projects..."
        case .measuring: "Measuring sizes..."
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(phaseLabel)
                    .font(.subheadline.weight(.medium))
                if !currentPath.isEmpty {
                    Text(currentPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
