using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Core.Relocate;
using DevDuster.Core.Scan;

namespace DevDuster.App.MoveTools;

public sealed partial class MoveTargetViewModel : ObservableObject
{
    public MoveTargetViewModel(RelocationTarget target)
    {
        Target = target;
    }

    public RelocationTarget Target { get; }
    public string Id => Target.Id;
    public string Title => Target.Title;
    public string Path => Target.Path;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SizeText))]
    public partial long? Bytes { get; set; }

    public string SizeText => Bytes is { } b ? ByteText.Format(b) : "Measuring...";
}

public sealed record MoveDriveChoice(LocalDrive Drive)
{
    public string DisplayName =>
        $"{(string.IsNullOrWhiteSpace(Drive.Label) ? Drive.Root : $"{Drive.Label} ({Drive.Root.TrimEnd('\\')})")} · {ByteText.Format(Drive.AvailableBytes)} free ({Drive.Format})";
}

public sealed record MovedToolViewModel(Relocation Relocation)
{
    public string Title => Relocation.Title;
    public string PathsText => $"{Relocation.Original} -> {Relocation.Destination}";
    public string Destination => Relocation.Destination;
    public string SizeText => ByteText.Format(Relocation.Bytes);
    public bool IsConnected => Relocation.IsDestinationConnected();
    public string StatusText => IsConnected ? "Connected" : "Drive missing";
}

public sealed partial class MoveToolsViewModel : ObservableObject
{
    private readonly AppServices _services;
    private CancellationTokenSource? _measureCts;
    private CancellationTokenSource? _moveCts;

    public MoveToolsViewModel(AppServices services)
    {
        _services = services;
        MovableTargets = [];
        BlockedTargets = [];
        MovedTools = [];
        AvailableDrives = [];
        CheckProblems = [];
        CheckNotes = [];
        DestinationPath = "";
        MoveTitle = "";
        SelectedTargetIndex = -1;
        SelectedDriveIndex = -1;
    }

    [ObservableProperty]
    public partial bool IsLoading { get; set; }

    [ObservableProperty]
    public partial bool IsMoving { get; set; }

    [ObservableProperty]
    public partial double MoveProgress { get; set; }

    [ObservableProperty]
    public partial string MoveTitle { get; set; }

    [ObservableProperty]
    public partial string? ResultMessage { get; set; }

    [ObservableProperty]
    public partial string? ErrorMessage { get; set; }

