<#
.SYNOPSIS
  Packages fh2wheels as a release zip: dist\fh2wheels-<Version>.zip.

.DESCRIPTION
  Builds fh2wheels.dll (tools\wheels\build.ps1, unless -NoBuild) and regenerates the gamedb SQL
  (tools\wheels\make_gamedb.py), then copies the DLL, the mod, the build/install tools its installer runs and the user
  docs (release\fh2wheels) into a clean folder with the same layout as the repo, so the scripts' relative paths keep
  working, and zips it. No game files are included: the installer builds the database part on the user's own game.

.EXAMPLE
  .\tools\release\Make-WheelsRelease.ps1 -Version 1.0.0
#>
param(
  [Parameter(Mandatory)][string]$Version,
  [switch]$NoBuild   # package the existing tools\wheels\out\fh2wheels.dll and mods\fh2wheels SQL
)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$wheels = Join-Path $root 'tools\wheels'
if (-not $NoBuild) {
  & (Join-Path $wheels 'build.ps1'); if ($LASTEXITCODE) { throw 'fh2wheels build failed' }
  & py -3 (Join-Path $wheels 'make_gamedb.py'); if ($LASTEXITCODE) { throw 'make_gamedb.py failed' }
}
$dll = Join-Path $wheels 'out\fh2wheels.dll'
if (-not (Test-Path $dll)) { throw "Missing $dll" }
$name = "fh2wheels-$Version"
$stage = Join-Path $root "build\release\$name"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory $stage | Out-Null

$files = @(
  'LICENSE'
  'tools\build\Build-Mod.ps1', 'tools\build\StockSource.ps1', 'tools\build\Repack-ForzaZip.ps1'
  'tools\build\stock-hashes.json', 'tools\build\stock-cars.txt'
  'tools\release\Install.ps1', 'tools\release\Uninstall.ps1', 'tools\wheels\Install.ps1'
)
$files += Get-ChildItem (Join-Path $root 'mods\fh2wheels') -Recurse -File | ForEach-Object { $_.FullName.Substring($root.Length + 1) }
foreach ($f in $files) {
  $src = Join-Path $root $f; if (-not (Test-Path $src)) { throw "Missing $f" }
  $dst = Join-Path $stage $f; New-Item -ItemType Directory (Split-Path $dst) -Force | Out-Null; Copy-Item $src $dst
}
Copy-Item $dll $stage
foreach ($d in Get-ChildItem (Join-Path $root 'release\fh2wheels') -File) { Copy-Item $d.FullName $stage }
New-Item -ItemType Directory (Join-Path $stage 'tools\bin') -Force | Out-Null
Set-Content (Join-Path $stage 'tools\bin\README.txt') 'sqlite3.exe is downloaded here on first use (sqlite-tools-win-x64-3470200 from sqlite.org, hash-checked).' -Encoding ASCII
Set-Content (Join-Path $stage 'VERSION.txt') "fh2wheels $Version" -Encoding ASCII

$zip = Join-Path $root "dist\$name.zip"
New-Item -ItemType Directory (Split-Path $zip) -Force | Out-Null
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Write-Host ("Built {0} ({1:N0} KB, {2} files)`nSHA-256 {3}" -f $zip, ((Get-Item $zip).Length / 1KB), (Get-ChildItem -Recurse -File $stage).Count, $sha)
