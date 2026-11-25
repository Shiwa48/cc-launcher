<#
.SYNOPSIS
  任意のフォルダで Claude Code を開くランチャー（トレイ常駐）。

.EXAMPLE
  cc-launcher.ps1 -Resident                    # 常駐を開始する（ログオン時に使う）
  cc-launcher.ps1 -Show                        # パネルを出す。常駐していなければ常駐も始める
  cc-launcher.ps1 -Show -Path C:\work          # そのフォルダを入れた状態でパネルを出す（「送る」メニュー用）
  cc-launcher.ps1 -Open C:\work -Mode continue # そのフォルダで直接起動する（右クリック・ジャンプリスト用）
  cc-launcher.ps1 -Quit                        # 常駐を終了する
#>
# 位置での割り当てはしない（「送る」で付いてくる余分なパスが -Open に入って起動してしまうのを防ぐ）
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Show,
    [switch]$Resident,
    [string]$Open,
    [ValidateSet('new', 'continue', 'resume')]
    [string]$Mode = 'new',
    [switch]$Quit,
    [string]$Path,
    # 「送る」で複数選んだときの残りのパス（使わずに捨てる）
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\Store.ps1')
. (Join-Path $PSScriptRoot 'lib\Launch.ps1')

# ---- 単発起動（右クリック・ジャンプリストから） ----
if ($PSBoundParameters.ContainsKey('Open')) {
    try { [void](Invoke-CCLaunch -Path $Open -Mode $Mode) }
    catch { Show-CCError $_.Exception.Message; exit 1 }
    exit 0
}

Import-CCNative

# 「送る」から渡されたパス（ファイルなら、そのフォルダ）を常駐側に渡す
$prefill = $null
if ($Path) {
    $prefill = ConvertTo-CCNormalPath $Path
    if ($prefill -and (Test-Path -LiteralPath $prefill -PathType Leaf)) { $prefill = Split-Path -Parent $prefill }
    if ($prefill) { $Show = $true; Set-CCPendingPath $prefill }
}

if ($Quit) {
    [void][CCLauncher.Signal]::Send($CC.QuitSignal)
    exit 0
}

# ---- すでに常駐していれば合図だけ送って終わる ----
$createdNew = $false
$mutex = [Threading.Mutex]::new($true, $CC.MutexName, [ref]$createdNew)
if (-not $createdNew) {
    if (-not $Resident) {
        # 常駐側がパネルを前面に出せるよう、前面に出す権利を譲る
        [CCLauncher.Native]::AllowAnyForeground()
        [void][CCLauncher.Signal]::Send($CC.ShowSignal)
    }
    $mutex.Dispose()
    exit 0
}

# ---- 常駐する ----
try {
    . (Join-Path $PSScriptRoot 'ui\Panel.ps1')
    . (Join-Path $PSScriptRoot 'lib\Tray.ps1')
    Start-CCResident -ShowOnStart:$Show
} catch {
    Show-CCError ("常駐中にエラーが起きました。`n`n{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
    exit 1
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
