<#
.SYNOPSIS
  Makes a copy of the stock Azimuth 0.9.7 launcher that accepts a given Mount\hash.manifest.

.DESCRIPTION
  Azimuth validates the game's file index (Mount\hash.manifest) by its exact size and SHA-256. Files missing from the
  index are invisible to the game, so mods that add files (e.g. imported cars) need a larger index and a launcher that
  expects it. Two spots change; nothing else:
    raw offset 0x252910  64 ASCII hex chars: expected SHA-256 of hash.manifest (null-terminated)
    raw offset 0x1C06E4  cmp qword [rbp-0x48], imm32: expected size of hash.manifest (imm32 at 0x1C06E8)
  Offsets from the GT500 patch guide, verified against the stock 0.9.7 build (SHA-256 below). Other builds are refused.

.EXAMPLE
  .\tools\Patch-Azimuth.ps1 -Azimuth G:\FH2-1\backups\azimuth-stock.exe -Index build\my-setup\hash.manifest -Out G:\FH2-1\azimuth\azimuth.exe
#>
param(
  [Parameter(Mandatory)][string]$Azimuth,   # untouched stock azimuth.exe
  [Parameter(Mandatory)][string]$Index,     # the hash.manifest the game will use
  [Parameter(Mandatory)][string]$Out
)
$ErrorActionPreference = 'Stop'
$StockSha = '5d3ce30b440dab2604fe42ff7cd129394f0b98418e22b2a44270f548199bc6a9'
$StockIndexSha = '56943e86659f7003eb66b9b23d8a5094e79bffa5d951d5439c98deb4f2a4a7b7'
$HashOffset = 0x252910
$CmpOffset = 0x1C06E4
$CmpPrefix = [byte[]](0x48, 0x81, 0x7D, 0xB8)
$StockSize = 0x7134

function Sha([byte[]]$b) { -join ([Security.Cryptography.SHA256]::Create().ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) }

$exe = [IO.File]::ReadAllBytes((Resolve-Path $Azimuth).Path)
if ((Sha $exe) -ne $StockSha) { throw "Not the stock Azimuth 0.9.7 launcher (SHA-256 $(Sha $exe)); pass the untouched original" }
$idx = [IO.File]::ReadAllBytes((Resolve-Path $Index).Path)
if ($idx.Length % 12) { throw "Index size $($idx.Length) isn't a multiple of 12 bytes" }
$idxSha = Sha $idx

# confirm both spots hold the stock values before touching them
if ([Text.Encoding]::ASCII.GetString($exe, $HashOffset, 64) -ne $StockIndexSha -or $exe[$HashOffset + 64] -ne 0) { throw 'Index hash literal not found at the expected offset' }
for ($i = 0; $i -lt 4; $i++) { if ($exe[$CmpOffset + $i] -ne $CmpPrefix[$i]) { throw 'Size comparison instruction not found at the expected offset' } }
if ([BitConverter]::ToUInt32($exe, $CmpOffset + 4) -ne $StockSize) { throw 'Unexpected stock index size immediate' }

$patched = [byte[]]$exe.Clone()
[Array]::Copy([Text.Encoding]::ASCII.GetBytes($idxSha), 0, $patched, $HashOffset, 64)
[Array]::Copy([BitConverter]::GetBytes([uint32]$idx.Length), 0, $patched, $CmpOffset + 4, 4)

$changed = @(for ($i = 0; $i -lt $exe.Length; $i++) { if ($exe[$i] -ne $patched[$i]) { $i } })
$allowed = { param($i) ($i -ge $HashOffset -and $i -lt $HashOffset + 64) -or ($i -ge $CmpOffset + 4 -and $i -lt $CmpOffset + 8) }
foreach ($i in $changed) { if (-not (& $allowed $i)) { throw "Unexpected change at 0x$($i.ToString('X'))" } }

$Out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)   # .NET would resolve relative paths elsewhere
[IO.File]::WriteAllBytes($Out, $patched)
Write-Host "Wrote $Out ($($changed.Count) bytes changed): expects hash.manifest of $($idx.Length) bytes, SHA-256 $idxSha"
