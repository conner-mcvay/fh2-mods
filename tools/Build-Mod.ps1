<#
.SYNOPSIS
  Builds a release zip for a mod in mods\<name>.

.DESCRIPTION
  Each mod folder mirrors the game's media folder, with zip archives represented as folders:
    mods\<name>\media\Camera.zip\CameraSettings.ini  ->  entry CameraSettings.ini inside media\Camera.zip
  Only changed/added files are stored in the repo. Stock zips and zipmanifest.xml are read from the
  game package (.zip of the Anthem_* folder), so the build never depends on an already-modded install.

  Output: dist\<name>.zip containing media\<zips>, media\zipmanifest.xml, README.txt and
  tools\Repack-ForzaZip.ps1. In README.txt, {{MANIFEST_VALUES}} is replaced with the manifest
  values for each rebuilt zip.

.EXAMPLE
  .\tools\Build-Mod.ps1 -Mod cockpit-fov -Package G:\FH2-1\Anthem_1.0.0.64_x64__8wekyb3d8bbwe.zip
#>
param(
  [Parameter(Mandatory)][string]$Mod,
  [string]$Package = $env:FH2_PACKAGE
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (-not $Package) { throw 'Pass -Package <path to Anthem_*.zip> or set FH2_PACKAGE' }

$root = Split-Path $PSScriptRoot
$modDir = Join-Path $root "mods\$Mod"
$modMedia = Join-Path $modDir 'media'
if (-not (Test-Path $modMedia)) { throw "No media folder in $modDir" }
$build = Join-Path $root "build\$Mod"
$dist = Join-Path $root 'dist'
if (Test-Path $build) { Remove-Item -Recurse -Force $build }
New-Item -ItemType Directory "$build\media", $dist -Force | Out-Null

$pkg = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $Package).Path)
function Get-StockEntry([string]$rel) {
  $suffix = '/Mount/media/' + $rel.Replace('\', '/')
  $e = $pkg.Entries | Where-Object { $_.FullName.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
  if (-not $e) { throw "Stock file not found in package: media\$rel" }
  $e
}

try {
  [IO.Compression.ZipFileExtensions]::ExtractToFile((Get-StockEntry 'zipmanifest.xml'), "$build\media\zipmanifest.xml")
  $packed = @()
  $zipDirs = Get-ChildItem -Recurse -Directory $modMedia | Where-Object { $_.Name -like '*.zip' }
  if (-not $zipDirs) { throw "No <name>.zip folders under $modMedia" }
  foreach ($zd in $zipDirs) {
    $rel = $zd.FullName.Substring($modMedia.Length + 1)
    $zipOut = Join-Path "$build\media" $rel
    New-Item -ItemType Directory (Split-Path $zipOut) -Force | Out-Null
    [IO.Compression.ZipFileExtensions]::ExtractToFile((Get-StockEntry $rel), $zipOut)

    $src = Join-Path $build "src\$rel"
    [IO.Compression.ZipFile]::ExtractToDirectory($zipOut, $src)
    Copy-Item -Recurse -Force "$($zd.FullName)\*" $src
    & (Join-Path $PSScriptRoot 'Repack-ForzaZip.ps1') -Zip $zipOut -SourceDir $src -Manifest "$build\media\zipmanifest.xml" | Out-Host
    Remove-Item "$zipOut.orig"
    $packed += $rel
  }
} finally { $pkg.Dispose() }
Remove-Item "$build\media\zipmanifest.xml.bak"

# README with manifest values for anyone merging by hand
$manifest = [IO.File]::ReadAllText("$build\media\zipmanifest.xml")
$values = foreach ($rel in $packed) {
  $m = [regex]::Match($manifest, 'path="(game:\\media\\' + [regex]::Escape($rel) + ')"[^>]*?(dirstart="\d+" dirsize="\d+" direntries="\d+")', 'IgnoreCase')
  "    {0}`r`n    {1}" -f $m.Groups[1].Value, $m.Groups[2].Value
}
$readme = [IO.File]::ReadAllText((Join-Path $modDir 'README.txt')).Replace('{{MANIFEST_VALUES}}', ($values -join "`r`n`r`n"))
[IO.File]::WriteAllText("$build\README.txt", $readme)

New-Item -ItemType Directory "$build\tools" -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'Repack-ForzaZip.ps1') "$build\tools\"
Remove-Item -Recurse -Force "$build\src"

$out = Join-Path $dist "$Mod.zip"
if (Test-Path $out) { Remove-Item $out }
Compress-Archive -Path "$build\*" -DestinationPath $out
Write-Host "Built $out"
