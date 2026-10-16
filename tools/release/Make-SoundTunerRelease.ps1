<#
.SYNOPSIS
  Packages the car sound tuner as a release zip: dist\car-sound-tuner-<Version>.zip.

.DESCRIPTION
  Copies the tuner (tools\audio), its launchers and the user docs (release\car-sound-tuner) into a clean folder with
  the same layout as the repo, so the scripts' relative paths keep working, then zips it. No game files are included.
  -Test extracts the zip and, from there, reads every car sound bank of a game folder (read-only) and lists one car.

.EXAMPLE
  .\tools\release\Make-SoundTunerRelease.ps1 -Version 1.0.0 -Test -GameRoot G:\FH2-1\game-test
#>
param(
  [Parameter(Mandatory)][string]$Version,
  [switch]$Test,          # self-test the extracted package against -GameRoot (read-only)
  [string]$GameRoot       # for -Test: an FH2 game folder
)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$name = "car-sound-tuner-$Version"
$stage = Join-Path $root "build\release\$name"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory $stage | Out-Null

$files = @(
  'Tune-CarSound.cmd', 'Set-BoostVolume.cmd', 'LICENSE'
  'tools\audio\FmodBank.cs', 'tools\audio\CarSound.ps1', 'tools\audio\Tune-CarSound.ps1'
  'tools\audio\Set-BoostVolume.ps1', 'tools\audio\Show-CarSound.ps1'
)
foreach ($f in $files) {
  $src = Join-Path $root $f; if (-not (Test-Path $src)) { throw "Missing $f" }
  $dst = Join-Path $stage $f; New-Item -ItemType Directory (Split-Path $dst) -Force | Out-Null; Copy-Item $src $dst
}
foreach ($d in Get-ChildItem (Join-Path $root 'release\car-sound-tuner') -File) { Copy-Item $d.FullName $stage }
Set-Content (Join-Path $stage 'VERSION.txt') "Car Sound Tuner $Version" -Encoding ASCII

$zip = Join-Path $root "dist\$name.zip"
New-Item -ItemType Directory (Split-Path $zip) -Force | Out-Null
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Write-Host ("Built {0} ({1:N0} KB, {2} files)`nSHA-256 {3}" -f $zip, ((Get-Item $zip).Length / 1KB), (Get-ChildItem -Recurse -File $stage).Count, $sha)

if ($Test) {
  if (-not $GameRoot) { throw 'Pass -GameRoot <FH2 game folder> with -Test' }
  $t = Join-Path ([IO.Path]::GetTempPath()) "car-sound-tuner-test-$([IO.Path]::GetRandomFileName())"
  Expand-Archive $zip $t
  try {
    # (a script file: PowerShell 5.1 mangles the quotes of a multi-line -Command argument)
    $check = Join-Path ([IO.Path]::GetTempPath()) "car-sound-tuner-check-$([IO.Path]::GetRandomFileName()).ps1"
    Set-Content $check -Encoding UTF8 -Value @'
param($Package, $GameRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $Package 'tools\audio\CarSound.ps1')
$ctx = Resolve-CarSoundFolders $GameRoot
$n = 0; foreach ($c in $ctx.Cars) { $b = Read-CarBank $ctx $c; if (@($b.Available()).Count) { $n++ } }
"$($ctx.Cars.Count) car sound banks read, $n with settings"
'@
    try { $out = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $check -Package $t -GameRoot $GameRoot) } finally { Remove-Item $check }
    if ($LASTEXITCODE -ne 0) { throw "Self-test failed: $($out -join "`n")" }
    $list = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $t 'tools\audio\Show-CarSound.ps1') -Car DOD_Dart_68 -GameRoot $GameRoot -Sheet EngineRPM 6>&1)
    if ($LASTEXITCODE -ne 0 -or -not ($list -match 'Exhaust_00720')) { throw "Self-test (Show-CarSound) failed: $($list -join "`n")" }
    Write-Host "Self-test: $($out -join ' '); Show-CarSound lists the Dart's layers"
  } finally { Remove-Item -Recurse -Force $t }
}
