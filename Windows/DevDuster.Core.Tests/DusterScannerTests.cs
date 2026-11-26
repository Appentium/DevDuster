using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class DusterScannerTests
{
    private static ScanOptions Options(Fixture fixture) => new() { Scope = new[] { fixture.Root } };

    [Fact]
    public void RunningProcessSkipsItsRuleAndReportsIt()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/.gradle/caches/build-cache-1/entry.bin");

        var report = fixture.Scan(Options(fixture), "java");
        Assert.DoesNotContain(report.Items, item => item.Rule.Id == "gradle.build-cache");
        Assert.Contains(report.Skipped, skipped => skipped.Rule.Id == "gradle.build-cache" && skipped.RunningProcess == "java");

        var free = fixture.Scan(Options(fixture));
        Assert.Contains(free.Items, item => item.Rule.Id == "gradle.build-cache");
    }

    [Fact]
    public void TempFileNewerThanSevenDaysIsNotOffered()
    {
        using var fixture = new Fixture();
        var fresh = fixture.MakeFile("tmp/fresh.tmp", ageDays: 0);
        var old = fixture.MakeFile("tmp/old.tmp", ageDays: 10);

        var offered = fixture.Scan(Options(fixture)).Items
            .Where(item => item.Rule.Id == "windows.temp")
            .Select(item => item.Path)
            .ToHashSet();
        Assert.Contains(old, offered);
        Assert.DoesNotContain(fresh, offered);
    }

    [Fact]
    public void StaleNodeModulesIsOfferedAndFreshOneIsNot()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/Code/old/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/old/index.js", ageDays: 40);
        fixture.MakeFile("home/Code/old/node_modules/lib/index.js", ageDays: 40);
        fixture.MakeFile("home/Code/new/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/new/index.js", ageDays: 2);
        fixture.MakeFile("home/Code/new/node_modules/lib/index.js", ageDays: 40);

        var offered = fixture.Scan(Options(fixture)).Items
            .Where(item => item.Rule.Id == "project.node-modules")
            .Select(item => item.Path)
            .ToList();
        var staleFolder = fixture.At("home/Code/old/node_modules");
        var freshFolder = fixture.At("home/Code/new/node_modules");
        Assert.Contains(offered, path => PathTools.IsSame(path, staleFolder));
        Assert.DoesNotContain(offered, path => PathTools.IsSame(path, freshFolder));
    }
}
public sealed class ScanStreamingTests
{
    [Fact]
    public void ProjectInsideAppDataIsNeverOfferedEvenWhenScannedDirectly()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/AppData/Local/Pub/Cache/hosted/pkg/package.json", ageDays: 40);
        fixture.MakeFile("home/AppData/Local/Pub/Cache/hosted/pkg/node_modules/x.js", ageDays: 40);

        var report = fixture.Scan(new ScanOptions { Scope = [fixture.At("home/AppData/Local/Pub")] });
        var projects = fixture.MakeProjectScanner().ScanAsync(new ScanOptions { Scope = [fixture.At("home/AppData/Local/Pub")] }, null, CancellationToken.None).GetAwaiter().GetResult();

        Assert.DoesNotContain(report.Items, item => item.Rule.Id == "project.node-modules");
        Assert.Empty(projects);
    }

    private sealed class Recorder : IProgress<ScanProgress>
    {
        private readonly Lock _gate = new();
        public List<ScanProgress> Reports { get; } = [];

        public void Report(ScanProgress value)
        {
            lock (_gate) Reports.Add(value);
        }
    }

    [Fact]
    public void EveryOfferedItemIsReportedAsFoundAndProgressReachesTheEnd()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/.gradle/caches/build-cache-1/entry.bin");
        fixture.MakeFile("home/Code/old/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/old/node_modules/lib/index.js", ageDays: 40);
        var recorder = new Recorder();

        var report = fixture.MakeScanner().RunAsync(new ScanOptions { Scope = [fixture.Root] }, recorder, CancellationToken.None).GetAwaiter().GetResult();

        var found = recorder.Reports.Where(entry => entry.Found is not null).Select(entry => entry.Found!.Path).ToHashSet(PathTools.Comparer);
        Assert.NotEmpty(report.Items);
        Assert.All(report.Items, item => Assert.Contains(item.Path, found));
        Assert.Contains(report.Items, item => item.Rule.Id == "project.node-modules");
        var fractions = recorder.Reports.Select(entry => entry.Fraction).OfType<double>().ToList();
        Assert.All(fractions, fraction => Assert.InRange(fraction, 0, 1));
        Assert.Equal(1, fractions.Max());
    }

    [Fact]
    public void FolderWalkReportsEachTopLevelFolderWhenItFinishes()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/Code/a/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/a/node_modules/x.js", ageDays: 40);
        fixture.MakeFile("home/Other/b/package.json", ageDays: 40);
        var roots = new[] { fixture.At("home") };
        var walker = new ProjectWalker(new Rules.ProjectArtifactMatcher(fixture.Catalog), []);
        var plan = walker.Plan(roots);
        var finished = new List<int>();

        var walk = walker.Walk(roots, plan, _ => { }, CancellationToken.None, (_, folder) =>
        {
            lock (finished) finished.Add(folder.Artifacts.Count);
        });

        Assert.Equal(plan.Count, finished.Count);
        Assert.Equal(walk.Artifacts.Count, finished.Sum());
    }

    [Fact]
    public void SplittingFoldersFinelyKeepsTheSameProjectsAndArtifacts()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/Work/clients/repo/package.json", ageDays: 40);
        fixture.MakeFile("home/Work/clients/repo/app/src/fresh.js", ageDays: 1);
        fixture.MakeFile("home/Work/clients/repo/app/node_modules/x.js", ageDays: 40);
        fixture.MakeFile("home/Work/clients/old/package.json", ageDays: 40);
        fixture.MakeFile("home/Work/clients/old/node_modules/x.js", ageDays: 40);
        fixture.MakeFile("home/Work/games/unity/ProjectSettings/ProjectVersion.txt", ageDays: 40);
        fixture.MakeFile("home/Work/games/unity/Library/cache.bin", ageDays: 40);
        fixture.MakeFile("home/Work/games/unity/Assets/new.cs", ageDays: 1);
        var roots = new[] { fixture.At("home") };
        var walker = new ProjectWalker(new Rules.ProjectArtifactMatcher(fixture.Catalog), []);

        var whole = walker.Walk(roots, walker.Plan(roots, splitDepth: 1), _ => { }, CancellationToken.None);
        var fine = walker.Walk(roots, walker.Plan(roots, splitDepth: 6), _ => { }, CancellationToken.None);

        Assert.True(walker.Plan(roots, splitDepth: 6).Count > walker.Plan(roots, splitDepth: 1).Count);
        Assert.Equal(whole.Activity.OrderBy(entry => entry.Key), fine.Activity.OrderBy(entry => entry.Key));
        Assert.Equal(whole.Artifacts.Select(a => a.Path).Order(), fine.Artifacts.Select(a => a.Path).Order());
        Assert.Equal(whole.Artifacts.Select(whole.OwnerOf).Order(), fine.Artifacts.Select(fine.OwnerOf).Order());
        Assert.Contains(fixture.At("home/Work/games/unity"), fine.Activity.Keys);
    }
}
