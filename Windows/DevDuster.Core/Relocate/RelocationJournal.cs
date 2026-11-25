using System.Text.Json;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Relocate;

internal sealed class RelocationJournal(UserFolders folders)
{
    private readonly string _path = Path.Combine(folders.DusterData, "relocations.json");

    public IReadOnlyList<Relocation> Load()
    {
        if (!File.Exists(_path)) return [];
        try { return JsonSerializer.Deserialize<List<Relocation>>(File.ReadAllBytes(_path)) ?? []; }
        catch (JsonException error) { throw new RelocationException($"The move journal at {_path} is damaged: {error.Message}"); }
    }

    public void Upsert(Relocation relocation) => Save([.. Others(relocation), relocation]);

    public void Remove(Relocation relocation) => Save([.. Others(relocation)]);

    private IEnumerable<Relocation> Others(Relocation relocation) => Load().Where(other => !PathTools.IsSame(other.Original, relocation.Original));

    private void Save(IReadOnlyList<Relocation> relocations)
    {
        Directory.CreateDirectory(folders.DusterData);
        var staging = _path + ".tmp";
        using (var stream = new FileStream(staging, FileMode.Create, FileAccess.Write))
        {
            JsonSerializer.Serialize(stream, relocations);
            // The journal must be on disk before the step it describes starts.
            stream.Flush(flushToDisk: true);
        }
        File.Move(staging, _path, overwrite: true);
    }
}
