import ArgumentParser
import Foundation

@main
struct DusterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duster",
        abstract: "Scan and clean reclaimable disk space.",
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        subcommands: [ScanCommand.self, CleanCommand.self, SystemCommand.self]
    )
}
