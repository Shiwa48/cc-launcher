# ランチャーパネル（Spotlight 風）の動作
# 前提：Application.ThemeMode を設定済みであること（Fluent のスタイルを StaticResource で参照するため）

$script:Panel = $null
$script:CCGlyph = @{ folder = [string][char]0xE8B7; star = [string][char]0xE735; clock = [string][char]0xE823; paste = [string][char]0xE77F }

function Get-CCRelativeTime([string]$Iso) {
    try { $t = [datetime]::Parse($Iso, $null, [Globalization.DateTimeStyles]::RoundtripKind) } catch { return '' }
    $d = (Get-Date) - $t.ToLocalTime()
    if ($d.TotalMinutes -lt 1) { return 'たった今' }
    if ($d.TotalHours -lt 1) { return '{0}分前' -f [int][math]::Floor($d.TotalMinutes) }
    if ($d.TotalDays -lt 1) { return '{0}時間前' -f [int][math]::Floor($d.TotalHours) }
    if ($d.TotalDays -lt 7) { return '{0}日前' -f [int][math]::Floor($d.TotalDays) }
    return $t.ToLocalTime().ToString('M/d')
}

# 長いパスは先頭と末尾を残して中央を省略する
function Format-CCMiddlePath([string]$Path, [int]$Max = 64) {
    if ($Path.Length -le $Max) { return $Path }
    $head = [IO.Path]::GetPathRoot($Path)
    $tailLen = $Max - $head.Length - 1
    return $head + '…' + $Path.Substring($Path.Length - $tailLen)
}

# 検索語との一致度（0 = 一致しない）
function Get-CCMatchScore([string]$Query, [string]$Name, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Query)) { return 1 }
    $total = 0
    foreach ($tok in ($Query.ToLowerInvariant() -split '\s+' | Where-Object { $_ })) {
        $n = $Name.ToLowerInvariant(); $p = $Path.ToLowerInvariant()
        $i = $n.IndexOf($tok)
        if ($i -eq 0) { $total += 100 }
        elseif ($i -gt 0) { $total += 80 - [math]::Min($i, 30) }
        elseif ($p.Contains($tok)) { $total += 40 }
        else {
            # フォルダ名に文字が順番どおりに含まれていれば弱く一致（例: ccl → cc-launcher）
            $k = 0
            foreach ($ch in $n.ToCharArray()) { if ($k -lt $tok.Length -and $ch -eq $tok[$k]) { $k++ } }
            if ($k -eq $tok.Length) { $total += 15 } else { return 0 }
        }
    }
    return $total
}

function Get-CCClipboardFolder {
    try {
        if ([System.Windows.Clipboard]::ContainsFileDropList()) {
            foreach ($f in [System.Windows.Clipboard]::GetFileDropList()) {
                if (Test-Path -LiteralPath $f -PathType Container) { return (ConvertTo-CCNormalPath $f) }
            }
        }
        if ([System.Windows.Clipboard]::ContainsText()) {
            $t = [System.Windows.Clipboard]::GetText().Trim()
            if ($t -and $t.Length -lt 400 -and $t -notmatch "[`r`n]") {
                $p = ConvertTo-CCNormalPath $t
                if ($p -and (Test-Path -LiteralPath $p -PathType Container)) { return $p }
            }
        }
    } catch { }
    return $null
}

function New-CCItem([string]$Kind, [string]$Group, [string]$Path, [string]$Name, [string]$Meta, [string]$Glyph, [bool]$Fav, [double]$Score) {
    $it = [CCLauncher.Item]::new()
    $it.Kind = $Kind; $it.Group = $Group; $it.Path = $Path
    $it.Name = Get-CCDisplayName $Path $Name
    $it.DisplayPath = Format-CCMiddlePath $Path
    $it.Meta = $Meta; $it.Glyph = $Glyph; $it.IsFavorite = $Fav; $it.Score = $Score
    return $it
}

function Test-CCLooksLikePath([string]$Text) {
    $Text -match '^\s*"?([a-zA-Z]:|\\\\|~|%|\.{1,2}\\)'
}

