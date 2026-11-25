using DevDuster.Core.Clean;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Relocate;

public sealed class Relocator(UserFolders folders, DriveService drives, IFileMeasure measure, IJunctionMaker junctions)
{
    private const string StagingSuffix = ".devduster-partial";
    private const string OldSuffix = ".devduster-old";
    private const string LinkChanged = "The link or the moved folder changed outside DevDuster, so it wasn't touched.";

    private readonly RelocationJournal _journal = new(folders);

    public IReadOnlyList<Relocation> Relocations() => [.. _journal.Load().Where(relocation => relocation.Phase == RelocationPhase.Moved)];

    public string SuggestedDestination(RelocationTarget target, LocalDrive drive)
    {
        // Same layout as the profile, so the data is easy to recognise on that drive.
        var relative = PathTools.IsInside(target.Path, folders.Home) ? Path.GetRelativePath(folders.Home, target.Path) : Path.GetFileName(target.Path);
        return Path.Combine(drive.Root, "DevDuster", relative);
    }

    public RelocationCheck Check(RelocationTarget target, long bytes, string destination)
    {
        if (target.BlockedReason is { } reason) return new RelocationCheck([reason], []);
        if (!PathTools.IsPlainDirectory(target.Path) || PathTools.Real(target.Path) is not { } source)
        {
            return new RelocationCheck([$"{target.Title} is missing or already moved."], []);
        }
        if (Resolve(destination) is not { } resolved) return new RelocationCheck(["Pick a folder on a connected drive."], []);
        if (DestinationProblem(source, bytes, resolved) is { } problem) return new RelocationCheck([problem], []);
        List<string> notes =
        [
            $"A link stays at {target.Path}, so tools, scripts and saved paths keep working.",
            "Quit the tools that use this folder first. Windows refuses the move while files are open.",
        ];
        if (drives.DriveOf(resolved) is { IsRemovable: true } drive)
        {
            notes.Add($"While {drive.Root} is unplugged, {target.Title} can't find its files.");
        }
        return new RelocationCheck([], notes);
    }

    public Task<string?> MoveAsync(
        RelocationTarget target, long bytes, string destination, IProgress<double>? progress, CancellationToken cancellation) =>
        Task.Run(() => Move(target, bytes, destination, progress, cancellation), cancellation);

    public Task<string?> MoveBackAsync(Relocation relocation, IProgress<double>? progress, CancellationToken cancellation) =>
        Task.Run(() => MoveBack(relocation, progress, cancellation), cancellation);

    public void Recover()
    {
        foreach (var record in _journal.Load())
        {
            // A missing drive or a locked folder leaves the record for the next launch.
            try { Recover(record); }
            catch (Exception error) when (PathTools.IsFileError(error)) { continue; }
        }
    }

