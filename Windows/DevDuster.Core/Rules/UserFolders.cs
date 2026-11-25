using DevDuster.Core.Scan;

namespace DevDuster.Core.Rules;

public sealed record UserFolders(string Home, string LocalAppData, string RoamingAppData, string Temp)
{
    public IReadOnlyList<string> SystemFolders { get; init; } = [];
    public IReadOnlyList<string> CloudFolders { get; init; } = [];
    public string? SystemDrive { get; init; }

    public string AppData => Path.Combine(Home, "AppData");
    public string DusterData => Path.Combine(LocalAppData, "DevDuster");

    public static UserFolders Current()
    {
        static string Known(Environment.SpecialFolder folder) => Environment.GetFolderPath(folder);
        string[] system =
        [
            Known(Environment.SpecialFolder.Windows), Known(Environment.SpecialFolder.ProgramFiles),
            Known(Environment.SpecialFolder.ProgramFilesX86), Known(Environment.SpecialFolder.CommonApplicationData),
        ];
        string[] cloud = ["OneDrive", "OneDriveConsumer", "OneDriveCommercial"];
        return new UserFolders(
            PathTools.Normalize(Known(Environment.SpecialFolder.UserProfile)),
            PathTools.Normalize(Known(Environment.SpecialFolder.LocalApplicationData)),
            PathTools.Normalize(Known(Environment.SpecialFolder.ApplicationData)),
            PathTools.Normalize(Path.GetTempPath()))
        {
            SystemFolders = [.. system.Where(path => path.Length > 0).Select(PathTools.Normalize)],
            CloudFolders = [.. cloud.Select(name => Environment.GetEnvironmentVariable(name)).Where(path => !string.IsNullOrWhiteSpace(path)).Select(path => PathTools.Normalize(path!)).Distinct(PathTools.Comparer)],
            SystemDrive = Path.GetPathRoot(Known(Environment.SpecialFolder.Windows)),
        };
    }

    public string Resolve(string pattern)
    {
        var slash = pattern.IndexOf('/');
        var token = slash < 0 ? pattern : pattern[..slash];
        var rest = slash < 0 ? "" : pattern[(slash + 1)..].Replace('/', Path.DirectorySeparatorChar);
        var root = token switch
        {
            "~" => Home,
            "%LOCAL%" => LocalAppData,
            "%ROAMING%" => RoamingAppData,
            "%TEMP%" => Temp,
            _ => throw new ArgumentException($"Unknown folder token in pattern: {pattern}", nameof(pattern)),
        };
        return rest.Length == 0 ? root : Path.Combine(root, rest);
    }
}
