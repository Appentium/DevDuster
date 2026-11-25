using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Explore;

public sealed record DevToolEssential(string Title, string RelativePath);

public sealed record DevTool(string Id, string Title, RulePlatform Platform, string[] Roots, DevToolEssential[] Essentials);

public enum DevPartKind { Essential, Cleanable, Other }

public sealed record DevStoragePart(string Title, DevPartKind Kind, Tier? Tier, long Bytes, IReadOnlyList<ScanItem> Items);

public sealed record DevToolUsage(DevTool Tool, string Root, long TotalBytes, IReadOnlyList<DevStoragePart> Parts);

public sealed class DevStorageAnalyzer(UserFolders folders, IReadOnlyList<DevTool> tools, IFileMeasure measure)
{
    public string? RootOf(DevTool tool)
    {
        foreach (var pattern in tool.Roots)
        {
            var candidate = Path.IsPathRooted(pattern)
                ? Path.GetFullPath(pattern.Replace('/', Path.DirectorySeparatorChar))
                : folders.Resolve(pattern);
            if (PathTools.Attributes(candidate) is not { } attributes || !attributes.HasFlag(FileAttributes.Directory)) continue;
            return PathTools.Real(candidate) ?? candidate;
        }
        return null;
    }

    public Task<IReadOnlyList<DevToolUsage>> RunAsync(IReadOnlyList<ScanItem> items, CancellationToken ct) =>
        Task.Run(() =>
        {
            var usages = new List<DevToolUsage>();
            foreach (var tool in tools)
            {
                ct.ThrowIfCancellationRequested();
                if (RootOf(tool) is not { } root) continue;
                var usage = Usage(tool, root, items);
                if (usage.TotalBytes > 0) usages.Add(usage);
            }
            return (IReadOnlyList<DevToolUsage>)[.. usages.OrderByDescending(usage => usage.TotalBytes)];
        }, ct);

    private DevToolUsage Usage(DevTool tool, string root, IReadOnlyList<ScanItem> items)
    {
        var inside = items.Where(item => PathTools.IsSameOrInside(item.Path, root)).ToList();
        var parts = CleanableParts(inside);
        var essentials = new List<(string Path, long Bytes)>();
        foreach (var essential in tool.Essentials)
        {
            var path = essential.RelativePath.Length == 0
                ? root
                : Path.Combine(root, essential.RelativePath.Replace('/', Path.DirectorySeparatorChar));
            var claimedByItems = inside.Where(item => PathTools.IsSameOrInside(item.Path, path)).Sum(item => item.Bytes);
            var claimedByEssentials = essentials.Where(entry => PathTools.IsInside(entry.Path, path)).Sum(entry => entry.Bytes);
            // A fresh calculator per folder keeps a hard link shared with another tool's root countable here.
            var bytes = new SizeCalculator(measure).AllocatedSize(path) - claimedByItems - claimedByEssentials;
            if (bytes <= 0) continue;
            essentials.Add((path, bytes));
            parts.Add(new DevStoragePart(essential.Title, DevPartKind.Essential, null, bytes, []));
        }
        var partsBytes = parts.Sum(part => part.Bytes);
        var measured = new SizeCalculator(measure).AllocatedSize(root);
        if (measured > partsBytes)
            parts.Add(new DevStoragePart("Other files", DevPartKind.Other, null, measured - partsBytes, []));
        return new DevToolUsage(tool, root, Math.Max(measured, partsBytes), [.. parts.OrderByDescending(part => part.Bytes)]);
    }

    private static List<DevStoragePart> CleanableParts(IReadOnlyList<ScanItem> items) =>
    [
        .. items.GroupBy(item => item.Rule.Id).Select(group =>
        {
            var first = group.First();
            return new DevStoragePart(first.Rule.Title, DevPartKind.Cleanable, first.Rule.Tier, group.Sum(item => item.Bytes), [.. group]);
        }),
    ];
}
