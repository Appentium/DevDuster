using DevDuster.Core.Explore;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Clean;

public sealed record DeleteAssessment(string Path, RiskLevel Level, IReadOnlyList<string> Reasons)
{
    public string Name => System.IO.Path.GetFileName(Path);

    public bool Confirms(string typed) => string.Equals(typed, Name, StringComparison.Ordinal);
}

public sealed class DeleteRisk(RuleCatalog catalog, IProcessProbe processes)
{
    private const int InspectLimit = 200_000;

    private static readonly Dictionary<DatabaseKind, string[]> Servers = new()
    {
        [DatabaseKind.MySql] = ["mysqld", "mariadbd"],
        [DatabaseKind.Postgres] = ["postgres"],
        [DatabaseKind.Redis] = ["redis-server"],
        [DatabaseKind.Mongo] = ["mongod"],
    };

    private readonly DenyGuard _guard = new(catalog);

    public DeleteAssessment Assess(string path)
    {
        string resolved;
        try { resolved = _guard.Check(path, RuleCatalog.UserSelected); }
        catch (Exception error) when (error is RefusedException || PathTools.IsFileError(error))
        {
            return new DeleteAssessment(path, RiskLevel.Blocked, [error.Message]);
        }
        var running = processes.RunningNames();
        var findings = new List<(RiskLevel Level, string Reason)>();
        if (PathKnowledge.Match(resolved) is { } fact) findings.Add((fact.Risk, $"{fact.Title}: {fact.Usage} {fact.Action}"));
        for (var parent = System.IO.Path.GetDirectoryName(resolved); parent is not null; parent = System.IO.Path.GetDirectoryName(parent))
        {
            AddDatabase(Names(PathTools.Children(parent)), running, findings);
        }
        // What was not looked at could be a database or a repository.
        if (!Inspect(resolved, running, findings) && !IsRebuildable(resolved))
        {
            findings.Add((RiskLevel.Critical, "Too large to inspect fully, so it may hold databases or repositories."));
        }
        if (findings.All(finding => finding.Level == RiskLevel.Safe))
        {
            if (IsRebuildable(resolved)) findings.Add((RiskLevel.Safe, "A cache or build folder that is rebuilt when needed."));
            else if (IsAppData(resolved)) findings.Add((RiskLevel.Critical, "An app's own data: settings, sign-ins or documents may be lost."));
            else if (findings.Count == 0) findings.Add((RiskLevel.Review, "Not something DevDuster can rebuild."));
        }
        var level = findings.Max(finding => finding.Level);
        return new DeleteAssessment(resolved, level, [.. findings.Where(finding => finding.Level == level).Select(finding => finding.Reason).Distinct()]);
    }

    private static HashSet<string> Names(IEnumerable<FileSystemInfo> children) =>
        children.Select(child => child.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);

    private static void AddDatabase(IReadOnlySet<string> names, IReadOnlySet<string> running, List<(RiskLevel, string)> findings)
    {
        if (Insights.Database(names) is not { } kind) return;
        findings.Add(Servers[kind].Any(running.Contains)
            ? (RiskLevel.Blocked, $"{kind} is running. Stop the server first.")
            : (RiskLevel.Critical, $"{kind} database data. Deleting it loses those databases."));
    }

    private static bool Inspect(string root, IReadOnlySet<string> running, List<(RiskLevel, string)> findings)
    {
        if (!PathTools.IsPlainDirectory(root)) return true;
        var seen = 0;
        var pending = new Queue<string>([root]);
        while (pending.TryDequeue(out var folder))
        {
            if (seen >= InspectLimit) return false;
            var children = PathTools.TryChildren(folder);
            if (children is null)
            {
                findings.Add((RiskLevel.Critical, "Part of this folder can't be read, so its contents are unknown."));
                continue;
            }
            seen += children.Count;
            AddDatabase(Names(children), running, findings);
            foreach (var child in children)
            {
                if (child.Name.Equals(".git", PathTools.Comparison)) findings.Add((RiskLevel.Critical, "Holds a git repository that may have unpushed work."));
                if (child.Extension.Equals(".vhdx", PathTools.Comparison)) findings.Add((RiskLevel.Critical, $"Holds the virtual disk {child.Name}."));
                if (child.Extension.Equals(".exe", PathTools.Comparison) && running.Contains(System.IO.Path.GetFileNameWithoutExtension(child.Name)))
                {
                    findings.Add((RiskLevel.Critical, $"{child.Name} is running."));
                }
                if (child is DirectoryInfo && !child.Attributes.HasFlag(FileAttributes.ReparsePoint)) pending.Enqueue(child.FullName);
            }
        }
        return true;
    }

    private bool IsRebuildable(string path)
    {
        var inSafeRule = catalog.Rules.Any(rule => rule.Tier == Tier.Safe && rule.Target is FolderTarget target
            && target.Patterns.Any(pattern => new RuleGlob(catalog.Folders, pattern).Contains(path)));
        return inSafeRule || new ProjectArtifactMatcher(catalog).RuleForArtifact(path) is { Tier: Tier.Safe };
    }

    private bool IsAppData(string path)
    {
        var appData = PathTools.Real(catalog.Folders.AppData) ?? PathTools.Normalize(catalog.Folders.AppData);
        return PathTools.IsInside(path, appData) && !PathTools.IsInside(path, System.IO.Path.Combine(appData, "Local", "Temp"));
    }
}
