using DevDuster.Core.Clean;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class CleanHistoryTests
{
    private static readonly DateTime Now = new(2026, 11, 25, 12, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void TotalsAndLastCleanedReflectRecords()
    {
        var history = new CleanHistory([new CleanRecord(Now.AddDays(-3), 100), new CleanRecord(Now.AddDays(-1), 250)]);

        Assert.Equal(350, history.TotalBytes);
        Assert.Equal(Now.AddDays(-1), history.LastCleanedUtc);
    }

    [Fact]
    public void EmptyHistoryHasNoLastCleaned()
    {
        var history = new CleanHistory([]);

        Assert.Equal(0, history.TotalBytes);
        Assert.Null(history.LastCleanedUtc);
    }

    [Fact]
    public void BytesSinceCountsOnlyRecordsAtOrAfterCutoff()
    {
        var history = new CleanHistory([new CleanRecord(Now.AddDays(-5), 100), new CleanRecord(Now.AddDays(-1), 200)]);

        Assert.Equal(300, history.BytesSince(Now.AddDays(-10)));
        Assert.Equal(200, history.BytesSince(Now.AddDays(-2)));
    }

    [Fact]
    public void WeeklyTotalsBucketsByMondayWeek()
    {
        var history = new CleanHistory(
        [
            new CleanRecord(Now, 10),
            new CleanRecord(Now.AddDays(-8), 20),
            new CleanRecord(Now.AddDays(-40), 99),
        ]);

        var totals = history.WeeklyTotals(2, Now);

        Assert.Equal(2, totals.Count);
        Assert.Equal(20, totals[0].Bytes);
        Assert.Equal(10, totals[1].Bytes);
        Assert.Equal(DayOfWeek.Monday, totals[1].WeekStart.DayOfWeek);
    }

    [Fact]
    public void WeeklyTotalsForNonPositiveWeeksIsEmpty()
    {
        var history = new CleanHistory([new CleanRecord(Now, 10)]);

        Assert.Empty(history.WeeklyTotals(0, Now));
    }
}