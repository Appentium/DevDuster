using DevDuster.Core.Rules;

namespace DevDuster.Core.Scan;

public sealed record DevProject(string Path, DateTime LastActivityUtc, IReadOnlyList<ScanItem> Folders)
{
    public long TotalBytes => Folders.Sum(folder => folder.Bytes);
    public IReadOnlyList<RulePlatform> Platforms => [.. Folders.Select(folder => folder.Rule.Platform).Distinct().Order()];
}

public sealed class ProjectScanner(RuleCatalog catalog, DriveService drives, IFileMeasure measure)
{
    public Task<IReadOnlyList<DevProject>> ScanAsync(ScanOptions options, Action<string> progress, CancellationToken cancellation) =>
        Task.Run<IReadOnlyList<DevProject>>(() =>
        {
            var walk = DusterScanner.WalkProjects(catalog, drives, options, progress, cancellation);
            var sizes = new SizeCalculator(measure);
            // An artifact with no known project has no activity to judge it by, so it is left out as the cleaner does.
            var owned = walk.Artifacts.Select(artifact => (Artifact: artifact, Owner: walk.OwnerOf(artifact))).Where(entry => entry.Owner is not null);
            var projects = new List<DevProject>();
            foreach (var group in owned.GroupBy(entry => entry.Owner!, PathTools.Comparer).OrderBy(group => group.Key, PathTools.Comparer))
            {
                cancellation.ThrowIfCancellationRequested();
                var folders = group.Select(entry => entry.Artifact).OrderBy(artifact => artifact.Path, PathTools.Comparer)
                    .Select(artifact => new ScanItem(artifact.Rule, artifact.Path, sizes.AllocatedSize(artifact.Path, cancellation))).ToList();
                projects.Add(new DevProject(group.Key, walk.Activity[group.Key], folders));
            }
            cancellation.ThrowIfCancellationRequested();
            return projects;
        }, cancellation);
}
