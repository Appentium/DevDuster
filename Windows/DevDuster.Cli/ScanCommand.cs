using System.Text.Json;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using DevDuster.Core.Settings;

namespace DevDuster.Cli;

internal static class ScanCommand
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static int Run(string[] args, CancellationToken cancellation)
    {
        var json = false;
        var tiers = new HashSet<Tier>();
        for (var index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--json":
                    json = true;
                    break;
                case "--tier":
                    if (index + 1 >= args.Length) return Program.Usage("Missing value for --tier.");
                    index++;
                    if (!TryTier(args[index], out var parsed)) return Program.Usage($"Unknown tier '{args[index]}'; use safe, review or caution.");
                    tiers.Add(parsed);
                    break;
                default:
                    return Program.Usage($"Unknown argument '{args[index]}'.");
            }
        }
        if (tiers.Count == 0) foreach (var tier in Enum.GetValues<Tier>()) tiers.Add(tier);

        var folders = UserFolders.Current();
        var catalog = new RuleCatalog(folders);
        var options = new SettingsStore(folders).Load().ToScanOptions(tiers);
        var report = Program.BuildScanner(catalog, folders).RunAsync(options, null, cancellation).GetAwaiter().GetResult();
        Console.Out.WriteLine(json ? Json(report) : Text(report));
        return 0;
    }

    internal static string Text(ScanReport report)
    {
        var lines = new List<string>();
        foreach (var group in Groups(report))
        {
            var total = group.Items.Sum(item => item.Bytes);
            lines.Add($"[{TierName(group.Rule.Tier)}] {group.Rule.Title}: {total.Size()} in {group.Items.Count} item(s)");
            lines.AddRange(group.Items.Select(item => $"  {item.Bytes.Size().PadLeft(10)} {item.Path}"));
        }
        lines.AddRange(report.Skipped.Select(skipped => $"Skipped {skipped.Rule.Title}: {skipped.RunningProcess} is running"));
        lines.AddRange(report.SkippedItems.Select(skipped => $"Skipped {skipped.Item.Bytes.Size()} {skipped.Item.Path}: quit {skipped.RunningApp} to clean it"));
        lines.Add($"Total: {report.TotalBytes.Size()} in {report.Items.Count} item(s)");
        return string.Join('\n', lines);
    }

    private static string Json(ScanReport report) => JsonSerializer.Serialize(new
    {
        rules = Groups(report).Select(group => new
        {
            bytes = group.Items.Sum(item => item.Bytes),
            id = group.Rule.Id,
            items = group.Items.Select(item => new { bytes = item.Bytes, path = item.Path }),
            tier = TierName(group.Rule.Tier),
            title = group.Rule.Title,
        }),
        skipped = report.Skipped.Select(skipped => skipped.Rule.Id),
        skippedItems = report.SkippedItems.Select(skipped => new { bytes = skipped.Item.Bytes, path = skipped.Item.Path, runningApp = skipped.RunningApp }),
        totalBytes = report.TotalBytes,
    }, JsonOptions);

    private static IEnumerable<(Rule Rule, List<ScanItem> Items)> Groups(ScanReport report)
    {
        var groups = new List<(Rule Rule, List<ScanItem> Items)>();
        foreach (var item in report.Items)
        {
            if (groups.Count > 0 && ReferenceEquals(groups[^1].Rule, item.Rule))
                groups[^1].Items.Add(item);
            else
                groups.Add((item.Rule, new List<ScanItem> { item }));
        }
        return groups;
    }

    private static bool TryTier(string value, out Tier tier)
    {
        switch (value.ToLowerInvariant())
        {
            case "safe": tier = Tier.Safe; return true;
            case "review": tier = Tier.Review; return true;
            case "caution": tier = Tier.Caution; return true;
            default: tier = default; return false;
        }
    }

    private static string TierName(Tier tier) => tier switch
    {
        Tier.Safe => "safe",
        Tier.Review => "review",
        _ => "caution",
    };
}