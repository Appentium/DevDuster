using System.Runtime.InteropServices;

namespace DevDuster.Platform;

public sealed class RecycleBin
{
    private const uint NoConfirmationNoProgressNoSound = 0x7;

    public long BytesOn(string driveRoot)
    {
        var info = new NativeMethods.RecycleBinInfo { Size = (uint)Marshal.SizeOf<NativeMethods.RecycleBinInfo>() };
        return NativeMethods.QueryRecycleBin(driveRoot, ref info) == 0 ? info.Bytes : 0;
    }

    public void Empty(string driveRoot)
    {
        if (string.IsNullOrWhiteSpace(driveRoot)) throw new ArgumentException("A drive is required; an empty root means every drive.", nameof(driveRoot));
        var result = NativeMethods.EmptyRecycleBin(0, driveRoot, NoConfirmationNoProgressNoSound);
        if (result < 0) throw new IOException($"Windows couldn't empty the Recycle Bin on {driveRoot}.");
    }
}
