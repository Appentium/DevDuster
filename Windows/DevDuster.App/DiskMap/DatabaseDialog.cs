using DevDuster.App.Shared;
using DevDuster.Core.Clean;
using DevDuster.Core.Explore;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DevDuster.App.DiskMap;

public static class DatabaseDialog
{
    public static async Task ShowAsync(AppServices services, XamlRoot xamlRoot)
    {
        var folders = services.Folders;
        var client = await Task.Run(() => MySqlInspector.FindClient(folders.SystemFolders, folders.SystemDrive ?? @"C:\"));
        if (client is null)
        {
            await ShowMessageAsync(xamlRoot, "No local MySQL or MariaDB installation was found.");
            return;
        }
        var inspector = MySqlInspector.ForClient(client);
        if (await Task.Run(inspector.Databases) is not { } databases)
        {
            await ShowMessageAsync(xamlRoot, "Couldn't connect. Start the server; DevDuster signs in as root on 127.0.0.1 port 3306, without a password or with a login saved by mysql_config_editor.");
            return;
        }
        var selected = await PickAsync(xamlRoot, client, databases);
        if (selected.Count == 0) return;
        var dropped = await Task.Run(() => Drop(services.CleanLog, inspector, selected));
        services.NotifyHistoryChanged();
        var failed = selected.Except(dropped).Select(database => database.Name).ToList();
        var report = $"Dropped {dropped.Count} database(s), about {ByteText.Format(dropped.Sum(database => database.Bytes))} freed.";
        await ShowMessageAsync(xamlRoot, failed.Count == 0 ? report : $"{report}\nFailed: {string.Join(", ", failed)}");
    }

    private static List<MySqlDatabase> Drop(CleanLog log, MySqlInspector inspector, IReadOnlyList<MySqlDatabase> selected)
    {
        var dropped = new List<MySqlDatabase>();
        foreach (var database in selected)
        {
            if (!inspector.Drop(database.Name)) continue;
            dropped.Add(database);
            log.Append(CleanMode.Delete, database.Bytes, $"mysql: {MySqlInspector.DropStatement(database.Name)}");
        }
        if (dropped.Count > 0) inspector.PurgeBinaryLogs();
        return dropped;
    }

    private static async Task<IReadOnlyList<MySqlDatabase>> PickAsync(XamlRoot xamlRoot, string client, IReadOnlyList<MySqlDatabase> databases)
    {
        var list = new ListView { SelectionMode = ListViewSelectionMode.Multiple, MaxHeight = 220 };
        foreach (var database in databases) list.Items.Add($"{database.Name}  ·  {ByteText.Format(database.Bytes)}");
        var statements = new TextBox { IsReadOnly = true, AcceptsReturn = true, MaxHeight = 120, Header = "SQL that will run" };
        var total = new TextBlock();
        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = "MySQL databases",
            PrimaryButtonText = "Drop databases",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            IsPrimaryButtonEnabled = false,
        };
        List<MySqlDatabase> Selected() => [.. list.SelectedRanges
            .SelectMany(range => Enumerable.Range(range.FirstIndex, (int)range.Length))
            .Select(index => databases[index])];
        list.SelectionChanged += (_, _) =>
        {
            var chosen = Selected();
            statements.Text = string.Join('\r', chosen.Select(database => MySqlInspector.DropStatement(database.Name) + ";")
                .Concat(chosen.Count > 0 ? ["PURGE BINARY LOGS BEFORE NOW();"] : []));
            total.Text = $"{chosen.Count} selected · {ByteText.Format(chosen.Sum(database => database.Bytes))}";
            dialog.IsPrimaryButtonEnabled = chosen.Count > 0;
        };

        var panel = new StackPanel { Spacing = 10, MinWidth = 460 };
        if (Insights.CloneSets(databases.Select(database => (database.Name, database.Bytes))).FirstOrDefault() is { } set)
        {
            var names = set.Names.ToHashSet(StringComparer.Ordinal);
            var selectSet = new Button { Content = $"Select clone set ({set.Names.Count} {set.Prefix}*)" };
            selectSet.Click += (_, _) =>
            {
                for (var index = 0; index < databases.Count; index++)
                {
                    if (names.Contains(databases[index].Name)) list.SelectRange(new Microsoft.UI.Xaml.Data.ItemIndexRange(index, 1));
                }
            };
            panel.Children.Add(selectSet);
        }
        panel.Children.Add(new TextBlock { Text = $"Server on 127.0.0.1:3306, using {client}", TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(list);
        panel.Children.Add(total);
        panel.Children.Add(statements);
        panel.Children.Add(new TextBlock
        {
            Text = "Dropped databases and purged binary logs cannot be recovered.",
            Foreground = Ui.ResourceBrush("SystemFillColorCriticalBrush"),
            TextWrapping = TextWrapping.Wrap,
        });
        dialog.Content = panel;
        return await dialog.ShowAsync() == ContentDialogResult.Primary ? Selected() : [];
    }

    private static async Task ShowMessageAsync(XamlRoot xamlRoot, string message)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = "MySQL databases",
            Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
            CloseButtonText = "OK",
        };
        await dialog.ShowAsync();
    }
}
