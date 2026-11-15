import ArgumentParser
import Foundation
import SweepCore

struct SystemCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "system",
        abstract: "Root-level cleanup through the privileged helper.",
        subcommands: [Status.self, Install.self, Uninstall.self, Snapshots.self, Caches.self, Logs.self, Trash.self]
    )

    static let approvalHint = "Approve it in System Settings → General → Login Items & Extensions → Allow in the Background → Sweep."

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show whether the helper is installed and reachable.")

        func run() async throws {
            let status = HelperInstaller().status
            print("Helper: \(status.rawValue)")
            switch status {
            case .enabled: print("Helper version: \(try await HelperClient().version())")
            case .requiresApproval: print(SystemCommand.approvalHint)
            case .notRegistered, .notFound: print("Run `sweep system install`.")
            }
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Register the privileged helper with launchd.")

        func run() async throws {
            let installer = HelperInstaller()
            let status = try installer.register()
            print("Helper: \(status.rawValue)")
            guard status == .requiresApproval else { return }
            print(SystemCommand.approvalHint)
            installer.openLoginItemsSettings()
        }
    }

    struct Uninstall: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Unregister the privileged helper.")

        func run() async throws {
            try await HelperInstaller().unregister()
            print("Helper: \(HelperInstaller().status.rawValue)")
        }
    }

    struct Snapshots: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List local Time Machine snapshots; --clean deletes them.")

        @OptionGroup var cleaning: CleanOptions

        @Option(name: .customLong("only"), help: "Only delete this snapshot date (YYYY-MM-DD-HHMMSS). Repeatable.")
        var dates: [String] = []

        func run() async throws {
            let client = HelperClient()
            let snapshots = try await client.localSnapshots()
            snapshots.forEach { print($0) }
            print("\(snapshots.count) local snapshot(s)")
            let selected = try cleaning.select(dates.isEmpty ? snapshots : dates, from: snapshots)
            guard try cleaning.confirmed("Delete \(selected.count) local snapshot(s)?", targets: selected) else { return }
            try cleaning.report(try await client.deleteLocalSnapshots(selected))
        }
    }

    struct Caches: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List /Library/Caches folders (never com.apple.*); --clean empties them.")

        @OptionGroup var cleaning: CleanOptions

        @Option(name: .customLong("only"), help: "Only empty this /Library/Caches folder. Repeatable.")
        var names: [String] = []

        func run() async throws {
            let client = HelperClient()
            let caches = try await client.systemCaches()
            printItems(caches)
            let reported = caches.map(\.name)
            let selected = try cleaning.select(names.isEmpty ? reported : names, from: reported)
            guard try cleaning.confirmed("Empty \(selected.count) folder(s) in /Library/Caches?", targets: selected) else { return }
            try cleaning.report(try await client.cleanSystemCaches(selected))
        }
    }

    struct Logs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List rotated log archives in /private/var/log; --clean deletes them.")

        @OptionGroup var cleaning: CleanOptions

        func run() async throws {
            let client = HelperClient()
            let logs = try await client.archivedLogs()
            printItems(logs)
            let names = logs.map(\.name)
            guard try cleaning.confirmed("Delete \(names.count) archived log(s)?", targets: names) else { return }
            try cleaning.report(try await client.cleanArchivedLogs())
        }
    }

    struct Trash: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List root-owned trash (.Trashes/0) per volume; --clean empties it.")

        @OptionGroup var cleaning: CleanOptions

        @Option(name: .customLong("only"), help: "Only empty this volume's root trash. Repeatable.")
        var volumes: [String] = []

        func run() async throws {
            let client = HelperClient()
            let trashes = try await client.rootTrashes()
            printItems(trashes)
            let reported = trashes.map(\.name)
            let selected = try cleaning.select(volumes.isEmpty ? reported : volumes, from: reported)
            guard try cleaning.confirmed("Permanently empty the root trash on \(selected.count) volume(s)?", targets: selected) else { return }
            try cleaning.report(try await client.emptyRootTrashes(selected))
        }
    }
}

struct CleanOptions: ParsableArguments {
    @Flag(help: "Perform the cleanup instead of only reporting.")
    var clean = false

    @Flag(help: "Skip the confirmation prompt.")
    var yes = false

    func select(_ requested: [String], from reported: [String]) throws -> [String] {
        if let unknown = requested.first(where: { !reported.contains($0) }) { throw ValidationError("'\(unknown)' is not in the report above.") }
        return requested
    }

    func confirmed(_ question: String, targets: [String]) throws -> Bool {
        guard clean else { return false }
        guard !targets.isEmpty else {
            print("Nothing to clean.")
            return false
        }
        targets.forEach { print("  \($0)") }
        if yes { return true }
        print("\(question) [y/N] ", terminator: "")
        guard ["y", "yes"].contains(readLine()?.lowercased() ?? "") else { throw CleanExit.message("Cancelled.") }
        return true
    }

    func report(_ result: PrivilegedCleanResult) throws {
        result.removed.forEach { print("Removed \($0.bytes.fileSize) \($0.name)") }
        result.failures.forEach { print("Failed: \($0)") }
        print("Freed \(result.freedBytes.fileSize)")
        if !result.failures.isEmpty { throw ExitCode.failure }
    }
}

private func printItems(_ items: [PrivilegedItem]) {
    items.forEach { print("\($0.bytes.fileSize.padding(toLength: 10, withPad: " ", startingAt: 0)) \($0.name)") }
    print("Total: \(items.reduce(0) { $0 + $1.bytes }.fileSize) in \(items.count) item(s)")
}
