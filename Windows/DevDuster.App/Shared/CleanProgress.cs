using CommunityToolkit.Mvvm.ComponentModel;
using DevDuster.Core.Clean;
using DevDuster.Core.Scan;
using Microsoft.UI.Dispatching;

namespace DevDuster.App.Shared;

// A list row that can show it is being deleted right now.
public abstract partial class CleanRow : ObservableObject
{
    [ObservableProperty]
    public partial bool IsDeleting { get; set; }
}

// Tracks a clean run for the footer's progress bar and lets the page update its list as each item finishes.
public sealed partial class CleanProgress : ObservableObject
{
    private static readonly TimeSpan FlushInterval = TimeSpan.FromMilliseconds(150);

    private IReadOnlyList<ScanItem> _items = [];
    private readonly List<CleanResult> _pending = [];
    private DispatcherQueueTimer? _timer;

    // The item now being deleted, or null when none is.
    public event Action<ScanItem?>? Starting;

    // Finished items, batched so a long run of small items doesn't rebuild the list for each one.
    public event Action<IReadOnlyList<CleanResult>>? Finished;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Percent), nameof(Text))]
    public partial bool IsActive { get; private set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Percent), nameof(Text))]
    public partial int Done { get; private set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Text))]
    public partial long FreedBytes { get; private set; }

    public int Total => _items.Count;

    public double Percent => Total == 0 ? 0 : 100.0 * Done / Total;

    public string Text => IsActive
        ? $"Deleting {Math.Min(Done + 1, Total)} of {Total} · {ByteText.Format(FreedBytes)} freed"
        : "";

    public void Begin(IReadOnlyList<ScanItem> items)
    {
        _items = items;
        _pending.Clear();
        FreedBytes = 0;
        Done = 0;
        IsActive = true;
        Starting?.Invoke(items.Count > 0 ? items[0] : null);
    }

    public void Report(CleanResult result)
    {
        if (!IsActive) return;
        FreedBytes += result.FreedBytes;
        Done++;
        _pending.Add(result);
        Starting?.Invoke(Done < Total ? _items[Done] : null);
        ScheduleFlush();
    }

    public void End()
    {
        if (!IsActive) return;
        _timer?.Stop();
        Flush();
        Starting?.Invoke(null);
        IsActive = false;
        _items = [];
    }

    private void ScheduleFlush()
    {
        if (_timer is null)
        {
            _timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
            _timer.Interval = FlushInterval;
            _timer.IsRepeating = false;
            _timer.Tick += (_, _) => Flush();
        }
        if (!_timer.IsRunning) _timer.Start();
    }

    private void Flush()
    {
        if (_pending.Count == 0) return;
        var batch = _pending.ToList();
        _pending.Clear();
        Finished?.Invoke(batch);
    }
}

public static class CleanRows
{
    // Marks the row holding the item now being deleted and clears the rest.
    public static void MarkDeleting<T>(IEnumerable<T> rows, Func<T, bool> holds, ScanItem? item) where T : CleanRow
    {
        foreach (var row in rows)
        {
            var deleting = item is not null && holds(row);
            if (row.IsDeleting != deleting) row.IsDeleting = deleting;
        }
    }
}
