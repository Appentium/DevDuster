using DevDuster.Core.Rules;

namespace DevDuster.Core.Scan;

public sealed record DevProject(string Path, DateTime LastActivityUtc, IReadOnlyList<ScanItem> Folders)
{
    public long TotalBytes => Folders.Sum(folder => folder.Bytes);
    public IReadOnlyList<RulePlatform> Platforms => [.. Folders.Select(folder => folder.Rule.Platform).Distinct().Order()];
}

public sealed class ProjectScanner(RuleCatalog catalog, DriveService drives, IFileMeasure measure)
{
    public Task<IReadOnlyList<DevProject>> ScanAsync(ScanOptions options, IProgress<ScanUpdate<DevProject>>? progress, CancellationToken cancellation) =>
        Task.Run<IReadOnlyList<DevProject>>(() =>
        {
            var walker = DusterScanner.MakeWalker(catalog, options);
            var roots = DusterScanner.ProjectRoots(catalog, drives, options);
            var plan = walker.Plan(roots);
            var counter = new UnitCounter(plan.Count);
            var sizes = new SizeCalculator(measure);
            var projects = new List<DevProject>();
            var gate = new Lock();
            // A project is never split across planned folders, so each folder's projects are complete when it finishes.
            walker.Walk(roots, plan, path => progress?.Report(new ScanUpdate<DevProject>(path, counter.Fraction)), cancellation, (start, folder) =>
            {
                // An artifact with no known project has no activity to judge it by, so it is left out as the cleaner does.
                var owned = folder.Artifacts.Select(artifact => (Artifact: artifact, Owner: folder.OwnerOf(artifact))).Where(entry => entry.Owner is not null);
                foreach (var group in owned.GroupBy(entry => entry.Owner!, PathTools.Comparer))
                {
                    if (cancellation.IsCancellationRequested) return;
                    var folders = group.Select(entry => entry.Artifact).OrderBy(artifact => artifact.Path, PathTools.Comparer)
                        .Select(artifact => new ScanItem(artifact.Rule, artifact.Path, sizes.AllocatedSize(artifact.Path, cancellation))).ToList();
                    var project = new DevProject(group.Key, folder.Activity[group.Key], folders);
                    lock (gate) projects.Add(project);
                    progress?.Report(new ScanUpdate<DevProject>(group.Key, counter.Fraction, project));
                }
                progress?.Report(new ScanUpdate<DevProject>(start, counter.Finish()));
            });
            cancellation.ThrowIfCancellationRequested();
            return [.. projects.OrderBy(project => project.Path, PathTools.Comparer)];
        }, cancellation);
}
