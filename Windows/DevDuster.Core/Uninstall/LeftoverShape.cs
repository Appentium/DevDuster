using DevDuster.Core.Explore;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Uninstall;

public static class LeftoverShape
{
    private static readonly string[] SystemNames =
    [
        "Microsoft", "Packages", "Programs", "Temp", "DevDuster", "Apps", "Application Data", "History", "Temporary Internet Files",
        "CrashDumps", "D3DSCache", "VirtualStore", "ConnectedDevicesPlatform", "Comms", "PeerDistRepub", "PeerDistPub", "Publishers",
        "PlaceholderTileLogoFolder", "ElevatedDiagnostics", "Microsoft_Corporation", "NVIDIA", "NVIDIA Corporation", "AMD", "Intel",
        "Realtek", "Python", "pip", "NuGet", "SquirrelTemp", "IsolatedStorage", "assembly", "ssh", "gnupg",
    ];

    public static IReadOnlyList<string> Roots(UserFolders folders) =>
        [folders.LocalAppData, folders.RoamingAppData, Path.Combine(folders.LocalAppData, "Programs")];

    // A leftover is an AppData app folder, directly or one publisher folder down, never a tool or Windows folder.
    public static bool Matches(UserFolders folders, string path)
    {
        var roots = Roots(folders).Select(root => PathTools.Real(root) ?? PathTools.Normalize(root)).ToList();
        if (roots.Any(root => PathTools.IsSame(root, path))) return false;
        var parent = Path.GetDirectoryName(path);
        if (parent is null || IsReserved(folders, Path.GetFileName(path))) return false;
        if (roots.Any(root => PathTools.IsSame(parent, root))) return true;
        var grandparent = Path.GetDirectoryName(parent);
        return grandparent is not null && roots.Any(root => PathTools.IsSame(grandparent, root)) && !IsReserved(folders, Path.GetFileName(parent));
    }

    public static bool IsReserved(UserFolders folders, string name) =>
        name.StartsWith('.') || SystemNames.Contains(name, PathTools.Comparer) || ToolNames(folders).Contains(name);

    private static HashSet<string> ToolNames(UserFolders folders)
    {
        var names = new HashSet<string>(PathTools.Comparer);
        foreach (var pattern in DevToolCatalog.BuiltIn.SelectMany(tool => tool.Roots))
        {
            var parts = pattern.Split('/');
            if (parts[0] is not ("%LOCAL%" or "%ROAMING%")) continue;
            var index = parts.Length > 2 && parts[1] == "Programs" ? 2 : 1;
            names.Add(parts[index]);
        }
        return names;
    }
}
