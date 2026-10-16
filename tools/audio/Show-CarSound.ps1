<#
.SYNOPSIS
  Lists what a car's sound is made of in Forza Horizon 2 (PC): every sound layer in its FMOD bank.

.DESCRIPTION
  For each event in the car's bank (Mount\media\audio\fmodanthem\durango\PG_<car>.bank; tools\audio\FmodBank.cs):
  the layers placed on its parameter sheets and timeline, with where they play (on an EngineRPM sheet: the RPM range
  they cover), their samples (Exhaust_00720 is the exhaust recorded at 720 rpm), their volume in dB, and "auto" when a
  parameter drives that volume (the stored value is then ignored). Reads the game's own bank (what the car sounds
  like stock), or with -Installed the one the game reads (Mount\mediapc first, i.e. with your changes).

.EXAMPLE
  .\tools\audio\Show-CarSound.ps1 -Car dart
.EXAMPLE
  .\tools\audio\Show-CarSound.ps1 -Car DOD_Dart_68 -Sheet EngineRPM
#>
param(
  [string]$Car,          # MediaName (DOD_Dart_68) or part of a name (dart); several matches are listed to pick from
  [string]$Sheet,        # only layers on this parameter's sheet (EngineRPM, Throttle, Boost, timeline, ...)
  [switch]$Installed,    # read the bank the game reads (Mount\mediapc first) instead of the stock one
  [string]$GameRoot
)
$ErrorActionPreference = 'Stop'
if (-not ('FmodBank' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'FmodBank.cs') -ReferencedAssemblies System.Core }
function Ask([string]$prompt) { $a = Read-Host $prompt; if ($null -eq $a) { throw 'Input ended' }; $a.Trim() }

$settingsPath = Join-Path $env:LOCALAPPDATA 'fh2-mods\import-fm5-cars.json'
$saved = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $GameRoot -and $saved.AzimuthRoot -and (Test-Path "$($saved.AzimuthRoot)\data\azimuth.ini")) {
  $m = [regex]::Match((Get-Content "$($saved.AzimuthRoot)\data\azimuth.ini" -Raw), '(?m)^game_folder=(.+?)\s*$'); if ($m.Success) { $GameRoot = $m.Groups[1].Value }
}
if (-not $GameRoot) { $GameRoot = $saved.GameRoot }
if (-not $GameRoot) { $GameRoot = (Ask 'FH2 game folder').Trim('"') }
$GameRoot = $GameRoot.TrimEnd('\')
$stockDir = Join-Path $GameRoot 'Mount\media\audio\fmodanthem\durango'
if (-not (Test-Path $stockDir)) { throw "No car sound banks in $stockDir" }
$allCars = @(Get-ChildItem $stockDir -Filter 'PG_*.bank' | ForEach-Object { $_.BaseName.Substring(3) } | Sort-Object)

if (-not $Car) { $Car = Ask 'Car (part of a name, e.g. dart)' }
$hits = @($allCars | Where-Object { $_ -ieq $Car })
if (-not $hits) { $words = @($Car -split '\s+' | Where-Object { $_ }); $hits = @($allCars | Where-Object { $n = $_; -not ($words | Where-Object { $n -notlike "*$_*" }) }) }
if (-not $hits) { throw "No car sound bank matches '$Car'" }
if ($hits.Count -gt 1) {
  for ($i = 0; $i -lt $hits.Count; $i++) { Write-Host ('  {0,3}) {1}' -f ($i + 1), $hits[$i]) }
  $n = Ask 'Number'; if ($n -notmatch '^\d+$' -or [int]$n -lt 1 -or [int]$n -gt $hits.Count) { throw 'Pick a number from the list' }
  $hits = @($hits[[int]$n - 1])
}
$c = $hits[0]
$path = Join-Path $stockDir "PG_$c.bank"
if ($Installed) { $pc = Join-Path $GameRoot "Mount\mediapc\audio\fmodanthem\durango\PG_$c.bank"; if (Test-Path $pc) { $path = $pc } }
$bank = New-Object FmodBank (, [IO.File]::ReadAllBytes($path))
$layers = @($bank.Layers() | Where-Object { -not $Sheet -or $_.Sheet -ieq $Sheet })

Write-Host "`n$c  ($path)" -ForegroundColor Cyan
Write-Host 'Volumes in dB; "auto" = a parameter drives it. On EngineRPM sheets the range is RPM, on the upgrade-level sheets 1-3.'
foreach ($g in $layers | Group-Object Event | Sort-Object { [int]$_.Name }) {
  $cats = @($g.Group | Where-Object Category | Group-Object Category | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object Name)
  Write-Host "`nEvent $($g.Name)$(if ($cats) { '  (' + ($cats -join ', ') + ')' })" -ForegroundColor Yellow
  foreach ($s in $g.Group | Group-Object Sheet) {
    Write-Host "  $($s.Name)"
    foreach ($l in $s.Group | Sort-Object Start, End) {
      $range = if ($s.Name -eq 'timeline') { '' } elseif ($s.Name -eq 'EngineRPM') { '{0,5:0}-{1,-5:0}' -f $l.Start, $l.End } else { '{0,5:0.##}-{1,-5:0.##}' -f $l.Start, $l.End }
      $smp = if ($l.Samples.Count -le 2) { $l.Samples -join ', ' } else { "$($l.Samples[0]) ... ($($l.Samples.Count) samples)" }
      Write-Host ('    {0,-12} {1,-6} {2,-20} {3,7} {4}' -f $range, $l.Type, $l.Category, $(if ($l.VolumeAutomated) { 'auto' } else { '{0:+0.0;-0.0;0.0}' -f $l.Volume }), $smp)
    }
  }
}
