using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Uninstall;

public sealed record Leftover(ScanItem Item, string Reason);

public sealed class LeftoverFinder(UserFolders folders, IFileMeasure measure, IProcessProbe processes)
{
    private const int QuietDays = 90;
    private const int SignalDepth = 2;
    private static readonly string[] AppDataMarkers = ["Local State", "Local Storage", "GPUCache", "Code Cache", "Update.exe", "unins000.exe", "uninstall.exe"];

    public IReadOnlyList<Leftover> Find(
        IReadOnlyList<InstalledProgram> installed, IReadOnlyList<InstalledProgram> removed, CancellationToken cancellation = default,
        IProgress<ScanUpdate<Leftover>>? progress = null)
    {
        // An empty inventory means the registry read failed, not that nothing is installed.
        if (installed.Count == 0) return [];
        var running = processes.RunningNames();
        var pathEntries = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        var sizes = new SizeCalculator(measure);
        var found = new List<Leftover>();
        var candidates = Candidates().ToList();
        var counter = new UnitCounter(candidates.Count);
        foreach (var folder in candidates)
        {
            cancellation.ThrowIfCancellationRequested();
            progress?.Report(new ScanUpdate<Leftover>(folder, counter.Finish()));
            var name = Path.GetFileName(folder);
            if (!LeftoverShape.Matches(folders, folder) || IsClaimed(folder, installed)) continue;
            if (pathEntries.Any(entry => PathTools.IsSameOrInside(entry.TrimEnd(Path.DirectorySeparatorChar), folder))) continue;
            var former = removed.FirstOrDefault(program => BelongedTo(folder, program));
            if (Inspect(folder, running) is not { } contents) continue;
            if (former is null)
            {
                var isPublisherChild = !LeftoverShape.Roots(folders).Any(root => PathTools.IsSame(Path.GetDirectoryName(folder)!, root));
                if (isPublisherChild || !contents.LooksLikeApp || contents.NewestWriteUtc > DateTime.UtcNow.AddDays(-QuietDays)) continue;
            }
            var reason = former is null
                ? $"No installed program matches “{name}”, unchanged for {QuietDays}+ days."
                : $"Left by {former.Name}.";
            var leftover = new Leftover(new ScanItem(RuleCatalog.Leftover, folder, sizes.AllocatedSize(folder, cancellation)), reason);
            found.Add(leftover);
            progress?.Report(new ScanUpdate<Leftover>(folder, counter.Fraction, leftover));
        }
        return [.. found.OrderByDescending(leftover => leftover.Item.Bytes)];
    }

    private IEnumerable<string> Candidates()
    {
        foreach (var root in LeftoverShape.Roots(folders))
        {
            foreach (var child in PathTools.Children(root).Where(IsPlainDirectory))
            {
                yield return child.FullName;
                if (LeftoverShape.IsReserved(folders, child.Name)) continue;
                foreach (var nested in PathTools.Children(child.FullName).Where(IsPlainDirectory)) yield return nested.FullName;
            }
        }
    }

    private static bool IsPlainDirectory(FileSystemInfo info) =>
        info is DirectoryInfo && !info.Attributes.HasFlag(FileAttributes.ReparsePoint);

    // Matching too much only hides a leftover, so every check here leans towards "still installed".
    private static bool IsClaimed(string folder, IReadOnlyList<InstalledProgram> installed)
    {
        var name = Key(Path.GetFileName(folder));
        if (name.Length < 3) return true;
        return installed.Any(program =>
        {
            if (!string.IsNullOrWhiteSpace(program.InstallLocation))
            {
                var location = program.InstallLocation.Trim('"').TrimEnd(Path.DirectorySeparatorChar);
                if (PathTools.IsSameOrInside(location, folder) || PathTools.IsInside(folder, location)) return true;
            }
            if (program.UninstallCommand.Contains(folder + Path.DirectorySeparatorChar, PathTools.Comparison)) return true;
            return Overlaps(name, Key(ProductName(program.Name))) || Overlaps(name, Key(program.Publisher));
        });
    }

    private static bool Overlaps(string folderKey, string programKey) =>
        programKey.Length >= 3 && (programKey.Contains(folderKey, StringComparison.Ordinal) || folderKey.Contains(programKey, StringComparison.Ordinal));

    private bool BelongedTo(string folder, InstalledProgram program)
    {
        var location = program.InstallLocation?.Trim('"').TrimEnd(Path.DirectorySeparatorChar);
        if (location is { Length: > 0 } && PathTools.IsSame(location, folder)) return true;
        var product = Key(ProductName(program.Name));
        if (product.Length < 3 || Key(Path.GetFileName(folder)) != product) return false;
        var parent = Path.GetDirectoryName(folder)!;
        return LeftoverShape.Roots(folders).Any(root => PathTools.IsSame(parent, root))
            || Key(Path.GetFileName(parent)) is { Length: >= 3 } vendor && Key(program.Publisher).Contains(vendor, StringComparison.Ordinal);
    }

    // "Foo 2.1 (x64)" and "Foo" are the same product.
    private static string ProductName(string name)
    {
        var words = name.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .TakeWhile(word => !word.StartsWith('(') && !(char.IsAsciiDigit(word.TrimStart('v', 'V').FirstOrDefault()) && word.Contains('.')));
        return string.Join(' ', words);
    }

    private static string Key(string text) => string.Concat(text.Where(char.IsLetterOrDigit)).ToLowerInvariant();

    private static (bool LooksLikeApp, DateTime NewestWriteUtc)? Inspect(string folder, IReadOnlySet<string> running)
    {
        var looksLikeApp = false;
        var newest = DateTime.MinValue;
        var pending = new Stack<(string Path, int Depth)>([(folder, 0)]);
        while (pending.TryPop(out var current))
        {
            // A folder that can't be read in full can't be judged.
            if (PathTools.TryChildren(current.Path) is not { } children) return null;
            foreach (var child in children)
            {
                if (child.Name is ".git") return null;
                if (current.Depth < SignalDepth && AppDataMarkers.Contains(child.Name, PathTools.Comparer)) looksLikeApp = true;
                if (child.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                if (child is DirectoryInfo)
                {
                    pending.Push((child.FullName, current.Depth + 1));
                    continue;
                }
                if (child.LastWriteTimeUtc > newest) newest = child.LastWriteTimeUtc;
                if (child.Extension.Equals(".exe", PathTools.Comparison) && running.Contains(Path.GetFileNameWithoutExtension(child.Name))) return null;
            }
        }
        return newest == DateTime.MinValue ? null : (looksLikeApp, newest);
    }
}
