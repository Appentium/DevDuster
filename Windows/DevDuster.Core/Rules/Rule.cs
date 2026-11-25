namespace DevDuster.Core.Rules;

public enum RulePlatform
{
    Windows, Android, Flutter, JavaScript, Python, Rust, Go, Jvm, Php, Ruby, DotNet, OtherLanguages,
    Editors, AiTools, AiModels, GameEngines, DevTools,
}

public enum RulePick { All, AllButNewestVersion, UnreferencedByAvds }

public abstract record RuleTarget;

public sealed record FolderTarget(params string[] Patterns) : RuleTarget;

public sealed record ProjectTarget(string Directory, string[] Markers, string? Proof = null) : RuleTarget;

public sealed record DockerPruneTarget : RuleTarget;

public sealed record UserSelectedTarget : RuleTarget;

public sealed record LeftoverTarget : RuleTarget;

public sealed class Rule(string id, string title, Tier tier, RulePlatform platform, RuleTarget target, string regenerate)
{
    public string Id { get; } = id;
    public string Title { get; } = title;
    public Tier Tier { get; } = tier;
    public RulePlatform Platform { get; } = platform;
    public RuleTarget Target { get; } = target;
    public string Regenerate { get; } = regenerate;
    public RulePick Pick { get; init; } = RulePick.All;
    public int? MinAgeDays { get; init; }
    public string[] ProcessGuard { get; init; } = [];
    public bool SkipsRunningApps { get; init; }
}
