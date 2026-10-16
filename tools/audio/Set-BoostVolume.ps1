<#
.SYNOPSIS
  Makes cars' turbo and supercharger sounds louder (or quieter) in Forza Horizon 2 (PC / Azimuth).

.DESCRIPTION
  FH2's car sounds are FMOD banks (Mount\media\audio\fmodanthem\durango\PG_<car>.bank). In each, the turbo, the
  positive-displacement supercharger (DSC) and the centrifugal supercharger (CSC) are separate sounds, played when the
  car has that part fitted (tools\audio\FmodBank.cs). This changes their volume by the given dB, starting from your
  game's own bank each time (so running it again replaces the earlier change), and writes the bank to Mount\mediapc,
  which Extra Options (0.2.74+, [Files] EnableMediaOverrides=1) makes the game read first. The game's own files are
  not changed.

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
  [string[]]$Car,             # car MediaNames (FOR_MustangGT500_13), wildcards ('*Mustang*'), or all
  [double]$Turbo = 0,         # dB to add to the turbo sounds (-80 to 24; 0 = leave as stock)
  [double]$DSC = 0,           # dB to add to the positive-displacement supercharger sounds
  [double]$CSC = 0,           # dB to add to the centrifugal supercharger sounds
  [switch]$List,              # show which cars have which sounds, and what this tool has set
  [switch]$Remove,            # delete the banks this tool wrote (all, or -Car's)
  [string]$GameRoot,          # FH2 folder containing Mount (default: Azimuth's game_folder, as the importer remembers it)
  [string]$AzimuthRoot        # folder containing azimuth.exe
)
$ErrorActionPreference = 'Stop'
if (-not ('FmodBank' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'FmodBank.cs') -ReferencedAssemblies System.Core }
function Ask([string]$prompt) { $a = Read-Host $prompt; if ($null -eq $a) { throw 'Input ended' }; $a.Trim() }
$interactive = -not $Car -and -not $List -and -not $Remove

# --- folders: parameters, then the importer's remembered ones / Azimuth's game_folder ---
$settingsPath = Join-Path $env:LOCALAPPDATA 'fh2-mods\import-fm5-cars.json'
$saved = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $AzimuthRoot) { $AzimuthRoot = $saved.AzimuthRoot }
if (-not $GameRoot -and $AzimuthRoot -and (Test-Path "$AzimuthRoot\data\azimuth.ini")) {
  $m = [regex]::Match((Get-Content "$AzimuthRoot\data\azimuth.ini" -Raw), '(?m)^game_folder=(.+?)\s*$'); if ($m.Success) { $GameRoot = $m.Groups[1].Value }
}
if (-not $GameRoot) { $GameRoot = $saved.GameRoot }
if ($interactive -or -not $GameRoot) {
  $a = (Ask "FH2 game folder$(if ($GameRoot) { " [$GameRoot]" })").Trim('"'); if ($a) { $GameRoot = $a }
}
$GameRoot = $GameRoot.TrimEnd('\')
if (-not (Test-Path (Join-Path $GameRoot 'Mount\forza_durango_release_final.exe'))) { throw "Not an FH2 game folder (no Mount\forza_durango_release_final.exe): $GameRoot" }
$stockDir = Join-Path $GameRoot 'Mount\media\audio\fmodanthem\durango'
$outDir = Join-Path $GameRoot 'Mount\mediapc\audio\fmodanthem\durango'
$manifestPath = Join-Path $outDir 'boost-volume.json'   # what this tool wrote: car -> gains and the file's SHA-256
$manifest = @{}
if (Test-Path $manifestPath) { (Get-Content $manifestPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $manifest[$_.Name] = $_.Value } }
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Save-Manifest {
  if ($manifest.Count) { [pscustomobject]$manifest | ConvertTo-Json | Set-Content $manifestPath -Encoding UTF8 }
  elseif (Test-Path $manifestPath) { Remove-Item $manifestPath }
}
function Assert-Closed {   # the game's Azimuth (any Azimuth when it isn't known)
  if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $(if ($AzimuthRoot) { $_.Path.StartsWith($AzimuthRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) } else { $_.Path -like '*\azimuth.exe' }) }) { throw 'Close the game first.' }
}

