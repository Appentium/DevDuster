using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using DevDuster.Core.Uninstall;
using Microsoft.Win32;
using Windows.ApplicationModel;
using Windows.Management.Deployment;

namespace DevDuster.Platform;

public sealed class InstalledPrograms
{
    private const string UninstallKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";

    public IReadOnlyList<InstalledProgram> Read() =>
        [.. ReadAll()
            .Where(entry => entry.Program.UninstallCommand.Length > 0 && !entry.IsComponent)
            .Select(entry => entry.Program)
            .DistinctBy(program => (program.Name, program.Version))
            .OrderBy(program => program.Name, StringComparer.CurrentCultureIgnoreCase)];

    // Hidden components still own folders, so leftover matching needs them too.
    public IReadOnlyList<InstalledProgram> ReadForLeftovers() => [.. ReadAll().Select(entry => entry.Program), .. ReadStoreApps()];

    // Store apps have no Uninstall key. A failure here must stop the leftover search, not thin the list.
    private static IEnumerable<InstalledProgram> ReadStoreApps() =>
        new PackageManager().FindPackagesForUser("").Select(package =>
            new InstalledProgram(package.Id.FullName, package.Id.Name, PublisherName(package), "", 0, null, ""));

    // The name comes from the package's resources, which can be missing.
    private static string PublisherName(Package package)
    {
        try { return package.PublisherDisplayName; }
        catch (Exception error) when (error is COMException or FileNotFoundException) { return ""; }
    }

    private IEnumerable<(InstalledProgram Program, bool IsComponent)> ReadAll()
    {
        (RegistryHive Hive, RegistryView View)[] sources =
        [
            (RegistryHive.CurrentUser, RegistryView.Default),
            (RegistryHive.LocalMachine, RegistryView.Registry64),
            (RegistryHive.LocalMachine, RegistryView.Registry32),
        ];
        return sources.SelectMany(source => Read(source.Hive, source.View));
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

    private static IEnumerable<(InstalledProgram Program, bool IsComponent)> Read(RegistryHive hive, RegistryView view)
    {
        using var root = RegistryKey.OpenBaseKey(hive, view);
        using var list = root.OpenSubKey(UninstallKey);
        if (list is null) yield break;
        foreach (var id in list.GetSubKeyNames())
        {
            using var key = list.OpenSubKey(id);
            if (key?.GetValue("DisplayName") is not string { Length: > 0 } name) continue;
            var command = key.GetValue("UninstallString") as string ?? "";
            var isComponent = key.GetValue("SystemComponent") is 1 || key.GetValue("ParentKeyName") is string { Length: > 0 };
            var program = new InstalledProgram(
                $@"{hive}\{view}\{id}", name, key.GetValue("Publisher") as string ?? "", key.GetValue("DisplayVersion") as string ?? "",
                key.GetValue("EstimatedSize") is int kilobytes ? kilobytes * 1024L : 0,
                key.GetValue("InstallLocation") is string location ? Environment.ExpandEnvironmentVariables(location) : null,
                Environment.ExpandEnvironmentVariables(command));
            yield return (program, isComponent);
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
