using System.Runtime.InteropServices;
using DevDuster.Core.Clean;
using DevDuster.Core.Scan;

namespace DevDuster.Platform;

public sealed class RecycleBinRemover : IFileRemover
{
    // Silent, no confirmation, no error UI, no connected elements, warn before a permanent delete, recycle on delete, fail early.
    private const uint Flags = 0x0004 | 0x0010 | 0x0400 | 0x2000 | 0x4000 | 0x00080000 | 0x00100000;

    private const string Refused = "Too big for the Recycle Bin, or this drive has none. Nothing was removed.";

    public void Recycle(string path)
    {
        if (!RecycleBinLimit.CanHold(path)) throw new IOException(Refused);
        Exception? failure = null;
        // IFileOperation needs an STA thread, and cleaning runs on the thread pool.
        var thread = new Thread(() =>
        {
            try { RecycleOnSta(path); }
            catch (Exception error) when (error is COMException || PathTools.IsFileError(error)) { failure = error; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null) throw failure as IOException ?? new IOException(failure.Message, failure);
    }

    private static void RecycleOnSta(string path)
    {
        NativeMethods.SHCreateItemFromParsingName(path, 0, typeof(IShellItem).GUID, out var item);
        var operation = (IFileOperation)new FileOperation();
        var sink = new RecycleSink();
        operation.SetOperationFlags(Flags);
        operation.DeleteItem(item, sink);
        COMException? failure = null;
        try { operation.PerformOperations(); }
        catch (COMException error) { failure = error; }
        if (sink.WasRefused) throw new IOException(Refused);
        if (failure is not null) throw new IOException("Windows couldn't recycle it. It may be open in another app.", failure);
        operation.GetAnyOperationsAborted(out var aborted);
        if (aborted || sink.DeleteResult < 0 || PathTools.Exists(path)) throw new IOException("Windows couldn't recycle it. It may be open in another app.");
        if (!sink.WasRecycled) throw new IOException("Windows removed it without using the Recycle Bin.");
    }
}