# 候補リストを作り直す。$SelectPath を渡すとその行を選ぶ
function Update-CCPanelList([string]$SelectPath) {
    $P = $script:Panel
    $cfg = $P.Config
    $q = $P.Search.Text.Trim()
    $items = [Collections.Generic.List[CCLauncher.Item]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    # 入力されたパス、または（未入力なら）クリップボードのパス
    if (Test-CCLooksLikePath $q) {
        $tp = ConvertTo-CCNormalPath $q
        if ($tp -and (Test-Path -LiteralPath $tp -PathType Container)) {
            $items.Add((New-CCItem 'typed' '入力したパス' $tp $null '' $CCGlyph.folder (Test-CCFavorite $cfg $tp) 1000))
            [void]$seen.Add($tp)
        }
    } elseif (-not $q) {
        $cp = Get-CCClipboardFolder
        if ($cp) {
            $items.Add((New-CCItem 'clipboard' 'クリップボード' $cp $null '' $CCGlyph.paste (Test-CCFavorite $cfg $cp) 1000))
            [void]$seen.Add($cp)
        }
    }
    $pathQuery = Test-CCLooksLikePath $q
    $filterQ = if ($pathQuery) { '' } else { $q }

    $favs = foreach ($f in $cfg.favorites) {
        $s = Get-CCMatchScore $filterQ (Get-CCDisplayName $f.path $f.name) $f.path
        if ($s -gt 0 -and -not $seen.Contains($f.path)) {
            [void]$seen.Add($f.path)
            New-CCItem 'favorite' 'お気に入り' $f.path $f.name '' $CCGlyph.star $true $s
        }
    }
    $recents = foreach ($r in $cfg.recent) {
        $s = Get-CCMatchScore $filterQ (Get-CCDisplayName $r.path) $r.path
        if ($s -gt 0 -and -not $seen.Contains($r.path)) {
            [void]$seen.Add($r.path)
            New-CCItem 'recent' '最近' $r.path $null (Get-CCRelativeTime $r.lastUsed) $CCGlyph.clock $false $s
        }
    }
    if ($filterQ) {
        $favs = $favs | Sort-Object -Property Score -Descending -Stable
        $recents = $recents | Sort-Object -Property Score -Descending -Stable
    }
    foreach ($i in @($favs) + @($recents)) { if ($i) { $items.Add($i) } }

    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($items)
    $view.GroupDescriptions.Clear()
    $view.GroupDescriptions.Add([System.Windows.Data.PropertyGroupDescription]::new('Group'))
    $P.Items = $items
    $P.List.ItemsSource = $view

    if ($items.Count -eq 0) {
        $P.Empty.Text = if ($q) { "「$q」に一致するフォルダはありません。`nフォルダのパスを入力するか、Ctrl+O でフォルダを選んでください。" }
                        else { "まだ履歴がありません。`nフォルダのパスを貼り付けるか、Ctrl+O でフォルダを選んでください。" }
        $P.Empty.Visibility = 'Visible'
        $P.List.Visibility = 'Collapsed'
    } else {
        $P.Empty.Visibility = 'Collapsed'
        $P.List.Visibility = 'Visible'
        $idx = 0
        if ($SelectPath) {
            for ($i = 0; $i -lt $items.Count; $i++) { if (Test-CCSamePath $items[$i].Path $SelectPath) { $idx = $i; break } }
        }
        $P.List.SelectedIndex = $idx
        $P.List.ScrollIntoView($P.List.SelectedItem)
    }
    Update-CCPanelButtons
}

function Update-CCPanelButtons {
    $P = $script:Panel
    $has = $null -ne $P.List.SelectedItem
    foreach ($b in $P.NewButton, $P.ContinueButton, $P.ResumeButton) { $b.IsEnabled = $has }
    $P.ClearButton.Visibility = if ($P.Search.Text) { 'Visible' } else { 'Collapsed' }
    $P.Placeholder.Visibility = if ($P.Search.Text) { 'Collapsed' } else { 'Visible' }
}

function Show-CCPanelMessage([string]$Text, [string]$ActionLabel, [scriptblock]$Action) {
    $P = $script:Panel
    $P.MessageText.Text = $Text
    $P.MessageAction.Visibility = if ($ActionLabel) { 'Visible' } else { 'Collapsed' }
    $P.MessageAction.Content = $ActionLabel
    $P.MessageCallback = $Action
    $P.MessageBar.Visibility = 'Visible'
}

function Hide-CCPanelMessage { $script:Panel.MessageBar.Visibility = 'Collapsed'; $script:Panel.MessageCallback = $null }

function Invoke-CCPanelLaunch([string]$Mode = 'new', [CCLauncher.Item]$Item) {
    $P = $script:Panel
    if (-not $Item) { $Item = $P.List.SelectedItem }
    if (-not $Item) { [System.Media.SystemSounds]::Beep.Play(); return }
    $path = $Item.Path
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $P.MessageData = $Item
        Show-CCPanelMessage "フォルダが見つかりません：$path" $(if ($Item.Kind -in 'recent', 'favorite') { '一覧から消す' }) {
            $it = $script:Panel.MessageData
            if ($it.Kind -eq 'favorite') { [void](Switch-CCFavorite $it.Path) } else { Remove-CCRecent $it.Path }
            Hide-CCPanelMessage
            Invoke-CCPanelReload
        }
        return
    }
    try {
        [void](Invoke-CCLaunch -Path $path -Mode $Mode)
    } catch {
        Show-CCPanelMessage $_.Exception.Message $null $null
        return
    }
    $P.Search.Text = ''
    Hide-CCPanel
    if ($P.OnChanged) { & $P.OnChanged }
}

