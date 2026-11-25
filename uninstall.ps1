<#
.SYNOPSIS
  install.ps1 で登録したものを取り除く。お気に入りと履歴（config.json）は -RemoveConfig を付けたときだけ消す。
#>
[CmdletBinding()]
param([switch]$RemoveConfig)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

# 常駐を終了する
try {
    Import-CCNative
    if ([CCLauncher.Signal]::Send($CC.QuitSignal)) { Start-Sleep -Seconds 2; Write-Host '常駐を終了しました。' }
} catch { Write-Warning "常駐の終了に失敗しました: $_" }

foreach ($lnk in (Get-CCStartMenuShortcutPath), (Get-CCStartupShortcutPath), (Get-CCSendToShortcutPath)) {
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Host "削除: $lnk" }
}

if ($RemoveConfig) {
    foreach ($d in $CC.ConfigDir, $CC.CacheDir) {
        if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force; Write-Host "削除: $d" }
    }
} else {
    Write-Host "お気に入りと履歴は残しています: $($CC.ConfigPath)"
}
Write-Host 'タスクバーにピン留めしている場合は、右クリック →「タスクバーからピン留めを外す」で外してください。'
