import SweepCore
import SwiftUI

struct DashboardView: View {
    @Bindable var model: DashboardModel
    let onScan: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.entries.isEmpty && model.isLoading {
                    ProgressView("Loading volumes...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if model.entries.isEmpty {
                    ContentUnavailableView("No Volumes Found", systemImage: "externaldrive")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                        ForEach(model.entries) { entry in
                            VolumeCard(
                                entry: entry,
                                isEmptying: model.isEmptying,
                                onEmptyTrash: { model.requestEmptyTrash(for: entry.volume) }
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)

                Button(action: onScan) {
                    Label("Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task {
            await model.refresh()
        }
        .emptyTrashAlerts(
            volume: $model.volumeToEmpty,
            error: $model.emptyError,
            onConfirm: { Task { await model.confirmEmptyTrash() } }
        )
    }
}

private struct VolumeCard: View {
    let entry: DashboardModel.VolumeEntry
    let isEmptying: Bool
    let onEmptyTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: entry.volume.isInternal ? "internaldrive" : "externaldrive")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(entry.volume.name)
                    .font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    BadgeView(
                        text: entry.volume.isInternal ? "Internal" : "External",
                        color: .secondary
                    )
                    if entry.volume.isReadOnly {
                        BadgeView(text: "Read-Only", color: .orange)
                    }
                }
            }

            SizeBar(usedBytes: entry.usedBytes, totalBytes: entry.volume.totalBytes)

            HStack {
                Text("\(ByteFormatter.string(entry.volume.availableBytes)) available")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("of \(ByteFormatter.string(entry.volume.totalBytes))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.string(entry.trashBytes))
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                Button("Empty Trash", action: onEmptyTrash)
                    .buttonStyle(.bordered)
                    .disabled(entry.volume.isReadOnly || entry.trashBytes == 0 || isEmptying)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}
