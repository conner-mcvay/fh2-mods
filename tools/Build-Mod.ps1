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
  [string]$Sqlite = $env:FH2_SQLITE,
  [string]$Fm5Media = $env:FH2_FM5_MEDIA
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
$imports = @{}   # rel path -> FM5 source file (from a mod's imports.txt)
function Get-Stock([string]$rel, [string]$dest) {
  # Copies a stock media file (or an imported FM5 file) to $dest unless an earlier mod in this build already produced it
  if (Test-Path $dest) { return }
  if ($imports.ContainsKey($rel)) {
    New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
    Copy-Item $imports[$rel] $dest
    return
  }
  $suffix = '/Mount/media/' + $rel.Replace('\', '/')
  $e = $pkg.Entries | Where-Object { $_.FullName.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
  if (-not $e) { throw "Stock file not found in package: media\$rel" }
  New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
  [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest)
}
function Read-Fm5([string]$rel, [string]$dest) {
  # Copies an FM5 media file to $dest; a path segment ending in .zip reads the entry inside that zip
  New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
  if ($rel -match '^(.*?\.zip)\\(.+)$' -and (Test-Path (Join-Path $Fm5Media $Matches[1]) -PathType Leaf)) {
    $za = [IO.Compression.ZipFile]::OpenRead((Join-Path $Fm5Media $Matches[1]))
    try {
      $want = $Matches[2].Replace('\', '/')
      $e = $za.Entries | Where-Object { $_.FullName -ieq $want } | Select-Object -First 1
      if (-not $e) { throw "FM5 entry not found: media\$rel" }
      [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
    } finally { $za.Dispose() }
  } else {
    $src = Join-Path $Fm5Media $rel
    if (-not (Test-Path $src -PathType Leaf)) { throw "FM5 file not found: $src" }
    Copy-Item $src $dest
  }
}
function Resolve-Sqlite {
  if ($script:Sqlite) { return $script:Sqlite }
  $cmd = Get-Command sqlite3 -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'SQL patches need sqlite3.exe: pass -Sqlite <path>, set FH2_SQLITE, or put it on PATH'
}

$zips = [ordered]@{}   # rel path -> extracted source dir (repacked once at the end)
function Use-Zip([string]$rel) {
  if ($zips.Contains($rel)) { return }
  $stockZip = Join-Path $work "stock\$rel"
  Get-Stock $rel $stockZip
  $zips[$rel] = Join-Path $work "src\$rel"
  [IO.Compression.ZipFile]::ExtractToDirectory($stockZip, $zips[$rel])
}
$readmes = @()
$indexDonors = @{}   # new media path (lower) -> stock media path whose index metadata it reuses (from index-donors.txt)
try {
  foreach ($m in $Mod) {
    $modDir = Join-Path $root "mods\$m"
    $modMedia = Join-Path $modDir 'media'
    if (-not (Test-Path $modMedia)) { throw "No media folder in $modDir" }
    if (Test-Path "$modDir\README.txt") { $readmes += "$modDir\README.txt" }
    if (Test-Path "$modDir\index-donors.txt") {
      foreach ($line in Get-Content "$modDir\index-donors.txt" | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') }) {
        $n, $d = $line -split '\s*<-\s*', 2
        $indexDonors[$n.Trim().ToLower()] = $d.Trim()
      }
    }

    # FM5 imports ("<FH2 media path> <- <FM5 media path>"): either side may go inside a zip, e.g.
    #   stripped\RC0.zip\Thumbnail_1065_Big.swatchbin <- ui\textures\data_bound\Feb14Update.zip\Thumbnail_1065_Big.swatchbin
    if (Test-Path "$modDir\imports.txt") {
      if (-not $Fm5Media) { throw "$m imports FM5 files: pass -Fm5Media <FM5 Mount\media folder> or set FH2_FM5_MEDIA" }
      foreach ($line in Get-Content "$modDir\imports.txt" | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') }) {
        $dest, $from = $line -split '\s*<-\s*', 2
        $dest = $dest.Trim(); $from = if ($from) { $from.Trim() } else { $dest }
        Write-Host "IMPORT   $m\$dest"
        $tmp = Join-Path $work ("import\" + [IO.Path]::GetRandomFileName())
        Read-Fm5 $from $tmp
        if ($dest -match '^(.*?\.zip)\\(.+)$' -and $Matches[2]) {
          $zr = $Matches[1]; $entry = $Matches[2]
          Use-Zip $zr
          $target = Join-Path $zips[$zr] $entry
          New-Item -ItemType Directory (Split-Path $target) -Force | Out-Null
          Copy-Item -Force $tmp $target
        } elseif ($dest -like '*.zip') {
          $imports[$dest] = $tmp
          Use-Zip $dest
        } else {
          $target = Join-Path "$build\media" $dest
          New-Item -ItemType Directory (Split-Path $target) -Force | Out-Null
          Copy-Item -Force $tmp $target
        }
      }
    }

    # zip overlays
    foreach ($zd in Get-ChildItem -Recurse -Directory $modMedia | Where-Object { $_.Name -like '*.zip' }) {
      $rel = $zd.FullName.Substring($modMedia.Length + 1)
      Use-Zip $rel
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
  $stockFiles = @{}
  foreach ($e in $pkg.Entries) { if ($e.FullName -match '/Mount/media/(.+)$' -and $e.Name) { $stockFiles[$Matches[1].Replace('/', '\').ToLower()] = 1 } }
  $ie = $pkg.Entries | Where-Object { $_.FullName -like '*/Mount/hash.manifest' } | Select-Object -First 1
  $ms = New-Object IO.MemoryStream; $s = $ie.Open(); $s.CopyTo($ms); $s.Close(); $stockIndex = $ms.ToArray()
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

# files the stock game doesn't have are invisible to Azimuth until listed in Mount\hash.manifest:
# append a record per new file (path key + metadata copied from its donor) and ship the patcher for azimuth.exe
$new = @(Get-ChildItem -Recurse -File "$build\media" | ForEach-Object { $_.FullName.Substring("$build\media".Length + 1) } | Where-Object { -not $stockFiles.ContainsKey($_.ToLower()) } | Sort-Object)
if ($new.Count) {
  if (-not ('ForzaPathKey' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ForzaPathKey.cs') }
  $records = @{}
  for ($i = 0; $i -lt $stockIndex.Length; $i += 12) { $records[[BitConverter]::ToUInt64($stockIndex, $i)] = [BitConverter]::ToUInt32($stockIndex, $i + 8) }
  $out = New-Object IO.MemoryStream
  $out.Write($stockIndex, 0, $stockIndex.Length)
  foreach ($n in $new) {
    $donor = $indexDonors[$n.ToLower()]
    if (-not $donor) { throw "New file media\$n has no index donor; add '$n <- <stock media path>' to the mod's index-donors.txt" }
    $key = [ForzaPathKey]::Compute("media\$n")
    $dkey = [ForzaPathKey]::Compute("media\$donor")
    if ($records.ContainsKey($key)) { throw "Index already has a record for media\$n" }
    if (-not $records.ContainsKey($dkey)) { throw "Index donor media\$donor isn't in the stock index" }
    $out.Write([BitConverter]::GetBytes($key), 0, 8); $out.Write([BitConverter]::GetBytes([uint32]$records[$dkey]), 0, 4)
    $records[$key] = $records[$dkey]
    Write-Host ("INDEX    media\{0} (metadata {1} from {2})" -f $n, $records[$dkey], $donor)
  }
  [IO.File]::WriteAllBytes("$build\hash.manifest", $out.ToArray())
  New-Item -ItemType Directory "$build\tools" -Force | Out-Null
  Copy-Item (Join-Path $PSScriptRoot 'Patch-Azimuth.ps1') "$build\tools\"
  $sha = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($out.ToArray()) | ForEach-Object { $_.ToString('x2') })
  Write-Host "Wrote hash.manifest ($($out.Length) bytes, SHA-256 $sha); azimuth.exe must be patched to match (tools\Patch-Azimuth.ps1)"
}

$out = Join-Path $dist "$Name.zip"
if (Test-Path $out) { Remove-Item $out }
Compress-Archive -Path "$build\*" -DestinationPath $out
Write-Host "Built $out"
