import ArgumentParser
import Foundation
import DusterCore

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
        let options = DusterSettings().scanOptions(tiers: tier.isEmpty ? Set(Tier.allCases) : Set(tier), scope: path.isEmpty ? nil : path)
        let report = await DusterScanner(catalog: RuleCatalog()).run(options)
        print(json ? try jsonText(report) : report.text)
    }

    static func tier(_ value: String) throws -> Tier {
        guard let tier = Tier(rawValue: value) else { throw ValidationError("Unknown tier '\(value)'; use safe, review or caution.") }
        return tier
    }

    private func jsonText(_ report: ScanReport) throws -> String {
        let output = JSONReport(
            totalBytes: report.totalBytes,
            rules: report.groups.map { group in
                JSONReport.Group(
                    id: group.rule.id,
                    title: group.rule.title,
                    tier: group.rule.tier.rawValue,
                    bytes: group.items.reduce(0) { $0 + $1.bytes },
                    items: group.items.map { JSONReport.Item(path: $0.url.path(percentEncoded: false), bytes: $0.bytes) }
                )
            },
            skipped: report.skipped.map { $0.rule.id },
            skippedItems: report.skippedItems.map { JSONReport.SkippedItem(path: $0.item.url.path(percentEncoded: false), bytes: $0.item.bytes, runningApp: $0.runningApp) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(output), as: UTF8.self)
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

    struct SkippedItem: Encodable {
        let path: String
        let bytes: Int64
        let runningApp: String
    }

    let totalBytes: Int64
    let rules: [Group]
    let skipped: [String]
    let skippedItems: [SkippedItem]
}
