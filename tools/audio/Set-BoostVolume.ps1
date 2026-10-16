<#
.SYNOPSIS
  Makes cars' turbo and supercharger sounds louder (or quieter) in Forza Horizon 2 (PC / Azimuth).

.DESCRIPTION
  FH2's car sounds are FMOD banks (Mount\media\audio\fmodanthem\durango\PG_<car>.bank). In each, the turbo, the
  positive-displacement supercharger (DSC) and the centrifugal supercharger (CSC) are separate sounds, played when the
  car has that part fitted (tools\audio\FmodBank.cs). This changes their volume by the given dB, starting from your
  game's own bank each time (so running it again replaces the earlier change), and writes the bank to Mount\mediapc,
  which Extra Options (0.2.74+, [Files] EnableMediaOverrides=1) makes the game read first. The game's own files are
  not changed. Tune-CarSound.cmd has sliders for these and the rest of a car's sound (exhaust, engine, intake, ...);
  both keep the same per-car settings, so settings this doesn't pass stay as they are.

  The blow-off valve (BOV) sounds have their own tracks, set with -BOV; where they're part of the turbo sound, -Turbo
  raises them too and -BOV adds on top.

  FH2 plays the same turbo sounds for single and twin turbos, so -Turbo covers both. Not every car has every sound
  (-List shows which do). Imported FM5 cars use the FH2 car their sound was borrowed from.

  -Remove deletes the banks this tool wrote (all, or -Car's). Close the game first.

.EXAMPLE
  .\tools\audio\Set-BoostVolume.ps1 -Car FOR_MustangGT500_13 -DSC 12
.EXAMPLE
  .\tools\audio\Set-BoostVolume.ps1 -Car all -Turbo 6 -DSC 6 -CSC 6
.EXAMPLE
  .\tools\audio\Set-BoostVolume.ps1 -List -Car '*Mustang*'
.EXAMPLE
  .\tools\audio\Set-BoostVolume.ps1 -Remove
#>
[CmdletBinding()]
param(
  [string[]]$Car,             # car MediaNames (FOR_MustangGT500_13), part of a name (mustang), wildcards, or all
  [double]$Turbo = 0,         # dB to add to the turbo sounds (-80 to 48; 0 = leave as stock)
  [double]$DSC = 0,           # dB to add to the positive-displacement supercharger sounds
  [double]$CSC = 0,           # dB to add to the centrifugal supercharger sounds
  [double]$BOV = 0,           # dB to add to the blow-off valve sounds (on top of -Turbo where they're part of the turbo sound)
  [switch]$List,              # show which cars have which sounds, and what's set
  [switch]$Remove,            # delete the banks this tool wrote (all, or -Car's)
  [string]$GameRoot,          # FH2 folder containing Mount (default: Azimuth's game_folder, as the importer remembers it)
  [string]$AzimuthRoot        # folder containing azimuth.exe
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CarSound.ps1')
function Ask([string]$prompt) { $a = Read-Host $prompt; if ($null -eq $a) { throw 'Input ended' }; $a.Trim() }
$interactive = -not $Car -and -not $List -and -not $Remove
$boost = 'Turbo', 'DSC', 'CSC', 'BOV'

$ctx = Resolve-CarSoundFolders $GameRoot $AzimuthRoot -Ask:$interactive
function Resolve-Cars([string[]]$names) {
  if (-not $names -or $names -contains 'all') { return $ctx.Cars }
  $out = foreach ($n in $names) {
    $hit = Find-Cars $ctx $n
    if (-not $hit) { throw "No car sound bank matches '$n' (names are MediaNames like FOR_MustangGT500_13; -List shows them)" }
    $hit
  }
  @($out | Sort-Object -Unique)
}
function Kinds-Of($bank) { ($bank.Sounds | Group-Object Kind | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ' }
function Set-Of([string]$c) {
  $s = Get-CarSoundSettings $ctx $c; $set = @($s.Keys | Where-Object { $s[$_] } | ForEach-Object { "$_ $($s[$_])" })
  if ($set) { "set: $($set -join ', ') dB" }
}

$interactiveGiven = @()
if ($interactive) {
  Write-Host "`nTurbo / supercharger volume for FH2 cars`n" -ForegroundColor Cyan
  Write-Host "Pick the cars: type part of a name (e.g. mustang, 'camaro 69'), then numbers from the list; 'all' for every car."
  $picked = @()
  while ($true) {
    $a = Ask "`nCar to change$(if ($picked) { ' (Enter when done)' })"
    if (-not $a) { if ($picked) { break } else { continue } }
    if ($a -ieq 'all') { $picked = $ctx.Cars; Write-Host "  all $($ctx.Cars.Count) cars"; break }
    $hits = Find-Cars $ctx $a
    if (-not $hits) { Write-Host '  No match. Try part of the name, e.g. "mustang" or "gt500".' -ForegroundColor Yellow; continue }
    if ($hits.Count -gt 1) {
      for ($i = 0; $i -lt $hits.Count; $i++) {
        $b = Read-CarBank $ctx $hits[$i]
        Write-Host ('  {0,3}) {1,-32} {2,-32} {3}' -f ($i + 1), $hits[$i], $(if ($b.Sounds.Count) { Kinds-Of $b } else { '(none)' }), (Set-Of $hits[$i]))
      }
      $sel = Ask "  Numbers (e.g. 1,3 or 2-4), 'a' for all $($hits.Count), Enter to search again"
      if (-not $sel) { continue }
      if ($sel -ieq 'a') { $chosen = $hits }
      else {
        $nums = @($sel -split '\s*,\s*' | ForEach-Object {
          if ($_ -match '^(\d+)\s*-\s*(\d+)$') { [int]$Matches[1]..[int]$Matches[2] } elseif ($_ -match '^\d+$') { [int]$_ }
        })
        $chosen = @($nums | Where-Object { $_ -ge 1 -and $_ -le $hits.Count } | ForEach-Object { $hits[$_ - 1] })
        if (-not $chosen) { Write-Host '  Type numbers from the list.' -ForegroundColor Yellow; continue }
      }
    } else { $chosen = $hits }
    $picked = @($picked + $chosen | Sort-Object -Unique)
    Write-Host "  added: $($chosen -join ', ')" -ForegroundColor Green
  }
  $Car = $picked
  Write-Host "`ndB to add to each sound (0 = stock; +6 is about twice as loud, +24 is loud; up to 48). Enter keeps each car's current setting."
  foreach ($k in @(@('Turbo', 'Turbo (single and twin)'), @('DSC', 'Positive-displacement supercharger (DSC)'), @('CSC', 'Centrifugal supercharger (CSC)'), @('BOV', 'Blow-off valve (BOV)'))) {
    $a = Ask "  $($k[1])"
    if ($a) { Set-Variable $k[0] ([double]$a); $interactiveGiven += $k[0] }
  }
  if (-not $interactiveGiven) { Write-Host 'Nothing to change.'; return }
}
$cars = Resolve-Cars $Car

if ($List) {
  foreach ($c in $cars) {
    $b = Read-CarBank $ctx $c
    "{0,-34} {1,-34} {2}" -f $c, $(if ($b.Sounds.Count) { Kinds-Of $b } else { '(no turbo/supercharger sounds)' }), (Set-Of $c)
  }
  return
}

if (Test-GameRunning $ctx) { throw 'Close the game first.' }
if ($Remove) {
  $targets = if ($Car) { $cars } else { @($ctx.Manifest.Keys) }
  $n = 0; foreach ($c in $targets) { if (Remove-CarSound $ctx $c) { $n++ } }
  Write-Host "Removed $n bank(s); those cars sound stock again."
  return
}

foreach ($g in $Turbo, $DSC, $CSC, $BOV) { if ($g -lt -80 -or $g -gt 48) { throw 'Gains must be between -80 and 48 dB' } }
# the settings given now; the others (here and from Tune-CarSound) keep what was set before
$given = @($boost | Where-Object { $interactiveGiven -contains $_ -or $PSBoundParameters.ContainsKey($_) })
if (-not $given) { throw 'Pass -Turbo, -DSC, -CSC and/or -BOV (dB to add; 0 = stock), or -Remove' }
$ini = if ($ctx.AzimuthRoot) { Join-Path $ctx.AzimuthRoot 'data\bin\FH2_ExtraOptions.ini' }
if ($ini -and (Test-Path $ini) -and (Get-Content $ini -Raw) -notmatch '(?m)^\s*EnableMediaOverrides\s*=\s*1') {
  Write-Warning "Extra Options' [Files] EnableMediaOverrides isn't 1 in $ini; the game won't read Mount\mediapc until it is (the FM5 car importer turns it on)."
}
$asked = @{ Turbo = $Turbo; DSC = $DSC; CSC = $CSC; BOV = $BOV }
$done = 0
foreach ($c in $cars) {
  $s = Get-CarSoundSettings $ctx $c
  foreach ($k in $given) { $s[$k] = $asked[$k] }
  $b = Read-CarBank $ctx $c
  foreach ($x in $b.Skipped) { Write-Warning "$c $x; left as it is" }
  $has = @($b.Sounds | ForEach-Object Kind)
  if ($cars.Count -le 5 -and -not ($given | Where-Object { $has -contains $_ -and $asked[$_] })) {
    $want = @($given | Where-Object { $asked[$_] })
    if ($want) { Write-Host "$c has no $($want -join '/') sounds ($(if ($has) { Kinds-Of $b } else { 'none' }))" }
  }
  try { $r = Write-CarSound $ctx $c $s } catch { Write-Warning "$_; $c skipped"; continue }
  if ($r -notmatch 'is stock$' -or $cars.Count -le 5) { Write-Host ("{0}  ({1})" -f $r, ((Set-Of $c) -replace '^set: ', '')) }
  if ($r -notmatch 'is stock$') { $done++ }
}
Write-Host "`n$done car(s) changed. Start the game to hear it; -Remove puts them back."
