using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Explore;

public sealed class DiskNode(string path, string name, long bytes, bool isDirectory, IReadOnlyList<DiskNode> children, int foldedCount = 0)
{
    public string Path { get; } = path;
    public string Name { get; } = name;
    public long Bytes { get; } = bytes;
    public bool IsDirectory { get; } = isDirectory;
    public IReadOnlyList<DiskNode> Children { get; } = children;
    public int FoldedCount { get; } = foldedCount;
    public IReadOnlyList<string> Unreadable { get; init; } = [];
    public IReadOnlyList<Insight> Insights { get; init; } = [];

    public DiskNode Removing(string path)
    {
        if (Children.FirstOrDefault(child => PathTools.IsSame(child.Path, path)) is { } removed)
        {
            IReadOnlyList<DiskNode> rest = [.. Children.Where(child => !PathTools.IsSame(child.Path, path))];
            return new DiskNode(Path, Name, Math.Max(0, Bytes - removed.Bytes), IsDirectory, rest, FoldedCount)
            {
                Unreadable = Unreadable,
                Insights = Insights,
            };
        }
        var delta = 0L;
        var updated = new List<DiskNode>(Children.Count);
        foreach (var child in Children)
        {
            var next = child.Removing(path);
            delta += child.Bytes - next.Bytes;
            updated.Add(next);
        }
        return new DiskNode(Path, Name, Math.Max(0, Bytes - delta), IsDirectory, updated, FoldedCount)
        {
            Unreadable = Unreadable,
            Insights = Insights,
        };
    }
}

public sealed record DiskMapProgress(string Path, long BytesScanned, int ItemsScanned);

public sealed class DiskMapBuilder(IFileMeasure measure)
{
    public const double MinShareRatio = 0.005;
    public const long MinNodeBytes = 1_000_000;
    public const int MaxChildren = 200;

    private sealed class Frame(string path)
    {
        public string Path { get; } = path;
        public string Name { get; } = DisplayName(path);
        public IReadOnlyList<FileSystemInfo>? Children { get; init; }
        public int Index { get; set; }
        public List<DiskNode> Nodes { get; } = [];
    }

    public Task<DiskNode?> RunAsync(string root, IReadOnlyList<string> excluded, IProgress<DiskMapProgress>? progress, CancellationToken ct)
    {
        var resolved = PathTools.Real(root) ?? PathTools.Normalize(root);
        if (PathTools.Attributes(resolved) is not { } attributes || attributes.HasFlag(FileAttributes.ReparsePoint)) return Task.FromResult<DiskNode?>(null);
        if (!attributes.HasFlag(FileAttributes.Directory))
        {
            var bytes = new SizeCalculator(measure).AllocatedSize(resolved);
            return Task.FromResult<DiskNode?>(new DiskNode(resolved, DisplayName(resolved), bytes, false, []));
        }

        var excludedSet = new HashSet<string>(excluded.Select(PathTools.Normalize), PathTools.Comparer);
        var sizes = new SizeCalculator(measure);
        var unreadable = new List<string>();
        var insights = new List<Insight>();
        var stack = new Stack<Frame>();
        stack.Push(new Frame(resolved) { Children = PathTools.TryChildren(resolved) });
        DiskNode? rootNode = null;
        var totalBytes = 0L;
        var items = 0;

        bool IsExcluded(string path) => excludedSet.Any(prefix => PathTools.IsSameOrInside(path, prefix));

        static void Attach(Stack<Frame> frames, ref DiskNode? result, DiskNode node)
        {
            if (frames.Count == 0) result = node;
            else frames.Peek().Nodes.Add(node);
        }

        while (stack.Count > 0 && !ct.IsCancellationRequested)
        {
            var frame = stack.Peek();
            if (frame.Children is null)
            {
                unreadable.Add(frame.Path);
                stack.Pop();
                Attach(stack, ref rootNode, new DiskNode(frame.Path, frame.Name, 0, true, []));
                continue;
            }
            if (frame.Index >= frame.Children.Count)
            {
                stack.Pop();
                var folded = Fold(frame.Nodes, frame.Path);
                // Insights are read before folding hides the many small items.
                insights.AddRange(Explore.Insights.ForFolder(
                    frame.Path, folded.Bytes, [.. frame.Nodes.Select(node => (node.Name, node.Bytes, node.IsDirectory))]));
                Attach(stack, ref rootNode, new DiskNode(frame.Path, frame.Name, folded.Bytes, true, folded.Children));
                continue;
            }
            var child = frame.Children[frame.Index++];
            if (child.Attributes.HasFlag(FileAttributes.ReparsePoint) || IsExcluded(child.FullName)) continue;
            items++;
            if (items % 500 == 0) progress?.Report(new DiskMapProgress(child.FullName, totalBytes, items));
            if (child is FileInfo file)
            {
                var bytes = sizes.AllocatedSize(file);
                totalBytes += bytes;
                if (bytes >= Explore.Insights.NotableBytes && PathKnowledge.Match(file.FullName) is { } fact)
                {
                    insights.Add(new Insight(file.FullName, bytes, fact.Title, fact.Usage, fact.Action));
                }
                frame.Nodes.Add(new DiskNode(file.FullName, file.Name, bytes, false, []));
            }
            else
            {
                stack.Push(new Frame(child.FullName) { Children = PathTools.TryChildren(child.FullName) });
            }
        }

        if (rootNode is not null) rootNode = new DiskNode(rootNode.Path, rootNode.Name, rootNode.Bytes, rootNode.IsDirectory, rootNode.Children, rootNode.FoldedCount)
        {
            Unreadable = unreadable,
            Insights = [.. insights.OrderByDescending(insight => insight.Bytes)],
        };
        return Task.FromResult(ct.IsCancellationRequested ? null : rootNode);
    }

    private static (IReadOnlyList<DiskNode> Children, long Bytes) Fold(List<DiskNode> children, string parentPath)
    {
        var total = children.Sum(node => node.Bytes);
        var sorted = children.OrderByDescending(node => node.Bytes).ToList();
        var kept = new List<DiskNode>();
        var otherBytes = 0L;
        var otherCount = 0;
        var otherFolders = new List<(string Name, long Bytes)>();
        for (var index = 0; index < sorted.Count; index++)
        {
            var child = sorted[index];
            var meetsShare = total > 0 && (double)child.Bytes / total >= MinShareRatio;
            if (index < MaxChildren && meetsShare && child.Bytes >= MinNodeBytes)
            {
                kept.Add(child);
            }
            else
            {
                otherBytes += child.Bytes;
                otherCount++;
                if (child.IsDirectory) otherFolders.Add((child.Name, child.Bytes));
            }
        }
        if (otherCount > 0)
        {
            var label = otherCount == 1 ? "Other (1 item)" : $"Other ({otherCount} items)";
            // A clone set is named only when it is most of what was folded.
            if (Explore.Insights.CloneSets(otherFolders).FirstOrDefault() is { } set && set.Names.Count * 2 > otherCount)
            {
                label = $"{set.Names.Count:N0} {set.Prefix}* folders and {otherCount - set.Names.Count:N0} more";
            }
            kept.Add(new DiskNode(Path.Combine(parentPath, "#other"), label, otherBytes, false, [], otherCount));
        }
        return (kept, total);
    }

    private static string DisplayName(string path)
    {
        var name = Path.GetFileName(Path.TrimEndingDirectorySeparator(path));
        return name.Length > 0 ? name : path;
    }
}
