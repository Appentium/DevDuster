using DevDuster.Core.Clean;
using DevDuster.Core.Rules;

namespace DevDuster.Core.Scan;

public sealed class DusterScanner(RuleCatalog catalog, DriveService drives, IFileMeasure measure, IProcessProbe processes, Docker docker)
{
    public Task<ScanReport> RunAsync(ScanOptions options, IProgress<ScanProgress>? progress, CancellationToken cancellation) =>
        Task.Run(() => Run(options, progress, cancellation), cancellation);

    internal static ProjectWalker MakeWalker(RuleCatalog catalog, ScanOptions options) =>
        new(new ProjectArtifactMatcher(catalog), WalkBlocked(catalog, options));

    // Where the project walk starts. A root inside app data, a system folder or OneDrive is dropped even when the user
    // picked it: build-like folders there belong to installed tools and package caches, not to projects.
    internal static IReadOnlyList<string> ProjectRoots(RuleCatalog catalog, DriveService drives, ScanOptions options)
    {
        var blocked = WalkBlocked(catalog, options);
        return [.. ProjectWalker.SearchRoots(catalog.Folders, drives, options.Scope).Where(root => !blocked.Any(other => PathTools.IsSameOrInside(root, other)))];
    }

    private static IReadOnlyList<string> WalkBlocked(RuleCatalog catalog, ScanOptions options)
    {
        var folders = catalog.Folders;
        string[] blocked = [.. options.ExcludedPaths, folders.AppData, .. folders.CloudFolders, .. folders.SystemFolders];
        return [.. blocked.Select(PathTools.Real).OfType<string>()];
    }

    private ScanReport Run(ScanOptions options, IProgress<ScanProgress>? progress, CancellationToken cancellation)
    {
        var excluded = options.ExcludedPaths.Select(PathTools.Real).OfType<string>().ToList();
        var scope = options.Scope?.Select(PathTools.Real).OfType<string>().ToList();
        progress?.Report(new ScanProgress(ScanPhase.Rules, catalog.Folders.Home));

        var (offered, claimed) = FolderCandidates([.. excluded, .. Existing(catalog.Folders.DusterData)]);
        var running = processes.RunningNames();
        var rules = catalog.Rules.Where(rule => options.Tiers.Contains(rule.Tier)).ToList();
        var folderCandidates = offered.Where(item =>
            options.Tiers.Contains(item.Rule.Tier)
            && !item.Rule.ProcessGuard.Any(running.Contains)
            && (scope is null || scope.Any(root => PathTools.IsSameOrInside(item.Path, root)))).ToList();

        var walksProjects = options.WalksProjects && rules.Any(rule => rule.Target is ProjectTarget);
        var folders = catalog.Folders;
        var walker = MakeWalker(catalog, options);
        var roots = walksProjects ? ProjectRoots(catalog, drives, options) : [];
        var plan = walker.Plan(roots);

        // One unit per cache folder and one per planned project folder; neither is known in bytes up front.
        var total = folderCandidates.Count + plan.Count;
        var done = 0;
        double? Fraction() => total == 0 ? null : Math.Min(1, (double)Volatile.Read(ref done) / total);
        void Report(ScanPhase phase, string path, ScanItem? found = null) => progress?.Report(new ScanProgress(phase, path, found, Fraction()));

        var guard = new RunningAppGuard(folders, running);
        var sizes = new SizeCalculator(measure);
        var gate = new Lock();
        var seen = new HashSet<string>(PathTools.Comparer);
        var items = new List<ScanItem>();
        var skippedItems = new List<SkippedItem>();

        // Called from several walker threads, so each item is shown the moment it is measured.
        void Measure(ScanItem candidate)
        {
            lock (gate)
            {
                if (!seen.Add(candidate.Path)) return;
            }
            Report(ScanPhase.Measuring, candidate.Path);
            var item = candidate with { Bytes = sizes.AllocatedSize(candidate.Path, cancellation) };
            if (item.Bytes == 0 || cancellation.IsCancellationRequested) return;
            var owner = guard.OwnerOf(item);
            lock (gate)
            {
                if (owner is null) items.Add(item);
                else skippedItems.Add(new SkippedItem(item, owner));
            }
            if (owner is null) Report(ScanPhase.Measuring, item.Path, item);
        }

        foreach (var candidate in folderCandidates)
        {
            cancellation.ThrowIfCancellationRequested();
            if (IsOldEnough(candidate, cancellation)) Measure(candidate);
            Interlocked.Increment(ref done);
            Report(ScanPhase.Rules, candidate.Path);
        }

        if (walksProjects)
        {
            walker.Walk(roots, plan, path => Report(ScanPhase.Projects, path), cancellation, (start, folder) =>
            {
                foreach (var artifact in folder.Artifacts)
                {
                    if (cancellation.IsCancellationRequested) return;
                    if (!options.Tiers.Contains(artifact.Rule.Tier) || folder.OwnerOf(artifact) is not { } owner || !options.IsStale(folder.Activity[owner])) continue;
                    foreach (var path in Claim(artifact.Path, claimed)) Measure(new ScanItem(artifact.Rule, path, 0));
                }
                Interlocked.Increment(ref done);
                Report(ScanPhase.Projects, start);
            });
        }
        cancellation.ThrowIfCancellationRequested();

        // Docker is asked only when the scan covers its data folder, as for a folder rule.
        var coversDocker = scope is null || scope.Any(root => PathTools.IsSameOrInside(docker.DataPath, root));
        if (coversDocker && rules.FirstOrDefault(rule => rule.Target is DockerPruneTarget) is { } dockerRule && docker.ReclaimableBytes() is { } reclaimable && reclaimable > 0)
        {
            var dockerItem = new ScanItem(dockerRule, docker.DataPath, reclaimable);
            items.Add(dockerItem);
            Report(ScanPhase.Measuring, dockerItem.Path, dockerItem);
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
