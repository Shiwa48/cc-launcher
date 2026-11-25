# config.json（お気に入り・履歴・設定）の読み書き
# 常駐プロセスと右クリックからの単発起動が同時に書くことがあるので、名前付き Mutex で排他にする

function New-CCDefaultConfig {
    [ordered]@{
        version   = 1
        hotkey    = 'Ctrl+Alt+C'
        recentMax = 20
        favorites = @()
        recent    = @()
    }
}

function ConvertTo-CCNormalPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $p = $Path.Trim().Trim('"').Trim()
    $p = [Environment]::ExpandEnvironmentVariables($p)
    if ($p -like '~*') { $p = $HOME + $p.Substring(1) }
    # "C:" だけだと「C ドライブのカレントフォルダ」になるので、ドライブ直下として扱う
    if ($p -match '^[a-zA-Z]:\.?$') { $p = $p.Substring(0, 2) + '\' }
    try { $p = [IO.Path]::GetFullPath($p) } catch { return $null }
    $root = [IO.Path]::GetPathRoot($p)
    if ($p.Length -gt $root.Length) { $p = $p.TrimEnd('\') }
    return $p
}

function Test-CCSamePath([string]$A, [string]$B) {
    [string]::Equals($A, $B, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-CCLocked([scriptblock]$Body) {
    $m = [Threading.Mutex]::new($false, 'Local\cc-launcher-config')
    $owned = $false
    try {
        try { $owned = $m.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $owned = $true }
        & $Body
    } finally {
        if ($owned) { $m.ReleaseMutex() }
        $m.Dispose()
    }
}

function Read-CCConfigUnlocked {
    $cfg = New-CCDefaultConfig
    if (Test-Path -LiteralPath $CC.ConfigPath) {
        try {
            $json = Get-Content -LiteralPath $CC.ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
            foreach ($k in @($json.Keys)) { $cfg[$k] = $json[$k] }
        } catch {
            Write-CCLog "config.json を読めませんでした（既定値で続行）: $_"
        }
    }
    # 配列が 1 件のときなどに配列でなくなるのを防ぐ
    $cfg.favorites = @($cfg.favorites | Where-Object { $_ -and $_.path })
    $cfg.recent    = @($cfg.recent    | Where-Object { $_ -and $_.path })
    return $cfg
}

function Write-CCConfigUnlocked($Config) {
    if (-not (Test-Path $CC.ConfigDir)) { New-Item -ItemType Directory -Force $CC.ConfigDir | Out-Null }
    $tmp = "$($CC.ConfigPath).tmp"
    $Config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmp -Encoding utf8
    Move-Item -LiteralPath $tmp -Destination $CC.ConfigPath -Force
}

function Get-CCConfig { Invoke-CCLocked { Read-CCConfigUnlocked } }

# 設定を読み、$Change で書き換えて保存する
function Update-CCConfig([scriptblock]$Change) {
    Invoke-CCLocked {
        $cfg = Read-CCConfigUnlocked
        & $Change $cfg
        Write-CCConfigUnlocked $cfg
        $cfg
    }
}

function Add-CCRecent([string]$Path) {
    [void](Update-CCConfig {
        param($cfg)
        $rest = @($cfg.recent | Where-Object { -not (Test-CCSamePath $_.path $Path) })
        $max = [int]$cfg.recentMax
        $cfg.recent = @(@(@{ path = $Path; lastUsed = (Get-Date).ToString('o') }) + $rest | Select-Object -First $max)
    })
}

function Remove-CCRecent([string]$Path) {
    [void](Update-CCConfig { param($cfg) $cfg.recent = @($cfg.recent | Where-Object { -not (Test-CCSamePath $_.path $Path) }) })
}

function Test-CCFavorite($Config, [string]$Path) {
    [bool](@($Config.favorites | Where-Object { Test-CCSamePath $_.path $Path }).Count)
}

# お気に入りの追加・解除を切り替える。戻り値は切り替え後の状態（$true = お気に入り）
function Switch-CCFavorite([string]$Path) {
    $script:ccFavResult = $false
    [void](Update-CCConfig {
        param($cfg)
        if (Test-CCFavorite $cfg $Path) {
            $cfg.favorites = @($cfg.favorites | Where-Object { -not (Test-CCSamePath $_.path $Path) })
            $script:ccFavResult = $false
        } else {
            $cfg.favorites = @($cfg.favorites) + @(@{ path = $Path; name = (Split-Path -Leaf $Path) })
            $script:ccFavResult = $true
        }
    })
    return $script:ccFavResult
}

# お気に入りの並べ替え（$Delta = -1 で上へ、+1 で下へ）
function Move-CCFavorite([string]$Path, [int]$Delta) {
    [void](Update-CCConfig {
        param($cfg)
        $list = [Collections.Generic.List[object]]::new()
        foreach ($f in $cfg.favorites) { $list.Add($f) }
        for ($i = 0; $i -lt $list.Count; $i++) {
            if (Test-CCSamePath $list[$i].path $Path) {
                $j = $i + $Delta
                if ($j -ge 0 -and $j -lt $list.Count) { $t = $list[$i]; $list[$i] = $list[$j]; $list[$j] = $t }
                break
            }
        }
        $cfg.favorites = @($list)
    })
}

function Get-CCDisplayName([string]$Path, [string]$Name) {
    if ($Name) { return $Name }
    $leaf = Split-Path -Leaf $Path
    if ([string]::IsNullOrEmpty($leaf)) { return $Path }
    return $leaf
}
