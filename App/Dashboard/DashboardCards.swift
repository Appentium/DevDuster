import Charts
import DusterCore
import SwiftUI

extension View {
    func dashboardCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CardHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}

struct StorageOverviewCard: View {
    let entry: DashboardModel.VolumeEntry
    let lastCleaned: Date?
    let onScan: () -> Void

    private var usedRatio: Double {
        guard entry.volume.totalBytes > 0 else { return 0 }
        return min(1, Double(entry.usedBytes) / Double(entry.volume.totalBytes))
    }

    private var ringColor: Color {
        if usedRatio >= 0.9 { return .red }
        if usedRatio >= 0.75 { return .orange }
        return .accentColor
    }

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: usedRatio)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(usedRatio, format: .percent.precision(.fractionLength(0)))
                        .font(.title.weight(.bold).monospacedDigit())
                    Text("used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 124, height: 124)

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.volume.name)
                    .font(.title2.weight(.semibold))
                Text("\(ByteFormatter.string(entry.volume.availableBytes)) free of \(ByteFormatter.string(entry.volume.totalBytes))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    LegendItem(color: ringColor, label: "Used", value: entry.usedBytes)
                    LegendItem(color: .secondary.opacity(0.4), label: "Free", value: entry.volume.availableBytes)
                    if entry.purgeableBytes > 0 {
                        LegendItem(color: .teal, label: "Purgeable", value: entry.purgeableBytes)
                    }
                }
                Group {
                    if let lastCleaned {
                        Text("Last cleaned \(lastCleaned, format: .relative(presentation: .named))")
                    } else {
                        Text("Never cleaned with DevDuster")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onScan) {
                Label("Scan for Junk", systemImage: "sparkles")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .dashboardCard()
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    let value: Int64

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
            Text(ByteFormatter.string(value))
                .monospacedDigit()
        }
        .font(.caption)
    }
}

struct StatTile: View {
    let title: String
    let value: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let value {
                    Text(value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .dashboardCard()
    }
}

struct ReclaimableCard: View {
    let cleaner: CleanerModel
    let onScan: () -> Void
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "Reclaimable Space", systemImage: "sparkles")
                Spacer()
                if cleaner.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if cleaner.hasScanned {
                HStack(spacing: 8) {
                    ForEach(Tier.allCases, id: \.self) { tier in
                        Text("\(tier.title) \(ByteFormatter.string(DashboardModel.junkBytes(in: cleaner.items, tier: tier)))")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(tier.color)
                            .background(tier.color.opacity(0.14), in: Capsule())
                    }
                }
                if cleaner.items.isEmpty {
                    Text("Nothing to clean right now.")
                        .foregroundStyle(.secondary)
                } else {
                    categoryBars
                }
                Button("Review in Cleaner", action: onReview)
            } else {
                VStack(spacing: 10) {
                    Text("Scan to see how much space caches, logs and build files take.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Scan for Junk", action: onScan)
                        .disabled(cleaner.isScanning)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .dashboardCard()
    }

    private var categoryBars: some View {
        let categories = DashboardModel.junkCategories(in: cleaner.items)
        let largest = Double(categories.first?.bytes ?? 1)
        return VStack(spacing: 8) {
            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(category.title)
                            .lineLimit(1)
                        Spacer()
                        Text(ByteFormatter.string(category.bytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(category.tier.color.opacity(0.75))
                            .frame(width: max(4, proxy.size.width * Double(category.bytes) / largest))
                    }
                    .frame(height: 5)
                }
            }
        }
    }
}

struct CleaningActivityCard: View {
    let history: CleanHistory

    var body: some View {
        let weeks = history.weeklyTotals(weeks: DashboardModel.chartWeeks)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "Cleaning Activity", systemImage: "chart.bar")
                Spacer()
                Text("Last \(DashboardModel.chartWeeks) weeks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if weeks.allSatisfy({ $0.bytes == 0 }) {
                ContentUnavailableView(
                    "No Cleanups Yet",
                    systemImage: "chart.bar",
                    description: Text("Space you free with DevDuster shows up here.")
                )
                .frame(minHeight: 180)
            } else {
                Chart(weeks) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Freed", week.bytes)
                    )
                    .foregroundStyle(Color.green.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bytes = value.as(Int64.self) {
                                Text(ByteFormatter.string(bytes))
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .dashboardCard()
    }
}

struct MacInfoCard: View {
    let info: MacInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "This Mac", systemImage: "laptopcomputer")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Name", info.computerName)
                row("Chip", info.chip)
                row("Cores", "\(info.coreCount)")
                row("Memory", ByteCountFormatter.string(fromByteCount: info.memoryBytes, countStyle: .memory))
                row("System", info.osVersion)
                row("Uptime", Duration.seconds(info.uptime).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
            }
            .font(.callout)
        }
        .dashboardCard()
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct QuickActionsCard: View {
    let onOpen: (SidebarSection) -> Void

    private let sections: [SidebarSection] = [.cleaner, .developerTools, .uninstaller, .largeFiles, .diskMap, .system]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Quick Actions", systemImage: "bolt")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(sections) { section in
                    Button {
                        onOpen(section)
                    } label: {
                        Label(section.rawValue, systemImage: section.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .dashboardCard()
    }
}

struct VolumeCard: View {
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
        .dashboardCard()
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