function Invoke-CCPanelReload([string]$SelectPath) {
    $script:Panel.Config = Get-CCConfig
    Update-CCPanelList $SelectPath
    if ($script:Panel.OnChanged) { & $script:Panel.OnChanged }
}

function Switch-CCPanelFavorite([CCLauncher.Item]$Item) {
    if (-not $Item) { $Item = $script:Panel.List.SelectedItem }
    if (-not $Item) { return }
    [void](Switch-CCFavorite $Item.Path)
    Invoke-CCPanelReload $Item.Path
}

function Remove-CCPanelRecent([CCLauncher.Item]$Item) {
    if (-not $Item) { $Item = $script:Panel.List.SelectedItem }
    if (-not $Item -or $Item.Kind -ne 'recent') { return }
    $list = $script:Panel.Items
    $i = $list.IndexOf($Item)
    $next = if ($i + 1 -lt $list.Count) { $list[$i + 1].Path } elseif ($i -gt 0) { $list[$i - 1].Path } else { $null }
    Remove-CCRecent $Item.Path
    Invoke-CCPanelReload $next
}

function Invoke-CCPanelBrowse {
    $P = $script:Panel
    $dlg = [Microsoft.Win32.OpenFolderDialog]::new()
    $dlg.Title = 'Claude Code を開くフォルダを選ぶ'
    $sel = $P.List.SelectedItem
    if ($sel -and (Test-Path -LiteralPath $sel.Path)) { $dlg.InitialDirectory = $sel.Path }
    $P.SuppressHide = $true
    try { $ok = $dlg.ShowDialog($P.Win) } finally { $P.SuppressHide = $false }
    Show-CCPanel -KeepText
    if ($ok) {
        # 選んだフォルダを「入力したパス」として出し、起動方法（Enter / Ctrl+Enter / Shift+Enter）を選べるようにする
        $P.Search.Text = $dlg.FolderName
        $P.Search.CaretIndex = $P.Search.Text.Length
    }
}

function Move-CCPanelSelection([int]$Delta) {
    $L = $script:Panel.List
    if ($L.Items.Count -eq 0) { return }
    $L.SelectedIndex = [math]::Max(0, [math]::Min($L.Items.Count - 1, $L.SelectedIndex + $Delta))
    $L.ScrollIntoView($L.SelectedItem)
}

function Set-CCPanelPosition {
    $w = $script:Panel.Win
    $wa = [System.Windows.SystemParameters]::WorkArea
    $w.Left = $wa.Right - $w.ActualWidth - 12
    $w.Top = $wa.Bottom - $w.ActualHeight - 12
}

