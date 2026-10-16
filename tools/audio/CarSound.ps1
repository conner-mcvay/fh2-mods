# Shared by Set-BoostVolume.ps1 and Tune-CarSound.ps1 (dot-source it): the game folders, the car list, and writing a
# car's tuned bank. A car's settings (FmodBank.Settings, each added to stock; 0 = stock) are built from the game's own
# bank in Mount\media every time and written to Mount\mediapc; car-sound.json next to them lists what was written
# (settings + SHA-256), so banks another mod put there are never overwritten and -Remove only deletes these.
if (-not ('FmodBank' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'FmodBank.cs') -ReferencedAssemblies System.Core }

function Resolve-CarSoundFolders([string]$GameRoot, [string]$AzimuthRoot, [switch]$Ask) {
  # parameters, then the FM5 importer's remembered folders / Azimuth's game_folder
  $settingsPath = Join-Path $env:LOCALAPPDATA 'fh2-mods\import-fm5-cars.json'
  $saved = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
  if (-not $AzimuthRoot) { $AzimuthRoot = $saved.AzimuthRoot }
  if (-not $GameRoot -and $AzimuthRoot -and (Test-Path "$AzimuthRoot\data\azimuth.ini")) {
    $m = [regex]::Match((Get-Content "$AzimuthRoot\data\azimuth.ini" -Raw), '(?m)^game_folder=(.+?)\s*$'); if ($m.Success) { $GameRoot = $m.Groups[1].Value }
  }
  if (-not $GameRoot) { $GameRoot = $saved.GameRoot }
  if ($Ask -or -not $GameRoot) {
    $a = Read-Host "FH2 game folder$(if ($GameRoot) { " [$GameRoot]" })"; if ($null -eq $a) { throw 'Input ended' }
    if ($a.Trim().Trim('"')) { $GameRoot = $a.Trim().Trim('"') }
  }
  if (-not $GameRoot) { throw 'No FH2 game folder (pass -GameRoot)' }
  $GameRoot = $GameRoot.TrimEnd('\')
  if (-not (Test-Path (Join-Path $GameRoot 'Mount\forza_durango_release_final.exe'))) { throw "Not an FH2 game folder (no Mount\forza_durango_release_final.exe): $GameRoot" }
  $ctx = [pscustomobject]@{
    GameRoot = $GameRoot; AzimuthRoot = $AzimuthRoot
    StockDir = Join-Path $GameRoot 'Mount\media\audio\fmodanthem\durango'
    OutDir = Join-Path $GameRoot 'Mount\mediapc\audio\fmodanthem\durango'
    Manifest = @{}
  }
  $ctx | Add-Member Cars @(Get-ChildItem $ctx.StockDir -Filter 'PG_*.bank' | ForEach-Object { $_.BaseName.Substring(3) } | Sort-Object)
  foreach ($f in 'boost-volume.json', 'car-sound.json') {   # boost-volume.json: what Set-BoostVolume wrote before
    $p = Join-Path $ctx.OutDir $f
    if (Test-Path $p) { (Get-Content $p -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $ctx.Manifest[$_.Name] = $_.Value } }
  }
  $ctx
}

function Save-CarSoundManifest($ctx) {
  $p = Join-Path $ctx.OutDir 'car-sound.json'
  if ($ctx.Manifest.Count) { New-Item -ItemType Directory $ctx.OutDir -Force | Out-Null; [pscustomobject]$ctx.Manifest | ConvertTo-Json -Depth 3 | Set-Content $p -Encoding UTF8 }
  elseif (Test-Path $p) { Remove-Item $p }
  $old = Join-Path $ctx.OutDir 'boost-volume.json'; if (Test-Path $old) { Remove-Item $old }
}

function Test-GameRunning($ctx) {   # any Azimuth: the remembered one may not be the one that runs this game folder
  [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ($_.Path -like '*\azimuth.exe' -or ($ctx.AzimuthRoot -and $_.Path.StartsWith($ctx.AzimuthRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase))) })
}

function Find-Cars($ctx, [string]$term) {
  # the exact name; a wildcard pattern (*Mustang*); or every car whose name holds all the words (mustang, 'camaro 69')
  $exact = @($ctx.Cars | Where-Object { $_ -ieq $term }); if ($exact) { return $exact }
  if ($term -match '[*?]') { return @($ctx.Cars | Where-Object { $_ -like $term }) }
  $words = @($term -split '\s+' | Where-Object { $_ })
  @($ctx.Cars | Where-Object { $n = $_; -not ($words | Where-Object { $n -notlike "*$_*" }) })
}

function Read-CarBank($ctx, [string]$car) { New-Object FmodBank (, [IO.File]::ReadAllBytes((Join-Path $ctx.StockDir "PG_$car.bank"))) }

function Get-CarSoundSettings($ctx, [string]$car) {   # what this tool set for the car (all settings; 0 when not set)
  $h = [ordered]@{}; $e = $ctx.Manifest[$car]
  foreach ($k in [FmodBank]::Settings) { $h[$k] = $(if ($e -and $null -ne $e.$k) { [double]$e.$k } else { 0.0 }) }
  $h
}

# Writes the car's bank with these settings (or removes it when they're all 0). Returns a status line; throws when the
# file in mediapc isn't this tool's.
function Write-CarSound($ctx, [string]$car, $settings) {
  $out = Join-Path $ctx.OutDir "PG_$car.bank"
  if ((Test-Path $out) -and -not ($ctx.Manifest.ContainsKey($car) -and (Get-FileHash $out -Algorithm SHA256).Hash.ToLowerInvariant() -eq $ctx.Manifest[$car].sha256)) {
    throw "$out exists and wasn't written by this tool (another mod, or a hand edit); move it away first"
  }
  $bank = Read-CarBank $ctx $car
  $d = New-Object 'System.Collections.Generic.Dictionary[string,float]'
  foreach ($k in [FmodBank]::Settings) { $d[$k] = [float]$(if ($null -ne $settings[$k]) { $settings[$k] } else { 0 }) }
  $n = $bank.Tune($d)
  if (-not $n) {
    if (Test-Path $out) { Remove-Item $out }
    $ctx.Manifest.Remove($car); Save-CarSoundManifest $ctx
    return "$car is stock"
  }
  New-Item -ItemType Directory $ctx.OutDir -Force | Out-Null
  [IO.File]::WriteAllBytes("$out.fh2-new", $bank.Data); Move-Item -Force "$out.fh2-new" $out
  $entry = [ordered]@{}; foreach ($k in [FmodBank]::Settings) { if ($d[$k]) { $entry[$k] = $d[$k] } }
  $entry['sha256'] = (Get-FileHash $out -Algorithm SHA256).Hash.ToLowerInvariant()
  $ctx.Manifest[$car] = [pscustomobject]$entry; Save-CarSoundManifest $ctx
  "$car written ($n value(s) changed)"
}

function Remove-CarSound($ctx, [string]$car) {
  if (-not $ctx.Manifest.ContainsKey($car)) { return $false }
  $p = Join-Path $ctx.OutDir "PG_$car.bank"
  if ((Test-Path $p) -and (Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ctx.Manifest[$car].sha256) { Write-Warning "$p changed since this tool wrote it (another mod?); left in place" }
  elseif (Test-Path $p) { Remove-Item $p }
  $ctx.Manifest.Remove($car); Save-CarSoundManifest $ctx
  $true
}
