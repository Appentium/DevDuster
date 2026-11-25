namespace DevDuster.App.Shared;

public sealed class ThrottledProgress<T>(Action<T> handler, int minIntervalMs = 100) : IProgress<T>
{
    private readonly Progress<T> _inner = new(handler);
    private long _lastTicks;

    public void Report(T value)
    {
        var now = Environment.TickCount64;
        var last = Volatile.Read(ref _lastTicks);
        if (now - last < minIntervalMs) return;
        if (Interlocked.CompareExchange(ref _lastTicks, now, last) != last) return;
        ((IProgress<T>)_inner).Report(value);
    }
}
