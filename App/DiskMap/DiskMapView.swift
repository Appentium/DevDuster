import SwiftUI
import SweepCore

public struct DiskMapView: View {
    @State private var model = DiskMapModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            breadcrumbBar
            Divider()
            content
            Divider()
            statusBar
        }
        .onAppear { model.scanIfNeeded() }
        .sheet(item: $model.pendingDelete) { node in
            deleteConfirmationSheet(for: node)
        }
        .alert("Could Not Remove Item", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Location", selection: Binding(
                get: { model.selectedSource },
                set: { model.selectSource($0) }
            )) {
                ForEach(model.availableSources) { source in
                    Text(source.label).tag(source)
                }
            }
            .frame(maxWidth: 220)

            Button("Choose Folder…") { model.chooseFolder() }

            if model.scanning {
                Button("Stop") { model.cancelScan() }
            } else {
                Button("Rescan") { model.startScan() }
            }

            Spacer()

            if !model.moveToTrash {
                Label("Permanent delete cannot be undone", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle("Move to Trash", isOn: $model.moveToTrash)
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Button {
                model.navigateUp()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(model.trail.count <= 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(model.trail.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button(node.name) {
                            model.navigate(to: index)
                        }
                        .buttonStyle(.plain)
                        .fontWeight(index == model.trail.count - 1 ? .semibold : .regular)
                    }
                }
            }

            Spacer()

            if let current = model.currentNode {
                Text(Self.formatBytes(current.bytes))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let current = model.currentNode {
            if current.children.allSatisfy({ $0.bytes == 0 }) {
                ContentUnavailableView("Empty Folder", systemImage: "folder", description: Text("No allocated files inside \(current.name)."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let tiles = TreemapLayout.tiles(for: current.children, in: CGRect(origin: .zero, size: proxy.size))
                    ZStack(alignment: .topLeading) {
                        ForEach(tiles) { tile in
                            TreemapTileView(
                                tile: tile,
                                isHovered: model.hoveredNode?.id == tile.id,
                                moveToTrash: model.moveToTrash,
                                onHover: { hovering in
                                    if hovering {
                                        model.hoveredNode = tile.node
                                    } else if model.hoveredNode?.id == tile.id {
                                        model.hoveredNode = nil
                                    }
                                },
                                onTap: { model.drillInto(tile.node) },
                                onReveal: { model.revealInFinder(tile.node) },
                                onDelete: { model.requestDelete(tile.node) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(8)
            }
        } else if model.scanning {
            VStack(spacing: 10) {
                ProgressView()
                Text("Scanning \(model.selectedSource.label)…")
                    .font(.headline)
                Text("\(Self.formatBytes(model.scannedBytes)) across \(model.scannedItems.formatted()) items")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if !model.progressPath.isEmpty {
                    Text(model.progressPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 460)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No Disk Map", systemImage: "square.grid.3x3", description: Text("Choose a location and click Rescan."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let hovered = model.hoveredNode {
                Text(hovered.name)
                    .fontWeight(.medium)
                Text(Self.formatBytes(hovered.bytes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let url = hovered.url {
                    Text(url.path)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if let current = model.currentNode {
                Text("\(current.children.count) items in \(current.name)")
                    .foregroundStyle(.secondary)
            } else {
                Text("Ready")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func deleteConfirmationSheet(for node: DiskNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.moveToTrash ? "Move to Trash?" : "Delete Permanently?")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(node.name) (\(Self.formatBytes(node.bytes)))")
                    .fontWeight(.medium)
                if let url = node.url {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
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
                    model.pendingDelete = nil
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

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct TreemapTileView: View {
    let tile: TreemapTile
    let isHovered: Bool
    let moveToTrash: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    private static let palette: [Color] = [
        .blue, .teal, .indigo, .orange, .purple, .mint, .cyan, .pink,
    ]

    var body: some View {
        let sizeText = DiskMapView.formatBytes(tile.node.bytes)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(tileColor.opacity(isHovered ? 0.85 : 0.65))
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isHovered ? Color.primary : Color.primary.opacity(0.25), lineWidth: isHovered ? 2 : 0.75)

            if tile.rect.width > 42 && tile.rect.height > 20 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if tile.node.isDirectory && tile.rect.width > 64 {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                        }
                        Text(tile.node.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    if tile.rect.height > 36 {
                        Text(sizeText)
                            .font(.caption2.monospacedDigit())
                            .opacity(0.9)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(5)
            }
        }
        .frame(width: tile.rect.width, height: tile.rect.height)
        .offset(x: tile.rect.minX, y: tile.rect.minY)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
        .help("\(tile.node.name) — \(sizeText)")
        .contextMenu {
            if tile.node.url != nil {
                Button("Reveal in Finder", action: onReveal)
                Divider()
                Button(moveToTrash ? "Move to Trash…" : "Delete Permanently…", role: .destructive, action: onDelete)
            }
        }
    }

    private var tileColor: Color {
        if tile.node.foldedCount > 0 { return .gray }
        let hash = tile.node.name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let base = Self.palette[abs(hash) % Self.palette.count]
        return tile.node.isDirectory ? base : base.opacity(0.85)
    }
}
