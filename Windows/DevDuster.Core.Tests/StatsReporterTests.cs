using System.Net;
using System.Text.Json;
using DevDuster.Core.Settings;
using DevDuster.Core.Stats;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class StatsReporterTests
{
    private sealed class FakeHandler : HttpMessageHandler
    {
        public List<JsonElement> Bodies { get; } = [];
        public HttpStatusCode Status { get; set; } = HttpStatusCode.NoContent;
        public bool Fail { get; set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (Fail) throw new HttpRequestException("offline");
            Assert.Equal(HttpMethod.Post, request.Method);
            Assert.Equal(StatsReporter.Endpoint, request.RequestUri);
            Bodies.Add(JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token)).RootElement.Clone());
            return new HttpResponseMessage(Status);
        }
    }

    private static (StatsReporter Reporter, DusterSettings Settings, FakeHandler Handler, Func<int> Saves) Make()
    {
        var settings = new DusterSettings();
        var handler = new FakeHandler();
        var saves = 0;
        var reporter = new StatsReporter(settings, _ => saves++, new HttpClient(handler), "1.2.3");
        return (reporter, settings, handler, () => saves);
    }

    private static Func<Task<long>> Bytes(long value) => () => Task.FromResult(value);

    [Fact]
    public async Task SendsNothingUntilEnabled()
    {
        var (reporter, settings, handler, _) = Make();
        await reporter.SyncAsync(Bytes(500));
        Assert.Empty(handler.Bodies);
        Assert.False(settings.ShareStats);
        Assert.Null(settings.StatsInstallId);
    }

    [Fact]
    public async Task ReportsOnlyTheAllowedFields()
    {
        var (reporter, settings, handler, _) = Make();
        reporter.Enable();
        await reporter.SyncAsync(Bytes(500));

        var body = Assert.Single(handler.Bodies);
        Assert.Equal(["freed", "id", "platform", "version"], body.EnumerateObject().Select(p => p.Name).Order());
        Assert.Equal(settings.StatsInstallId, body.GetProperty("id").GetString());
        Assert.True(Guid.TryParse(settings.StatsInstallId, out _));
        Assert.Equal("windows", body.GetProperty("platform").GetString());
        Assert.Equal("1.2.3", body.GetProperty("version").GetString());
        Assert.Equal(500, body.GetProperty("freed").GetInt64());
        Assert.True(settings.ShareStatsAsked);
    }

    [Fact]
    public async Task SkipsWhenTheTotalHasNotChanged()
    {
        var (reporter, settings, handler, _) = Make();
        reporter.Enable();
        await reporter.SyncAsync(Bytes(500));
        await reporter.SyncAsync(Bytes(500));
        await reporter.SyncAsync(Bytes(900));

        Assert.Equal(2, handler.Bodies.Count);
        Assert.Equal(900, handler.Bodies[1].GetProperty("freed").GetInt64());
        Assert.Equal(handler.Bodies[0].GetProperty("id").GetString(), handler.Bodies[1].GetProperty("id").GetString());
        Assert.Equal(900, settings.StatsLastSentBytes);
    }

    [Fact]
    public async Task RetriesAfterAFailedSend()
    {
        var (reporter, settings, handler, _) = Make();
        reporter.Enable();
        handler.Fail = true;
        await reporter.SyncAsync(Bytes(500));
        Assert.Null(settings.StatsLastSentBytes);

        handler.Fail = false;
        handler.Status = HttpStatusCode.InternalServerError;
        await reporter.SyncAsync(Bytes(500));
        Assert.Null(settings.StatsLastSentBytes);

        handler.Status = HttpStatusCode.NoContent;
        await reporter.SyncAsync(Bytes(500));
        Assert.Equal(500, settings.StatsLastSentBytes);
    }

    [Fact]
    public async Task DisablingDeletesTheServerEntryAndForgetsTheId()
    {
        var (reporter, settings, handler, _) = Make();
        reporter.Enable();
        await reporter.SyncAsync(Bytes(500));
        var id = settings.StatsInstallId;

        reporter.Disable();
        Assert.Null(settings.StatsInstallId);
        Assert.Equal(id, settings.StatsPendingRemovalId);

        handler.Fail = true;
        await reporter.SyncAsync(Bytes(500));
        Assert.Equal(id, settings.StatsPendingRemovalId);

        handler.Fail = false;
        await reporter.SyncAsync(Bytes(500));
        var removal = handler.Bodies[^1];
        Assert.Equal(id, removal.GetProperty("id").GetString());
        Assert.True(removal.GetProperty("remove").GetBoolean());
        Assert.Null(settings.StatsPendingRemovalId);
        Assert.Equal(2, handler.Bodies.Count);
    }

    [Fact]
    public async Task ReEnablingUsesAFreshId()
    {
        var (reporter, settings, handler, _) = Make();
        reporter.Enable();
        await reporter.SyncAsync(Bytes(500));
        var first = settings.StatsInstallId;
        reporter.Disable();
        reporter.Enable();
        await reporter.SyncAsync(Bytes(500));

        Assert.True(handler.Bodies[1].GetProperty("remove").GetBoolean());
        Assert.Equal(first, handler.Bodies[1].GetProperty("id").GetString());
        Assert.NotEqual(first, handler.Bodies[2].GetProperty("id").GetString());
    }

    [Fact]
    public void SharingSettingsRoundTrip()
    {
        using var fixture = new Fixture();
        var store = new SettingsStore(fixture.Folders);
        store.Save(new DusterSettings { ShareStats = true, ShareStatsAsked = true, StatsInstallId = "abc", StatsLastSentBytes = 7 });
        var loaded = store.Load();
        Assert.True(loaded.ShareStats);
        Assert.True(loaded.ShareStatsAsked);
        Assert.Equal("abc", loaded.StatsInstallId);
        Assert.Equal(7, loaded.StatsLastSentBytes);
        Assert.False(new DusterSettings().ShareStats);
    }
}
