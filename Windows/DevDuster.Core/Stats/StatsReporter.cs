using System.Net.Http.Json;
using System.Text.Json.Serialization;
using DevDuster.Core.Settings;

namespace DevDuster.Core.Stats;

// Sends the anonymous totals behind the devduster.com counter and world map:
// a random install id, the platform, the app version and the lifetime bytes freed. Nothing else.
public sealed class StatsReporter(DusterSettings settings, Action<DusterSettings> save, HttpClient http, string version)
{
    public static readonly Uri Endpoint = new("https://devduster.com/api/report.php");
    public const string Platform = "windows";

    private readonly SemaphoreSlim _gate = new(1, 1);

    public void Enable()
    {
        settings.ShareStatsAsked = true;
        if (settings.ShareStats) return;
        settings.ShareStats = true;
        save(settings);
    }

    // Turning sharing off forgets the install id; the server entry is deleted on the next sync.
    public void Disable()
    {
        settings.ShareStatsAsked = true;
        if (settings.StatsInstallId is { } id) settings.StatsPendingRemovalId = id;
        settings.ShareStats = false;
        settings.StatsInstallId = null;
        settings.StatsLastSentBytes = null;
        save(settings);
    }

    // Removes a pending entry, then reports the lifetime total if sharing is on and it changed.
    public async Task SyncAsync(Func<Task<long>> lifetimeBytes, CancellationToken token = default)
    {
        await _gate.WaitAsync(token);
        try
        {
            if (settings.StatsPendingRemovalId is { } removal)
            {
                if (!await PostAsync(new RemoveBody(removal, true), token)) return;
                settings.StatsPendingRemovalId = null;
                save(settings);
            }
            // On by default, but nothing is sent before the one-time notice has been shown.
            if (!settings.ShareStats || !settings.ShareStatsAsked) return;
            var bytes = Math.Max(await lifetimeBytes(), 0);
            if (settings.StatsInstallId is not null && settings.StatsLastSentBytes == bytes) return;
            var id = settings.StatsInstallId ??= Guid.NewGuid().ToString("D");
            if (!await PostAsync(new ReportBody(id, Platform, version, bytes), token) || settings.StatsInstallId != id) return;
            settings.StatsLastSentBytes = bytes;
            save(settings);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<bool> PostAsync<T>(T body, CancellationToken token)
    {
        try
        {
            using var response = await http.PostAsJsonAsync(Endpoint, body, token);
            return response.IsSuccessStatusCode;
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
        {
            return false;
        }
    }

    private sealed record ReportBody(
        [property: JsonPropertyName("id")] string Id,
        [property: JsonPropertyName("platform")] string Platform,
        [property: JsonPropertyName("version")] string Version,
        [property: JsonPropertyName("freed")] long Freed);

    private sealed record RemoveBody(
        [property: JsonPropertyName("id")] string Id,
        [property: JsonPropertyName("remove")] bool Remove);
}
