<#
.SYNOPSIS
  Puts fh2wheels.dll in front of Azimuth's data\bin\azimuth-tls.dll (or takes it out with -Uninstall).
.DESCRIPTION
  The existing azimuth-tls.dll (Extra Options', fh2net or Azimuth's own) is renamed fh2wheels-next.dll; fh2wheels
  takes its name, loads it and forwards its exports. fh2net uses azimuth-tls-next.dll for the same, so they chain
  in either order. When fh2net is already azimuth-tls.dll, fh2wheels goes behind it instead (taking
  azimuth-tls-next.dll), so fh2net's installer keeps working; -Uninstall works in either place.
  A starter fh2wheels.ini is written if there is none. The log is data\bin\fh2wheels.log.
  -Dll: the DLL to install (default: out\fh2wheels.dll, the build's).
#>
param([Parameter(Mandatory)][string]$Azimuth, [switch]$Uninstall, [string]$Dll)
$ErrorActionPreference = 'Stop'
if (Get-Process | Where-Object { $_.Path -and $_.Path -like (Join-Path $Azimuth '*') }) { throw 'Close the game first.' }
$bin = Join-Path $Azimuth 'data\bin'
$cur = Join-Path $bin 'azimuth-tls.dll'; $next = Join-Path $bin 'fh2wheels-next.dll'
$ours = if ($Dll) { $Dll } else { Join-Path $PSScriptRoot 'out\fh2wheels.dll' }
$isOurs = { param($f) (Test-Path $f) -and ([IO.File]::ReadAllText($f, [Text.Encoding]::ASCII).Contains('fh2wheels loaded')) }
if ($Uninstall) {
  if (-not (Test-Path $next)) { throw 'Not installed (no fh2wheels-next.dll).' }
  # fh2wheels is azimuth-tls.dll, or azimuth-tls-next.dll when fh2net went in front of it later
  $at = @($cur, (Join-Path $bin 'azimuth-tls-next.dll')) | Where-Object { & $isOurs $_ } | Select-Object -First 1
  if (-not $at -and (Test-Path $cur)) {   # the chain was replaced since (see below): only the old fh2wheels-next.dll is left
    Remove-Item $next
    Write-Host 'fh2wheels was already out of the azimuth-tls.dll chain (Azimuth updated or reinstalled?); removed its leftover fh2wheels-next.dll.'
    return
  }
  if (-not $at) { throw 'fh2wheels-next.dll exists but neither fh2wheels nor azimuth-tls.dll is in data\bin; left alone.' }
  Remove-Item $at; Rename-Item $next (Split-Path $at -Leaf)
  Write-Host "fh2wheels removed; $(Split-Path $at -Leaf) restored."
  return
}
if (-not (Test-Path $ours)) { throw "Build first: $ours" }
$netNext = Join-Path $bin 'azimuth-tls-next.dll'
$at = @($cur, $netNext) | Where-Object { & $isOurs $_ } | Select-Object -First 1
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
  if (-not (Test-Path $at)) { throw "No $(Split-Path $at -Leaf) in $bin to put fh2wheels in front of; reinstall Azimuth (and Extra Options) first." }
  Rename-Item $at 'fh2wheels-next.dll'
}
Copy-Item $ours $at -Force
$ini = Join-Path $bin 'fh2wheels.ini'
if (-not (Test-Path $ini)) {
  Set-Content $ini -Encoding ASCII -Value @(
    '; fh2wheels: per-axle wheel offsets, read again on every car build (edit, then re-enter the garage).',
    '; <Data_Car Id>=<front mm>,<rear mm>: how far each wheel moves out per side (negative: in).',
    '; fh2wheels.log lists every car the game builds, with its Id and stock track widths.',
    '[offsets]')
}
Write-Host "fh2wheels installed as $(Split-Path $at -Leaf). Settings: $ini  Log: $(Join-Path $bin 'fh2wheels.log')"
