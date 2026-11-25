using DevDuster.Core.Clean;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class CleanLogTests
{
    [Fact]
    public void AppendThenReadRoundTrips()
    {
        using var fixture = new Fixture();
        var log = new CleanLog(fixture.At("logs/clean.log"));
        log.Append(CleanMode.Recycle, 1_000, "/a");
        log.Append(CleanMode.Delete, 2_500, "/b");

        var records = log.Records();
        Assert.Equal(new long[] { 1_000, 2_500 }, records.Select(record => record.Bytes).ToArray());
    }
}