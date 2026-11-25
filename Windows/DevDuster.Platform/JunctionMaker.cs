using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using DevDuster.Core.Relocate;

namespace DevDuster.Platform;

public sealed class JunctionMaker : IJunctionMaker
{
    private const uint MountPointTag = 0xA0000003;
    private const int HeaderSize = 16;

    public void Create(string link, string target)
    {
        if (Path.Exists(link)) throw new IOException($"{link} already exists.");
        Directory.CreateDirectory(link);
        try
        {
            using var handle = NativeMethods.CreateFile(
                link, NativeMethods.GenericWrite, NativeMethods.ShareAll, 0, NativeMethods.OpenExisting,
                NativeMethods.BackupSemantics | NativeMethods.OpenReparsePoint, 0);
            if (handle.IsInvalid) throw LastError(link);
            var buffer = MountPointBuffer(target);
            if (!NativeMethods.DeviceIoControl(handle, NativeMethods.SetReparsePoint, buffer, buffer.Length, 0, 0, out _, 0)) throw LastError(link);
        }
        catch
        {
            Directory.Delete(link, recursive: false);
            throw;
        }
    }

    private static byte[] MountPointBuffer(string target)
    {
        var substitute = Encoding.Unicode.GetBytes(@"\??\" + target);
        var print = Encoding.Unicode.GetBytes(target);
        var buffer = new byte[HeaderSize + substitute.Length + 2 + print.Length + 2];
        using var writer = new BinaryWriter(new MemoryStream(buffer));
        writer.Write(MountPointTag);
        // Everything after the 8-byte tag header counts as data.
        writer.Write((ushort)(buffer.Length - 8));
        writer.Write((ushort)0);
        writer.Write((ushort)0);
        writer.Write((ushort)substitute.Length);
        writer.Write((ushort)(substitute.Length + 2));
        writer.Write((ushort)print.Length);
        writer.Write(substitute);
        writer.Write((ushort)0);
        writer.Write(print);
        return buffer;
    }

    private static IOException LastError(string link) => new($"{link}: {new Win32Exception(Marshal.GetLastPInvokeError()).Message}");
}
