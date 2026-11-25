# 常駐：トレイアイコン・トレイメニュー・グローバルホットキー・ジャンプリスト
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:Tray = $null

function Get-CCTaskbarIsLight {
    try { return [bool](Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme') }
    catch { return $false }
}

# タスクバーが明るいときは黒いアイコン、暗いときは白いアイコン
function Get-CCTrayIcon {
    $name = if (Get-CCTaskbarIsLight) { 'tray-dark.ico' } else { 'tray-light.ico' }
    $path = Join-Path $CC.Root "assets\$name"
    if (Test-Path -LiteralPath $path) {
        return [System.Drawing.Icon]::new($path, [System.Windows.Forms.SystemInformation]::SmallIconSize)
    }
    return [System.Drawing.SystemIcons]::Application
}

function ConvertTo-CCHotKey([string]$Text) {
    $mods = 0; $key = $null
    foreach ($part in ($Text -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        switch -Regex ($part) {
            '^(ctrl|control)$' { $mods = $mods -bor 2; continue }
            '^alt$'            { $mods = $mods -bor 1; continue }
            '^shift$'          { $mods = $mods -bor 4; continue }
            '^win$'            { $mods = $mods -bor 8; continue }
            default            { $key = [System.Windows.Input.Key]$part }
        }
    }
    if ($null -eq $key) { throw "ホットキーの指定が読めません: $Text" }
    [pscustomobject]@{ Modifiers = [uint32]$mods; Vk = [uint32][System.Windows.Input.KeyInterop]::VirtualKeyFromKey($key) }
}

# ジャンプリスト（ピン留めアイコンの右クリック）にお気に入りと最近を並べる
function Update-CCJumpList {
    try {
        $cfg = Get-CCConfig
        $jl = [System.Windows.Shell.JumpList]::new()
        $jl.ShowRecentCategory = $false
        $jl.ShowFrequentCategory = $false
        $newTask = {
            param($title, $desc, $argLine, $category)
            $cmd = Get-CCHiddenCommand $argLine
            $t = [System.Windows.Shell.JumpTask]::new()
            $t.Title = $title; $t.Description = $desc
            $t.ApplicationPath = $cmd.Exe; $t.Arguments = $cmd.Args
            $t.IconResourcePath = $CC.AppIcon; $t.IconResourceIndex = 0
            $t.WorkingDirectory = $CC.Root
            if ($category) { $t.CustomCategory = $category }
            $jl.JumpItems.Add($t)
        }
        foreach ($f in $cfg.favorites) {
            & $newTask (Get-CCDisplayName $f.path $f.name) $f.path ('-Open {0}' -f (ConvertTo-CCArgPath $f.path)) 'お気に入り'
        }
        $recent = @($cfg.recent | Where-Object { -not (Test-CCFavorite $cfg $_.path) } | Select-Object -First 8)
        foreach ($r in $recent) {
            & $newTask (Get-CCDisplayName $r.path) $r.path ('-Open {0}' -f (ConvertTo-CCArgPath $r.path)) '最近'
        }
        & $newTask 'ランチャーを開く' 'フォルダを選んで Claude Code を開く' '-Show' $null
        [System.Windows.Shell.JumpList]::SetJumpList([System.Windows.Application]::Current, $jl)
        $jl.Apply()
    } catch {
        Write-CCLog "ジャンプリストを更新できませんでした: $_"
    }
}

function Update-CCFavoritesMenu($Parent) {
    $Parent.DropDownItems.Clear()
    $cfg = Get-CCConfig
    if (@($cfg.favorites).Count -eq 0) {
        $empty = [System.Windows.Forms.ToolStripMenuItem]::new('（まだありません。パネルで Ctrl+D）')
        $empty.Enabled = $false
        [void]$Parent.DropDownItems.Add($empty)
        return
    }
    foreach ($f in $cfg.favorites) {
        $mi = [System.Windows.Forms.ToolStripMenuItem]::new((Get-CCDisplayName $f.path $f.name))
        $mi.ToolTipText = $f.path
        $mi.Tag = $f.path
        $mi.add_Click({ param($s, $e)
            try { [void](Invoke-CCLaunch -Path $s.Tag -Mode 'new'); Update-CCJumpList }
            catch { Show-CCTrayBalloon $_.Exception.Message }
        })
        [void]$Parent.DropDownItems.Add($mi)
    }
}

function Show-CCTrayBalloon([string]$Text) {
    if ($script:Tray -and $script:Tray.Icon) {
        $script:Tray.Icon.ShowBalloonTip(5000, $CC.AppName, $Text, [System.Windows.Forms.ToolTipIcon]::Warning)
    }
}

function New-CCTrayMenu {
    $menu = [System.Windows.Forms.ContextMenuStrip]::new()
    $open = [System.Windows.Forms.ToolStripMenuItem]::new('ランチャーを開く')
    $open.Font = [System.Drawing.Font]::new($open.Font, [System.Drawing.FontStyle]::Bold)
    $open.add_Click({ Show-CCPanel -KeepText })
    $favs = [System.Windows.Forms.ToolStripMenuItem]::new('お気に入り')
    $config = [System.Windows.Forms.ToolStripMenuItem]::new('設定ファイルを開く')
    $config.add_Click({ if (-not (Test-Path $CC.ConfigPath)) { [void](Update-CCConfig { }) }; Invoke-Item -LiteralPath $CC.ConfigPath })
    $startup = [System.Windows.Forms.ToolStripMenuItem]::new('ログオン時に起動')
    $startup.add_Click({
        $lnk = Get-CCStartupShortcutPath
        if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
        else { New-CCShortcut -LnkPath $lnk -Arguments '-Resident' }
    })
    $quit = [System.Windows.Forms.ToolStripMenuItem]::new('終了')
    $quit.add_Click({ Stop-CCResident })

    [void]$menu.Items.Add($open)
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    [void]$menu.Items.Add($favs)
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    [void]$menu.Items.Add($config)
    [void]$menu.Items.Add($startup)
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    [void]$menu.Items.Add($quit)

    $menu.Tag = @{ Favorites = $favs; Startup = $startup }
    $menu.add_Opening({ param($s, $e)
        Hide-CCPanel
        Update-CCFavoritesMenu $s.Tag.Favorites
        $s.Tag.Startup.Checked = Test-Path -LiteralPath (Get-CCStartupShortcutPath)
    })
    return $menu
}

function Stop-CCResident {
    if ($script:Tray) {
        if ($script:Tray.Icon) { $script:Tray.Icon.Visible = $false; $script:Tray.Icon.Dispose() }
        if ($script:Tray.HotKey) { $script:Tray.HotKey.Dispose() }
        if ($script:Tray.Timer) { $script:Tray.Timer.Stop() }
    }
    Write-CCLog 'resident stop'
    [System.Windows.Application]::Current.Shutdown()
}

function Start-CCResident([switch]$ShowOnStart) {
    Write-CCLog 'resident start'
    [CCLauncher.Native]::SetAppId($CC.AppId)

    $app = [System.Windows.Application]::new()
    $app.ThemeMode = [System.Windows.ThemeMode]::System   # Windows 11 の Fluent スタイル（ライト/ダーク自動）
    $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown

    Initialize-CCPanel -OnChanged { Update-CCJumpList }

    $T = @{ Icon = $null; HotKey = $null; Timer = $null; Show = $null; Quit = $null; LightTaskbar = (Get-CCTaskbarIsLight); ConfigStamp = $null }
    $script:Tray = $T

    $icon = [System.Windows.Forms.NotifyIcon]::new()
    $icon.Icon = Get-CCTrayIcon
    $icon.Text = $CC.AppName
    $icon.ContextMenuStrip = New-CCTrayMenu
    $icon.add_MouseClick({ param($s, $e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Switch-CCPanel } })
    $icon.Visible = $true
    $T.Icon = $icon

    # 別プロセス（ピン留めアイコン・スタートメニュー）からの合図
    $T.Show = [CCLauncher.Signal]::new($CC.ShowSignal)
    $T.Show.add_Fired({ try { Show-CCPanel -KeepText -Prefill (Get-CCPendingPath) } catch { Write-CCLog "ERROR show: $_ $($_.ScriptStackTrace)" } })
    $T.Quit = [CCLauncher.Signal]::new($CC.QuitSignal)
    $T.Quit.add_Fired({ Stop-CCResident })

    # グローバルホットキー
    $hotkeyText = (Get-CCConfig).hotkey
    try {
        $hk = ConvertTo-CCHotKey $hotkeyText
        $T.HotKey = [CCLauncher.HotKey]::new($hk.Modifiers, $hk.Vk)
        if ($T.HotKey.Registered) {
            $T.HotKey.add_Pressed({ Switch-CCPanel })
            $icon.Text = "$($CC.AppName) ($hotkeyText)"
        } else {
            Show-CCTrayBalloon "ホットキー $hotkeyText はほかのアプリが使っているため登録できませんでした。config.json の hotkey を変えてください。"
        }
    } catch { Show-CCTrayBalloon $_.Exception.Message }

    # 30 秒ごと：テーマの変化でトレイアイコンを替え、右クリック起動などで履歴が変わったらジャンプリストを更新
    $T.Timer = [System.Windows.Threading.DispatcherTimer]::new()
    $T.Timer.Interval = [TimeSpan]::FromSeconds(30)
    $T.Timer.add_Tick({
        $T = $script:Tray
        $light = Get-CCTaskbarIsLight
        if ($light -ne $T.LightTaskbar) { $T.LightTaskbar = $light; $T.Icon.Icon = Get-CCTrayIcon }
        $stamp = if (Test-Path $CC.ConfigPath) { (Get-Item $CC.ConfigPath).LastWriteTimeUtc } else { $null }
        if ($stamp -ne $T.ConfigStamp) { $T.ConfigStamp = $stamp; Update-CCJumpList }
    })
    $T.Timer.Start()
    $T.ConfigStamp = if (Test-Path $CC.ConfigPath) { (Get-Item $CC.ConfigPath).LastWriteTimeUtc } else { $null }

    Update-CCJumpList
    if ($ShowOnStart) { Show-CCPanel -Prefill (Get-CCPendingPath) }
    try { [void]$app.Run() }
    finally {
        try { if ($T.Icon) { $T.Icon.Visible = $false; $T.Icon.Dispose() } } catch { }
    }
}
