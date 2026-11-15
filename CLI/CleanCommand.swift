import ArgumentParser
import Foundation
import SweepCore

struct CleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Clean the Safe tier. Moves to Trash unless --delete is given."
    )

    @Option(help: "Tier to clean. Only safe is supported.", transform: ScanCommand.tier)
    var tier: Tier

    @Flag(help: "Delete permanently instead of moving to Trash.")
    var delete = false

    @Flag(help: "Skip the confirmation prompt.")
    var yes = false

    func validate() throws {
        guard tier == .safe else { throw ValidationError("Only the safe tier can be cleaned from the command line.") }
    }

    func run() async throws {
        let catalog = RuleCatalog()
        let report = await SweepScanner(catalog: catalog).run(SweepSettings().scanOptions(tiers: [tier]))
        print(report.text)
        guard !report.items.isEmpty else { return }

        let action = delete ? "Permanently delete" : "Move to Trash"
        if !yes {
            print("\(action) \(report.items.count) item(s), \(report.totalBytes.fileSize)? [y/N] ", terminator: "")
            guard ["y", "yes"].contains(readLine()?.lowercased() ?? "") else { throw CleanExit.message("Cancelled.") }
        }

        let results = await Cleaner(catalog: catalog).clean(items: report.items, mode: delete ? .delete : .trash)
        let failures = results.filter { $0.error != nil }
        let freed = results.filter { $0.error == nil }.reduce(0) { $0 + $1.item.bytes }
        for result in failures {
            print("Failed: \(result.item.url.path(percentEncoded: false)): \(result.error?.message ?? "")")
        }
        print("\(delete ? "Deleted" : "Moved to Trash"): \(freed.fileSize) in \(results.count - failures.count) item(s)")
        print("Skipped: \(report.skipped.count) rule(s), \(report.skippedItems.count) item(s)")
        if !failures.isEmpty { throw ExitCode.failure }
    }
}
