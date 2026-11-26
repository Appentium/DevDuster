import DusterCore
import SwiftUI

struct CleanResultSummaryView: View {
    let summary: CleanSummary
    let emptiedVolumeIDs: Set<URL>
    let onEmptyTrash: (Volume) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    "\(summary.mode == .trash ? "Moved to Trash" : "Deleted"): \(ByteFormatter.string(summary.freedBytes)) (\(summary.cleanedCount) items)",
                    systemImage: summary.issues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(summary.issues.isEmpty ? .green : .orange)
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.borderless)
            }

            if summary.mode == .trash, summary.cleanedCount > 0 {
                Text("Space is only freed once that volume's Trash is emptied.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !summary.affectedVolumes.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(summary.affectedVolumes) { volume in
                            let isEmptied = emptiedVolumeIDs.contains(volume.id)
                            Button(isEmptied ? "Emptied \(volume.name)" : "Empty Trash on \(volume.name)") {
                                onEmptyTrash(volume)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isEmptied || volume.isReadOnly)
                        }
                    }
                }
            }

            if summary.cleanedCount > 0 {
                ShareStatsPrompt()
            }

            if !summary.issues.isEmpty {
                Divider()
                Text("Failures & Refusals (\(summary.issues.count))")
                    .font(.subheadline.weight(.semibold))
                ForEach(summary.issues) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.reason)
                            .font(.callout)
                            .foregroundStyle(.red)
                        Text(issue.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

// Asked once, after the first clean that removed something; Settings has the same switch.
private struct ShareStatsPrompt: View {
    @State private var isVisible = !DusterSettings().shareStatsAsked

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add your total to the DevDuster world counter?")
                    .font(.subheadline.weight(.semibold))
                Text("Shares only a random ID, the platform, the app version and the total space freed. No paths or file names. You can turn it off in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Share Anonymously") {
                        StatsSharing.setSharing(true)
                        isVisible = false
                    }
                    .buttonStyle(.borderedProminent)
                    Button("No Thanks") {
                        StatsSharing.decline()
                        isVisible = false
                    }
                    .buttonStyle(.bordered)
                    Link("What is sent", destination: StatsSharing.privacyURL)
                        .font(.callout)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
