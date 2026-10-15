<#
.SYNOPSIS
  Packages the FM5 car importer as a release zip: dist\fm5-car-importer-<Version>.zip.

.DESCRIPTION
  Copies the importer, the build/install tools it runs and the user docs (release\fm5-car-importer) into a clean
  folder with the same layout as the repo, so the scripts' relative paths keep working, then zips it. No game files
  are included. Run the self-test afterwards with -Test (lists FM5-only cars from the extracted zip, read-only).

.EXAMPLE
  .\tools\release\Make-ImporterRelease.ps1 -Version 1.0.0 -Test
#>
param(
  [Parameter(Mandatory)][string]$Version,
  [switch]$Test   # extract the zip to a temp folder and run the importer's read-only -ListFm5Only from there
)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$name = "fm5-car-importer-$Version"
$stage = Join-Path $root "build\release\$name"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory $stage | Out-Null

$files = @(
  'Import-Fm5Cars.cmd', 'LICENSE'
  'tools\fm5-import\Import-Fm5Cars.ps1', 'tools\fm5-import\Export-Fm5Car.ps1', 'tools\fm5-import\Add-CarLights.ps1'
  'tools\fm5-import\Add-ImportedCarWheels.ps1', 'tools\fm5-import\WheelSwap.ps1', 'tools\fm5-import\CarLights.cs'
  'tools\fm5-import\ForzaModel.cs', 'tools\fm5-import\Fm5ModelConverter.cs'
  'tools\build\Build-Mod.ps1', 'tools\build\StockSource.ps1', 'tools\build\Repack-ForzaZip.ps1'
  'tools\build\stock-hashes.json', 'tools\build\stock-cars.txt'
  'tools\release\Install.ps1', 'tools\release\Uninstall.ps1'
)
foreach ($f in $files) {
  $src = Join-Path $root $f; if (-not (Test-Path $src)) { throw "Missing $f" }
  $dst = Join-Path $stage $f; New-Item -ItemType Directory (Split-Path $dst) -Force | Out-Null; Copy-Item $src $dst
}
foreach ($d in Get-ChildItem (Join-Path $root 'release\fm5-car-importer') -File) { Copy-Item $d.FullName $stage }
New-Item -ItemType Directory (Join-Path $stage 'tools\bin') -Force | Out-Null
Set-Content (Join-Path $stage 'tools\bin\README.txt') 'sqlite3.exe is downloaded here on first use (sqlite-tools-win-x64-3470200 from sqlite.org, hash-checked).' -Encoding ASCII
Set-Content (Join-Path $stage 'VERSION.txt') "FM5 Car Importer $Version" -Encoding ASCII

$zip = Join-Path $root "dist\$name.zip"
New-Item -ItemType Directory (Split-Path $zip) -Force | Out-Null
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Write-Host ("Built {0} ({1:N0} KB, {2} files)`nSHA-256 {3}" -f $zip, ((Get-Item $zip).Length / 1KB), (Get-ChildItem -Recurse -File $stage).Count, $sha)

if ($Test) {
  $t = Join-Path ([IO.Path]::GetTempPath()) "fm5-importer-test-$([IO.Path]::GetRandomFileName())"
  Expand-Archive $zip $t
  try {
    $cars = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $t 'tools\fm5-import\Import-Fm5Cars.ps1') -ListFm5Only)
    if ($LASTEXITCODE -ne 0 -or $cars.Count -eq 0) { throw "Self-test failed: $($cars -join "`n")" }
    Write-Host "Self-test: the extracted package lists $($cars.Count) importable FM5 cars"
  } finally { Remove-Item -Recurse -Force $t }
}
