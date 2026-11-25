using DevDuster.Core.Clean;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using DevDuster.Core.Settings;

namespace DevDuster.Cli;

internal static class CleanCommand
{
    public static int Run(string[] args, CancellationToken cancellation)
    {
        var delete = false;
        var yes = false;
        for (var index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--delete":
                    delete = true;
                    break;
                case "--yes":
                    yes = true;
                    break;
                default:
                    return Program.Usage($"Unknown argument '{args[index]}'.");
            }
        }

        var folders = UserFolders.Current();
        var catalog = new RuleCatalog(folders);
        var tiers = new HashSet<Tier> { Tier.Safe };
        var options = new SettingsStore(folders).Load().ToScanOptions(tiers);
        var report = Program.BuildScanner(catalog, folders).RunAsync(options, null, cancellation).GetAwaiter().GetResult();
        Console.Out.WriteLine(ScanCommand.Text(report));
        if (report.Items.Count == 0) return 0;

        var mode = delete ? CleanMode.Delete : CleanMode.Recycle;
        var action = delete ? "Permanently delete" : "Move to Recycle Bin";
        if (!yes)
        {
            Console.Out.Write($"{action} {report.Items.Count} item(s), {report.TotalBytes.Size()}? [y/N] ");
            if (!Confirmed(Console.ReadLine())) { Console.Out.WriteLine("Cancelled."); return 0; }
        }

        var results = Program.BuildCleaner(catalog, folders).CleanAsync(report.Items, mode, null, cancellation).GetAwaiter().GetResult();
        var failures = results.Where(result => result.Error is not null).ToList();
        var freed = results.Sum(result => result.FreedBytes);
        foreach (var failure in failures) Console.Out.WriteLine($"Failed: {failure.Item.Path}: {failure.Error}");
        var verb = delete ? "Deleted" : "Moved to Recycle Bin";
        Console.Out.WriteLine($"{verb}: {freed.Size()} in {results.Count - failures.Count} item(s)");
        Console.Out.WriteLine($"Skipped: {report.Skipped.Count} rule(s), {report.SkippedItems.Count} item(s)");
        return failures.Count == 0 ? 0 : 1;
    }

    private static bool Confirmed(string? answer) =>
        answer is not null && (answer.Equals("y", StringComparison.OrdinalIgnoreCase) || answer.Equals("yes", StringComparison.OrdinalIgnoreCase));
}