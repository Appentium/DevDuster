import DusterCore
import SwiftUI

struct DevStorageView: View {
    let model: DevStorageModel
    let selectedIDs: Set<ScanItem.ID>
    let onTogglePart: ([ScanItem]) -> Void

    var body: some View {
        if model.usages.isEmpty {
            if model.isMeasuring {
                ProgressView("Measuring developer tools...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Developer Tools Found",
                    systemImage: "hammer",
                    description: Text("None of the known SDKs, toolchains or package stores are on this Mac.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    summary
                    ForEach(model.usages) { usage in
                        ToolCard(
                            usage: usage,
                            share: Double(usage.totalBytes) / Double(max(1, model.totalBytes)),
                            selectedIDs: selectedIDs,
                            onTogglePart: onTogglePart
                        )
                    }
                }
                .padding(16)
            }
            .overlay(alignment: .topTrailing) {
                if model.isMeasuring {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            SummaryTile(title: "Measured", bytes: model.totalBytes, total: 0, color: .accentColor, systemImage: "internaldrive")
            SummaryTile(
                title: "Safe to clean",
                bytes: model.bytes { $0 == .cleanable(.safe) },
                total: model.totalBytes,
                color: .green,
                systemImage: "checkmark.shield"
            )
            SummaryTile(
                title: "Needs review",
                bytes: model.bytes { $0 == .cleanable(.review) || $0 == .cleanable(.caution) },
                total: model.totalBytes,
                color: .orange,
                systemImage: "eye"
            )
            SummaryTile(
                title: "Essential",
                bytes: model.bytes { $0 == .essential },
                total: model.totalBytes,
                color: DevStoragePart.Kind.essential.color,
                systemImage: "lock.shield"
            )
        }
    }
}

private struct SummaryTile: View {
    let title: String
    let bytes: Int64
    let total: Int64
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ByteFormatter.string(bytes))
                    .font(.title3.weight(.semibold).monospacedDigit())
                if total > 0 {
                    Text(Double(bytes) / Double(total), format: .percent.precision(.fractionLength(0)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .dashboardCard()
    }
}

private struct ToolCard: View {
    let usage: DevToolUsage
    let share: Double
    let selectedIDs: Set<ScanItem.ID>
    let onTogglePart: ([ScanItem]) -> Void
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            PartsBar(parts: usage.parts, total: usage.totalBytes)
            if isExpanded {
                ForEach(usage.parts) { part in
                    PartRow(
                        part: part,
                        isSelected: !part.items.isEmpty && part.items.allSatisfy { selectedIDs.contains($0.id) },
                        onToggle: { onTogglePart(part.items) }
                    )
                }
            }
        }
        .dashboardCard()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: usage.tool.platform.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(usage.tool.title)
                    .font(.headline)
                Text(usage.root.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.string(usage.totalBytes))
                    .font(.headline.monospacedDigit())
                Text("\(share.formatted(.percent.precision(.fractionLength(1)))) of measured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                FinderActions.reveal(usage.root)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .buttonStyle(.borderless)
            .help(isExpanded ? "Hide parts" : "Show parts")
        }
    }
}

private struct PartsBar: View {
    let parts: [DevStoragePart]
    let total: Int64

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(parts) { part in
                    Rectangle()
                        .fill(part.kind.color)
                        .frame(width: max(2, proxy.size.width * Double(part.bytes) / Double(max(1, total)) - 2))
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }
}

private struct PartRow: View {
    let part: DevStoragePart
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if part.items.isEmpty {
                Circle()
                    .fill(part.kind.color)
                    .frame(width: 8, height: 8)
                    .frame(width: 16)
            } else {
                Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 16)
            }
            Text(part.title)
            Spacer()
            Text(ByteFormatter.string(part.bytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            StatusBadge(title: part.kind.title, color: part.kind.color)
                .frame(width: 86, alignment: .leading)
        }
        .help(part.kind.help)
    }
}

private extension DevStoragePart.Kind {
    var title: String {
        switch self {
        case .essential: "Essential"
        case .cleanable(let tier): tier.title
        case .other: "Unsorted"
        }
    }

    var color: Color {
        switch self {
        case .essential: .blue
        case .cleanable(let tier): tier.color
        case .other: .gray
        }
    }

    var help: String {
        switch self {
        case .essential: "The tool needs this to work. DevDuster never cleans it."
        case .cleanable(.safe): "Rebuilt or downloaded again when needed."
        case .cleanable: "Can be cleaned, but check you no longer need it first."
        case .other: "Not matched by any rule. Look before deleting anything here."
        }
    }
}
