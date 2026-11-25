# 共通の定数・パス・ログ・ネイティブ部品の読み込み
Set-StrictMode -Version Latest

$script:CC = [ordered]@{
    AppId       = 'CCLauncher.App'
    AppName     = 'Claude Code Launcher'
    Root        = Split-Path -Parent $PSScriptRoot
    ConfigDir   = Join-Path $env:APPDATA 'cc-launcher'
    CacheDir    = Join-Path $env:LOCALAPPDATA 'cc-launcher'
    MutexName   = 'Local\cc-launcher-resident'
    ShowSignal  = 'Local\cc-launcher-show'
    QuitSignal  = 'Local\cc-launcher-quit'
}
$CC.ConfigPath = Join-Path $CC.ConfigDir 'config.json'
$CC.LogPath    = Join-Path $CC.CacheDir 'cc-launcher.log'
$CC.Script     = Join-Path $CC.Root 'cc-launcher.ps1'
$CC.AppIcon    = Join-Path $CC.Root 'assets\app.ico'

function Get-CCPwshPath {
    # Microsoft Store 版でもバージョンアップでパスが変わらない実行エイリアスを優先する
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
    if (Test-Path $alias) { return $alias }
    $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return (Join-Path $PSHOME 'pwsh.exe')
}

# 黒い窓を出さずに cc-launcher.ps1 を起動するためのコマンド（exe と引数）
function Get-CCHiddenCommand([string]$Arguments) {
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    $pwsh = Get-CCPwshPath
    [pscustomobject]@{
        Exe  = $conhost
        Args = "--headless `"$pwsh`" -NoProfile -ExecutionPolicy Bypass -File `"$($CC.Script)`" $Arguments"
    }
}

function Write-CCLog([string]$Message) {
    try {
        if (-not (Test-Path $CC.CacheDir)) { New-Item -ItemType Directory -Force $CC.CacheDir | Out-Null }
        $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $PID, $Message
        Add-Content -LiteralPath $CC.LogPath -Value $line -Encoding utf8
    } catch { }
}

function Show-CCError([string]$Message) {
    Write-CCLog "ERROR: $Message"
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show($Message, $CC.AppName, 'OK', 'Warning')
}

# Native.cs をコンパイルして読み込む（ソースが変わらない限りキャッシュ済み DLL を使う）
function Import-CCNative {
    if ('CCLauncher.Native' -as [type]) { return }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $src = Join-Path $PSScriptRoot 'Native.cs'
    $hash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.Substring(0, 12)
    $dll = Join-Path $CC.CacheDir "CCLauncher.Native.$hash.dll"
    if (-not (Test-Path $dll)) {
        if (-not (Test-Path $CC.CacheDir)) { New-Item -ItemType Directory -Force $CC.CacheDir | Out-Null }
        Get-ChildItem -LiteralPath $CC.CacheDir -Filter 'CCLauncher.Native.*.dll' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        $refs = @(
            [System.Windows.Interop.HwndSource].Assembly.Location      # PresentationCore
            [System.Windows.Threading.Dispatcher].Assembly.Location    # WindowsBase
            'System.Threading', 'System.Threading.Thread'
        )
        # -OutputAssembly でコンパイルすると、その場で型も読み込まれる
        Add-Type -LiteralPath $src -ReferencedAssemblies $refs -OutputAssembly $dll -OutputType Library -PassThru | Out-Null
        if ('CCLauncher.Native' -as [type]) { return }
    }
    [void][Reflection.Assembly]::LoadFrom($dll)
}

# 引数として渡すパスを引用符で囲む（"C:\" のように \ で終わると閉じ引用符が壊れるので . を足す）
function ConvertTo-CCArgPath([string]$Path) {
    if ($Path.EndsWith('\')) { $Path += '.' }
    return '"' + $Path + '"'
}

# 「送る」などから受け取ったパスを、常駐側に渡すための一時ファイル
function Set-CCPendingPath([string]$Path) {
    if (-not (Test-Path $CC.CacheDir)) { New-Item -ItemType Directory -Force $CC.CacheDir | Out-Null }
    Set-Content -LiteralPath (Join-Path $CC.CacheDir 'pending-path.txt') -Value $Path -Encoding utf8
}
function Get-CCPendingPath {
    $f = Join-Path $CC.CacheDir 'pending-path.txt'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $p = (Get-Content -LiteralPath $f -Raw -Encoding utf8).Trim()
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    return $p
}

function Get-CCSendToShortcutPath { Join-Path ([Environment]::GetFolderPath('SendTo')) 'Claude Code.lnk' }
function Get-CCStartupShortcutPath { Join-Path ([Environment]::GetFolderPath('Startup')) "$($CC.AppName).lnk" }
function Get-CCStartMenuShortcutPath { Join-Path ([Environment]::GetFolderPath('Programs')) "$($CC.AppName).lnk" }

# 黒い窓を出さずに cc-launcher.ps1 を起動するショートカットを作る
function New-CCShortcut([string]$LnkPath, [string]$Arguments, [string]$Description = 'フォルダを選んで Claude Code を開く', [switch]$SetAppId) {
    $cmd = Get-CCHiddenCommand $Arguments
    $shell = New-Object -ComObject WScript.Shell
    try {
        $lnk = $shell.CreateShortcut($LnkPath)
        $lnk.TargetPath = $cmd.Exe
        $lnk.Arguments = $cmd.Args
        $lnk.WorkingDirectory = $CC.Root
        $lnk.Description = $Description
        if (Test-Path -LiteralPath $CC.AppIcon) { $lnk.IconLocation = "$($CC.AppIcon),0" }
        $lnk.WindowStyle = 7
        $lnk.Save()
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    if ($SetAppId) {
        Import-CCNative
        [CCLauncher.Native]::SetShortcutAppId($LnkPath, $CC.AppId)
    }
}
