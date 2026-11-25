using DevDuster.Core.Relocate;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class RelocationJournalTests
{
    private static Relocation Record(Fixture fixture) =>
        new("id", "Title", fixture.At("orig"), fixture.At("dest"), 1_000, new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc), RelocationPhase.Copying);

    [Fact]
    public void SaveThenLoadRoundTrips()
    {
        using var fixture = new Fixture();
        var journal = new RelocationJournal(fixture.Folders);

        journal.Upsert(Record(fixture));

        var loaded = Assert.Single(journal.Load());
        Assert.Equal(Record(fixture), loaded);
    }

    [Fact]
    public void MissingFileLoadsEmpty()
    {
        using var fixture = new Fixture();
        var journal = new RelocationJournal(fixture.Folders);

        Assert.Empty(journal.Load());
    }

    [Fact]
    public void UpsertReplacesSameOriginal()
    {
        using var fixture = new Fixture();
        var journal = new RelocationJournal(fixture.Folders);
        var first = Record(fixture);
        var second = first with { Phase = RelocationPhase.Moved };

        journal.Upsert(first);
        journal.Upsert(second);

        var loaded = Assert.Single(journal.Load());
        Assert.Equal(RelocationPhase.Moved, loaded.Phase);
    }
}