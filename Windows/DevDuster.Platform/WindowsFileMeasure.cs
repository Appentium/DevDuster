using System.Runtime.InteropServices;
using DevDuster.Core.Scan;

namespace DevDuster.Platform;

public sealed class WindowsFileMeasure : IFileMeasure
{
    public FileMeasure Measure(FileInfo file)
    {
        // Zero access reads sizes of locked files too, and never downloads a cloud file.
        using var handle = NativeMethods.CreateFile(
            file.FullName, 0, NativeMethods.ShareAll, 0, NativeMethods.OpenExisting,
            NativeMethods.OpenReparsePoint | NativeMethods.OpenNoRecall, 0);
        if (handle.IsInvalid || !NativeMethods.GetStandardInfo(handle, NativeMethods.FileStandardInfo, out var info, Marshal.SizeOf<NativeMethods.StandardInfo>()))
        {
            return new FileMeasure(LengthOf(file), null);
        }
        if (info.NumberOfLinks <= 1 || !NativeMethods.GetIdInfo(handle, NativeMethods.FileIdInfo, out var id, Marshal.SizeOf<NativeMethods.IdInfo>()))
        {
            return new FileMeasure(info.AllocationSize, null);
        }
        return new FileMeasure(info.AllocationSize, $"{id.VolumeSerialNumber:x}:{id.FileIdHigh:x}:{id.FileIdLow:x}");
    }

    private static long LengthOf(FileInfo file)
    {
        try { return file.Length; }
        catch (IOException) { return 0; }
    }
}
