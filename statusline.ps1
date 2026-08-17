#requires -Version 5.1
<#
  claude-quota-line
  Two-line Claude Code status line: context window, 5-hour limit,
  weekly all-models limit and weekly per-model limit, with progress bars.

  Input:  Claude Code status line JSON on stdin.
  Output: two ANSI-colored lines.

  Data sources, in order:
    1. rate_limits on stdin (Claude Code >= 2.1.x, Pro/Max). No network.
    2. https://api.anthropic.com/api/oauth/usage with the OAuth token from
       ~/.claude/.credentials.json. Undocumented, community-discovered.
       Used only for the per-model weekly figure and as a fallback when
       stdin has no rate_limits. Cached for RefreshSeconds.
#>
[CmdletBinding()]
param(
    [int]$BarWidth = 10,
    [int]$RefreshSeconds = 300,
    [string]$ModelKey = 'fable',
    [string]$ModelLabel = 'Fable',
    [switch]$Ascii,
    [ValidateSet('left','right')][string]$Align = 'left',
    [int]$Width = 0,
    [int]$RightMargin = 2,
    [switch]$DumpInput,
    [string]$InputJson
)

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---------- input ----------
$raw = $InputJson
if (-not $raw) {
    try { if ([Console]::IsInputRedirected) { $raw = [Console]::In.ReadToEnd() } } catch {}
}
$data = $null
if ($raw) { try { $data = $raw | ConvertFrom-Json } catch {} }
if ($DumpInput) {
    $h = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    try { $raw | Set-Content (Join-Path $h '.claude\quota-line-last-input.json') -Encoding UTF8 } catch {}
}

# ---------- styling ----------
$E = [char]27
$RST = "$E[0m"; $DIM = "$E[90m"; $BOLD = "$E[1m"
$GREEN = "$E[32m"; $YELLOW = "$E[33m"; $RED = "$E[31m"; $CYAN = "$E[36m"
$FULL  = if ($Ascii) { '#' } else { [string][char]0x2588 }
$EMPTY = if ($Ascii) { '.' } else { [string][char]0x2591 }
$ARROW = if ($Ascii) { '~' } else { [string][char]0x21BB }
$SEP   = if ($Ascii) { ' | ' } else { "  $DIM$([char]0x2502)$RST  " }

function Get-Color([double]$p) {
    if ($p -ge 80) { return $RED }
    if ($p -ge 50) { return $YELLOW }
    return $GREEN
}

function New-Bar([double]$p) {
    $p = [Math]::Max(0, [Math]::Min(100, $p))
    $n = [int][Math]::Round($p / 100 * $BarWidth)
    $c = Get-Color $p
    return "$c$($FULL * $n)$DIM$($EMPTY * ($BarWidth - $n))$RST $c$([int][Math]::Round($p))%$RST"
}