$allCars = @(Get-ChildItem $stockDir -Filter 'PG_*.bank' | ForEach-Object { $_.BaseName.Substring(3) } | Sort-Object)
function Resolve-Cars([string[]]$names) {
  if (-not $names -or $names -contains 'all') { return $allCars }
  $out = foreach ($n in $names) {
    $hit = @($allCars | Where-Object { $_ -like $n })
    if (-not $hit) { throw "No car sound bank matches '$n' (names are MediaNames like FOR_MustangGT500_13; -List shows them)" }
    $hit
  }
  @($out | Sort-Object -Unique)
}
function Read-Bank([string]$c) { New-Object FmodBank (, [IO.File]::ReadAllBytes((Join-Path $stockDir "PG_$c.bank"))) }
function Kinds-Of($bank) { ($bank.Sounds | Group-Object Kind | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ' }

if ($interactive) {
  Write-Host "`nTurbo / supercharger volume for FH2 cars`n" -ForegroundColor Cyan
  Write-Host 'Cars: MediaNames like FOR_MustangGT500_13, wildcards like *Mustang*, or all (comma-separated).'
  $Car = @((Ask 'Cars') -split '\s*,\s*' | Where-Object { $_ })
  if (-not $Car) { return }
  Write-Host 'dB to add to each sound (0 = stock; +6 is about twice as loud, +24 is very loud; up to 24).'
  $Turbo = [double]('0' + (Ask 'Turbo (single and twin) [0]')); $DSC = [double]('0' + (Ask 'Positive-displacement supercharger (DSC) [0]')); $CSC = [double]('0' + (Ask 'Centrifugal supercharger (CSC) [0]'))
}
$cars = Resolve-Cars $Car

if ($List) {
  foreach ($c in $cars) {
    $b = Read-Bank $c; $set = $manifest[$c]
    "{0,-34} {1,-34} {2}" -f $c, $(if ($b.Sounds.Count) { Kinds-Of $b } else { '(no turbo/supercharger sounds)' }),
      $(if ($set) { "set: Turbo $($set.Turbo), DSC $($set.DSC), CSC $($set.CSC) dB" })
  }
  return
}

Assert-Closed
if ($Remove) {
  $targets = if ($Car) { $cars } else { @($manifest.Keys) }
  $n = 0
  foreach ($c in $targets) {
    if (-not $manifest.ContainsKey($c)) { continue }
    $p = Join-Path $outDir "PG_$c.bank"
    if ((Test-Path $p) -and (Sha $p) -ne $manifest[$c].sha256) { Write-Warning "$p changed since this tool wrote it (another mod?); left in place"; $manifest.Remove($c); continue }
    if (Test-Path $p) { Remove-Item $p }
    $manifest.Remove($c); $n++
  }
  Save-Manifest
  Write-Host "Removed $n bank(s); those cars sound stock again."
  return
}

foreach ($g in $Turbo, $DSC, $CSC) { if ($g -lt -80 -or $g -gt 24) { throw 'Gains must be between -80 and 24 dB' } }
# the kinds given now; the others keep what this tool set before (so -Turbo later doesn't undo an earlier -DSC)
$given = @('Turbo', 'DSC', 'CSC' | Where-Object { $interactive -or $PSBoundParameters.ContainsKey($_) })
if (-not $given) { throw 'Pass -Turbo, -DSC and/or -CSC (dB to add; 0 = stock), or -Remove' }
$ini = if ($AzimuthRoot) { Join-Path $AzimuthRoot 'data\bin\FH2_ExtraOptions.ini' }
if ($ini -and (Test-Path $ini) -and (Get-Content $ini -Raw) -notmatch '(?m)^\s*EnableMediaOverrides\s*=\s*1') {
  Write-Warning "Extra Options' [Files] EnableMediaOverrides isn't 1 in $ini; the game won't read Mount\mediapc until it is (the FM5 car importer turns it on)."
}
New-Item -ItemType Directory $outDir -Force | Out-Null
$asked = @{ Turbo = $Turbo; DSC = $DSC; CSC = $CSC }
$done = 0
foreach ($c in $cars) {
  $gain = New-Object 'System.Collections.Generic.Dictionary[string,float]'
  foreach ($k in 'Turbo', 'DSC', 'CSC') { $gain[$k] = $(if ($given -contains $k) { $asked[$k] } elseif ($manifest.ContainsKey($c)) { $manifest[$c].$k } else { 0 }) }
  $b = Read-Bank $c
  foreach ($s in $b.Skipped) { Write-Warning "$c $s; left as it is" }
  $n = $b.Apply($gain)
  $out = Join-Path $outDir "PG_$c.bank"
  if ((Test-Path $out) -and -not ($manifest.ContainsKey($c) -and (Sha $out) -eq $manifest[$c].sha256)) {
    Write-Warning "$out exists and isn't this tool's (another mod?); $c skipped"; continue
  }
  if (-not $n) {   # nothing of the asked kinds: stock again
    if ($manifest.ContainsKey($c)) { if (Test-Path $out) { Remove-Item $out }; $manifest.Remove($c) }
    if ($cars.Count -le 5) {
      $want = @('Turbo', 'DSC', 'CSC' | Where-Object { $gain[$_] })
      Write-Host $(if ($want) { "$c has no $($want -join '/') sounds ($(if ($b.Sounds.Count) { Kinds-Of $b } else { 'none' }))" } else { "$c is stock" })
    }
    continue
  }
  [IO.File]::WriteAllBytes("$out.fh2-new", $b.Data); Move-Item -Force "$out.fh2-new" $out
  $manifest[$c] = [pscustomobject]@{ Turbo = $gain['Turbo']; DSC = $gain['DSC']; CSC = $gain['CSC']; sha256 = (Sha $out) }
  Write-Host ("{0,-34} Turbo {1}, DSC {2}, CSC {3} dB: {4} sound(s) changed (has {5})" -f $c, $gain['Turbo'], $gain['DSC'], $gain['CSC'], $n, (Kinds-Of $b))
  $done++
}
Save-Manifest
Write-Host "`n$done car(s) changed. Start the game to hear it; -Remove puts them back."
