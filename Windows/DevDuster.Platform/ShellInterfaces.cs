using System.Runtime.InteropServices;

namespace DevDuster.Platform;

[ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IShellItem
{
    void BindToHandler(nint context, in Guid handler, in Guid interfaceId, out nint result);
    void GetParent(out IShellItem parent);
    void GetDisplayName(uint kind, out nint name);
    void GetAttributes(uint mask, out uint attributes);
    void Compare(IShellItem other, uint hint, out int order);
}

[ComImport, Guid("947aab5f-0a5c-4c13-b4d6-4bf7836fc9f8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IFileOperation
{
    void Advise(IFileOperationProgressSink sink, out uint cookie);
    void Unadvise(uint cookie);
    void SetOperationFlags(uint flags);
    void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string message);
    void SetProgressDialog(nint dialog);
    void SetProperties(nint properties);
    void SetOwnerWindow(nint window);
    void ApplyPropertiesToItem(IShellItem item);
    void ApplyPropertiesToItems(nint items);
    void RenameItem(IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, nint sink);
    void RenameItems(nint items, [MarshalAs(UnmanagedType.LPWStr)] string name);
    void MoveItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string? name, nint sink);
    void MoveItems(nint items, IShellItem destination);
    void CopyItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string? name, nint sink);
    void CopyItems(nint items, IShellItem destination);
    void DeleteItem(IShellItem item, IFileOperationProgressSink? sink);
    void DeleteItems(nint items);
    void NewItem(IShellItem folder, uint attributes, [MarshalAs(UnmanagedType.LPWStr)] string name, [MarshalAs(UnmanagedType.LPWStr)] string? template, nint sink);
    void PerformOperations();
    void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool aborted);
}

[ComImport, Guid("3ad05575-8857-4850-9277-11b85bdb8e09")]
internal class FileOperation;

[ComImport, Guid("04b0f1a7-9490-44bc-96e1-4296a31252e2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IFileOperationProgressSink
{
    [PreserveSig] int StartOperations();
    [PreserveSig] int FinishOperations(int result);
    [PreserveSig] int PreRenameItem(uint flags, nint item, nint name);
    [PreserveSig] int PostRenameItem(uint flags, nint item, nint name, int result, nint created);
    [PreserveSig] int PreMoveItem(uint flags, nint item, nint destination, nint name);
    [PreserveSig] int PostMoveItem(uint flags, nint item, nint destination, nint name, int result, nint created);
    [PreserveSig] int PreCopyItem(uint flags, nint item, nint destination, nint name);
    [PreserveSig] int PostCopyItem(uint flags, nint item, nint destination, nint name, int result, nint created);
    [PreserveSig] int PreDeleteItem(uint flags, nint item);
    [PreserveSig] int PostDeleteItem(uint flags, nint item, int result, nint created);
    [PreserveSig] int PreNewItem(uint flags, nint destination, nint name);
    [PreserveSig] int PostNewItem(uint flags, nint destination, nint name, nint template, uint attributes, int result, nint item);
    [PreserveSig] int UpdateProgress(uint total, uint done);
    [PreserveSig] int ResetTimer();
    [PreserveSig] int PauseTimer();
    [PreserveSig] int ResumeTimer();
}
