namespace DevDuster.Core.Maintenance;

public sealed record SystemTask(string Id, string Title, string Detail)
{
    public static readonly SystemTask UpdateCache = new(
        "update-cache", "Windows Update downloads", "Installers Windows Update already downloaded. It downloads again what it still needs.");

    public static readonly SystemTask ComponentCleanup = new(
        "component-cleanup", "Superseded Windows components", "Runs DISM component cleanup. Older updates can no longer be rolled back to those versions.");

    public static readonly SystemTask Dumps = new(
        "dumps", "System crash dumps", "Memory dumps written after crashes. Keep them if you are still diagnosing one.");

    // The elevated process accepts these ids and nothing else.
    public static IReadOnlyList<SystemTask> All { get; } = [UpdateCache, ComponentCleanup, Dumps];
}
