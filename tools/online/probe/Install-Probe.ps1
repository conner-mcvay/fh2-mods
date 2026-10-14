<#
.SYNOPSIS
  Puts fh2net.dll in front of Azimuth's data\bin\azimuth-tls.dll (or takes it out with -Uninstall).
.DESCRIPTION
  The existing azimuth-tls.dll (Extra Options', or Azimuth's own) is renamed azimuth-tls-next.dll; fh2net.dll
  takes its name, loads it and forwards its exports. The log is written to data\bin\fh2net.log.
#>
param([string]$Azimuth = 'G:\FH2-1\azimuth', [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
if (Get-Process | Where-Object { $_.Path -and $_.Path -like (Join-Path $Azimuth '*') }) { throw 'Close the game first.' }
$bin = Join-Path $Azimuth 'data\bin'
$cur = Join-Path $bin 'azimuth-tls.dll'; $next = Join-Path $bin 'azimuth-tls-next.dll'
$ours = Join-Path $PSScriptRoot 'out\fh2net.dll'
$isOurs = { (Test-Path $cur) -and ([IO.File]::ReadAllText($cur, [Text.Encoding]::ASCII).Contains('fh2net probe loaded')) }
if ($Uninstall) {
  if (-not (Test-Path $next)) { throw 'Not installed (no azimuth-tls-next.dll).' }
  if (-not (& $isOurs)) { throw 'azimuth-tls.dll is not fh2net; left alone.' }
  Remove-Item $cur; Rename-Item $next 'azimuth-tls.dll'
  Write-Host 'fh2net removed; azimuth-tls.dll restored.'
  return
}
if (-not (Test-Path $ours)) { throw "Build first: $ours" }
if (-not (Test-Path $next)) {
  if (& $isOurs) { throw 'azimuth-tls.dll is fh2net but azimuth-tls-next.dll is missing.' }
  Rename-Item $cur 'azimuth-tls-next.dll'
}
Copy-Item $ours $cur -Force
Write-Host "fh2net installed. Log: $(Join-Path $bin 'fh2net.log')"
