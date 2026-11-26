using System.Collections.Concurrent;
using DevDuster.Core.Scan;
using Microsoft.UI.Dispatching;

namespace DevDuster.App.Shared;

// Scan threads report here; a UI timer hands the batch to the page, so a fast scan never floods the UI thread.
public sealed class LiveFeed<T> : IProgress<ScanUpdate<T>> where T : class
{
    private static readonly TimeSpan Interval = TimeSpan.FromMilliseconds(250);

    private readonly ConcurrentQueue<T> _found = new();
    private readonly Action<IReadOnlyList<T>, ScanUpdate<T>?> _apply;
    private ScanUpdate<T>? _latest;
    private DispatcherQueueTimer? _timer;

    // Call on the UI thread; apply always runs there.
    public LiveFeed(Action<IReadOnlyList<T>, ScanUpdate<T>?> apply)
    {
        _apply = apply;
        _timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _timer.Interval = Interval;
        _timer.Tick += (_, _) => Drain();
        _timer.Start();
    }

    public void Report(ScanUpdate<T> value)
    {
        if (value.Found is { } item) _found.Enqueue(item);
        _latest = value;
    }

    // Delivers what is left; later reports are ignored.
    public void Stop()
    {
        if (_timer is null) return;
        _timer.Stop();
        _timer = null;
        Drain();
    }

    private void Drain()
    {
        var batch = new List<T>();
        while (_found.TryDequeue(out var item)) batch.Add(item);
        _apply(batch, _latest);
    }
}

// Calls the action on the reporting thread, unlike Progress<T>, which posts every report to the UI.
public sealed class ActionProgress<T>(Action<T> report) : IProgress<T>
{
    public void Report(T value) => report(value);
}
