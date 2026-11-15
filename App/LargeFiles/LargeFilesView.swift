import AppKit
import SwiftUI
import SweepCore

public struct LargeFilesView: View {
    @State private var model = LargeFilesModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            tableContent
            Divider()
            actionBar
        }
        .onAppear { model.scanIfNeeded() }
        .onChange(of: model.minSize) { model.startScan() }
        .onChange(of: model.ageFilter) { model.startScan() }
        .onChange(of: model.volumeFilter) { model.startScan() }
        .sheet(isPresented: $model.showDeleteConfirmation) {
            deleteConfirmationSheet
        }
        .alert("Could Not Remove Selected Files", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
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

            Picker("Volume", selection: $model.volumeFilter) {
                ForEach(model.availableVolumeFilters) { option in
                    Text(option.label).tag(option)
                }
            }
            .frame(maxWidth: 190)

            Spacer()

            if model.scanning {
                ProgressView()
                    .controlSize(.small)
                Button("Stop") { model.cancelScan() }
            } else {
                Button("Rescan") { model.startScan() }
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
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(file.name)
                            .lineLimit(1)
                    }
                }
                .width(min: 150, ideal: 220)

                TableColumn("Size", value: \.bytes) { file in
                    Text(Self.formatBytes(file.bytes))
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
                    Button(model.moveToTrash ? "Move to Trash…" : "Delete Permanently…", role: .destructive) {
                        model.requestDelete(targets)
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            statusSummary

            Spacer()

            if !model.moveToTrash {
                Label("Permanent delete cannot be undone", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle("Move to Trash", isOn: $model.moveToTrash)
                .toggleStyle(.checkbox)

            Button("Reveal in Finder") {
                model.revealInFinder(model.selectedFiles)
            }
            .disabled(model.selectedFiles.isEmpty)

            Button(model.moveToTrash ? "Move to Trash…" : "Delete Permanently…", role: .destructive) {
                model.requestDelete(model.selectedFiles)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.moveToTrash ? .accentColor : .red)
            .disabled(model.selectedFiles.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusSummary: some View {
        if model.scanning {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scanned \(model.filesScanned.formatted()) entries • Found \(model.files.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.progressPath.isEmpty {
                    Text(model.progressPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .leading)
                }
            }
        } else if !model.selectedFiles.isEmpty {
            Text("\(model.selectedFiles.count) selected (\(Self.formatBytes(model.selectedBytes)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Text("\(model.files.count) files (\(Self.formatBytes(model.totalBytes)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var deleteConfirmationSheet: some View {
        let count = model.pendingDeletion.count
        let label = count == 1
            ? "\(model.pendingDeletion[0].name) (\(Self.formatBytes(model.pendingBytes)))"
            : "\(count) files (\(Self.formatBytes(model.pendingBytes)))"

        return VStack(alignment: .leading, spacing: 14) {
            Text(model.moveToTrash ? "Move to Trash?" : "Delete Permanently?")
                .font(.headline)

            Text(label)
                .fontWeight(.medium)

            if count == 1, let file = model.pendingDeletion.first {
                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Text(RuleCatalog.userSelected.regenerate)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Move to Trash", isOn: $model.moveToTrash)
                .toggleStyle(.checkbox)

            if !model.moveToTrash {
                Label("Permanent deletion cannot be undone.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    model.pendingDeletion = []
                    model.showDeleteConfirmation = false
                }
                Button(model.moveToTrash ? "Move to Trash" : "Delete Permanently", role: .destructive) {
                    Task { await model.confirmDelete() }
                }
                .buttonStyle(.borderedProminent)
                .tint(model.moveToTrash ? .accentColor : .red)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
