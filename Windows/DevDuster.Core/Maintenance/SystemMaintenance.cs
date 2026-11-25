using DevDuster.Core.Clean;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Maintenance;

public sealed class SystemMaintenance(string windowsFolder, string systemFolder, Func<string, string[], TimeSpan, bool> run)
{
    private static readonly string[] UpdateServices = ["wuauserv", "bits"];
    private static readonly TimeSpan ServiceTimeout = TimeSpan.FromMinutes(2);
    private static readonly TimeSpan DismTimeout = TimeSpan.FromHours(3);

    public IReadOnlyList<string> Targets(SystemTask task)
    {
        if (task == SystemTask.UpdateCache)
        {
            return Folder("SoftwareDistribution", "Download") is { } download
                ? [.. PathTools.Children(download).Select(child => child.FullName)]
                : [];
        }
        if (task != SystemTask.Dumps) return [];
        var targets = new List<string>();
        var memory = Path.Combine(windowsFolder, "MEMORY.DMP");
        if (Folder() is not null && PathTools.IsPlainFile(memory)) targets.Add(memory);
        foreach (var name in new[] { "Minidump", "LiveKernelReports" })
        {
            if (Folder(name) is { } folder) AddDumps(folder, targets);
        }
        return targets;
    }

    public bool Run(SystemTask task)
    {
        if (task == SystemTask.ComponentCleanup)
        {
            return run(Path.Combine(systemFolder, "Dism.exe"), ["/Online", "/Cleanup-Image", "/StartComponentCleanup"], DismTimeout);
        }
        if (task != SystemTask.UpdateCache) return Remove(Targets(task));
        var net = Path.Combine(systemFolder, "net.exe");
        // Only services this run stopped are started again.
        var stopped = UpdateServices.Where(service => run(net, ["stop", service, "/y"], ServiceTimeout)).ToList();
        try { return Remove(Targets(task)); }
        finally
        {
            foreach (var service in stopped) run(net, ["start", service], ServiceTimeout);
        }
    }

    private static bool Remove(IReadOnlyList<string> targets)
    {
        var complete = true;
        foreach (var target in targets) complete &= TreeRemover.Remove(target).Count == 0;
        return complete;
    }

    // A link anywhere on the way would let an elevated delete land somewhere else.
    private string? Folder(params string[] parts)
    {
        var path = windowsFolder;
        if (!PathTools.IsPlainDirectory(path)) return null;
        foreach (var part in parts)
        {
            path = Path.Combine(path, part);
            if (!PathTools.IsPlainDirectory(path)) return null;
        }
        return path;
    }

    private static void AddDumps(string folder, List<string> targets)
    {
        foreach (var child in PathTools.Children(folder))
        {
            if (child.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
            if (child is DirectoryInfo) AddDumps(child.FullName, targets);
            else if (child.Extension.Equals(".dmp", PathTools.Comparison)) targets.Add(child.FullName);
        }
    }
}
