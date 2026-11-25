using DevDuster.Core.Rules;

namespace DevDuster.Core.Scan;

public sealed record ScanOptions
{
    public int StaleDays { get; init; } = 14;
    public IReadOnlyList<string> ExcludedPaths { get; init; } = [];
    public IReadOnlySet<Tier> Tiers { get; init; } = Enum.GetValues<Tier>().ToHashSet();
    public IReadOnlyList<string>? Scope { get; init; }

    public bool IsStale(DateTime activityUtc) => activityUtc < DateTime.UtcNow.AddDays(-StaleDays);
}
