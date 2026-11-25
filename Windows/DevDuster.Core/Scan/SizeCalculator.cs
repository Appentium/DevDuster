using System.Collections.Concurrent;

namespace DevDuster.Core.Scan;

public sealed class SizeCalculator(IFileMeasure measure)
{
    private readonly ConcurrentDictionary<string, bool> _seenLinks = new();

    public long AllocatedSize(string path, CancellationToken cancellation = default)
    {
        if (PathTools.Attributes(path) is not { } attributes || attributes.HasFlag(FileAttributes.ReparsePoint)) return 0;
        if (!attributes.HasFlag(FileAttributes.Directory)) return AllocatedSize(new FileInfo(path));
        long total = 0;
        var pending = new Stack<string>([path]);
        while (pending.TryPop(out var folder) && !cancellation.IsCancellationRequested)
        {
            foreach (var child in PathTools.Children(folder))
            {
                if (child.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                if (child is FileInfo file) total += AllocatedSize(file);
                else pending.Push(child.FullName);
            }
        }
        return total;
    }

    public long AllocatedSize(FileInfo file)
    {
        var result = measure.Measure(file);
        return result.HardLinkId is { } id && !_seenLinks.TryAdd(id, true) ? 0 : result.AllocatedBytes;
    }
}
