using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Relocate;

public enum RelocationPhase { Copying, Switching, Moved, CopyingBack, SwitchingBack }

public sealed record Relocation(
    string TargetId, string Title, string Original, string Destination, long Bytes, DateTime DateUtc, RelocationPhase Phase)
{
    public bool IsDestinationConnected() => PathTools.IsPlainDirectory(Destination);
}

public sealed record RelocationTarget(string Id, string Title, RulePlatform Platform, string Path, string? BlockedReason);

public sealed record RelocationCheck(IReadOnlyList<string> Problems, IReadOnlyList<string> Notes);

public sealed class RelocationException(string message) : IOException(message);