function Show-CCPanel([switch]$KeepText, [string]$Prefill) {
    $P = $script:Panel
    if (-not $KeepText) { Hide-CCPanelMessage }
    $P.Config = Get-CCConfig
    if ($Prefill) { $P.Search.Text = $Prefill }
    Update-CCPanelList
    if ($Prefill) { $P.Search.CaretIndex = $P.Search.Text.Length } else { $P.Search.SelectAll() }
    if (-not $P.Win.IsVisible) { $P.Win.Show() }
    Set-CCPanelPosition
    $P.Win.Activate() | Out-Null
    $fgOk = [CCLauncher.Native]::ForceForeground([System.Windows.Interop.WindowInteropHelper]::new($P.Win).Handle)
    Write-CCLog "panel show (foreground=$fgOk, prefill=$([bool]$Prefill))"
    [void]$P.Search.Focus()
}

function Hide-CCPanel {
    $P = $script:Panel
    if ($P.Win.IsVisible) {
        $P.Win.Hide()
        $P.LastHidden = [datetime]::UtcNow
    }
}

# トレイのクリック用：開いていれば閉じる。直前にフォーカスが外れて閉じた場合は開き直さない
function Switch-CCPanel {
    $P = $script:Panel
    if ($P.Win.IsVisible) { Hide-CCPanel; return }
    if (([datetime]::UtcNow - $P.LastHidden).TotalMilliseconds -lt 300) { return }
    Show-CCPanel -KeepText
}

function New-CCRowContextMenu([CCLauncher.Item]$Item) {
    $m = [System.Windows.Controls.ContextMenu]::new()
    $entries = @(
        @('新規で開く', 'new'), @('続きから', 'continue'), @('選んで再開', 'resume'), $null,
        @($(if ($Item.IsFavorite) { 'お気に入りから外す' } else { 'お気に入りに追加' }), 'fav'),
        @('エクスプローラーで開く', 'explorer')
    )
    if ($Item.Kind -eq 'recent') { $entries += $null; $entries += , @('履歴から削除', 'remove') }
    foreach ($en in $entries) {
        if ($null -eq $en) { [void]$m.Items.Add([System.Windows.Controls.Separator]::new()); continue }
        $mi = [System.Windows.Controls.MenuItem]::new()
        $mi.Header = $en[0]
        $mi.Tag = @{ Action = $en[1]; Item = $Item }
        $mi.add_Click({ param($s, $e) Invoke-CCRowAction $s.Tag.Action $s.Tag.Item })
        [void]$m.Items.Add($mi)
    }
    return $m
}

