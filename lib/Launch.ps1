# Windows Terminal の新しいウィンドウで Claude Code を起動する

$script:CCModeArgs = @{
    new      = ''
    continue = ' --continue'
    resume   = ' --resume'
}

# wt.exe に渡す引数文字列を組み立てる
function Get-CCWtArguments([string]$Path, [string]$Mode = 'new') {
    if (-not $CCModeArgs.ContainsKey($Mode)) { throw "不明なモードです: $Mode" }
    $name = Get-CCDisplayName $Path
    # wt は ; をコマンドの区切りとして扱うので \; にする
    $wtEscape = { param($s) $s.Replace(';', '\;') }
    # "C:\" のように \ で終わると閉じ引用符がエスケープされてしまうので、末尾に . を足す
    $dir = $Path
    if ($dir.EndsWith('\')) { $dir += '.' }
    $title = (& $wtEscape $name.TrimEnd('\')).Replace('"', '')
    $pwsh = 'pwsh.exe'
    '-w new -d "{0}" --title "{1}" --suppressApplicationTitle {2} -NoExit -Command claude{3}' -f (& $wtEscape $dir), $title, $pwsh, $CCModeArgs[$Mode]
}

# 起動して履歴に記録する。失敗したら例外を投げる
function Invoke-CCLaunch([string]$Path, [string]$Mode = 'new') {
    $p = ConvertTo-CCNormalPath $Path
    if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Container)) {
        throw [IO.DirectoryNotFoundException]::new("フォルダが見つかりません: $Path")
    }
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $wt) { throw 'Windows Terminal (wt.exe) が見つかりません。' }
    $argLine = Get-CCWtArguments $p $Mode
    Write-CCLog "launch [$Mode] $p"
    Start-Process -FilePath $wt.Source -ArgumentList $argLine
    Add-CCRecent $p
    return $p
}
