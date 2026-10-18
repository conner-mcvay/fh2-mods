<#
.SYNOPSIS
  Puts fh2wheels.dll in front of Azimuth's data\bin\azimuth-tls.dll (or takes it out with -Uninstall).
.DESCRIPTION
  The existing azimuth-tls.dll (Extra Options', fh2net or Azimuth's own) is renamed fh2wheels-next.dll; fh2wheels
  takes its name, loads it and forwards its exports. fh2net uses azimuth-tls-next.dll for the same, so they chain
  in either order; -Uninstall also works when fh2net was installed in front of fh2wheels afterwards.
  A starter fh2wheels.ini is written if there is none. The log is data\bin\fh2wheels.log.
#>
param([Parameter(Mandatory)][string]$Azimuth, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
if (Get-Process | Where-Object { $_.Path -and $_.Path -like (Join-Path $Azimuth '*') }) { throw 'Close the game first.' }
$bin = Join-Path $Azimuth 'data\bin'
$cur = Join-Path $bin 'azimuth-tls.dll'; $next = Join-Path $bin 'fh2wheels-next.dll'
$ours = Join-Path $PSScriptRoot 'out\fh2wheels.dll'
$isOurs = { param($f) (Test-Path $f) -and ([IO.File]::ReadAllText($f, [Text.Encoding]::ASCII).Contains('fh2wheels loaded')) }
if ($Uninstall) {
  if (-not (Test-Path $next)) { throw 'Not installed (no fh2wheels-next.dll).' }
  # fh2wheels is azimuth-tls.dll, or azimuth-tls-next.dll when fh2net went in front of it later
  $at = @($cur, (Join-Path $bin 'azimuth-tls-next.dll')) | Where-Object { & $isOurs $_ } | Select-Object -First 1
  if (-not $at) { throw 'fh2wheels-next.dll exists but fh2wheels.dll was not found in the chain; left alone.' }
  Remove-Item $at; Rename-Item $next (Split-Path $at -Leaf)
  Write-Host "fh2wheels removed; $(Split-Path $at -Leaf) restored."
  return
}
if (-not (Test-Path $ours)) { throw "Build first: $ours" }
if (-not (Test-Path $next)) {
  if (& $isOurs $cur) { throw 'azimuth-tls.dll is fh2wheels but fh2wheels-next.dll is missing.' }
  Rename-Item $cur 'fh2wheels-next.dll'
}
$at = @($cur, (Join-Path $bin 'azimuth-tls-next.dll')) | Where-Object { & $isOurs $_ } | Select-Object -First 1
if (-not $at) { $at = $cur }
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
