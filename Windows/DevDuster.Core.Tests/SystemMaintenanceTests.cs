using DevDuster.Core.Maintenance;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class SystemMaintenanceTests
{
    private static SystemMaintenance Make(Fixture fixture, List<string> commands, bool succeeds = true) =>
        new(fixture.At("Windows"), fixture.At("Windows/System32"), (executable, arguments, _) =>
        {
            commands.Add($"{Path.GetFileName(executable)} {string.Join(' ', arguments)}");
            return succeeds;
        });

    [Fact]
    public void UpdateCacheRemovesOnlyDownloadContentsAndRestartsServices()
    {
        using var fixture = new Fixture();
        var file = fixture.MakeFile("Windows/SoftwareDistribution/Download/a/package.cab");
        var database = fixture.MakeFile("Windows/SoftwareDistribution/DataStore/store.edb");
        List<string> commands = [];
        Assert.True(Make(fixture, commands).Run(SystemTask.UpdateCache));
        Assert.False(File.Exists(file));
        Assert.True(Directory.Exists(fixture.At("Windows/SoftwareDistribution/Download")));
        Assert.True(File.Exists(database));
        Assert.Equal(["net.exe stop wuauserv /y", "net.exe stop bits /y", "net.exe start wuauserv", "net.exe start bits"], commands);
    }

    [Fact]
    public void ServicesThatWereNotStoppedAreNotStarted()
    {
        using var fixture = new Fixture();
        fixture.MakeDirectory("Windows");
        List<string> commands = [];
        Make(fixture, commands, succeeds: false).Run(SystemTask.UpdateCache);
        Assert.Equal(2, commands.Count);
    }

    [Fact]
    public void DumpsListsOnlyDumpFiles()
    {
        using var fixture = new Fixture();
        var memory = fixture.MakeFile("Windows/MEMORY.DMP");
        var mini = fixture.MakeFile("Windows/Minidump/a.dmp");
        var live = fixture.MakeFile("Windows/LiveKernelReports/WATCHDOG/b.dmp");
        fixture.MakeFile("Windows/LiveKernelReports/notes.txt");
        var targets = Make(fixture, []).Targets(SystemTask.Dumps);
        Assert.Equal(new[] { memory, mini, live }.Order(), targets.Order());
    }

    [Fact]
    public void LinkedDownloadFolderIsRefused()
    {
        using var fixture = new Fixture();
        var outside = fixture.MakeFile("home/Documents/keep.txt");
        fixture.MakeDirectory("Windows/SoftwareDistribution");
        // Windows refuses symlinks without Developer Mode.
        try { Directory.CreateSymbolicLink(fixture.At("Windows/SoftwareDistribution/Download"), Path.GetDirectoryName(outside)!); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return; }
        Assert.Empty(Make(fixture, []).Targets(SystemTask.UpdateCache));
    }
}
