<#
.SYNOPSIS
  Installs fh2wheels.dll where this Azimuth loads it (or takes it out with -Uninstall).
.DESCRIPTION
  Azimuth 0.9 (data\bin\azimuth-tls.dll): fh2wheels goes in front of azimuth-tls.dll. The existing azimuth-tls.dll
  (Extra Options', fh2net or Azimuth's own) is renamed fh2wheels-next.dll; fh2wheels takes its name, loads it and
  forwards its exports. fh2net uses azimuth-tls-next.dll for the same, so they chain in either order. When fh2net is
  already azimuth-tls.dll, fh2wheels goes behind it instead (taking azimuth-tls-next.dll), so fh2net's installer keeps
  working. A starter fh2wheels.ini is written if there is none. The log is data\bin\fh2wheels.log.

  Azimuth 1.0 and later (data\bin\azimuth-tls-1.dll, no azimuth-tls.dll): those are thread-local storage slots that
  Azimuth checks and fills for the game, so nothing can stand in for them. fh2wheels goes in as an FH2 Extra Options
  mod instead, mods\Forza Horizon 2\fh2wheels (mods\fh2wheels for an Extra Options with mods\loadorder.txt):
  mod.json, strings.json (-Strings, its menu text) and, in plugins, fh2wheels.dll, which Extra Options loads, and
  fh2wheels.sql (-Sql, its database part), which fh2wheels runs on the game's database at every start (plugin.c).
  Its fh2wheels.ini and log are in that plugins folder. A leftover fh2wheels-next.dll from an Azimuth 0.9 install is
  removed.

  -Uninstall works for either. -Dll: the DLL to install (default: out\fh2wheels.dll, the build's).
#>
param([Parameter(Mandatory)][string]$Azimuth, [switch]$Uninstall, [string]$Dll, [string]$Sql, [string]$Strings, [string]$Version = 'fh2wheels')
$ErrorActionPreference = 'Stop'
if (Get-Process | Where-Object { $_.Path -and $_.Path -like (Join-Path $Azimuth '*') }) { throw 'Close the game first.' }
$bin = Join-Path $Azimuth 'data\bin'
$cur = Join-Path $bin 'azimuth-tls.dll'; $next = Join-Path $bin 'fh2wheels-next.dll'
$ours = if ($Dll) { $Dll } else { Join-Path $PSScriptRoot 'out\fh2wheels.dll' }
$isOurs = { param($f) (Test-Path $f) -and ([IO.File]::ReadAllText($f, [Text.Encoding]::ASCII).Contains('fh2wheels loaded')) }
$starterIni = @(
  '; fh2wheels: per-axle wheel offsets, read again on every car build (edit, then re-enter the garage).',
  '; <Data_Car Id>=<front mm>,<rear mm>: how far each wheel moves out per side (negative: in).',
  '; fh2wheels.log lists every car the game builds, with its Id and stock track widths.',
  '[offsets]')
# Extra Options' mod folder for fh2wheels: Extra Options 0.6 keeps each game's mods in mods\<game>, earlier ones in mods
$eoMods = Join-Path $Azimuth 'mods'
if (-not (Test-Path (Join-Path $eoMods 'Forza Horizon 2')) -and (Test-Path (Join-Path $eoMods 'loadorder.txt'))) { $modDir = Join-Path $eoMods 'fh2wheels' }
else { $modDir = Join-Path $eoMods 'Forza Horizon 2\fh2wheels' }
$plugins = Join-Path $modDir 'plugins'

if ($Uninstall) {
  $did = $false
  if (Test-Path $modDir) {   # the Extra Options mod: everything but the settings (*.ini) goes
    Get-ChildItem $modDir -Recurse -File | Where-Object { $_.Extension -ne '.ini' } | Remove-Item
    Get-ChildItem $modDir -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending | Where-Object { -not (Get-ChildItem $_.FullName -Force) } | Remove-Item
    if (-not (Get-ChildItem $modDir -Force)) { Remove-Item $modDir }
    Write-Host "fh2wheels removed from $modDir$(if (Test-Path $modDir) { ' (its settings, *.ini, are kept there)' })."
    $did = $true
  }
  if (Test-Path $next) {
    # fh2wheels is azimuth-tls.dll, or azimuth-tls-next.dll when fh2net went in front of it later
    $at = @($cur, (Join-Path $bin 'azimuth-tls-next.dll')) | Where-Object { & $isOurs $_ } | Select-Object -First 1
    if (-not $at) {   # the chain was replaced since (an Azimuth update or reinstall): only the old fh2wheels-next.dll is left
      Remove-Item $next
      Write-Host 'fh2wheels was already out of the azimuth-tls.dll chain (Azimuth updated or reinstalled?); removed its leftover fh2wheels-next.dll.'
    } else {
      Remove-Item $at; Rename-Item $next (Split-Path $at -Leaf)
      Write-Host "fh2wheels removed; $(Split-Path $at -Leaf) restored."
    }
    $did = $true
  }
  if (-not $did) { throw 'Not installed (no fh2wheels-next.dll in data\bin, no Extra Options mod folder).' }
  return
}
if (-not (Test-Path $ours)) { throw "Build first: $ours" }
$netNext = Join-Path $bin 'azimuth-tls-next.dll'
$at = @($cur, $netNext) | Where-Object { & $isOurs $_ } | Select-Object -First 1

if (-not $at -and -not (Test-Path $cur) -and (Test-Path (Join-Path $bin 'azimuth-tls-1.dll'))) {
  # Azimuth 1.0 and later: an Extra Options mod
  foreach ($f in @($Sql, $Strings)) { if (-not $f -or -not (Test-Path $f)) { throw "Missing $f (-Sql and -Strings are needed for Azimuth 1.0 and later)" } }
  if (Test-Path $next) {
    Remove-Item $next
    Write-Host 'Removed the fh2wheels-next.dll left from an install on an older Azimuth (Azimuth 1.0 has no azimuth-tls.dll chain).'
  }
  New-Item -ItemType Directory $plugins -Force | Out-Null
  Copy-Item $ours (Join-Path $plugins 'fh2wheels.dll') -Force
  Copy-Item $Sql (Join-Path $plugins 'fh2wheels.sql') -Force
  Copy-Item $Strings (Join-Path $modDir 'strings.json') -Force
  $manifest = [ordered]@{ format_version = 1; id = 'fh2wheels'; name = 'fh2wheels'; version = ($Version -replace '^fh2wheels\s*', '')
    description = 'Wheel offsets, tire profiles, rear rims, rim sizes, tire widths, drag and rally tires, ride height and camber ranges.'
    media = $null; database = $null; strings = 'strings.json'; dependencies = @() }
  [IO.File]::WriteAllText((Join-Path $modDir 'mod.json'), ($manifest | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
  $ini = Join-Path $plugins 'fh2wheels.ini'
  if (-not (Test-Path $ini)) { Set-Content $ini -Encoding ASCII -Value $starterIni }
  Write-Host "fh2wheels installed as an FH2 Extra Options mod in $modDir. Settings: $ini  Log: $(Join-Path $plugins 'fh2wheels.log')"
  return
}

if (-not $at -and (Test-Path $next)) {
  # fh2wheels-next.dll left from an earlier install, but fh2wheels is no longer in the chain: azimuth-tls.dll was
  # replaced since (an Azimuth update or reinstall puts its own back). The one there now is current; the old one goes.
  Write-Host "fh2wheels was no longer in the azimuth-tls.dll chain (Azimuth updated or reinstalled?); putting it back."
  Remove-Item $next
}
if (-not (Test-Path $next)) {
  if ($at) { throw "$(Split-Path $at -Leaf) is fh2wheels but fh2wheels-next.dll is missing." }
  # behind fh2net when it is there (azimuth-tls.dll), so fh2net's own installer still finds itself in front
  $isNet = (Test-Path $cur) -and [IO.File]::ReadAllText($cur, [Text.Encoding]::ASCII).Contains('fh2net probe loaded')
  $at = if ($isNet -and (Test-Path $netNext)) { $netNext } else { $cur }
  if (-not (Test-Path $at)) { throw "No $(Split-Path $at -Leaf) or azimuth-tls-1.dll in $bin to put fh2wheels in front of; reinstall Azimuth (and Extra Options) first." }
  Rename-Item $at 'fh2wheels-next.dll'
}
Copy-Item $ours $at -Force
$ini = Join-Path $bin 'fh2wheels.ini'
if (-not (Test-Path $ini)) { Set-Content $ini -Encoding ASCII -Value $starterIni }
Write-Host "fh2wheels installed as $(Split-Path $at -Leaf). Settings: $ini  Log: $(Join-Path $bin 'fh2wheels.log')"