# Accepts epoch seconds, epoch ms, or ISO 8601. Returns DateTimeOffset or $null.
function ConvertTo-Time($v) {
    if ($null -eq $v -or "$v" -eq '') { return $null }
    try {
        if ($v -is [DateTimeOffset]) { return $v.ToLocalTime() }
        if ($v -is [datetime]) { return ([DateTimeOffset]$v).ToLocalTime() }
        if ($v -is [string] -and $v -notmatch '^\d+(\.\d+)?$') {
            return [DateTimeOffset]::Parse($v, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()
        }
        $n = [double]$v
        if ($n -gt 1e12) { $n = $n / 1000 }
        return [DateTimeOffset]::FromUnixTimeSeconds([long]$n).ToLocalTime()
    } catch { return $null }
}

function Get-ResetLabel($v, [bool]$Weekly) {
    $t = ConvertTo-Time $v
    if ($null -eq $t) { return '' }
    if ($Weekly) { return "$DIM$ARROW $($t.ToString('ddd HH:mm'))$RST" }
    $d = $t - [DateTimeOffset]::Now
    if ($d.TotalSeconds -le 0) { return "$DIM$ARROW now$RST" }
    return "$DIM$ARROW {0}h{1:00}m$RST" -f [int][Math]::Floor($d.TotalHours), $d.Minutes
}

# Reads either .used_percentage (stdin shape) or .utilization (usage API shape).
function Get-Pct($obj) {
    if ($null -eq $obj) { return $null }
    foreach ($k in 'used_percentage', 'utilization', 'percent') {
        $p = $obj.PSObject.Properties[$k]
        if ($p -and $null -ne $p.Value) {
            $x = [double]$p.Value
            if ($k -eq 'utilization' -and $x -le 1) { $x = $x * 100 }
            return $x
        }
    }
    return $null
}

# ---------- usage API (cached) ----------
function Get-UsageFromApi {
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $dir   = Join-Path $userHome '.claude'
    $cache = Join-Path $dir 'quota-line-cache.json'
    $cred  = Join-Path $dir '.credentials.json'

    if (Test-Path $cache) {
        $age = (Get-Date) - (Get-Item $cache).LastWriteTime
        if ($age.TotalSeconds -lt $RefreshSeconds) {
            try { return (Get-Content $cache -Raw | ConvertFrom-Json) } catch { return $null }
        }
    }
    if (-not (Test-Path $cred)) { return $null }
    $token = $null
    try { $token = (Get-Content $cred -Raw | ConvertFrom-Json).claudeAiOauth.accessToken } catch {}
    if (-not $token) { return $null }

    try {
        $r = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec 4 -Headers @{
            Authorization    = "Bearer $token"
            'anthropic-beta' = 'oauth-2025-04-20'
        }
        $r | ConvertTo-Json -Depth 6 | Set-Content $cache -Encoding UTF8
        return $r
    } catch {
        # Do not hammer the endpoint on failure: refresh the cache timestamp.
        if (Test-Path $cache) {
            (Get-Item $cache).LastWriteTime = Get-Date
            try { return (Get-Content $cache -Raw | ConvertFrom-Json) } catch {}
        } else {
            '{}' | Set-Content $cache -Encoding UTF8
        }
        return $null
    }
}

# Finds the per-model weekly bucket. Two shapes are supported:
#   1. limits[] entry with kind "weekly_scoped" and scope.model.display_name
#      matching the key (current API shape).
#   2. top-level seven_day_<key> object (older shape).
# Returns an object with utilization and resets_at, or $null.
function Get-ModelBucket($usage, [string]$key) {
    if ($null -eq $usage) { return $null }
    if ($usage.limits) {
        foreach ($l in $usage.limits) {
            if ($l.kind -ne 'weekly_scoped') { continue }
            $name = "$($l.scope.model.display_name) $($l.scope.model.id)"
            if ($name -match [regex]::Escape($key)) {
                return [pscustomobject]@{ utilization = $l.percent; resets_at = $l.resets_at }
            }
        }
    }
    foreach ($p in $usage.PSObject.Properties) {
        if ($p.Name -match '^seven_day_' -and $p.Name -match [regex]::Escape($key) -and $null -ne $p.Value) { return $p.Value }
    }
    return $null
}

# ---------- gather ----------
$ctxPct  = Get-Pct $data.context_window
# Fresh session: used_percentage is null and token counts are 0. Show 0%.
if ($null -eq $ctxPct -and $data.context_window) { $ctxPct = 0 }
$rl      = $data.rate_limits
$fiveH   = $rl.five_hour
$week    = $rl.seven_day
$usage   = $null

$needApi = ($null -eq $fiveH -or $null -eq $week -or $ModelKey)
if ($needApi) { $usage = Get-UsageFromApi }
if ($null -eq $fiveH -and $usage) { $fiveH = $usage.five_hour }
if ($null -eq $week  -and $usage) { $week  = $usage.seven_day }
$model = if ($ModelKey) { Get-ModelBucket $usage $ModelKey } else { $null }

# ---------- alignment ----------
function Get-TerminalWidth {
    if ($Width -gt 0) { return $Width }
    $w = 0
    try { $w = [Console]::WindowWidth } catch {}
    if (-not $w) { try { $w = $Host.UI.RawUI.WindowSize.Width } catch {} }
    if (-not $w -and $env:COLUMNS) { try { $w = [int]$env:COLUMNS } catch {} }
    if (-not $w -and $IsWindows -ne $false) {
        try {
            $m = (cmd /c mode con 2>$null | Select-String 'Columns:\s+(\d+)')
            if ($m) { $w = [int]$m.Matches[0].Groups[1].Value }
        } catch {}
    }
    return [int]$w
}
function Format-Line([string]$s) {
    if ($Align -ne 'right') { return $s }
    $w = Get-TerminalWidth
    if ($w -le 0) { return $s }
    $visible = ([regex]::Replace($s, "$E\[[0-9;]*m", '')).Length
    $pad = $w - $RightMargin - $visible
    if ($pad -le 0) { return $s }
    return (' ' * $pad) + $s
}

# ---------- render ----------
$parts1 = @()
$parts2 = @()

if ($null -ne $ctxPct) { $parts1 += "$($BOLD)Ctx$RST  $(New-Bar $ctxPct)" }

$p = Get-Pct $fiveH
if ($null -ne $p) { $parts1 += "$($BOLD)5h$RST   $(New-Bar $p) $(Get-ResetLabel $fiveH.resets_at $false)" }

$p = Get-Pct $week
if ($null -ne $p) { $parts2 += "$($BOLD)Week$RST $(New-Bar $p) $(Get-ResetLabel $week.resets_at $true)" }

$p = Get-Pct $model
if ($null -ne $p) { $parts2 += "$BOLD$ModelLabel$RST $(New-Bar $p) $(Get-ResetLabel $model.resets_at $true)" }

if ($parts1.Count -eq 0 -and $parts2.Count -eq 0) {
    Write-Output (Format-Line "$($DIM)quota: waiting for first response$RST")
    exit 0
}
if ($parts1.Count) { Write-Output (Format-Line ($parts1 -join $SEP)) }
if ($parts2.Count) { Write-Output (Format-Line ($parts2 -join $SEP)) }