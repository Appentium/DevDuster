using System.Text.Json;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Settings;

public sealed class SettingsStore(UserFolders folders)
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    public DusterSettings Load()
    {
        var path = Path.Combine(folders.DusterData, "settings.json");
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            return JsonSerializer.Deserialize<DusterSettings>(stream, Options) ?? new DusterSettings();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or ArgumentException or NotSupportedException)
        {
            return new DusterSettings();
        }
    }

    public void Save(DusterSettings settings)
    {
        Directory.CreateDirectory(folders.DusterData);
        var temp = Path.Combine(folders.DusterData, $"settings.{Guid.NewGuid():N}.tmp");
        using (var stream = new FileStream(temp, FileMode.Create, FileAccess.Write))
        {
            JsonSerializer.Serialize(stream, settings, Options);
        }
        File.Move(temp, Path.Combine(folders.DusterData, "settings.json"), true);
    }
}
