using DevDuster.Core.Rules;

namespace DevDuster.Core.Explore;

public sealed record Insight(string Path, long Bytes, string Title, string Reason, string Action);

public sealed record CloneSet(string Prefix, IReadOnlyList<string> Names, long Bytes);

public enum DatabaseKind { MySql, Postgres, Redis, Mongo }

public static class Insights
{
    public const int CloneSetSize = 20;
    public const long NotableBytes = 500_000_000;

    public static IReadOnlyList<CloneSet> CloneSets(IEnumerable<(string Name, long Bytes)> siblings) =>
        [.. siblings.Select(sibling => (sibling.Name, sibling.Bytes, Prefix: PrefixOf(sibling.Name)))
            .Where(sibling => sibling.Prefix.Length > 1)
            .GroupBy(sibling => sibling.Prefix, StringComparer.OrdinalIgnoreCase)
            .Where(group => group.Count() >= CloneSetSize)
            .Select(group => new CloneSet(group.Key, [.. group.Select(sibling => sibling.Name)], group.Sum(sibling => sibling.Bytes)))
            .OrderByDescending(set => set.Bytes)];

    public static DatabaseKind? Database(IReadOnlySet<string> childNames)
    {
        if (childNames.Contains("ibdata1") || childNames.Contains("mysql.ibd")) return DatabaseKind.MySql;
        // Postgres writes PG_VERSION in every database folder too; only the data root also has "global".
        if (childNames.Contains("PG_VERSION") && childNames.Contains("global")) return DatabaseKind.Postgres;
        if (childNames.Contains("dump.rdb") || childNames.Contains("appendonlydir")) return DatabaseKind.Redis;
        return childNames.Contains("WiredTiger") ? DatabaseKind.Mongo : null;
    }

    public static IEnumerable<Insight> ForFolder(string path, long bytes, IReadOnlyList<(string Name, long Bytes, bool IsDirectory)> children)
    {
        if (bytes < NotableBytes) yield break;
        var names = children.Select(child => child.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (Database(names) is { } kind)
        {
            var logs = children.Where(child => !child.IsDirectory && IsBinaryLog(child.Name)).Sum(child => child.Bytes);
            var detail = logs > 0 ? $" Binary logs take {logs / 1_000_000_000.0:0.0} GB of it." : "";
            yield return new Insight(path, bytes, $"{kind} database data", "Databases live here; deleting files corrupts the server." + detail, "Drop the databases you don't need.");
        }
        else if (PathKnowledge.Match(path) is { } fact)
        {
            yield return new Insight(path, bytes, fact.Title, fact.Usage, fact.Action);
        }
        foreach (var set in CloneSets(children.Where(child => child.IsDirectory).Select(child => (child.Name, child.Bytes))))
        {
            if (set.Bytes < NotableBytes) continue;
            yield return new Insight(path, set.Bytes, $"{set.Names.Count:N0} {set.Prefix}* folders", "Many near-identical folders, often leftover test copies.", "Check what created them before removing any.");
        }
    }

    private static string PrefixOf(string name)
    {
        var separator = name.IndexOfAny(['_', '-']);
        return separator > 0 ? name[..(separator + 1)] : name.TrimEnd("0123456789".ToCharArray()) is var stem && stem.Length < name.Length ? stem : "";
    }

    private static bool IsBinaryLog(string name) =>
        name.Contains("bin.", StringComparison.OrdinalIgnoreCase) && char.IsAsciiDigit(name[^1]);
}
