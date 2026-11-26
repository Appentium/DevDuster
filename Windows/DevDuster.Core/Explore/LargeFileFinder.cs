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

    private const int SplitDepth = 3;
    private const int ProgressEvery = 500;

    public Task<IReadOnlyList<LargeFile>> RunAsync(LargeFileOptions options, IProgress<ScanUpdate<LargeFile>>? progress, CancellationToken ct) =>
        Task.Run<IReadOnlyList<LargeFile>>(() =>
        {
            var roots = ProjectWalker.SearchRoots(folders, drives, options.Roots);
            var skipRoots = new List<string>();
            skipRoots.AddRange(folders.SystemFolders.Select(PathTools.Normalize));
            skipRoots.AddRange(folders.CloudFolders.Select(PathTools.Normalize));
            skipRoots.AddRange(options.ExcludedPaths.Select(PathTools.Normalize));
            DateTime? cutoff = options.MinAgeDays is { } days ? DateTime.UtcNow.AddDays(-days) : null;
            var sizes = new SizeCalculator(measure);
            var found = new List<LargeFile>();
            var gate = new Lock();
            var scanned = 0;

            bool Skip(string path) =>
                SkippedNames.Contains(System.IO.Path.GetFileName(System.IO.Path.TrimEndingDirectorySeparator(path)))
                || skipRoots.Any(skip => PathTools.IsSameOrInside(path, skip));

            // Folders near the top are split so progress can count them; files met on the way are checked at once.
            var units = new List<string>();
            var shallowFiles = new List<FileInfo>();
            void Plan(string folder, int depth)
            {
                if (PathTools.IsLink(folder)) return;
                foreach (var child in PathTools.Children(folder))
                {
                    if (child.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                    if (child is FileInfo file) shallowFiles.Add(file);
                    else if (!Skip(child.FullName))
                    {
                        if (depth > 1) Plan(child.FullName, depth - 1);
                        else units.Add(child.FullName);
                    }
                }
            }
            foreach (var root in roots.Where(root => !Skip(root))) Plan(root, SplitDepth);
            var counter = new UnitCounter(units.Count + 1);

            void Check(FileInfo file)
            {
                if (Interlocked.Increment(ref scanned) % ProgressEvery == 0) progress?.Report(new ScanUpdate<LargeFile>(file.FullName, counter.Fraction));
                if (file.Length < options.MinBytes) return;
                var allocated = sizes.AllocatedSize(file);
                if (allocated < options.MinBytes) return;
                var modified = file.LastWriteTimeUtc;
                if (cutoff is { } limit && modified >= limit) return;
                var large = new LargeFile(file.FullName, allocated, modified);
                lock (gate) found.Add(large);
                progress?.Report(new ScanUpdate<LargeFile>(large.Path, counter.Fraction, large));
            }

            foreach (var file in shallowFiles)
            {
                if (ct.IsCancellationRequested) break;
                Check(file);
            }
            counter.Finish();

            Parallel.ForEach(units, new ParallelOptions { MaxDegreeOfParallelism = 4 }, unit =>
            {
                var pending = new Stack<string>([unit]);
                while (pending.Count > 0 && !ct.IsCancellationRequested)
                {
                    var folder = pending.Pop();
                    if (PathTools.IsLink(folder)) continue;
                    foreach (var child in PathTools.Children(folder))
                    {
                        if (ct.IsCancellationRequested) break;
                        if (child.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                        if (child is DirectoryInfo directory)
                        {
                            if (!Skip(directory.FullName)) pending.Push(directory.FullName);
                        }
                        else Check((FileInfo)child);
                    }
                }
                progress?.Report(new ScanUpdate<LargeFile>(unit, counter.Finish()));
            });
            ct.ThrowIfCancellationRequested();
            return [.. found.OrderByDescending(file => file.Bytes)];
        }, ct);
}
