import DusterCore
import SwiftUI

struct DashboardView: View {
    @Bindable var model: DashboardModel
    let cleaner: CleanerModel
    let onScan: () -> Void
    let onOpen: (SidebarSection) -> Void

    private let wideColumns = [GridItem(.adaptive(minimum: 380), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let boot = model.bootEntry {
                    StorageOverviewCard(entry: boot, lastCleaned: model.history.lastCleaned, onScan: onScan)
                    statTiles
                    LazyVGrid(columns: wideColumns, spacing: 16) {
                        ReclaimableCard(cleaner: cleaner, onScan: onScan, onReview: { onOpen(.cleaner) })
                        CleaningActivityCard(history: model.history)
                        MacInfoCard(info: model.macInfo)
                        QuickActionsCard(onOpen: onOpen)
                    }
                    volumes
                } else if model.isLoading {
                    ProgressView("Loading volumes...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ContentUnavailableView("No Volumes Found", systemImage: "externaldrive")
                        .frame(maxWidth: .infinity, minHeight: 200)
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
            await model.loadIfNeeded()
        }
        .emptyTrashAlerts(model: model.emptyTrash) { _ in
            await model.refresh()
        }
    }

    private var statTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            StatTile(
                title: "Reclaimable Now",
                value: cleaner.hasScanned ? ByteFormatter.string(cleaner.items.reduce(0) { $0 + $1.bytes }) : "Not scanned",
                systemImage: "sparkles",
                tint: .accentColor
            )
            StatTile(
                title: "Freed Last 30 Days",
                value: ByteFormatter.string(model.history.bytes(since: .now.addingTimeInterval(-30 * 86_400))),
                systemImage: "calendar",
                tint: .green
            )
            StatTile(
                title: "Freed All Time",
                value: ByteFormatter.string(model.history.totalBytes),
                systemImage: "chart.line.uptrend.xyaxis",
                tint: .purple
            )
            StatTile(
                title: "In Trash",
                value: ByteFormatter.string(model.totalTrashBytes),
                systemImage: "trash",
                tint: .orange
            )
        }
    }

    private var volumes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volumes")
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                ForEach(model.entries) { entry in
                    VolumeCard(
                        entry: entry,
                        isEmptying: model.emptyTrash.isEmptying,
                        onEmptyTrash: { model.emptyTrash.request(entry.volume) }
                    )
                }
            }
        }
        .padding(.top, 4)
    }
}
