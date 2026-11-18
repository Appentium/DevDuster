import SweepCore
import SwiftUI

struct CleanerView: View {
    @Bindable var model: CleanerModel

    var body: some View {
        VStack(spacing: 0) {
            if model.isScanning {
                ScanProgressBanner(
                    phase: model.scanPhase,
                    currentPath: model.currentPath,
                    onCancel: model.cancelScan
                )
                Divider()
            }

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
        .navigationTitle(title)
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
        .cleanFlowModals(
            session: model.cleanSession,
            selectedCount: model.selectedItems.count,
            selectedBytes: model.selectedBytes,
            onConfirmClean: { Task { await model.cleanSelected() } }
        )
    }

    private var title: String {
        switch model.grouping {
        case .tier: "Cleaner"
        case .platform: "Xcode & Android"
        }
    }

    private var scanDescription: String {
        switch model.grouping {
        case .tier: "Scan your home folder and mounted volumes for caches, logs, and stale build artifacts."
        case .platform: "Scan for Xcode, simulator, Gradle and Android SDK leftovers."
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.sections.isEmpty && model.skipped.isEmpty && model.skippedItems.isEmpty && model.cleanSession.summary == nil {
            if model.isScanning {
                ProgressView("Scanning...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.hasScanned {
                ContentUnavailableView(
                    "Nothing to Clean",
                    systemImage: "sparkles",
                    description: Text("No reclaimable items matched the built-in rules.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("Ready to Scan", systemImage: "magnifyingglass")
                } description: {
                    Text(scanDescription)
                } actions: {
                    Button("Scan", action: model.startScan)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            List {
                if let summary = model.cleanSession.summary {
                    Section {
                        CleanResultSummaryView(
                            summary: summary,
                            emptiedVolumeIDs: model.cleanSession.emptiedVolumeIDs,
                            onEmptyTrash: { model.cleanSession.emptyTrash.request($0) },
                            onDismiss: model.cleanSession.dismissSummary
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }

                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.rules) { ruleGroup in
                            RuleHeaderRow(ruleGroup: ruleGroup, showsTier: model.grouping == .platform)
                            ForEach(ruleGroup.items) { item in
                                ScanItemRow(
                                    item: item,
                                    isSelected: model.selectedIDs.contains(item.id),
                                    onToggle: { model.toggleItem(item) }
                                )
                            }
                        }
                    } header: {
                        RuleSectionHeader(section: section)
                    }
                }

                if !model.skippedItems.isEmpty || !model.skipped.isEmpty {
                    Section("Skipped") {
                        ForEach(model.skippedItems, id: \.item.id) { skippedItem in
                            SkippedItemRow(skippedItem: skippedItem)
                        }
                        ForEach(model.skipped, id: \.rule.id) { skippedRule in
                            SkippedRuleRow(skippedRule: skippedRule)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct ScanProgressBanner: View {
    let phase: ScanPhase
    let currentPath: String
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
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(phaseLabel)
                    .font(.subheadline.weight(.medium))
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

private struct RuleSectionHeader: View {
    let section: CleanerModel.RuleSection

    var body: some View {
        HStack {
            switch section.kind {
            case .tier(let tier):
                Text(tier.title)
                    .font(.headline)
                TierBadge(tier: tier)
            case .platform(let platform):
                Label(platform.title, systemImage: platform.systemImage)
                    .font(.headline)
            }
            Spacer()
            Text(ByteFormatter.string(section.totalBytes))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TierBadge: View {
    let tier: Tier

    var body: some View {
        Text(tier.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tier.color)
            .background(tier.color.opacity(0.14), in: Capsule())
    }
}

private extension Tier {
    var title: String {
        switch self {
        case .safe: "Safe"
        case .review: "Review"
        case .caution: "Caution"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .caution: .red
        }
    }
}

private extension Rule.Platform {
    var title: String {
        switch self {
        case .apple: "Apple"
        case .android: "Android"
        }
    }

    var systemImage: String {
        switch self {
        case .apple: "apple.logo"
        case .android: "smartphone"
        }
    }
}

private struct RuleHeaderRow: View {
    let ruleGroup: CleanerModel.RuleGroup
    let showsTier: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(ruleGroup.rule.title)
                    .font(.subheadline.weight(.semibold))
                if showsTier {
                    TierBadge(tier: ruleGroup.rule.tier)
                }
                Spacer()
                Text(ByteFormatter.string(ruleGroup.totalBytes))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(ruleGroup.rule.regenerate)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

private struct ScanItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(item.projectName ?? item.url.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                Text((item.workspace ?? item.url).path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormatter.string(item.bytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                FinderActions.reveal(item.url)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.leading, 12)
    }
}

private struct SkippedItemRow: View {
    let skippedItem: SkippedItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quit \(skippedItem.runningApp) to clean \(ByteFormatter.string(skippedItem.item.bytes))")
                    .font(.callout)
                Text(skippedItem.item.url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                FinderActions.reveal(skippedItem.item.url)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
    }
}

private struct SkippedRuleRow: View {
    let skippedRule: SkippedRule

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(skippedRule.rule.title)
                    .font(.callout)
                Text("Skipped while \(skippedRule.runningProcess) is running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
