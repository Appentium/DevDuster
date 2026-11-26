import DusterCore
import SwiftUI

struct LargeFilesView: View {
    @Bindable var model: LargeFilesModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if let summary = model.cleanSession.summary {
                CleanResultSummaryView(
                    summary: summary,
                    emptiedVolumeIDs: model.cleanSession.emptiedVolumeIDs,
                    onEmptyTrash: { model.cleanSession.emptyTrash.request($0) },
                    onDismiss: model.cleanSession.dismissSummary
                )
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            tableContent
            Divider()
            CleanFooterBar(
                selectedCount: model.selectedFiles.count,
                selectedBytes: model.selectedBytes,
                moveToTrash: $model.cleanSession.moveToTrash,
                isDisabled: model.selectedFiles.isEmpty || model.scanning,
                isCleaning: model.cleanSession.isCleaning,
                onClean: { model.requestDelete(model.selectedFiles) }
            )
        }
        .navigationTitle("Large Files")
        .toolbar {
            ToolbarItem {
                Button("Reveal in Finder") {
                    model.revealInFinder(model.selectedFiles)
                }
                .disabled(model.selectedFiles.isEmpty)
            }
            ToolbarItem {
                if model.scanning {
                    Button("Stop", action: model.cancelScan)
                } else {
                    Button {
                        model.startScan()
                    } label: {
                        Label("Rescan", systemImage: "magnifyingglass")
                    }
                }
            }
        }
        .onAppear { model.scanIfNeeded() }
        .onChange(of: model.minSize) { model.startScan() }
        .onChange(of: model.ageFilter) { model.startScan() }
        .cleanFlowModals(
            session: model.cleanSession,
            selectedCount: model.pendingDeletion.count,
            selectedBytes: model.pendingBytes,
            onConfirmClean: { Task { await model.confirmDelete() } }
        )
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Min Size", selection: $model.minSize) {
                ForEach(LargeFilesModel.MinSizeFilter.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .frame(maxWidth: 165)

            Picker("Older Than", selection: $model.ageFilter) {
                ForEach(LargeFilesModel.AgeFilter.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .frame(maxWidth: 175)

            LocationPicker(location: model.location, onChange: { model.startScan() })
                .disabled(model.scanning)

            SelectAllButtons(
                canSelectAll: model.selection.count < model.files.count,
                canDeselectAll: !model.selection.isEmpty,
                onSelectAll: model.selectAll,
                onDeselectAll: model.deselectAll
            )

            Spacer()

            if model.scanning {
                if let fraction = model.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                        .accessibilityLabel("Scan progress")
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("Scanned \(model.filesScanned.formatted()) • Found \(model.files.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(model.files.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var tableContent: some View {
        if model.files.isEmpty && !model.scanning {
            ContentUnavailableView(
                "No Large Files Found",
                systemImage: "doc.text.magnifyingglass",
                description: Text("No files matched at least \(model.minSize.label)\(model.ageFilter.days.map { " older than \($0) days" } ?? "").")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(model.sortedFiles, selection: $model.selection, sortOrder: $model.sortOrder) {
                TableColumn("Name", value: \.name) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(file.name)
                            .lineLimit(1)
                    }
                }
                .width(min: 150, ideal: 220)

                TableColumn("Size", value: \.bytes) { file in
                    Text(ByteFormatter.string(file.bytes))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 100, max: 120)

                TableColumn("Modified", value: \.modified) { file in
                    Text(file.modified.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .width(min: 130, ideal: 155, max: 180)

                TableColumn("Path", value: \.path) { file in
                    Text(file.url.deletingLastPathComponent().path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(file.path)
                }
                .width(min: 180, ideal: 300)
            }
            .contextMenu(forSelectionType: LargeFile.ID.self) { ids in
                let targets = model.targets(for: ids)
                if !targets.isEmpty {
                    Button("Reveal in Finder") {
                        model.revealInFinder(targets)
                    }
                    Divider()
                    Button(model.cleanSession.moveToTrash ? "Move to Trash…" : "Delete Permanently…", role: .destructive) {
                        model.requestDelete(targets)
                    }
                }
            }
        }
    }
}
