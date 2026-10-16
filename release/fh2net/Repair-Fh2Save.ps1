<#
.SYNOPSIS
  Repairs saves whose single-player XP and CR payouts were zeroed by fh2srv before fh2net 0.1.2. Close the game first.
.DESCRIPTION
  The old server answered the game's economy settings with zeros, and the game keeps them in the save
  (SaveState: the ForzaEconomyState object), so events paid no XP or CR even offline. For every save under
  Azimuth's data folder whose economy has XPPerKmOffline 0, this adds a new save revision without that object;
  the game then uses its built-in values again (and the current server sends the same ones). The older
  revisions are left as they are, so nothing is lost.
.EXAMPLE
  .\Repair-Fh2Save.ps1 -AzimuthRoot C:\Games\azimuth
#>
param([string]$AzimuthRoot)
$ErrorActionPreference = 'Stop'
if (-not $AzimuthRoot) { $AzimuthRoot = Read-Host 'Azimuth folder (the one with azimuth.exe)' }
$AzimuthRoot = $AzimuthRoot.Trim('"').TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $AzimuthRoot 'azimuth.exe'))) { throw "No azimuth.exe in $AzimuthRoot" }
if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($AzimuthRoot + '\', [StringComparison]::OrdinalIgnoreCase) }) { throw 'Close Azimuth first.' }

$latin1 = [Text.Encoding]::GetEncoding(28591)   # byte-for-byte
$sha = [Security.Cryptography.SHA256]::Create()
$hex = { param($b) -join ($sha.ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) }
$econ = '(?s)[ \t]*<Object Id="ForzaEconomyState" Type="ForzaEconomyState">.*?</Object>\r?\n'
$saves = Get-ChildItem -LiteralPath (Join-Path $AzimuthRoot 'data') -Directory -Recurse |
  Where-Object { $_.Name -match '^User_[0-9A-Fa-f]+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'revisions')) }
if (-not $saves) { Write-Host 'No saves found.'; return }
foreach ($save in $saves) {
  $revs = Join-Path $save.FullName 'revisions'
  $last = Get-ChildItem -LiteralPath $revs -Directory | Where-Object Name -match '^[0-9a-f]{16}$' | Sort-Object Name | Select-Object -Last 1
  if (-not $last) { Write-Host "$($save.FullName): no revisions, skipped."; continue }
  $ssPath = Join-Path $last.FullName 'data\SaveState'; $commitPath = Join-Path $last.FullName 'commit'
  if (-not (Test-Path -LiteralPath $ssPath) -or -not (Test-Path -LiteralPath $commitPath)) { Write-Host "$($save.FullName): not an Azimuth complete save revision, skipped."; continue }
  $ss = [IO.File]::ReadAllBytes($ssPath); $text = $latin1.GetString($ss)
  $m = [regex]::Matches($text, $econ)
  if ($m.Count -ne 1 -or $m[0].Value -notmatch '<Property Name="XPPerKmOffline" Value="0"/>') { Write-Host "$($save.FullName): fine, nothing to repair."; continue }
  $new = $latin1.GetBytes($text.Remove($m[0].Index, $m[0].Length))
  $lines = $latin1.GetString([IO.File]::ReadAllBytes($commitPath)).Split("`n")
  $i = [Array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match '^[0-9a-f]{64} \d+ SaveState$' })
  if ($i -lt 0 -or $lines[$i] -ne "$(& $hex $ss) $($ss.Length) SaveState") { Write-Host "$($save.FullName): its commit file doesn't match SaveState, skipped."; continue }
  $lines[$i] = "$(& $hex $new) $($new.Length) SaveState"
  $dst = Join-Path $revs ('{0:x16}' -f ([Convert]::ToUInt64($last.Name, 16) + 1))
  Copy-Item -LiteralPath $last.FullName $dst -Recurse
  [IO.File]::WriteAllBytes((Join-Path $dst 'data\SaveState'), $new)
  [IO.File]::WriteAllBytes((Join-Path $dst 'commit'), $latin1.GetBytes($lines -join "`n"))
  Write-Host "$($save.FullName): repaired (revision $($last.Name) -> $(Split-Path $dst -Leaf)); XP and CR pay again."
}