    private string? Move(RelocationTarget target, long bytes, string requested, IProgress<double>? progress, CancellationToken cancellation)
    {
        var check = Check(target, bytes, requested);
        if (check.Problems.Count > 0) throw new RelocationException(string.Join(Environment.NewLine, check.Problems));
        var destination = Resolve(requested)!;
        var source = PathTools.Real(target.Path)!;
        var staging = destination + StagingSuffix;
        var old = source + OldSuffix;
        var record = new Relocation(target.Id, target.Title, source, destination, bytes, DateTime.UtcNow, RelocationPhase.Copying);
        if (_journal.Load().Any(other => PathTools.IsSame(other.Original, source))) throw new RelocationException("An earlier move of this folder isn't finished. Restart DevDuster to recover it.");
        _journal.Upsert(record);
        TreeSnapshot before;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            before = CopyVerified(source, staging, bytes, progress, cancellation);
            if (Directory.Exists(destination)) Directory.Delete(destination, recursive: false);
            record = record with { Phase = RelocationPhase.Switching };
            _journal.Upsert(record);
            Directory.Move(staging, destination);
        }
        catch
        {
            Discard(staging);
            // After the rename the copy is at the destination, and the source is still whole.
            _journal.Remove(record);
            throw;
        }
        try
        {
            RenameUnused(source, old);
        }
        catch
        {
            Discard(destination);
            _journal.Remove(record);
            throw;
        }
        try
        {
            // Nothing can write under the old name now, so this catches writes made during the copy.
            if (before.FirstDifference(TreeSnapshot.Of(old, CancellationToken.None)) is not null) throw new RelocationException("A tool changed files while they were copied. Nothing was moved. Quit the tool and try again.");
            junctions.Create(source, destination);
            if (PathTools.Real(source) is not { } linked || !PathTools.IsSame(linked, destination)) throw new RelocationException("The link couldn't be made. Nothing was moved.");
            _journal.Upsert(record with { Phase = RelocationPhase.Moved });
        }
        catch
        {
            // If the original can't be put back now, the journal stays in switching and Recover() restores it.
            RemoveLink(source);
            Directory.Move(old, source);
            Discard(destination);
            _journal.Remove(record);
            throw;
        }
        return RemoveLeavingLeftover(old);
    }

    private string? MoveBack(Relocation record, IProgress<double>? progress, CancellationToken cancellation)
    {
        var original = record.Original;
        var destination = record.Destination;
        if (!LinksToDestination(record)) throw new RelocationException(LinkChanged);
        var staging = original + StagingSuffix;
        if (PathTools.Exists(staging)) throw new RelocationException($"A partial copy is in the way at {staging}. Remove it first.");
        var bytes = new SizeCalculator(measure).AllocatedSize(destination, cancellation);
        if (drives.DriveOf(original) is { } drive && drive.AvailableBytes < NeededBytes(bytes)) throw new RelocationException($"Not enough space on {drive.Root}.");
        var current = record with { Phase = RelocationPhase.CopyingBack };
        var old = destination + OldSuffix;
        TreeSnapshot before;
        try
        {
            _journal.Upsert(current);
            before = CopyVerified(destination, staging, bytes, progress, cancellation);
            current = record with { Phase = RelocationPhase.SwitchingBack };
            _journal.Upsert(current);
            RenameUnused(destination, old);
        }
        catch
        {
            Discard(staging);
            _journal.Upsert(record);
            throw;
        }
        try
        {
            if (before.FirstDifference(TreeSnapshot.Of(old, CancellationToken.None)) is not null) throw new RelocationException("A tool changed files while they were copied. Nothing was moved back. Quit the tool and try again.");
            RemoveLink(original);
            Directory.Move(staging, original);
        }
        catch
        {
            // If a step fails here, the journal stays in switchingBack and Recover() finishes it.
            Directory.Move(old, destination);
            if (!PathTools.Exists(original)) junctions.Create(original, destination);
            Discard(staging);
            _journal.Upsert(record);
            throw;
        }
        _journal.Remove(current);
        return RemoveLeavingLeftover(old);
    }

    private void Recover(Relocation record)
    {
        var original = record.Original;
        var destination = record.Destination;
        var old = original + OldSuffix;
        var forwardStaging = destination + StagingSuffix;
        var backStaging = original + StagingSuffix;
        var movedAway = destination + OldSuffix;
        switch (record.Phase)
        {
            case RelocationPhase.Moved:
                if (PathTools.IsPlainDirectory(original)) _journal.Remove(record);
                break;
            case RelocationPhase.Copying:
                if (!PathTools.IsPlainDirectory(original)) break;
                DiscardOrThrow(forwardStaging);
                _journal.Remove(record);
                break;
            case RelocationPhase.Switching when PathTools.IsPlainDirectory(original) && !PathTools.Exists(old):
                DiscardOrThrow(forwardStaging);
                DiscardOrThrow(destination);
                _journal.Remove(record);
                break;
            case RelocationPhase.Switching when LinksToDestination(record):
                // The link is only made after the last check, so the copy is complete and may already be in use.
                _journal.Upsert(record with { Phase = RelocationPhase.Moved });
                DiscardOrThrow(old);
                break;
            case RelocationPhase.Switching when PathTools.IsPlainDirectory(old):
                if (!PathTools.IsPlainDirectory(original)) RemoveLink(original);
                if (PathTools.Exists(original)) break;
                Directory.Move(old, original);
                DiscardOrThrow(destination);
                _journal.Remove(record);
                break;
            case RelocationPhase.CopyingBack:
                if (!record.IsDestinationConnected()) break;
                DiscardOrThrow(backStaging);
                _journal.Upsert(record with { Phase = RelocationPhase.Moved });
                break;
            case RelocationPhase.SwitchingBack when PathTools.IsPlainDirectory(original):
                _journal.Remove(record);
                break;
            case RelocationPhase.SwitchingBack when PathTools.IsPlainDirectory(movedAway) || record.IsDestinationConnected():
                if (!PathTools.Exists(destination)) Directory.Move(movedAway, destination);
                if (!PathTools.Exists(original)) junctions.Create(original, destination);
                DiscardOrThrow(backStaging);
                _journal.Upsert(record with { Phase = RelocationPhase.Moved });
                break;
        }
    }

    private string? DestinationProblem(string source, long bytes, string destination)
    {
        if (PathTools.IsSameOrInside(destination, source) || PathTools.IsInside(source, destination)) return $"Pick a folder outside {source}.";
        if (PathTools.Exists(destination) && (!PathTools.IsPlainDirectory(destination) || PathTools.TryChildren(destination) is not { Count: 0 }))
        {
            return $"{destination} already exists. Pick a new or empty folder.";
        }
        string[] leftovers = [destination + StagingSuffix, destination + OldSuffix, source + OldSuffix, source + StagingSuffix];
        if (leftovers.FirstOrDefault(PathTools.Exists) is { } leftover) return $"An older copy is in the way at {leftover}. Remove it first.";
        if (drives.DriveOf(destination) is not { } drive) return "Pick a folder on a connected drive.";
        if (PathTools.Components(destination).Length == 0) return "Pick a folder, not a whole drive.";
        if (folders.SystemFolders.Any(system => PathTools.IsSameOrInside(destination, system))) return "Pick a folder outside Windows and Program Files.";
        if (folders.CloudFolders.Any(cloud => PathTools.IsSameOrInside(destination, cloud))) return "Pick a folder that OneDrive doesn't sync.";
        if (drives.DriveOf(source) is { } sourceDrive && PathTools.IsSame(sourceDrive.Root, drive.Root)) return $"{drive.Root} is the drive the folder is on now. Pick another drive to free space.";
        if (!drive.CanHoldMovedTools) return $"{drive.Root} is formatted as {drive.Format}. Use an NTFS or ReFS drive.";
        return drive.AvailableBytes < NeededBytes(bytes) ? $"Not enough space on {drive.Root}." : null;
    }

    private TreeSnapshot CopyVerified(string source, string staging, long bytes, IProgress<double>? progress, CancellationToken cancellation)
    {
        var before = TreeSnapshot.Of(source, cancellation);
        new TreeCopier(junctions, bytes, progress, cancellation).Copy(source, staging);
        if (before.FirstDifference(TreeSnapshot.Of(staging, cancellation)) is { } path) throw new RelocationException($"The copy didn't match the original at {path}. Nothing was moved.");
        return before;
    }

    private static void RenameUnused(string from, string to)
    {
        try { Directory.Move(from, to); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new RelocationException($"{from} is in use. Quit the tools that use it and try again. Nothing was moved.");
        }
    }

    private static bool LinksToDestination(Relocation record) =>
        PathTools.IsLink(record.Original) && record.IsDestinationConnected()
        && PathTools.Real(record.Original) is { } linked && PathTools.Real(record.Destination) is { } real && PathTools.IsSame(linked, real);

    private static void RemoveLink(string path)
    {
        if (PathTools.IsLink(path) && PathTools.LinkTarget(path) is not null) Directory.Delete(path, recursive: false);
    }

    private static void Discard(string path) => TreeRemover.Remove(path);

    private static void DiscardOrThrow(string path)
    {
        if (TreeRemover.Remove(path).Count > 0) throw new IOException($"{path} is in use.");
    }

    private static string? RemoveLeavingLeftover(string path) => TreeRemover.Remove(path).Count == 0 ? null : path;

    // Room for files that are compressed on this drive but copied out in full.
    private static long NeededBytes(long bytes) => bytes + (bytes / 10) + 1_000_000_000;

    private static string? Resolve(string path)
    {
        if (!Path.IsPathFullyQualified(path)) return null;
        var existing = PathTools.Normalize(path);
        var missing = new Stack<string>();
        while (!PathTools.Exists(existing))
        {
            if (Path.GetDirectoryName(existing) is not { } parent) return null;
            missing.Push(Path.GetFileName(existing));
            existing = parent;
        }
        return PathTools.Real(existing) is { } real ? missing.Aggregate(real, Path.Combine) : null;
    }
}
