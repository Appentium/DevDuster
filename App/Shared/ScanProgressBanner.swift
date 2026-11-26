import DusterCore
import SwiftUI

struct ScanProgressBanner: View {
    let phase: ScanPhase
    let currentPath: String
    var fraction: Double? = nil
    var foundCount = 0
    var foundBytes: Int64 = 0
    var foundNoun = "items"
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
            if fraction == nil {
                ProgressView()
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(phaseLabel)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if foundCount > 0 {
                        Text("Found \(foundCount) \(foundNoun), \(foundBytes.formatted(.byteCount(style: .file)))")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                if let fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Scan progress")
                }
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
