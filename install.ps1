<#
.SYNOPSIS
  Claude Code Launcher を登録する（何度実行しても同じ状態になる）。
  - スタートメニューにショートカットを作る（右クリックで「タスクバーにピン留め」できる）
  - ログオン時に常駐するように登録する
  - エクスプローラーの「送る」に「Claude Code」を追加する
  レジストリは一切書き換えない（置くのはショートカットと設定ファイルだけ）。
  - 常駐を開始する
#>
[CmdletBinding()]
param(
    [switch]$NoStartup,      # ログオン時の自動起動を登録しない
    [switch]$NoSendTo,       # 「送る」メニューに追加しない
    [switch]$NoStart         # 常駐を今すぐ開始しない
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\Store.ps1')

if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) { Write-Warning 'Windows Terminal (wt.exe) が見つかりません。起動にはWindows Terminalが必要です。' }
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Warning 'claude コマンドが見つかりません。Claude Code をインストールしてください。' }

# 1. アイコンとネイティブ部品
if (-not (Test-Path -LiteralPath $CC.AppIcon)) {
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'assets\make-icons.ps1') | Out-Null
}
Import-CCNative

# 2. 設定ファイル（無ければ既定値で作る）
if (-not (Test-Path -LiteralPath $CC.ConfigPath)) { [void](Update-CCConfig { }) }
Write-Host "設定ファイル: $($CC.ConfigPath)"

# 3. スタートメニュー（ピン留め用。ジャンプリストと結び付けるため AppUserModelID を付ける）
$startMenu = Get-CCStartMenuShortcutPath
New-CCShortcut -LnkPath $startMenu -Arguments '-Show' -SetAppId
Write-Host "スタートメニュー: $startMenu"

# 4. ログオン時に常駐
$startup = Get-CCStartupShortcutPath
if ($NoStartup) {
    if (Test-Path -LiteralPath $startup) { Remove-Item -LiteralPath $startup -Force }
} else {
    New-CCShortcut -LnkPath $startup -Arguments '-Resident'
    Write-Host "ログオン時に起動: $startup"
}

# 5. エクスプローラーの「送る」（レジストリは使わず、SendTo フォルダにショートカットを置くだけ）
$sendTo = Get-CCSendToShortcutPath
if ($NoSendTo) {
    if (Test-Path -LiteralPath $sendTo) { Remove-Item -LiteralPath $sendTo -Force }
} else {
    New-CCShortcut -LnkPath $sendTo -Arguments '-Show -Path' -Description '選んだフォルダで Claude Code を開く'
    Write-Host "送る: $sendTo（フォルダを右クリック →「送る」→「Claude Code」）"
}
# 6. 常駐を開始（すでに常駐していればパネルを出すだけ）
if (-not $NoStart) {
    $cmd = Get-CCHiddenCommand '-Resident -Show'
    Start-Process -FilePath $cmd.Exe -ArgumentList $cmd.Args -WorkingDirectory $CC.Root
    Write-Host 'トレイに常駐させました。'
}

Write-Host ''
Write-Host 'タスクバーにピン留めするには：スタートメニューで「Claude Code Launcher」を右クリック →「タスクバーにピン留めする」。'
$hk = (Get-CCConfig).hotkey
Write-Host "どこからでも $hk でパネルを開けます。"
