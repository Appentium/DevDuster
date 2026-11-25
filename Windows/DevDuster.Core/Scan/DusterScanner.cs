using DevDuster.Core.Clean;
using DevDuster.Core.Rules;

namespace DevDuster.Core.Scan;

public sealed class DusterScanner(RuleCatalog catalog, DriveService drives, IFileMeasure measure, IProcessProbe processes, Docker docker)
{
    public Task<ScanReport> RunAsync(ScanOptions options, IProgress<ScanProgress>? progress, CancellationToken cancellation) =>
        Task.Run(() => Run(options, progress, cancellation), cancellation);

    internal static ProjectWalk WalkProjects(
        RuleCatalog catalog, DriveService drives, ScanOptions options, Action<string> progress, CancellationToken cancellation)
    {
        var folders = catalog.Folders;
        string[] blocked = [.. options.ExcludedPaths, folders.AppData, .. folders.CloudFolders, .. folders.SystemFolders];
        var excluded = blocked.Select(PathTools.Real).OfType<string>().ToList();
        var walker = new ProjectWalker(new ProjectArtifactMatcher(catalog), excluded);
        var walk = walker.Walk(ProjectWalker.SearchRoots(folders, drives, options.Scope), progress, cancellation);
        // A cut-short walk has incomplete activity, which could make an active project look stale.
        cancellation.ThrowIfCancellationRequested();
        return walk;
    }

    private ScanReport Run(ScanOptions options, IProgress<ScanProgress>? progress, CancellationToken cancellation)
    {
        var excluded = options.ExcludedPaths.Select(PathTools.Real).OfType<string>().ToList();
        var scope = options.Scope?.Select(PathTools.Real).OfType<string>().ToList();
        progress?.Report(new ScanProgress(ScanPhase.Rules, catalog.Folders.Home));

        var (offered, claimed) = FolderCandidates([.. excluded, .. Existing(catalog.Folders.DusterData)]);
        var running = processes.RunningNames();
        var rules = catalog.Rules.Where(rule => options.Tiers.Contains(rule.Tier)).ToList();
        var candidates = offered.Where(item =>
            options.Tiers.Contains(item.Rule.Tier)
            && !item.Rule.ProcessGuard.Any(running.Contains)
            && IsOldEnough(item, cancellation)
            && (scope is null || scope.Any(root => PathTools.IsSameOrInside(item.Path, root)))).ToList();

        if (rules.Any(rule => rule.Target is ProjectTarget))
        {
            var walk = WalkProjects(catalog, drives, options, path => progress?.Report(new ScanProgress(ScanPhase.Projects, path)), cancellation);
            candidates.AddRange(walk.Artifacts
                .Where(artifact => options.Tiers.Contains(artifact.Rule.Tier) && walk.OwnerOf(artifact) is { } owner && options.IsStale(walk.Activity[owner]))
                .SelectMany(artifact => Claim(artifact.Path, claimed).Select(path => new ScanItem(artifact.Rule, path, 0))));
        }

        var guard = new RunningAppGuard(catalog.Folders, running);
        var sizes = new SizeCalculator(measure);
        var items = new List<ScanItem>();
        var skippedItems = new List<SkippedItem>();
        foreach (var candidate in candidates.DistinctBy(item => item.Path, PathTools.Comparer))
        {
            cancellation.ThrowIfCancellationRequested();
            progress?.Report(new ScanProgress(ScanPhase.Measuring, candidate.Path));
            var item = candidate with { Bytes = sizes.AllocatedSize(candidate.Path, cancellation) };
            if (item.Bytes == 0) continue;
            if (guard.OwnerOf(item) is { } owner)
            {
                skippedItems.Add(new SkippedItem(item, owner));
                continue;
            }
            items.Add(item);
            progress?.Report(new ScanProgress(ScanPhase.Measuring, item.Path, item));
        }

        if (scope is null && rules.FirstOrDefault(rule => rule.Target is DockerPruneTarget) is { } dockerRule && docker.ReclaimableBytes() is { } reclaimable && reclaimable > 0)
        {
            items.Add(new ScanItem(dockerRule, docker.DataPath, reclaimable));
        }

        cancellation.ThrowIfCancellationRequested();
        var order = catalog.Rules.Select((rule, index) => (rule.Id, index)).ToDictionary(entry => entry.Id, entry => entry.index);
        var skipped = rules.Select(rule => (Rule: rule, Process: rule.ProcessGuard.FirstOrDefault(running.Contains)))
            .Where(entry => entry.Process is not null).Select(entry => new SkippedRule(entry.Rule, entry.Process!)).ToList();
        return new ScanReport(
            [.. items.OrderBy(item => order[item.Rule.Id]).ThenByDescending(item => item.Bytes)],
            skipped,
            [.. skippedItems.OrderByDescending(entry => entry.Item.Bytes)]);
    }

    private (List<ScanItem> Offered, List<string> Claimed) FolderCandidates(IReadOnlyList<string> excluded)
    {
        var expander = new FolderRuleExpander(catalog.Folders);
        var claimed = new List<string>();
        var offered = new List<ScanItem>();
        foreach (var rule in catalog.Rules)
        {
            var expansion = expander.Expand(rule);
            string[] blocked = [.. claimed, .. excluded];
            foreach (var path in expansion.Offered)
            {
                offered.AddRange(Claim(path, blocked).Select(free => new ScanItem(rule, free, 0)));
            }
            claimed.AddRange(expansion.All);
        }
        return (offered, claimed);
    }

    private static IEnumerable<string> Claim(string path, IReadOnlyList<string> blocked)
    {
        if (blocked.Any(other => PathTools.IsSameOrInside(path, other))) return [];
        var inner = blocked.Where(other => PathTools.IsInside(other, path)).ToList();
        if (inner.Count == 0) return [path];
        // Split into children so the blocked path inside is never offered with its parent.
        return PathTools.Children(path)
            .Where(child => !child.Attributes.HasFlag(FileAttributes.ReparsePoint) && !child.Name.StartsWith('.'))
            .SelectMany(child => Claim(child.FullName, inner));
    }

    private static IEnumerable<string> Existing(string path) => PathTools.Real(path) is { } real ? [real] : [];

    private static bool IsOldEnough(ScanItem item, CancellationToken cancellation)
    {
        if (item.Rule.MinAgeDays is not { } days) return true;
        var cutoff = DateTime.UtcNow.AddDays(-days);
        // A folder's own date misses edits deeper down, so every file inside must be old.
        var pending = new Stack<FileSystemInfo>([Directory.Exists(item.Path) ? new DirectoryInfo(item.Path) : new FileInfo(item.Path)]);
        while (pending.TryPop(out var entry))
        {
            cancellation.ThrowIfCancellationRequested();
            if (entry.LastWriteTimeUtc >= cutoff || entry.CreationTimeUtc >= cutoff) return false;
            if (entry is not DirectoryInfo || entry.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
            if (PathTools.TryChildren(entry.FullName) is not { } children) return false;
            foreach (var child in children) pending.Push(child);
        }
        return true;
    }
}
