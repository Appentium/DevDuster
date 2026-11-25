namespace DevDuster.Platform;

internal sealed class RecycleSink : IFileOperationProgressSink
{
    private const uint DeleteRecycleIfPossible = 0x80;
    private const int Ok = 0;
    private const int Abort = unchecked((int)0x80004004);

    public bool WasRefused { get; private set; }
    public bool WasRecycled { get; private set; }
    public int DeleteResult { get; private set; } = Abort;

    public int PreDeleteItem(uint flags, nint item)
    {
        // Without this flag Windows would delete the item for good instead of recycling it.
        if ((flags & DeleteRecycleIfPossible) != 0) return Ok;
        WasRefused = true;
        return Abort;
    }

    public int PostDeleteItem(uint flags, nint item, int result, nint created)
    {
        DeleteResult = result;
        WasRecycled = created != 0;
        return Ok;
    }

    public int StartOperations() => Ok;
    public int FinishOperations(int result) => Ok;
    public int PreRenameItem(uint flags, nint item, nint name) => Ok;
    public int PostRenameItem(uint flags, nint item, nint name, int result, nint created) => Ok;
    public int PreMoveItem(uint flags, nint item, nint destination, nint name) => Ok;
    public int PostMoveItem(uint flags, nint item, nint destination, nint name, int result, nint created) => Ok;
    public int PreCopyItem(uint flags, nint item, nint destination, nint name) => Ok;
    public int PostCopyItem(uint flags, nint item, nint destination, nint name, int result, nint created) => Ok;
    public int PreNewItem(uint flags, nint destination, nint name) => Ok;
    public int PostNewItem(uint flags, nint destination, nint name, nint template, uint attributes, int result, nint item) => Ok;
    public int UpdateProgress(uint total, uint done) => Ok;
    public int ResetTimer() => Ok;
    public int PauseTimer() => Ok;
    public int ResumeTimer() => Ok;
}