    [ObservableProperty]
    public partial string? LeftoverPath { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<MoveTargetViewModel> MovableTargets { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<RelocationTarget> BlockedTargets { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<MovedToolViewModel> MovedTools { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<MoveDriveChoice> AvailableDrives { get; set; }

    [ObservableProperty]
    public partial int SelectedTargetIndex { get; set; }

    [ObservableProperty]
    public partial int SelectedDriveIndex { get; set; }

    [ObservableProperty]
    public partial string DestinationPath { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<string> CheckProblems { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<string> CheckNotes { get; set; }

    [ObservableProperty]
    public partial bool HasSelection { get; set; }

    [ObservableProperty]
    public partial bool CanMove { get; set; }

    [ObservableProperty]
    public partial bool HasMovedTools { get; set; }

    [ObservableProperty]
    public partial bool HasBlockedTargets { get; set; }

    public MoveTargetViewModel? SelectedTarget =>
        SelectedTargetIndex >= 0 && SelectedTargetIndex < MovableTargets.Count
            ? MovableTargets[SelectedTargetIndex]
            : null;

    public bool IsBusy => IsLoading || IsMoving;

    partial void OnIsLoadingChanged(bool value) => UpdateCanMove();
    partial void OnIsMovingChanged(bool value) => UpdateCanMove();

    partial void OnSelectedTargetIndexChanged(int value)
    {
        var target = SelectedTarget;
        HasSelection = target is not null;
        if (target is null)
        {
            AvailableDrives = [];
            SelectedDriveIndex = -1;
            DestinationPath = "";
            CheckProblems = [];
            CheckNotes = [];
            UpdateCanMove();
            return;
        }
        var sourceDrive = _services.Drives.DriveOf(target.Path);
        AvailableDrives = [.. _services.Drives.Drives()
            .Where(d => d.CanHoldMovedTools && (sourceDrive is null || !PathTools.IsSame(d.Root, sourceDrive.Root)))
            .Select(d => new MoveDriveChoice(d))];
        if (AvailableDrives.Count > 0)
        {
            SelectedDriveIndex = 0;
            DestinationPath = _services.Relocator.SuggestedDestination(target.Target, AvailableDrives[0].Drive);
        }
        else
        {
            SelectedDriveIndex = -1;
            DestinationPath = "";
        }
        RunCheck();
    }

    partial void OnSelectedDriveIndexChanged(int value)
    {
        if (SelectedTarget is not { } target) return;
        if (value < 0 || value >= AvailableDrives.Count) return;
        DestinationPath = _services.Relocator.SuggestedDestination(target.Target, AvailableDrives[value].Drive);
    }

    partial void OnDestinationPathChanged(string value) => RunCheck();

    [RelayCommand]
    public async Task LoadAsync()
    {
        CancelMeasure();
        _measureCts = new CancellationTokenSource();
        var ct = _measureCts.Token;
        IsLoading = true;
        try
        {
            await _services.RecoveryTask;
            if (_services.RecoveryError is { } recoveryError) ErrorMessage = recoveryError;

            var (targets, relocations) = await Task.Run(() =>
                (_services.RelocationCatalog.Targets(), _services.Relocator.Relocations()), ct);
            if (ct.IsCancellationRequested) return;

            MovedTools = [.. relocations.Select(r => new MovedToolViewModel(r))];
            HasMovedTools = MovedTools.Count > 0;
            BlockedTargets = [.. targets.Where(t => t.BlockedReason is not null)];
            HasBlockedTargets = BlockedTargets.Count > 0;
            var movable = targets.Where(t => t.BlockedReason is null).Select(t => new MoveTargetViewModel(t)).ToList();
            MovableTargets = movable;
            SelectedTargetIndex = -1;
            IsLoading = false;

            foreach (var item in movable)
            {
                if (ct.IsCancellationRequested) break;
                var bytes = await Task.Run(() => new SizeCalculator(_services.Measure).AllocatedSize(item.Path, ct), ct);
                item.Bytes = bytes;
                if (ReferenceEquals(item, SelectedTarget)) RunCheck();
            }
            if (!ct.IsCancellationRequested)
            {
                var currentId = SelectedTarget?.Id;
                MovableTargets = [.. movable.OrderByDescending(m => m.Bytes ?? 0)];
                if (currentId is not null)
                {
                    var idx = MovableTargets.ToList().FindIndex(m => m.Id == currentId);
                    SelectedTargetIndex = idx;
                }
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            IsLoading = false;
        }
    }

    public void SetPickedFolder(string folder)
    {
        if (SelectedTarget is not { } target) return;
        DestinationPath = Path.Combine(folder, Path.GetFileName(target.Path));
    }

    public void RunCheck()
    {
        if (SelectedTarget is not { Bytes: { } bytes } target || string.IsNullOrWhiteSpace(DestinationPath))
        {
            CheckProblems = [];
            CheckNotes = [];
            UpdateCanMove();
            return;
        }
        var result = _services.Relocator.Check(target.Target, bytes, DestinationPath);
        CheckProblems = result.Problems;
        CheckNotes = result.Notes;
        UpdateCanMove();
    }

    public async Task MoveSelectedAsync()
    {
        if (SelectedTarget is not { Bytes: { } bytes } target || !CanMove) return;
        await RunMoveAsync($"Moving {target.Title}", async (progress, ct) =>
        {
            var leftover = await _services.Relocator.MoveAsync(target.Target, bytes, DestinationPath, progress, ct);
            LeftoverPath = leftover;
            ResultMessage = $"{target.Title} now lives at {DestinationPath}.";
        });
    }

    public async Task MoveBackAsync(Relocation relocation)
    {
        await RunMoveAsync($"Moving {relocation.Title} back", async (progress, ct) =>
        {
            var leftover = await _services.Relocator.MoveBackAsync(relocation, progress, ct);
            LeftoverPath = leftover;
            ResultMessage = $"{relocation.Title} is back at {relocation.Original}.";
        });
    }

    [RelayCommand]
    public void CancelMove()
    {
        _moveCts?.Cancel();
    }

    public void CancelMeasure()
    {
        _measureCts?.Cancel();
        _measureCts?.Dispose();
        _measureCts = null;
    }

    private async Task RunMoveAsync(string title, Func<IProgress<double>, CancellationToken, Task> work)
    {
        await _services.RecoveryTask;
        _moveCts?.Cancel();
        _moveCts?.Dispose();
        _moveCts = new CancellationTokenSource();
        var ct = _moveCts.Token;

        IsMoving = true;
        MoveTitle = title;
        MoveProgress = 0;
        ResultMessage = null;
        ErrorMessage = null;
        LeftoverPath = null;

        var progress = new ThrottledProgress<double>(value => MoveProgress = value * 100.0, 100);
        try
        {
            await work(progress, ct);
            MoveProgress = 100;
        }
        catch (OperationCanceledException)
        {
            ErrorMessage = "Stopped. Nothing was moved.";
        }
        catch (Exception error)
        {
            ErrorMessage = error.Message;
        }
        finally
        {
            IsMoving = false;
            SelectedTargetIndex = -1;
            await LoadAsync();
        }
    }

    private void UpdateCanMove()
    {
        CanMove = !IsBusy
            && SelectedTarget is { Bytes: not null }
            && !string.IsNullOrWhiteSpace(DestinationPath)
            && CheckProblems.Count == 0;
    }
}
