using System.ComponentModel;
using System.Diagnostics;
using Microsoft.Win32;

namespace DevDuster.Platform;

public sealed record InstalledProgram(string Id, string Name, string Publisher, string Version, long Bytes, string? InstallLocation, string UninstallCommand);

public sealed class InstalledPrograms
{
    private const string UninstallKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";

    public IReadOnlyList<InstalledProgram> Read()
    {
        (RegistryHive Hive, RegistryView View)[] sources =
        [
            (RegistryHive.CurrentUser, RegistryView.Default),
            (RegistryHive.LocalMachine, RegistryView.Registry64),
            (RegistryHive.LocalMachine, RegistryView.Registry32),
        ];
        return [.. sources.SelectMany(source => Read(source.Hive, source.View))
            .DistinctBy(program => (program.Name, program.Version))
            .OrderBy(program => program.Name, StringComparer.CurrentCultureIgnoreCase)];
    }

    // Runs the vendor's own uninstaller, which asks before it removes anything.
    public void Uninstall(InstalledProgram program)
    {
        var (file, arguments) = Split(program.UninstallCommand);
        try { Process.Start(new ProcessStartInfo(file, arguments) { UseShellExecute = true })?.Dispose(); }
        catch (Exception error) when (error is Win32Exception or FileNotFoundException)
        {
            throw new IOException($"{program.Name}'s uninstaller couldn't start: {error.Message}", error);
        }
    }

    private static IEnumerable<InstalledProgram> Read(RegistryHive hive, RegistryView view)
    {
        using var root = RegistryKey.OpenBaseKey(hive, view);
        using var list = root.OpenSubKey(UninstallKey);
        if (list is null) yield break;
        foreach (var id in list.GetSubKeyNames())
        {
            using var key = list.OpenSubKey(id);
            if (key?.GetValue("DisplayName") is not string { Length: > 0 } name) continue;
            if (key.GetValue("UninstallString") is not string { Length: > 0 } command) continue;
            if (key.GetValue("SystemComponent") is 1 || key.GetValue("ParentKeyName") is string { Length: > 0 }) continue;
            yield return new InstalledProgram(
                $@"{hive}\{view}\{id}", name, key.GetValue("Publisher") as string ?? "", key.GetValue("DisplayVersion") as string ?? "",
                key.GetValue("EstimatedSize") is int kilobytes ? kilobytes * 1024L : 0,
                key.GetValue("InstallLocation") as string, Environment.ExpandEnvironmentVariables(command));
        }
    }

    private static (string File, string Arguments) Split(string command)
    {
        var text = command.Trim();
        if (text.StartsWith('"') && text.IndexOf('"', 1) is > 0 and var quote) return (text[1..quote], text[(quote + 1)..].Trim());
        var end = text.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
        return end < 0 ? (text, "") : (text[..(end + 4)], text[(end + 4)..].Trim());
    }
}
