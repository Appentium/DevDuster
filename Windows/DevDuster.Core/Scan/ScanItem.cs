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

// Fraction is the share of scan units finished, or null before any are known.
public sealed record ScanProgress(ScanPhase Phase, string Path, ScanItem? Found = null, double? Fraction = null);

// A live update from a scan: where it is, the share of work finished (null until known), and anything it just found.
public sealed record ScanUpdate<T>(string Path, double? Fraction, T? Found = null) where T : class;

// Counts finished units of work from any thread and turns them into a fraction.
public sealed class UnitCounter(int total)
{
    private int _done;

    public double? Fraction => total == 0 ? null : Math.Min(1, (double)Volatile.Read(ref _done) / total);

    public double? Finish()
    {
        Interlocked.Increment(ref _done);
        return Fraction;
    }
}
