using DevDuster.Core.Rules;

namespace DevDuster.Core.Scan;

public sealed record ScanItem(Rule Rule, string Path, long Bytes)
{
    public string Name => System.IO.Path.GetFileName(Path);
}

public sealed record SkippedRule(Rule Rule, string RunningProcess);

public sealed record SkippedItem(ScanItem Item, string RunningApp);

public sealed record ScanReport(IReadOnlyList<ScanItem> Items, IReadOnlyList<SkippedRule> Skipped, IReadOnlyList<SkippedItem> SkippedItems)
{
    public long TotalBytes => Items.Sum(item => item.Bytes);
}

public enum ScanPhase { Rules, Projects, Measuring }

public sealed record ScanProgress(ScanPhase Phase, string Path, ScanItem? Found = null);
