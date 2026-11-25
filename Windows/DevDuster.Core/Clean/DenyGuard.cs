using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using DevDuster.Core.Uninstall;

namespace DevDuster.Core.Clean;

public enum Refusal { Missing, UnsupportedPath, TooShallow, HomeOrDriveRoot, Protected, OutsideRule }

public sealed class RefusedException(Refusal refusal) : Exception(Describe(refusal))
{
    public Refusal Refusal { get; } = refusal;

    private static string Describe(Refusal refusal) => refusal switch
    {
        Refusal.Missing => "Item no longer exists.",
        Refusal.UnsupportedPath => "Only plain paths on local drives can be removed.",
        Refusal.TooShallow => "Refused to remove a top-level system folder.",
        Refusal.HomeOrDriveRoot => "Refused to remove a profile folder or drive root.",
        Refusal.Protected => "Refused to remove protected system or app data.",
        _ => "Path is outside the allowed cleanup rule.",
    };
}

public sealed class DenyGuard
{
    private static readonly string[] ProtectedPatterns =
    [
        "~/.ssh", "~/.gnupg", "~/.aws", "~/.azure", "~/.kube",
        "%LOCAL%/Microsoft/Credentials", "%LOCAL%/Microsoft/Vault", "%LOCAL%/Microsoft/Protect",
        "%LOCAL%/Microsoft/Windows/UsrClass.dat", "%LOCAL%/Microsoft/Outlook", "%LOCAL%/Microsoft/OneDrive",
        "%ROAMING%/Microsoft/Credentials", "%ROAMING%/Microsoft/Crypto", "%ROAMING%/Microsoft/Protect",
        "%ROAMING%/Microsoft/Vault", "%ROAMING%/Microsoft/SystemCertificates", "%ROAMING%/gnupg",
        "%LOCAL%/DevDuster",
    ];

    private static readonly string[] SystemNames =
        ["$Recycle.Bin", "System Volume Information", "$WinREAgent", "Recovery", "Boot", "EFI", "pagefile.sys", "swapfile.sys", "hiberfil.sys", "bootmgr", "BOOTNXT", "Windows.old"];

    private readonly UserFolders _folders;
    private readonly string _home;
    private readonly string[] _protected;
    private readonly string[] _appDataLevels;
    private readonly string _packages;
    private readonly string? _users;
    private readonly ProjectArtifactMatcher _matcher;

    public DenyGuard(RuleCatalog catalog)
    {
        _folders = catalog.Folders;
        _home = Real(_folders.Home);
        _users = Path.GetDirectoryName(_home);
        _protected = [.. _folders.SystemFolders.Concat(_folders.CloudFolders).Concat(ProtectedPatterns.Select(_folders.Resolve)).SelectMany(path => new[] { path, Real(path) }).Distinct(PathTools.Comparer)];
        _appDataLevels = [Real(_folders.AppData), Real(_folders.LocalAppData), Real(_folders.RoamingAppData), Path.Combine(Real(_folders.AppData), "LocalLow")];
        _packages = Path.Combine(Real(_folders.LocalAppData), "Packages");
        _matcher = new ProjectArtifactMatcher(catalog);
    }

    public string Check(string path, Rule rule)
    {
        if (!IsPlainLocalPath(path)) throw new RefusedException(Refusal.UnsupportedPath);
        var resolved = PathTools.RealParent(path);
        if (resolved is null || !PathTools.Exists(resolved)) throw new RefusedException(Refusal.Missing);
        if (!IsPlainLocalPath(resolved)) throw new RefusedException(Refusal.UnsupportedPath);
        RefuseProtected(resolved, rule);
        if (PathTools.IsLink(resolved))
        {
            // Only the link itself is ever removed, but a link aimed at protected data is refused anyway.
            if (PathTools.Real(resolved) is not { } target || PathTools.IsSame(target, resolved)) throw new RefusedException(Refusal.UnsupportedPath);
            RefuseProtected(target, rule);
        }
        if (!IsWithin(rule, resolved)) throw new RefusedException(Refusal.OutsideRule);
        return resolved;
    }

    private static bool IsPlainLocalPath(string path)
    {
        if (!Path.IsPathFullyQualified(path)) return false;
        if (!OperatingSystem.IsWindows()) return true;
        // Refuses UNC shares, \\?\ device paths and alternate data streams.
        return path.Length >= 3 && char.IsAsciiLetter(path[0]) && path[1] == ':' && path.IndexOf(':', 2) < 0;
    }

    private void RefuseProtected(string path, Rule rule)
    {
        var components = PathTools.Components(path);
        var onSystemDrive = _folders.SystemDrive is { } drive && PathTools.IsInside(path, drive);
        if (components.Length == 0 || PathTools.IsSame(path, _home) || PathTools.IsInside(_home, path)) throw new RefusedException(Refusal.HomeOrDriveRoot);
        if (onSystemDrive && components.Length < 2) throw new RefusedException(Refusal.TooShallow);
        if (SystemNames.Contains(components[0], PathTools.Comparer)) throw new RefusedException(Refusal.Protected);
        if (_protected.Any(other => PathTools.IsSameOrInside(path, other) || PathTools.IsInside(other, path))) throw new RefusedException(Refusal.Protected);
        if (_appDataLevels.Any(level => PathTools.IsSameOrInside(level, path))) throw new RefusedException(Refusal.Protected);
        // Another account's profile is never ours to clean.
        if (onSystemDrive && _users is not null && PathTools.IsInside(path, _users) && !PathTools.IsInside(path, _home)) throw new RefusedException(Refusal.Protected);
        if (Path.GetFileName(path).StartsWith("NTUSER.", PathTools.Comparison)) throw new RefusedException(Refusal.Protected);
        if (rule.Target is not UserSelectedTarget) return;
        var parent = Path.GetDirectoryName(path);
        var isFirstLevel = parent is not null && (PathTools.IsSame(parent, _home) || _appDataLevels.Any(level => PathTools.IsSame(parent, level)));
        if (isFirstLevel || PathTools.IsSameOrInside(path, _packages)) throw new RefusedException(Refusal.Protected);
    }

    private bool IsWithin(Rule rule, string path)
    {
        switch (rule.Target)
        {
            case FolderTarget target:
                return target.Patterns.Any(pattern => new RuleGlob(_folders, pattern).Contains(path));
            case ProjectTarget:
                for (var current = path; current is not null; current = Path.GetDirectoryName(current))
                {
                    if (ReferenceEquals(_matcher.RuleForArtifact(current), rule)) return true;
                }
                return false;
            case UserSelectedTarget:
                return true;
            case LeftoverTarget:
                return PathTools.IsPlainDirectory(path) && LeftoverShape.Matches(_folders, path) && !PathTools.IsSameOrInside(path, _packages);
            default:
                return false;
        }
    }

    private static string Real(string path) => PathTools.Real(path) ?? PathTools.Normalize(path);
}
