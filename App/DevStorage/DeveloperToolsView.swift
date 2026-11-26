import DusterCore
import SwiftUI

struct DeveloperToolsView: View {
    @Bindable var cleaner: CleanerModel
    let storage: DevStorageModel

    private var finishedItems: [ScanItem]? {
        cleaner.isScanning || !cleaner.hasScanned ? nil : cleaner.items
    }

    var body: some View {
        VStack(spacing: 0) {
            locationBar
            Divider()
            if cleaner.isScanning {
                ScanProgressBanner(phase: cleaner.scanPhase, currentPath: cleaner.currentPath, fraction: cleaner.fraction, onCancel: cleaner.cancelScan)
                Divider()
            }
            if let summary = cleaner.cleanSession.summary {
                CleanResultSummaryView(
                    summary: summary,
                    emptiedVolumeIDs: cleaner.cleanSession.emptiedVolumeIDs,
                    onEmptyTrash: { cleaner.cleanSession.emptyTrash.request($0) },
                    onDismiss: cleaner.cleanSession.dismissSummary
                )
                .padding(16)
                Divider()
            }
            content
            Divider()
            CleanFooterBar(
                selectedCount: cleaner.selectedItems.count,
                selectedBytes: cleaner.selectedBytes,
                moveToTrash: $cleaner.cleanSession.moveToTrash,
                isDisabled: cleaner.selectedItems.isEmpty || cleaner.isScanning,
                isCleaning: cleaner.cleanSession.isCleaning,
                onClean: cleaner.cleanSession.requestConfirmation
            )
        }
        .navigationTitle("Developer Tools")
        .toolbar {
            ToolbarItem {
                if cleaner.isScanning {
                    Button("Cancel", action: cleaner.cancelScan)
                } else {
                    Button(action: scan) {
                        Label(cleaner.hasScanned ? "Rescan" : "Scan", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .task { storage.loadVolumes() }
        .onChange(of: storage.selectedVolumeURL) { scan() }
        .onChange(of: finishedItems) { _, items in
            if let items { storage.refresh(items: items) }
        }
        .cleanFlowModals(
            session: cleaner.cleanSession,
            selectedCount: cleaner.selectedItems.count,
            selectedBytes: cleaner.selectedBytes,
            onConfirmClean: { Task { await cleaner.cleanSelected() } }
        )
    }

    private var locationBar: some View {
        HStack(spacing: 12) {
            Picker("Location", selection: Bindable(storage).selectedVolumeURL) {
                Text("This Mac").tag(URL?.none)
                ForEach(storage.externalVolumes) { volume in
                    Text(volume.name).tag(URL?.some(volume.url))
                }
            }
            .frame(maxWidth: 260)
            .disabled(cleaner.isScanning)
            Button {
                storage.loadVolumes()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Look for newly connected drives")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func scan() {
        // Only cache items inside tool folders are counted, so no project walk is needed.
        cleaner.startScan(home: storage.scanHome, scope: storage.scanScope, walksProjects: false)
    }

    @ViewBuilder
    private var content: some View {
        if cleaner.hasScanned {
            DevStorageView(model: storage, selectedIDs: cleaner.selectedIDs, onTogglePart: cleaner.toggleItems)
        } else if cleaner.isScanning {
            ProgressView("Scanning...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("See Where Your Space Goes", systemImage: "hammer")
            } description: {
                Text("Measure each SDK, toolchain and package store, and see which parts are essential and which are safe to clean.")
            } actions: {
                Button("Scan", action: scan)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
