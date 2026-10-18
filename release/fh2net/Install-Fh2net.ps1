<#
.SYNOPSIS
  Installs fh2net into Azimuth (or removes it with -Uninstall). Close the game first.
.DESCRIPTION
  Azimuth loads data\bin\azimuth-tls.dll. The one there now (Extra Options' for Azimuth 0.9.9, Azimuth's own for
  0.9.10, where Extra Options is winmm.dll beside azimuth.exe) is renamed azimuth-tls-next.dll and fh2net.dll takes
  its name; fh2net loads it itself, so both keep working. fh2net.ini is copied into
  data\bin only if there isn't one yet. -Uninstall puts Extra Options back as azimuth-tls.dll and leaves
  fh2net.ini (it does nothing without fh2net).
.EXAMPLE
  .\Install-Fh2net.ps1 -AzimuthRoot C:\Games\azimuth
#>
param([string]$AzimuthRoot, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
if (-not $AzimuthRoot) { $AzimuthRoot = Read-Host 'Azimuth folder (the one with azimuth.exe)' }
$AzimuthRoot = $AzimuthRoot.Trim('"').TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $AzimuthRoot 'azimuth.exe'))) { throw "No azimuth.exe in $AzimuthRoot" }
if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($AzimuthRoot + '\', [StringComparison]::OrdinalIgnoreCase) }) { throw 'Close Azimuth first.' }
$bin = Join-Path $AzimuthRoot 'data\bin'
$cur = Join-Path $bin 'azimuth-tls.dll'; $next = Join-Path $bin 'azimuth-tls-next.dll'
$isOurs = { param($p) (Test-Path -LiteralPath $p) -and ([IO.File]::ReadAllText($p, [Text.Encoding]::ASCII).Contains('fh2net probe loaded')) }

if ($Uninstall) {
  if (-not (& $isOurs $cur)) { throw 'fh2net is not installed (azimuth-tls.dll is not fh2net).' }
  if (-not (Test-Path -LiteralPath $next)) { throw 'azimuth-tls-next.dll is missing; reinstall Extra Options as azimuth-tls.dll.' }
  Remove-Item -LiteralPath $cur; Rename-Item -LiteralPath $next 'azimuth-tls.dll'
  Write-Host 'fh2net removed; Extra Options is azimuth-tls.dll again.'
  return
}
$ours = Join-Path $PSScriptRoot 'fh2net.dll'
if (-not (Test-Path -LiteralPath $ours)) { throw "fh2net.dll is missing next to this script; run it from the extracted release." }
if (-not (Test-Path -LiteralPath $cur)) { throw "No azimuth-tls.dll in $bin. Install Extra Options first." }
if (& $isOurs $cur) {
  if (-not (Test-Path -LiteralPath $next)) { throw 'azimuth-tls.dll is fh2net but azimuth-tls-next.dll is missing; put Extra Options there.' }
  Write-Host 'Updating fh2net.'
} else {
  if (Test-Path -LiteralPath $next) { throw "Both azimuth-tls.dll and azimuth-tls-next.dll exist and neither is fh2net; move one away first." }
  # Extra Options is winmm.dll beside azimuth.exe for Azimuth 0.9.10+, azimuth-tls.dll (0.2.74+) for 0.9.9
  $eoWinmm = Join-Path $AzimuthRoot 'winmm.dll'
  $eoFound = ((Test-Path -LiteralPath $eoWinmm) -and [IO.File]::ReadAllText($eoWinmm, [Text.Encoding]::ASCII).Contains('game:\mediapc\')) -or
    [IO.File]::ReadAllText($cur, [Text.Encoding]::ASCII).Contains('game:\mediapc\')
  if (-not $eoFound) { Write-Warning 'Extra Options was not found (winmm.dll beside azimuth.exe, or azimuth-tls.dll 0.2.74+); continuing anyway.' }
  Rename-Item -LiteralPath $cur 'azimuth-tls-next.dll'
}
Copy-Item -LiteralPath $ours $cur -Force
$ini = Join-Path $bin 'fh2net.ini'
if (Test-Path -LiteralPath $ini) { Write-Host "Kept your $ini" } else { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fh2net.ini') $ini; Write-Host "Copied fh2net.ini to $ini; edit it (see README.md)." }
Write-Host "fh2net installed. Log: $(Join-Path $bin 'fh2net.log')"
