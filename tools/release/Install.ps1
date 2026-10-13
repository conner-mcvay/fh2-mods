<#
.SYNOPSIS
  Installs this mod into a Forza Horizon 2 (PC / Azimuth) game folder, with backups.

.DESCRIPTION
  Reads install.json next to this script. Checks the game and Azimuth versions, refuses to overwrite files another
  mod already changed (unless -Force), backs up every file it replaces, copies the mod's files in, and - when the mod
  adds files the game doesn't have - patches azimuth.exe to accept the mod's Mount\hash.manifest (the stock launcher is
  kept as azimuth.stock.exe). Prints the backup folder; pass it to Uninstall.ps1 to undo.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -GameRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe" -AzimuthRoot "D:\azimuth"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$GameRoot,      # folder containing Mount
  [Parameter(Mandatory)][string]$AzimuthRoot,   # folder containing azimuth.exe
  [switch]$Force                                # overwrite files that aren't stock (e.g. changed by another mod)
)
$ErrorActionPreference = 'Stop'
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

$pkg = $PSScriptRoot
$m = Get-Content -LiteralPath (Join-Path $pkg 'install.json') -Raw | ConvertFrom-Json
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path; $AzimuthRoot = (Resolve-Path -LiteralPath $AzimuthRoot).Path
$mount = Join-Path $GameRoot 'Mount'
$exe = Join-Path $mount 'forza_durango_release_final.exe'
if (-not (Test-Path -LiteralPath $exe) -or (Sha $exe) -ne $m.game_exe_sha256) { throw "Unsupported game: needs FH2 $($m.game_version) (Mount\forza_durango_release_final.exe SHA-256 $($m.game_exe_sha256))" }
if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($AzimuthRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }) { throw 'Close Azimuth first.' }

# payload integrity
foreach ($f in $m.files) { if ((Sha (Join-Path $pkg $f.source)) -ne $f.sha256) { throw "Corrupt package file: $($f.source)" } }

# targets must be stock (or absent for new files) unless -Force
$conflicts = @()
foreach ($f in $m.files) {
  $t = Join-Path $mount $f.target
  if ($f.stock_sha256) { if (-not (Test-Path -LiteralPath $t) -or (Sha $t) -ne $f.stock_sha256) { $conflicts += $f.target } }
  elseif (Test-Path -LiteralPath $t) { $conflicts += $f.target }
}
if ($conflicts.Count -and -not $Force) {
  throw ("These files aren't stock (another mod may have changed them; installing would undo it):`n  " + ($conflicts -join "`n  ") + "`nUninstall that mod first, build the mods together from the fh2-mods repo, or pass -Force.")
}

# azimuth: needs patching only when the mod ships a hash.manifest
$azExe = Join-Path $AzimuthRoot 'azimuth.exe'; $azStock = Join-Path $AzimuthRoot 'azimuth.stock.exe'
$index = $m.files | Where-Object { $_.target -eq 'hash.manifest' }
if ($index) {
  if (-not (Test-Path -LiteralPath $azExe)) { throw "azimuth.exe not found in $AzimuthRoot" }
  $haveStock = if ((Sha $azExe) -eq $m.azimuth_stock_sha256) { $azExe } elseif ((Test-Path -LiteralPath $azStock) -and (Sha $azStock) -eq $m.azimuth_stock_sha256) { $azStock } else { $null }
  if (-not $haveStock) { throw "Needs the stock Azimuth $($m.azimuth_version) launcher (azimuth.exe or azimuth.stock.exe with SHA-256 $($m.azimuth_stock_sha256))" }
}

# back up, then install
$backup = Join-Path $GameRoot ("mod-backups\" + $m.name + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$record = @()
try {
  foreach ($f in $m.files) {
    $t = Join-Path $mount $f.target; $existed = Test-Path -LiteralPath $t; $saved = $null
    if ($existed) { $saved = Join-Path $backup ('files\' + $f.target); New-Item -ItemType Directory -Path (Split-Path $saved) -Force | Out-Null; Copy-Item -LiteralPath $t -Destination $saved }
    $record += [pscustomobject]@{ target = $f.target; existed = $existed; backup_sha256 = $(if ($existed) { Sha $saved } else { $null }); installed_sha256 = $f.sha256 }
    New-Item -ItemType Directory -Path (Split-Path $t) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $pkg $f.source) -Destination $t -Force
    if ((Sha $t) -ne $f.sha256) { throw "Install verification failed: $($f.target)" }
  }
  $az = $null
  if ($index) {
    if (-not (Test-Path -LiteralPath $azStock)) { Copy-Item -LiteralPath $haveStock -Destination $azStock }
    Copy-Item -LiteralPath $azExe -Destination (Join-Path $backup 'azimuth.exe')
    & (Join-Path $pkg 'tools\Patch-Azimuth.ps1') -Azimuth $azStock -Index (Join-Path $mount 'hash.manifest') -Out $azExe | Out-Host
    $az = [pscustomobject]@{ backup = 'azimuth.exe'; backup_sha256 = (Sha (Join-Path $backup 'azimuth.exe')); installed_sha256 = (Sha $azExe) }
  }
  [pscustomobject]@{ mod = $m.name; game_root = $GameRoot; azimuth_root = $AzimuthRoot; files = $record; azimuth = $az } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'restore.json') -Encoding UTF8
} catch {
  Write-Warning "Install failed; rolling back. $_"
  foreach ($r in $record) {
    $t = Join-Path $mount $r.target
    if ($r.existed) { Copy-Item -LiteralPath (Join-Path $backup ('files\' + $r.target)) -Destination $t -Force } elseif (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t }
  }
  if (Test-Path -LiteralPath (Join-Path $backup 'azimuth.exe')) { Copy-Item -LiteralPath (Join-Path $backup 'azimuth.exe') -Destination $azExe -Force }
  throw
}
Write-Output "Installed $($m.name)."
Write-Output "Backup: $backup"
Write-Output "To undo: powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -BackupRoot `"$backup`""
