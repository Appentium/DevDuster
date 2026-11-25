using DevDuster.Core.Relocate;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class RelocatorTests
{
    private sealed class SymlinkJunctions : IJunctionMaker
    {
        public void Create(string link, string target) => Directory.CreateSymbolicLink(link, target);
    }

    private sealed class TwoDrives : DriveService
    {
        private readonly IReadOnlyList<LocalDrive> _drives;

        public TwoDrives(IReadOnlyList<LocalDrive> drives) => _drives = drives;

        public override IReadOnlyList<LocalDrive> Drives() => _drives;
    }

    private static bool CanSymlink(Fixture fixture)
    {
        var probe = fixture.At("probe-link");
        try
        {
            Directory.CreateSymbolicLink(probe, fixture.Root);
            Directory.Delete(probe);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return false;
        }
    }

    private static DriveService Drives(Fixture fixture) => new TwoDrives(
    [
        new LocalDrive(fixture.At("home"), "Home", "NTFS", 1_000_000_000_000, 1_000_000_000_000, false, false),
        new LocalDrive(fixture.At("dest"), "Dest", "NTFS", 1_000_000_000_000, 1_000_000_000_000, false, false),
    ]);

    private static Relocator Make(Fixture fixture, IJunctionMaker junctions) =>
        new(fixture.Folders, Drives(fixture), fixture.Measure, junctions);

    private static Relocation Record(Fixture fixture, RelocationPhase phase) =>
        new("id", "Title", fixture.At("home/Tool"), fixture.At("dest/Tool"), 1_000,
            new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc), phase);

    private static void Seed(Fixture fixture, Relocation record) =>
        new RelocationJournal(fixture.Folders).Upsert(record);

    [Fact]
    public void MoveThenUndoKeepsDataAtSource()
    {
        using var fixture = new Fixture();
        if (!CanSymlink(fixture)) return;
        var source = fixture.MakeDirectory("home/Tool");
        fixture.MakeFile("home/Tool/data.bin", text: "payload");
        var destination = fixture.At("dest/Tool");
        var target = new RelocationTarget("id", "Title", RulePlatform.Windows, source, null);
        var relocator = Make(fixture, new SymlinkJunctions());

        var leftover = relocator.MoveAsync(target, 1_000, destination, null, CancellationToken.None).GetAwaiter().GetResult();

        Assert.Null(leftover);
        Assert.True(File.Exists(Path.Combine(destination, "data.bin")));
        var moved = Assert.Single(relocator.Relocations());
        var back = relocator.MoveBackAsync(moved, null, CancellationToken.None).GetAwaiter().GetResult();
        Assert.Null(back);
        Assert.Equal("payload", File.ReadAllText(Path.Combine(source, "data.bin")));
        Assert.False(Directory.Exists(destination));
        Assert.Empty(relocator.Relocations());
    }

    [Fact]
    public void RecoverCopyingRemovesPartialAndKeepsSource()
    {
        using var fixture = new Fixture();
        var source = fixture.MakeDirectory("home/Tool");
        fixture.MakeFile("home/Tool/data.bin", text: "payload");
        var staging = fixture.At("dest/Tool") + ".devduster-partial";
        fixture.MakeFile("dest/Tool.devduster-partial/data.bin", text: "partial");
        Seed(fixture, Record(fixture, RelocationPhase.Copying));

        Make(fixture, new SymlinkJunctions()).Recover();

        Assert.Equal("payload", File.ReadAllText(Path.Combine(source, "data.bin")));
        Assert.False(Directory.Exists(staging));
        Assert.Empty(new RelocationJournal(fixture.Folders).Load());
    }

    [Fact]
    public void RecoverSwitchingRenamedRestoresSource()
    {
        using var fixture = new Fixture();
        var source = fixture.At("home/Tool");
        var old = source + ".devduster-old";
        fixture.MakeFile("home/Tool.devduster-old/data.bin", text: "payload");
        fixture.MakeFile("dest/Tool/data.bin", text: "payload");
        Seed(fixture, Record(fixture, RelocationPhase.Switching));

        Make(fixture, new SymlinkJunctions()).Recover();

        Assert.Equal("payload", File.ReadAllText(Path.Combine(source, "data.bin")));
        Assert.False(Directory.Exists(fixture.At("dest/Tool")));
        Assert.Empty(new RelocationJournal(fixture.Folders).Load());
    }

    [Fact]
    public void RecoverSwitchingJunctionMadeKeepsCopyAndDropsOld()
    {
        using var fixture = new Fixture();
        if (!CanSymlink(fixture)) return;
        var source = fixture.At("home/Tool");
        var destination = fixture.MakeDirectory("dest/Tool");
        fixture.MakeFile("dest/Tool/data.bin", text: "payload");
        Directory.CreateSymbolicLink(source, destination);
        var old = source + ".devduster-old";
        fixture.MakeFile("home/Tool.devduster-old/data.bin", text: "payload");
        Seed(fixture, Record(fixture, RelocationPhase.Switching));

        Make(fixture, new SymlinkJunctions()).Recover();

        Assert.Equal("payload", File.ReadAllText(Path.Combine(destination, "data.bin")));
        Assert.False(Directory.Exists(old));
        var journal = new RelocationJournal(fixture.Folders).Load();
        Assert.Equal(RelocationPhase.Moved, Assert.Single(journal).Phase);
    }

    [Fact]
    public void RecoverMovedClearsRecord()
    {
        using var fixture = new Fixture();
        var source = fixture.MakeDirectory("home/Tool");
        fixture.MakeFile("home/Tool/data.bin", text: "payload");
        Seed(fixture, Record(fixture, RelocationPhase.Moved));

        Make(fixture, new SymlinkJunctions()).Recover();

        Assert.Equal("payload", File.ReadAllText(Path.Combine(source, "data.bin")));
        Assert.Empty(new RelocationJournal(fixture.Folders).Load());
    }

    [Fact]
    public void RecoverCopyingBackDiscardsPartialAndKeepsDestination()
    {
        using var fixture = new Fixture();
        var destination = fixture.MakeDirectory("dest/Tool");
        fixture.MakeFile("dest/Tool/data.bin", text: "payload");
        fixture.MakeFile("home/Tool.devduster-partial/data.bin", text: "partial");
        Seed(fixture, Record(fixture, RelocationPhase.CopyingBack));

        Make(fixture, new SymlinkJunctions()).Recover();

        Assert.Equal("payload", File.ReadAllText(Path.Combine(destination, "data.bin")));
        Assert.False(Directory.Exists(fixture.At("home/Tool.devduster-partial")));
        var journal = new RelocationJournal(fixture.Folders).Load();
        Assert.Equal(RelocationPhase.Moved, Assert.Single(journal).Phase);
    }

    [Fact]
    public void RecoverSwitchingBackClearsRecord()
    {
        using var fixture = new Fixture();
        var source = fixture.MakeDirectory("home/Tool");
        fixture.MakeFile("home/Tool/data.bin", text: "payload");
        Seed(fixture, Record(fixture, RelocationPhase.SwitchingBack));

        Make(fixture, new SymlinkJunctions()).Recover();

        Assert.Equal("payload", File.ReadAllText(Path.Combine(source, "data.bin")));
        Assert.Empty(new RelocationJournal(fixture.Folders).Load());
    }
}