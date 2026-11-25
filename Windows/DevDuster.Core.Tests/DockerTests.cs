using DevDuster.Core.Clean;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class DockerTests
{
    [Fact]
    public void BytesInParsesReclaimableAmount()
    {
        Assert.Equal((long?)1_500_000_000, Docker.BytesIn("1.5GB (30%)"));
    }

    [Fact]
    public void BytesInIgnoresText()
    {
        Assert.Null(Docker.BytesIn("none"));
    }
}