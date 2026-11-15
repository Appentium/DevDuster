import ArgumentParser
import Foundation
import SweepCore

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "List reclaimable items grouped by rule. Read-only: nothing is deleted."
    )

    @Flag(help: "Print JSON instead of text.")
    var json = false

    @Option(help: "Only include this tier (safe, review or caution). Repeatable.", transform: Self.tier)
    var tier: [Tier] = []

    @Option(help: "Only include items inside this folder. Repeatable.", transform: { URL(filePath: $0) })
    var path: [URL] = []

    func run() async throws {
        let options = ScanOptions(tiers: tier.isEmpty ? Set(Tier.allCases) : Set(tier), scope: path.isEmpty ? nil : path)
        let report = await SweepScanner(catalog: RuleCatalog()).run(options)
        print(json ? try jsonText(report) : text(report))
    }

    private static func tier(_ value: String) throws -> Tier {
        guard let tier = Tier(rawValue: value) else { throw ValidationError("Unknown tier '\(value)'; use safe, review or caution.") }
        return tier
    }

    private func groups(_ report: ScanReport) -> [(rule: Rule, items: [ScanItem])] {
        var groups: [(rule: Rule, items: [ScanItem])] = []
        for item in report.items {
            if groups.last?.rule == item.rule {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((item.rule, [item]))
            }
        }
        return groups
    }

    private func text(_ report: ScanReport) -> String {
        var lines: [String] = []
        for group in groups(report) {
            let total = group.items.reduce(0) { $0 + $1.bytes }
            lines.append("[\(group.rule.tier.rawValue)] \(group.rule.title): \(size(total)) in \(group.items.count) item(s)")
            lines += group.items.map { "  \(size($0.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \($0.url.path(percentEncoded: false))" }
        }
        lines += report.skipped.map { "Skipped \($0.rule.title): \($0.runningProcess) is running" }
        lines.append("Total: \(size(report.totalBytes)) in \(report.items.count) item(s)")
        return lines.joined(separator: "\n")
    }

    private func jsonText(_ report: ScanReport) throws -> String {
        let output = JSONReport(
            totalBytes: report.totalBytes,
            rules: groups(report).map { group in
                JSONReport.Group(
                    id: group.rule.id,
                    title: group.rule.title,
                    tier: group.rule.tier.rawValue,
                    bytes: group.items.reduce(0) { $0 + $1.bytes },
                    items: group.items.map { JSONReport.Item(path: $0.url.path(percentEncoded: false), bytes: $0.bytes) }
                )
            },
            skipped: report.skipped.map { $0.rule.id }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(output), as: UTF8.self)
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct JSONReport: Encodable {
    struct Item: Encodable {
        let path: String
        let bytes: Int64
    }

    struct Group: Encodable {
        let id: String
        let title: String
        let tier: String
        let bytes: Int64
        let items: [Item]
    }

    let totalBytes: Int64
    let rules: [Group]
    let skipped: [String]
}
