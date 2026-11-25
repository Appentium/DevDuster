namespace DevDuster.Core.Clean;

public sealed record WeeklyCleanTotal(DateTime WeekStart, long Bytes);

public sealed class CleanHistory(IReadOnlyList<CleanRecord> records)
{
    public long TotalBytes => records.Sum(record => record.Bytes);

    public DateTime? LastCleanedUtc => records.Count == 0 ? null : records.Max(record => record.DateUtc);

    public long BytesSince(DateTime utc) => records.Where(record => record.DateUtc >= utc).Sum(record => record.Bytes);

    public IReadOnlyList<WeeklyCleanTotal> WeeklyTotals(int weeks, DateTime now)
    {
        if (weeks <= 0) return [];
        var mondayOffset = ((int)now.DayOfWeek + 6) % 7;
        var thisWeek = now.Date.AddDays(-mondayOffset);
        var totals = new List<WeeklyCleanTotal>(weeks);
        for (var offset = weeks - 1; offset >= 0; offset--)
        {
            var start = thisWeek.AddDays(-7 * offset);
            var end = start.AddDays(7);
            var bytes = records.Where(record => record.DateUtc >= start && record.DateUtc < end).Sum(record => record.Bytes);
            totals.Add(new WeeklyCleanTotal(start, bytes));
        }
        return totals;
    }
}
