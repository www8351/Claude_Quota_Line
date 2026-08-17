#requires -Version 5.1
<#
  Installs claude-quota-line as the Claude Code status line.
  Copies statusline.ps1 to ~/.claude/quota-line/ and merges the statusLine
  key into ~/.claude/settings.json. Existing settings are backed up first.

  Usage:
    .\install.ps1
    .\install.ps1 -ModelKey opus -ModelLabel Opus
    .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$ModelKey = 'fable',
    [string]$ModelLabel = 'Fable',
    [int]$BarWidth = 10,
    [int]$RefreshSeconds = 300,
    [switch]$Ascii,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$claude   = Join-Path $userHome '.claude'
$target   = Join-Path $claude 'quota-line'
$script   = Join-Path $target 'statusline.ps1'
$settings = Join-Path $claude 'settings.json'

New-Item -ItemType Directory -Force -Path $claude | Out-Null

$cfg = [ordered]@{}
if (Test-Path $settings) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item $settings "$settings.bak-$stamp"
    $json = Get-Content $settings -Raw
    if ($json.Trim()) { $cfg = $json | ConvertFrom-Json }
}

if ($Uninstall) {
    if ($cfg.PSObject.Properties['statusLine']) { $cfg.PSObject.Properties.Remove('statusLine') }
    $cfg | ConvertTo-Json -Depth 20 | Set-Content $settings -Encoding UTF8
    Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $claude 'quota-line-cache.json') -ErrorAction SilentlyContinue
    Write-Host "Removed. Restart Claude Code." -ForegroundColor Yellow
    return
}

New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'statusline.ps1') $script -Force

$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
$cmdArgs = "-NoProfile -NoLogo -ExecutionPolicy Bypass -File `"$($script -replace '\\','/')`""
$cmdArgs += " -BarWidth $BarWidth -RefreshSeconds $RefreshSeconds"
if ($ModelKey)   { $cmdArgs += " -ModelKey $ModelKey -ModelLabel $ModelLabel" }
if ($Ascii)      { $cmdArgs += " -Ascii" }

$statusLine = [ordered]@{ type = 'command'; command = "$shell $cmdArgs"; padding = 0 }

if ($cfg -is [System.Collections.IDictionary]) {
    $cfg['statusLine'] = $statusLine
} else {
    if ($cfg.PSObject.Properties['statusLine']) { $cfg.statusLine = $statusLine }
    else { $cfg | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLine }
}
$cfg | ConvertTo-Json -Depth 20 | Set-Content $settings -Encoding UTF8

Write-Host "Installed to $script" -ForegroundColor Green
Write-Host "Command: $shell $cmdArgs" -ForegroundColor Cyan
Write-Host "Restart Claude Code to see the status line." -ForegroundColor Yellow