function Invoke-CCRowAction([string]$Action, [CCLauncher.Item]$Item) {
    switch ($Action) {
        { $_ -in 'new', 'continue', 'resume' } { Invoke-CCPanelLaunch $Action $Item }
        'fav'      { Switch-CCPanelFavorite $Item }
        'explorer' { Start-Process explorer.exe -ArgumentList "`"$($Item.Path)`""; Hide-CCPanel }
        'remove'   { Remove-CCPanelRecent $Item }
    }
}

function Initialize-CCPanel([scriptblock]$OnChanged) {
    $xamlPath = Join-Path $CC.Root 'ui\Panel.xaml'
    $win = [System.Windows.Markup.XamlReader]::Parse((Get-Content -LiteralPath $xamlPath -Raw -Encoding utf8))
    $P = @{ Win = $win; Config = $null; Items = $null; LastHidden = [datetime]::MinValue; SuppressHide = $false; OnChanged = $OnChanged; MessageCallback = $null; MessageData = $null }
    foreach ($n in 'Search', 'Placeholder', 'ClearButton', 'List', 'Empty', 'MessageBar', 'MessageText', 'MessageAction',
                   'BrowseButton', 'NewButton', 'ContinueButton', 'ResumeButton', 'Hint') {
        $P[$n] = $win.FindName($n)
    }
    $script:Panel = $P

    # Windows 11 の角丸（DWM）
    $win.add_SourceInitialized({ [CCLauncher.Native]::SetRoundCorners([System.Windows.Interop.WindowInteropHelper]::new($script:Panel.Win).Handle) })

    # 外側をクリックしたら閉じる（入力中の文字は残す）
    $win.add_Deactivated({ if (-not $script:Panel.SuppressHide) { Hide-CCPanel } })
    $win.add_Closing({ param($s, $e) $e.Cancel = $true; Hide-CCPanel })
    $win.add_SizeChanged({ if ($script:Panel.Win.IsVisible) { Set-CCPanelPosition } })

    $P.Search.add_TextChanged({ Hide-CCPanelMessage; Update-CCPanelList })
    $P.ClearButton.add_Click({ $script:Panel.Search.Text = ''; [void]$script:Panel.Search.Focus() })
    $P.List.add_SelectionChanged({ Update-CCPanelButtons })
    $P.List.add_MouseDoubleClick({ param($s, $e)
        if ($e.OriginalSource -is [System.Windows.FrameworkElement] -and $e.OriginalSource.DataContext -is [CCLauncher.Item]) { Invoke-CCPanelLaunch 'new' }
    })
    # 行の右クリック：その行を選んでからメニューを出す
    $P.List.add_PreviewMouseRightButtonDown({ param($s, $e)
        $dc = if ($e.OriginalSource -is [System.Windows.FrameworkElement]) { $e.OriginalSource.DataContext }
        if ($dc -is [CCLauncher.Item]) {
            $script:Panel.List.SelectedItem = $dc
            $script:Panel.List.ContextMenu = New-CCRowContextMenu $dc
        } else { $script:Panel.List.ContextMenu = $null }
    })
    $P.MessageAction.add_Click({ if ($script:Panel.MessageCallback) { & $script:Panel.MessageCallback } })
    $P.BrowseButton.add_Click({ Invoke-CCPanelBrowse })
    $P.NewButton.add_Click({ Invoke-CCPanelLaunch 'new' })
    $P.ContinueButton.add_Click({ Invoke-CCPanelLaunch 'continue' })
    $P.ResumeButton.add_Click({ Invoke-CCPanelLaunch 'resume' })

    $win.add_PreviewKeyDown({ param($s, $e)
        $K = [System.Windows.Input.Key]
        $mods = [System.Windows.Input.Keyboard]::Modifiers
        $ctrl = $mods.HasFlag([System.Windows.Input.ModifierKeys]::Control)
        $shift = $mods.HasFlag([System.Windows.Input.ModifierKeys]::Shift)
        $alt = $mods.HasFlag([System.Windows.Input.ModifierKeys]::Alt)
        $key = if ($e.Key -eq $K::System) { $e.SystemKey } else { $e.Key }
        $P = $script:Panel
        $sel = $P.List.SelectedItem
        switch ($key) {
            { $_ -in $K::Up, $K::Down } {
                $d = if ($key -eq $K::Up) { -1 } else { 1 }
                if ($alt) {
                    if ($sel -and $sel.Kind -eq 'favorite') { Move-CCFavorite $sel.Path $d; Invoke-CCPanelReload $sel.Path }
                } else { Move-CCPanelSelection $d }
                $e.Handled = $true; break
            }
            $K::PageUp   { Move-CCPanelSelection -8; $e.Handled = $true; break }
            $K::PageDown { Move-CCPanelSelection 8; $e.Handled = $true; break }
            $K::Enter {
                $mode = if ($ctrl) { 'continue' } elseif ($shift) { 'resume' } else { 'new' }
                Invoke-CCPanelLaunch $mode; $e.Handled = $true; break
            }
            $K::Escape {
                if ($P.MessageBar.Visibility -eq 'Visible') { Hide-CCPanelMessage }
                elseif ($P.Search.Text) { $P.Search.Text = '' }
                else { Hide-CCPanel }
                $e.Handled = $true; break
            }
            $K::D { if ($ctrl) { Switch-CCPanelFavorite; $e.Handled = $true }; break }
            $K::O { if ($ctrl) { Invoke-CCPanelBrowse; $e.Handled = $true }; break }
            $K::Delete {
                # 検索欄が空のときだけ、選んだ履歴を消す（文字の削除と区別するため）
                if (-not $P.Search.Text -and $sel -and $sel.Kind -eq 'recent') { Remove-CCPanelRecent; $e.Handled = $true }
                break
            }
        }
    })
}
