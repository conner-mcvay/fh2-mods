<#
.SYNOPSIS
  Installs fh2wheels into Forza Horizon 2 on Azimuth (or removes it with -Uninstall). Close the game first.
.DESCRIPTION
  Two halves:
  - the game database part (mods\fh2wheels): built on the game's own database as it is now, imported cars
    included (tools\build\Build-Mod.ps1 -Layer), then installed into Mount\mediapc with backups
    (tools\release\Install.ps1; needs FH2 Extra Options, whose EnableMediaOverrides it turns on);
  - fh2wheels.dll, put in Azimuth's data\bin\azimuth-tls.dll chain (tools\wheels\Install.ps1).
  Running it again (an update, or after importing more cars) takes the previous database part out first; when another
  mod went in after it (so it can't come out without undoing that one), the new one goes on top instead, which
  adds the options for cars that came since. sqlite3.exe is downloaded from sqlite.org (hash-checked) when it isn't
  on PATH or in tools\bin.
  The game folder (the one with Mount) is read from Azimuth's data\azimuth.ini when not given.
.EXAMPLE
  .\Install-Fh2wheels.ps1 -AzimuthRoot C:\Games\azimuth
.EXAMPLE
  .\Install-Fh2wheels.ps1 -AzimuthRoot C:\Games\azimuth -Uninstall
#>
param([string]$AzimuthRoot, [string]$GameRoot, [string]$Sqlite = $env:FH2_SQLITE, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

if (-not $AzimuthRoot) { $AzimuthRoot = Read-Host 'Azimuth folder (the one with azimuth.exe)' }
$AzimuthRoot = $AzimuthRoot.Trim('"').TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $AzimuthRoot 'azimuth.exe'))) { throw "No azimuth.exe in $AzimuthRoot" }
if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($AzimuthRoot + '\', [StringComparison]::OrdinalIgnoreCase) }) { throw 'Close Azimuth first.' }
if (-not $GameRoot) {   # [title-1a96545b] folder= in data\azimuth.ini (UTF-16)
  $ini = Join-Path $AzimuthRoot 'data\azimuth.ini'
  if (Test-Path -LiteralPath $ini) {
    $section = ''
    foreach ($line in Get-Content -LiteralPath $ini) {
      if ($line -match '^\s*\[(.+)\]') { $section = $Matches[1] }
      elseif ($section -eq 'title-1a96545b' -and $line -match '^\s*folder\s*=\s*(.+?)\s*$') { $GameRoot = $Matches[1] }
    }
  }
  if (-not $GameRoot) { $GameRoot = Read-Host 'Game folder (the one with Mount)' }
}
$GameRoot = $GameRoot.Trim('"').TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'Mount\forza_durango_release_final.exe'))) { throw "No Mount\forza_durango_release_final.exe in $GameRoot" }
Write-Host "Azimuth: $AzimuthRoot`nGame:    $GameRoot"

# the database parts installed earlier, newest first, not yet uninstalled
$backups = @(Get-ChildItem -LiteralPath (Join-Path $GameRoot 'mod-backups') -Directory -Filter 'fh2wheels-*' -ErrorAction SilentlyContinue |
  Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'restore.json')) -and -not (Test-Path -LiteralPath (Join-Path $_.FullName 'uninstalled.txt')) } |
  Sort-Object Name -Descending)
$uninstallDb = Join-Path $here 'tools\release\Uninstall.ps1'
$wheelsDll = Join-Path $here 'tools\wheels\Install.ps1'

if ($Uninstall) {
  foreach ($b in $backups) {
    try { & $uninstallDb -BackupRoot $b.FullName }
    catch { Write-Warning "Left the database part in $($b.Name): $($_.Exception.Message)"; break }
  }
  try { & $wheelsDll -Azimuth $AzimuthRoot -Uninstall } catch { Write-Warning $_.Exception.Message }
  Write-Host 'fh2wheels removed.'
  return
}

# --- sqlite3: -Sqlite, PATH, tools\bin, or download the official build ---
$bin = Join-Path $here 'tools\bin'
if (-not $Sqlite) { $Sqlite = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Source }
if (-not $Sqlite -and (Test-Path (Join-Path $bin 'sqlite3.exe'))) { $Sqlite = Join-Path $bin 'sqlite3.exe' }
if (-not $Sqlite) {
  $url = 'https://www.sqlite.org/2024/sqlite-tools-win-x64-3470200.zip'; $zipSha = '8c7fffbf4eec1f43e63153cca6deb018e4360d4d6b0d99bbdd2a541c53b7fa1c'
  Write-Host "Downloading sqlite3 from $url"
  New-Item -ItemType Directory $bin -Force | Out-Null
  $zip = Join-Path $bin 'sqlite-tools.zip'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  if ((Sha $zip) -ne $zipSha) { Remove-Item $zip; throw 'sqlite download failed its hash check' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::OpenRead($zip)
  try { [IO.Compression.ZipFileExtensions]::ExtractToFile(($z.Entries | Where-Object Name -eq 'sqlite3.exe'), (Join-Path $bin 'sqlite3.exe'), $true) } finally { $z.Dispose() }
  Remove-Item $zip; $Sqlite = Join-Path $bin 'sqlite3.exe'
}

# --- the database part: the previous one out (when nothing went in after it), then built on what's there now ---
if ($backups) {
  try { & $uninstallDb -BackupRoot $backups[0].FullName; Write-Host "Took out the previous fh2wheels database part ($($backups[0].Name))." }
  catch { Write-Host "The previous fh2wheels database part stays (another mod went in after it); the new one goes on top." }
}
& (Join-Path $here 'tools\build\Build-Mod.ps1') -Mod fh2wheels -Game $GameRoot -Layer -Sqlite $Sqlite
& (Join-Path $here 'build\fh2wheels\Install.ps1') -GameRoot $GameRoot -AzimuthRoot $AzimuthRoot

# --- the DLL ---
& $wheelsDll -Azimuth $AzimuthRoot -Dll (Join-Path $here 'fh2wheels.dll')
Write-Host "`nfh2wheels installed. Start the game and look under Upgrades > Tires & Rims."
