<#
.SYNOPSIS
  Undoes Install.ps1: restores the backed-up files, removes the files the mod added, restores azimuth.exe.

.DESCRIPTION
  Refuses to touch anything that changed since installation (e.g. another mod installed on top), so it never
  overwrites someone else's changes: with several mods installed, uninstall them newest first.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -BackupRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe\mod-backups\fm5-pon-transam-02-20261012-210000"
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupRoot)
$ErrorActionPreference = 'Stop'
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

$BackupRoot = (Resolve-Path -LiteralPath $BackupRoot).Path
$r = Get-Content -LiteralPath (Join-Path $BackupRoot 'restore.json') -Raw | ConvertFrom-Json
$mount = Join-Path $r.game_root 'Mount'; $azExe = Join-Path $r.azimuth_root 'azimuth.exe'
if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($r.azimuth_root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }) { throw 'Close Azimuth first.' }

$done = Join-Path $BackupRoot 'uninstalled.txt'
if (Test-Path -LiteralPath $done) { throw "$($r.mod) was already uninstalled from this backup ($(Get-Content -LiteralPath $done))" }

# verify before changing anything
$later = 'Another mod was probably installed after this one; uninstall mods newest first.'
foreach ($f in $r.files) {
  $t = Join-Path $mount $f.target
  if ($f.target -match '(^|\\)\.\.(\\|$)') { throw "Bad path in restore.json: $($f.target)" }
  if (-not (Test-Path -LiteralPath $t) -or (Sha $t) -ne $f.installed_sha256) { throw "Changed since installation, not restoring: $($f.target). $later" }
  if ($f.existed -and (Sha (Join-Path $BackupRoot ('files\' + $f.target))) -ne $f.backup_sha256) { throw "Corrupt backup: $($f.target)" }
}
if ($r.azimuth -and (Sha $azExe) -ne $r.azimuth.installed_sha256) { throw "azimuth.exe changed since installation, not restoring it. $later" }

foreach ($f in $r.files) {
  $t = Join-Path $mount $f.target
  if ($f.existed) { Copy-Item -LiteralPath (Join-Path $BackupRoot ('files\' + $f.target)) -Destination $t -Force } else { Remove-Item -LiteralPath $t }
}
if ($r.azimuth) { Copy-Item -LiteralPath (Join-Path $BackupRoot $r.azimuth.backup) -Destination $azExe -Force }
Set-Content -LiteralPath $done -Value "uninstalled $(Get-Date -Format 's')"
Write-Output "Uninstalled $($r.mod). Game files and azimuth.exe are back to their state before installation."
