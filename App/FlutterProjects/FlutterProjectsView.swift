import SweepCore
import SwiftUI

struct FlutterProjectsView: View {
    @Bindable var model: FlutterProjectsModel

    var body: some View {
        VStack(spacing: 0) {
            controlsBar
            Divider()
            content
            Divider()
            CleanFooterBar(
                selectedCount: model.selectedItems.count,
                selectedBytes: model.selectedBytes,
                moveToTrash: $model.cleanSession.moveToTrash,
                isDisabled: model.selectedItems.isEmpty || model.isScanning,
                isCleaning: model.cleanSession.isCleaning,
                onClean: model.cleanSession.requestConfirmation
            )
        }
        .navigationTitle("Flutter Projects")
        .toolbar {
            ToolbarItem {
                if model.isScanning {
                    Button("Cancel", action: model.cancelScan)
                } else {
                    Button {
                        model.startScan()
                    } label: {
                        Label(model.hasScanned ? "Rescan" : "Scan", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .task {
            if !model.hasScanned && !model.isScanning {
                model.startScan()
            }
        }
        .cleanFlowModals(
            session: model.cleanSession,
            selectedCount: model.selectedItems.count,
            selectedBytes: model.selectedBytes,
            onConfirmClean: { Task { await model.cleanSelected() } }
        )
    }

    private var controlsBar: some View {
        HStack(spacing: 10) {
            Button("Select All", action: model.selectAll)
                .disabled(model.allFolderItems.isEmpty || model.isScanning)
            Button("Select Stale", action: model.selectStale)
                .disabled(model.allFolderItems.isEmpty || model.isScanning)
            Button("Deselect All", action: model.deselectAll)
                .disabled(model.selectedIDs.isEmpty || model.isScanning)

            Spacer()

            Picker("Sort", selection: $model.sortOrder) {
                ForEach(FlutterProjectsModel.SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning {
            ProgressView("Scanning Flutter projects...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.projects.isEmpty && model.cleanSession.summary == nil {
            ContentUnavailableView(
                "No Flutter Projects Found",
                systemImage: "folder.badge.questionmark",
                description: Text("No projects with a Flutter pubspec.yaml were found across mounted volumes.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if let summary = model.cleanSession.summary {
                    Section {
                        CleanResultSummaryView(
                            summary: summary,
                            emptiedVolumeIDs: model.cleanSession.emptiedVolumeIDs,
                            onEmptyTrash: { model.cleanSession.requestEmptyTrash(for: $0) },
                            onDismiss: model.cleanSession.dismissSummary
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }

                ForEach(model.projects) { project in
                    Section {
                        ProjectRow(project: project, isStale: model.isStale(project))
                        ForEach(project.folders) { folder in
                            FolderRow(
                                folder: folder,
                                projectURL: project.url,
                                isSelected: model.selectedIDs.contains(folder.id),
                                onToggle: { model.toggleFolder(folder) }
                            )
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct ProjectRow: View {
    let project: FlutterProjectsModel.ProjectEntry
    let isStale: Bool

    private var activityText: String {
        if project.lastActivity == .distantPast { return "Unknown activity" }
        return project.lastActivity.formatted(.relative(presentation: .named))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(project.url.lastPathComponent)
                        .font(.headline)
                    if isStale {
                        Text("Stale")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                    }
                }
                Text(project.url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteFormatter.string(project.totalBytes))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(activityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct FolderRow: View {
    let folder: ScanItem
    let projectURL: URL
    let isSelected: Bool
    let onToggle: () -> Void

    private var relativeName: String {
        let base = projectURL.path(percentEncoded: false)
        let full = folder.url.path(percentEncoded: false)
        let prefix = base.hasSuffix("/") ? base : base + "/"
        if full.hasPrefix(prefix) {
            return String(full.dropFirst(prefix.count))
        }
        return folder.url.lastPathComponent
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(relativeName)
                .font(.body.monospaced())

            Spacer()

            Text(ByteFormatter.string(folder.bytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                FinderActions.reveal(folder.url)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.leading, 12)
    }
}
