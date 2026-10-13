<#
.SYNOPSIS
  Writes a copy of the Azimuth 0.9.7 launcher that accepts a given Mount\hash.manifest.

.DESCRIPTION
  Azimuth validates the game's file index (Mount\hash.manifest) by its exact size and SHA-256. Files missing from the
  index are invisible to the game, so mods that add files (e.g. imported cars) need a larger index and a launcher that
  expects it. Two spots change; nothing else:
    raw offset 0x252910  64 ASCII hex chars: expected SHA-256 of hash.manifest (null-terminated)
    raw offset 0x1C06E4  cmp qword [rbp-0x48], imm32: expected size of hash.manifest (imm32 at 0x1C06E8)
  Offsets from the GT500 patch guide. The input may be the stock 0.9.7 launcher or one already patched this way
  (e.g. by an earlier mod): it's identified by its SHA-256 with those two spots blanked. Other builds are refused.

.EXAMPLE
  .\tools\Patch-Azimuth.ps1 -Azimuth G:\FH2-1\azimuth\azimuth.exe -Index G:\FH2-1\game\Mount\hash.manifest -Out G:\FH2-1\azimuth\azimuth.exe
#>
param(
  [Parameter(Mandatory)][string]$Azimuth,   # Azimuth 0.9.7 launcher, stock or already patched
  [Parameter(Mandatory)][string]$Index,     # the hash.manifest the game will use
  [Parameter(Mandatory)][string]$Out
)
$ErrorActionPreference = 'Stop'
$MaskedSha = '300a259728b6f28fe612a237aaebb74538fbbf35da6b3e2fb5762d19e2b1224f'   # stock 0.9.7 with both spots zeroed
$HashOffset = 0x252910
$CmpOffset = 0x1C06E4
$CmpPrefix = [byte[]](0x48, 0x81, 0x7D, 0xB8)

function Sha([byte[]]$b) { -join ([Security.Cryptography.SHA256]::Create().ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) }

$exe = [IO.File]::ReadAllBytes((Resolve-Path $Azimuth).Path)
$masked = [byte[]]$exe.Clone()
[Array]::Clear($masked, $HashOffset, 64); [Array]::Clear($masked, $CmpOffset + 4, 4)
if ((Sha $masked) -ne $MaskedSha) { throw "Not an Azimuth 0.9.7 launcher (stock or index-patched); SHA-256 $(Sha $exe)" }
for ($i = 0; $i -lt 4; $i++) { if ($exe[$CmpOffset + $i] -ne $CmpPrefix[$i]) { throw 'Size comparison instruction not found at the expected offset' } }
if ($exe[$HashOffset + 64] -ne 0) { throw 'Index hash literal not found at the expected offset' }
$idx = [IO.File]::ReadAllBytes((Resolve-Path $Index).Path)
if ($idx.Length % 12) { throw "Index size $($idx.Length) isn't a multiple of 12 bytes" }
$idxSha = Sha $idx

$patched = [byte[]]$exe.Clone()
[Array]::Copy([Text.Encoding]::ASCII.GetBytes($idxSha), 0, $patched, $HashOffset, 64)
[Array]::Copy([BitConverter]::GetBytes([uint32]$idx.Length), 0, $patched, $CmpOffset + 4, 4)

$Out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)   # .NET would resolve relative paths elsewhere
[IO.File]::WriteAllBytes($Out, $patched)
Write-Host "Wrote ${Out}: expects hash.manifest of $($idx.Length) bytes, SHA-256 $idxSha"
