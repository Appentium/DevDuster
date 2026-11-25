using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Explore;

public sealed record LargeFile(string Path, long Bytes, DateTime ModifiedUtc)
{
    public string Name => System.IO.Path.GetFileName(Path);
}

public sealed record LargeFileOptions
{
    public long MinBytes { get; init; } = 500_000_000;
    public int? MinAgeDays { get; init; }
    public IReadOnlyList<string>? Roots { get; init; }
    public IReadOnlyList<string> ExcludedPaths { get; init; } = [];
}

public sealed class LargeFileFinder(UserFolders folders, DriveService drives, IFileMeasure measure)
{
    private static readonly HashSet<string> SkippedNames = new(["$Recycle.Bin", "System Volume Information"], PathTools.Comparer);

    public Task<IReadOnlyList<LargeFile>> RunAsync(LargeFileOptions options, IProgress<string>? progress, CancellationToken ct)
    {
        var roots = ProjectWalker.SearchRoots(folders, drives, options.Roots);
        var skipRoots = new List<string>();
        skipRoots.AddRange(folders.SystemFolders.Select(PathTools.Normalize));
        skipRoots.AddRange(folders.CloudFolders.Select(PathTools.Normalize));
        skipRoots.AddRange(options.ExcludedPaths.Select(PathTools.Normalize));
        DateTime? cutoff = options.MinAgeDays is { } days ? DateTime.UtcNow.AddDays(-days) : null;
        var sizes = new SizeCalculator(measure);
        var found = new List<LargeFile>();
        var scanned = 0;

        bool Skip(string path) =>
            SkippedNames.Contains(System.IO.Path.GetFileName(System.IO.Path.TrimEndingDirectorySeparator(path)))
            || skipRoots.Any(skip => PathTools.IsSameOrInside(path, skip));

        foreach (var root in roots)
        {
            if (ct.IsCancellationRequested || Skip(root)) continue;
            var pending = new Stack<string>([root]);
            while (pending.Count > 0 && !ct.IsCancellationRequested)
            {
                var folder = pending.Pop();
                if (PathTools.IsLink(folder)) continue;
                foreach (var child in PathTools.Children(folder))
                {
                    if (child.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                    scanned++;
                    if (scanned % 500 == 0) progress?.Report(child.FullName);
                    if (child is DirectoryInfo directory)
                    {
                        if (!Skip(directory.FullName)) pending.Push(directory.FullName);
                        continue;
                    }
                    if (ct.IsCancellationRequested) break;
                    var file = (FileInfo)child;
                    if (file.Length < options.MinBytes) continue;
                    var allocated = sizes.AllocatedSize(file);
                    if (allocated < options.MinBytes) continue;
                    var modified = file.LastWriteTimeUtc;
                    if (cutoff is { } limit && modified >= limit) continue;
                    found.Add(new LargeFile(file.FullName, allocated, modified));
                }
            }
        }
        return Task.FromResult<IReadOnlyList<LargeFile>>([.. found.OrderByDescending(file => file.Bytes)]);
    }
}
