using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace DevDuster.Platform;

internal static partial class NativeMethods
{
    internal const uint GenericWrite = 0x40000000;
    internal const uint ShareAll = 0x7;
    internal const uint OpenExisting = 3;
    internal const uint BackupSemantics = 0x02000000;
    internal const uint OpenReparsePoint = 0x00200000;
    internal const uint OpenNoRecall = 0x00100000;
    internal const uint SetReparsePoint = 0x000900A4;
    internal const int FileStandardInfo = 1;
    internal const int FileIdInfo = 18;

    [StructLayout(LayoutKind.Sequential)]
    internal struct StandardInfo
    {
        public long AllocationSize;
        public long EndOfFile;
        public uint NumberOfLinks;
        public byte DeletePending;
        public byte Directory;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct IdInfo
    {
        public ulong VolumeSerialNumber;
        public ulong FileIdLow;
        public ulong FileIdHigh;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RecycleBinInfo
    {
        public uint Size;
        public long Bytes;
        public long Items;
    }

    [LibraryImport("kernel32.dll", EntryPoint = "CreateFileW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    internal static partial SafeFileHandle CreateFile(
        string path, uint access, uint share, nint security, uint disposition, uint flags, nint template);

    [LibraryImport("kernel32.dll", EntryPoint = "GetFileInformationByHandleEx", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetStandardInfo(SafeFileHandle file, int infoClass, out StandardInfo info, int size);

    [LibraryImport("kernel32.dll", EntryPoint = "GetFileInformationByHandleEx", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetIdInfo(SafeFileHandle file, int infoClass, out IdInfo info, int size);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool DeviceIoControl(
        SafeFileHandle device, uint code, byte[] input, int inputSize, nint output, int outputSize, out uint returned, nint overlapped);

    [LibraryImport("shell32.dll", EntryPoint = "SHQueryRecycleBinW", StringMarshalling = StringMarshalling.Utf16)]
    internal static partial int QueryRecycleBin(string root, ref RecycleBinInfo info);

    [LibraryImport("shell32.dll", EntryPoint = "SHEmptyRecycleBinW", StringMarshalling = StringMarshalling.Utf16)]
    internal static partial int EmptyRecycleBin(nint window, string root, uint flags);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    internal static extern void SHCreateItemFromParsingName(
        string path, nint bindContext, in Guid interfaceId, out IShellItem item);
}
