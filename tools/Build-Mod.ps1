<#
.SYNOPSIS
  Builds a release zip from one or more mods in mods\<name>.

.DESCRIPTION
  Each mod folder mirrors the game's media folder. Only changed/added content is stored in the repo:
    mods\<name>\media\Camera.zip\CameraSettings.ini       folder named like a zip: replacement/new entries for that zip
    mods\<name>\media\stripped\gamedbRC.slt\*.sql          folder named like a .slt: SQL patches, applied in name order
    mods\<name>\media\<path>\<file>                        anything else: loose file copied as-is

  Stock zips, databases and zipmanifest.xml are read from the game package (.zip of the Anthem_* folder),
  so a build never depends on an already-modded install. Mods are applied in the order given, so several
  mods can patch the same zip or database; later mods win on conflicts.

  Output: dist\<name>.zip with the changed media files, zipmanifest.xml (if any zip changed), README.txt
  (each mod's README, {{MANIFEST_VALUES}} filled in) and tools\Repack-ForzaZip.ps1 (if any zip changed).

.EXAMPLE
  .\tools\Build-Mod.ps1 -Mod cockpit-fov -Package G:\FH2-1\Anthem_1.0.0.64_x64__8wekyb3d8bbwe.zip
.EXAMPLE
  .\tools\Build-Mod.ps1 -Mod cockpit-fov,dlc-unlock -Name my-setup
#>
param(
  [Parameter(Mandatory)][string[]]$Mod,
  [string]$Name,
  [string]$Package = $env:FH2_PACKAGE,
  [string]$Sqlite = $env:FH2_SQLITE
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (-not $Package) { throw 'Pass -Package <path to Anthem_*.zip> or set FH2_PACKAGE' }
if (-not $Name) { if ($Mod.Count -eq 1) { $Name = $Mod[0] } else { throw 'Pass -Name when building several mods together' } }

$root = Split-Path $PSScriptRoot
$build = Join-Path $root "build\$Name"
$dist = Join-Path $root 'dist'
$work = Join-Path $root "build\.work-$Name"
foreach ($d in $build, $work) { if (Test-Path $d) { Remove-Item -Recurse -Force $d } }
New-Item -ItemType Directory "$build\media", $work, $dist -Force | Out-Null

$pkg = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $Package).Path)
function Get-Stock([string]$rel, [string]$dest) {
  # Copies a stock media file to $dest unless an earlier mod in this build already produced it
  if (Test-Path $dest) { return }
  $suffix = '/Mount/media/' + $rel.Replace('\', '/')
  $e = $pkg.Entries | Where-Object { $_.FullName.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
  if (-not $e) { throw "Stock file not found in package: media\$rel" }
  New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
  [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest)
}
function Resolve-Sqlite {
  if ($script:Sqlite) { return $script:Sqlite }
  $cmd = Get-Command sqlite3 -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'SQL patches need sqlite3.exe: pass -Sqlite <path>, set FH2_SQLITE, or put it on PATH'
}

$zips = [ordered]@{}   # rel path -> extracted source dir (repacked once at the end)
$readmes = @()
try {
  foreach ($m in $Mod) {
    $modDir = Join-Path $root "mods\$m"
    $modMedia = Join-Path $modDir 'media'
    if (-not (Test-Path $modMedia)) { throw "No media folder in $modDir" }
    if (Test-Path "$modDir\README.txt") { $readmes += "$modDir\README.txt" }

    # zip overlays
    foreach ($zd in Get-ChildItem -Recurse -Directory $modMedia | Where-Object { $_.Name -like '*.zip' }) {
      $rel = $zd.FullName.Substring($modMedia.Length + 1)
      if (-not $zips.Contains($rel)) {
        $stockZip = Join-Path $work "stock\$rel"
        Get-Stock $rel $stockZip
        $zips[$rel] = Join-Path $work "src\$rel"
        [IO.Compression.ZipFile]::ExtractToDirectory($stockZip, $zips[$rel])
      }
      Copy-Item -Recurse -Force "$($zd.FullName)\*" $zips[$rel]
    }

    # SQL patches
    foreach ($dd in Get-ChildItem -Recurse -Directory $modMedia | Where-Object { $_.Name -like '*.slt' }) {
      $rel = $dd.FullName.Substring($modMedia.Length + 1)
      $db = Join-Path "$build\media" $rel
      Get-Stock $rel $db
      $sqlite = Resolve-Sqlite
      foreach ($sql in Get-ChildItem $dd.FullName -Filter *.sql | Sort-Object Name) {
        Write-Host "SQL      $m\$($sql.Name) -> media\$rel"
        # one transaction per script; -bail stops (and rolls back) on the first error
        # (arguments rather than stdin: PowerShell 5.1 prefixes piped text with a BOM)
        & $sqlite -bail $db 'BEGIN;' ".read '$($sql.FullName.Replace('\', '/'))'" 'COMMIT;'
        if ($LASTEXITCODE -ne 0) { throw "SQL patch failed: $($sql.FullName)" }
      }
    }

    # loose files (outside any *.zip / *.slt folder)
    foreach ($f in Get-ChildItem -Recurse -File $modMedia) {
      $rel = $f.FullName.Substring($modMedia.Length + 1)
      if ($rel -match '(^|\\)[^\\]+\.(zip|slt)\\') { continue }
      Write-Host "FILE     $m\$rel"
      $dest = Join-Path "$build\media" $rel
      New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
      Copy-Item -Force $f.FullName $dest
    }
  }
  if ($zips.Count) { Get-Stock 'zipmanifest.xml' "$build\media\zipmanifest.xml" }
} finally { $pkg.Dispose() }

# repack each touched zip once, after every mod's overlay is in place
foreach ($rel in $zips.Keys) {
  $zipOut = Join-Path "$build\media" $rel
  New-Item -ItemType Directory (Split-Path $zipOut) -Force | Out-Null
  Copy-Item (Join-Path $work "stock\$rel") $zipOut
  & (Join-Path $PSScriptRoot 'Repack-ForzaZip.ps1') -Zip $zipOut -SourceDir $zips[$rel] -Manifest "$build\media\zipmanifest.xml" | Out-Host
  Remove-Item "$zipOut.orig"
}
if (Test-Path "$build\media\zipmanifest.xml.bak") { Remove-Item "$build\media\zipmanifest.xml.bak" }

# README(s) with manifest values for anyone merging by hand
$values = ''
if ($zips.Count) {
  $manifest = [IO.File]::ReadAllText("$build\media\zipmanifest.xml")
  $values = (@(foreach ($rel in $zips.Keys) {
    $mm = [regex]::Match($manifest, 'path="(game:\\media\\' + [regex]::Escape($rel) + ')"[^>]*?(dirstart="\d+" dirsize="\d+" direntries="\d+")', 'IgnoreCase')
    "    {0}`r`n    {1}" -f $mm.Groups[1].Value, $mm.Groups[2].Value
  })) -join "`r`n`r`n"
}
$readme = (@($readmes | ForEach-Object { [IO.File]::ReadAllText($_) }) -join "`r`n`r`n").Replace('{{MANIFEST_VALUES}}', $values)
if ($readme) { [IO.File]::WriteAllText("$build\README.txt", $readme) }

if ($zips.Count) {
  New-Item -ItemType Directory "$build\tools" -Force | Out-Null
  Copy-Item (Join-Path $PSScriptRoot 'Repack-ForzaZip.ps1') "$build\tools\"
}
Remove-Item -Recurse -Force $work

$out = Join-Path $dist "$Name.zip"
if (Test-Path $out) { Remove-Item $out }
Compress-Archive -Path "$build\*" -DestinationPath $out
Write-Host "Built $out"
