import ArgumentParser

@main
struct SweepCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sweep",
        abstract: "Scan and clean reclaimable disk space.",
        version: "0.1.0",
        subcommands: [ScanCommand.self, SystemCommand.self]
    )
}
