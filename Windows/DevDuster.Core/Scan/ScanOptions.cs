using DevDuster.Core.Rules;

namespace DevDuster.Core.Scan;

public sealed record ScanOptions
{
    public int StaleDays { get; init; } = 14;
    public IReadOnlyList<string> ExcludedPaths { get; init; } = [];
    public IReadOnlySet<Tier> Tiers { get; init; } = Enum.GetValues<Tier>().ToHashSet();
    public IReadOnlyList<string>? Scope { get; init; }

    // Off for scans that only need cache folders, such as measuring developer tools.
    public bool WalksProjects { get; init; } = true;

    public bool IsStale(DateTime activityUtc) => activityUtc < DateTime.UtcNow.AddDays(-StaleDays);
}
