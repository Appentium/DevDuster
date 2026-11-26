using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class ProjectScannerTests
{
    private static IReadOnlyList<DevProject> Scan(Fixture fixture, ScanOptions options) =>
        fixture.MakeProjectScanner().ScanAsync(options, null, CancellationToken.None).GetAwaiter().GetResult();

    private static ScanOptions Options(Fixture fixture, string? excluded = null) => new()
    {
        Scope = new[] { fixture.Root },
        ExcludedPaths = excluded is null ? Array.Empty<string>() : new[] { excluded },
    };

    [Fact]
    public void FreshAndStaleActivityAreReported()
    {
        using var fixture = new Fixture();
        var oldPath = fixture.MakeFile("home/Code/old/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/old/node_modules/lib/index.js", ageDays: 40);
        var newPath = fixture.MakeFile("home/Code/new/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/new/index.js", ageDays: 2);
        fixture.MakeFile("home/Code/new/node_modules/lib/index.js", ageDays: 40);

        var projects = Scan(fixture, Options(fixture));
        var options = Options(fixture);
        var old = projects.Single(project => PathTools.IsSame(project.Path, Path.GetDirectoryName(oldPath)!));
        var fresh = projects.Single(project => PathTools.IsSame(project.Path, Path.GetDirectoryName(newPath)!));
        Assert.True(options.IsStale(old.LastActivityUtc));
        Assert.False(options.IsStale(fresh.LastActivityUtc));
    }

    [Fact]
    public void NestedProjectIsOwnedByOutermost()
    {
        using var fixture = new Fixture();
        var repo = fixture.MakeFile("home/Code/repo/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/repo/web/src/app.ts", ageDays: 1);
        fixture.MakeFile("home/Code/repo/android/build.gradle", ageDays: 40);
        var build = fixture.MakeFile("home/Code/repo/android/build/out.apk", ageDays: 40);
        var repoPath = Path.GetDirectoryName(repo)!;

        var projects = Scan(fixture, Options(fixture));
        var project = Assert.Single(projects);
        Assert.True(PathTools.IsSame(project.Path, repoPath));
        Assert.Contains(project.Folders, folder => PathTools.IsSame(folder.Path, Path.GetDirectoryName(build)!));
    }

    [Fact]
    public void FolderWithUninstallerIsSkipped()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/Code/app/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/app/node_modules/x.js", ageDays: 40);
        fixture.MakeFile("home/Code/app/unins000.exe", ageDays: 40);

        Assert.Empty(Scan(fixture, Options(fixture)));
    }

    [Fact]
    public void ExcludedPathIsSkipped()
    {
        using var fixture = new Fixture();
        var keep = fixture.MakeFile("home/Keep/app/package.json", ageDays: 40);
        fixture.MakeFile("home/Keep/app/node_modules/x.js", ageDays: 40);
        var code = fixture.MakeFile("home/Code/app/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/app/node_modules/x.js", ageDays: 40);

        var projects = Scan(fixture, Options(fixture, Path.GetDirectoryName(keep)!));
        var project = Assert.Single(projects);
        Assert.True(PathTools.IsSame(project.Path, Path.GetDirectoryName(code)!));
    }
}