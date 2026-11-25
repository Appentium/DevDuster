using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Clean;

public enum CleanMode { Recycle, Delete }

public sealed record CleanResult(ScanItem Item, string? Error, long FreedBytes, IReadOnlyList<string> LeftBehind)
{
    public bool Succeeded => Error is null;
}

public sealed class Cleaner(RuleCatalog catalog, IFileRemover remover, IFileMeasure measure, CleanLog log, Docker docker)
{
    private readonly DenyGuard _guard = new(catalog);

    public Task<IReadOnlyList<CleanResult>> CleanAsync(
        IReadOnlyList<ScanItem> items, CleanMode mode, IProgress<CleanResult>? progress, CancellationToken cancellation) =>
        Task.Run<IReadOnlyList<CleanResult>>(() =>
        {
            var results = new List<CleanResult>();
            foreach (var item in items)
            {
                if (cancellation.IsCancellationRequested) break;
                var result = Clean(item, mode);
                results.Add(result);
                progress?.Report(result);
            }
            return results;
        }, CancellationToken.None);

    private CleanResult Clean(ScanItem item, CleanMode mode)
    {
        if (item.Rule.Target is DockerPruneTarget) return PruneDocker(item);
        try
        {
            var target = _guard.Check(item.Path, item.Rule);
            if (mode == CleanMode.Recycle)
            {
                remover.Recycle(target);
                Record(mode, item.Bytes, target);
                return new CleanResult(item, null, item.Bytes, []);
            }
            var left = TreeRemover.Remove(target);
            var remaining = left.Count == 0 ? 0 : new SizeCalculator(measure).AllocatedSize(target);
            var freed = Math.Max(0, item.Bytes - remaining);
            Record(mode, freed, target);
            var error = left.Count == 0 ? null : $"{left.Count} item(s) are in use or protected and were left.";
            return new CleanResult(item, error, freed, left);
        }
        catch (Exception error) when (error is RefusedException || PathTools.IsFileError(error))
        {
            return new CleanResult(item, error.Message, 0, []);
        }
    }

    private CleanResult PruneDocker(ScanItem item)
    {
        if (docker.Prune() is not { } reclaimed) return new CleanResult(item, "Docker is not running.", 0, []);
        Record(CleanMode.Delete, reclaimed, "docker system prune -f");
        return new CleanResult(item, null, reclaimed, []);
    }

    private void Record(CleanMode mode, long bytes, string path)
    {
        // The removal already happened, so a log write failure must not report it as failed.
        try { log.Append(mode, bytes, path); }
        catch (Exception error) when (PathTools.IsFileError(error)) { return; }
    }
}
