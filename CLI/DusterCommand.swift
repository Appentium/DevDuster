import ArgumentParser

@main
struct DusterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duster",
        abstract: "Scan and clean reclaimable disk space.",
        version: "0.1.0",
        subcommands: [ScanCommand.self, CleanCommand.self, SystemCommand.self]
    )
}
