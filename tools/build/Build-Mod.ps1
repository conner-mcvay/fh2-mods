<#
.SYNOPSIS
  Builds a release zip from one or more mods in mods\<name>.

.DESCRIPTION
  Each mod folder mirrors the game's media folder. Only changed/added content is stored in the repo:
    mods\<name>\media\Camera.zip\CameraSettings.ini       folder named like a zip: replacement/new entries for that zip
    mods\<name>\media\stripped\gamedbRC.slt\*.sql          folder named like a .slt: SQL patches, applied in name order
    mods\<name>\media\<path>\<file>                        anything else: loose file copied as-is
    mods\<name>\media\<path>\<file>.set                    "key value" lines patched into the game's <file> (as in zips)

  Stock zips, databases and zipmanifest.xml are read from the game package (.zip of the Anthem_* folder) or from a
  game folder whose files are verified against tools\build\stock-hashes.json, so a build never starts from a modded file.
  -Layer -Game <folder> instead builds on top of what's installed there (e.g. earlier car imports), so mods stack.
  Mods are applied in the order given, so several mods can patch the same zip or database; later mods win on conflicts.

  Output: dist\<name>.zip with the changed media files, zipmanifest.xml (if any zip changed), README.txt
  (each mod's README, {{MANIFEST_VALUES}} filled in) and tools\Repack-ForzaZip.ps1 (if any zip changed).

.EXAMPLE
  .\tools\build\Build-Mod.ps1 -Mod cockpit-fov -Package G:\FH2-1\Anthem_1.0.0.64_x64__8wekyb3d8bbwe.zip
.EXAMPLE
  .\tools\build\Build-Mod.ps1 -Mod cockpit-fov,my-other-mod -Name my-setup
#>
param(
  [Parameter(Mandatory)][string[]]$Mod,
  [string]$Name,
  [string]$Package = $env:FH2_PACKAGE,   # stock source: the game package zip...
  [string]$Game = $env:FH2_GAME,         # ...or a game folder (containing Mount) with stock files
  [switch]$Layer,                        # with -Game: build on top of the installed files (other mods included); the
                                         #   result installs only onto exactly that state
  [string]$Sqlite = $env:FH2_SQLITE,
  [string]$Fm5Media = $env:FH2_FM5_MEDIA
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
. (Join-Path $PSScriptRoot 'StockSource.ps1')
if (-not $Name) { if ($Mod.Count -eq 1) { $Name = $Mod[0] } else { throw 'Pass -Name when building several mods together' } }
if ($Game) { Open-StockSource -Game $Game -Layer:$Layer } else { Open-StockSource -Package $Package }

$root = Split-Path (Split-Path $PSScriptRoot)   # tools\build -> repo root
$modsRoot = if ($env:FH2_MODS_ROOT) { $env:FH2_MODS_ROOT } else { Join-Path $root 'mods' }   # generated mods can live outside the repo
$build = Join-Path $root "build\$Name"
$dist = Join-Path $root 'dist'
$work = Join-Path $root "build\.work-$Name"
foreach ($d in $build, $work) { if (Test-Path $d) { Remove-Item -Recurse -Force $d } }
New-Item -ItemType Directory "$build\media", $work, $dist -Force | Out-Null

$imports = @{}   # rel path -> FM5 source file (from a mod's imports.txt)
function Get-Stock([string]$rel, [string]$dest) {
  # Copies a stock media file (or an imported FM5 file) to $dest unless an earlier mod in this build already produced it
  if (Test-Path $dest) { return }
  if ($imports.ContainsKey($rel)) {
    New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
    Copy-Item $imports[$rel] $dest
    return
  }
  Copy-StockFile "media\$rel" $dest
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
function Set-IniKeys([string]$file, [string]$set, [string]$label) {
  # Patches "key value" lines of $file from the .set file $set (replacing a key's line, or adding it), keeping the
  # file's other lines
  $lines = [Collections.Generic.List[string]]([IO.File]::ReadAllLines($file))
  foreach ($kv in Get-Content $set | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') }) {
    $key, $val = $kv.Trim() -split '\s+', 2
    $i = -1; for ($j = 0; $j -lt $lines.Count; $j++) { if (($lines[$j].Trim() -split '\s+', 2)[0] -ieq $key) { $i = $j; break } }
    if ($i -ge 0) { $lines[$i] = "$key $val" } else { $lines.Add("$key $val") }
    Write-Host "SET      ${label}: $key $val"
  }
  [IO.File]::WriteAllLines($file, $lines)
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
  if (-not $imports.ContainsKey($rel) -and -not (Test-StockFile "media\$rel")) {
    # a new zip: start from an empty archive (just the end-of-central-directory record)
    New-Item -ItemType Directory (Split-Path $stockZip) -Force | Out-Null
    $eocd = New-Object byte[] 22; $eocd[0] = 0x50; $eocd[1] = 0x4B; $eocd[2] = 5; $eocd[3] = 6
    [IO.File]::WriteAllBytes($stockZip, $eocd)
  } else { Get-Stock $rel $stockZip }
  $zips[$rel] = Join-Path $work "src\$rel"
  [IO.Compression.ZipFile]::ExtractToDirectory($stockZip, $zips[$rel])
}
$readmes = @()
$fm5CarZips = @()   # FM5 car zips whose models get converted for FH2's shaders
try {
  foreach ($m in $Mod) {
    $modDir = Join-Path $modsRoot $m
    $modMedia = Join-Path $modDir 'media'
    if (-not (Test-Path $modMedia)) { throw "No media folder in $modDir" }
    if (Test-Path "$modDir\README.txt") { $readmes += "$modDir\README.txt" }

    # imports ("<FH2 media path> <- <source media path>"): from FM5, or with an "fh2:" source from the base game
    # (e.g. to repackage a file the game already has). Either side may go inside a zip, e.g.
    #   stripped\RC0.zip\Thumbnail_1065_Big.swatchbin <- ui\textures\data_bound\Feb14Update.zip\Thumbnail_1065_Big.swatchbin
    #   cars\_library\scene\wheels\TOY_2000GT_69.zip\TOY_2000GT_69_wheelLF.modelbin <- fh2:cars\TOY_2000GT_69.zip\scene\_library\Scene\Wheels\TOY_2000GT_69_WheelLF.modelbin
    # A destination zip the base doesn't have is created.
    if (Test-Path "$modDir\imports.txt") {
      $lines = @(Get-Content "$modDir\imports.txt" | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') })
      if (-not $Fm5Media -and ($lines | Where-Object { $_ -notmatch '<-\s*fh2:' })) { throw "$m imports FM5 files: pass -Fm5Media <FM5 Mount\media folder> or set FH2_FM5_MEDIA" }
      $n = 0
      foreach ($line in $lines) {
        $dest, $from = $line -split '\s*<-\s*', 2
        $dest = $dest.Trim(); $from = if ($from) { $from.Trim() } else { $dest }
        $n++; if ($lines.Count -le 20 -or $n % 100 -eq 0 -or $n -eq $lines.Count) { Write-Host "IMPORT   $m\$dest ($n/$($lines.Count))" }
        $tmp = Join-Path $work ("import\" + [IO.Path]::GetRandomFileName())
        if ($from -match '^fh2:(.+)$') {
          $src = $Matches[1]
          if ($src -match '^(.*?\.zip)\\(.+)$') { Copy-StockEntry "media\$($Matches[1])" $Matches[2] $tmp } else { Copy-StockFile "media\$src" $tmp }
        } else { Read-Fm5 $from $tmp }
        if ($dest -match '^(.*?\.zip)\\(.+)$' -and $Matches[2]) {
          $zr = $Matches[1]; $entry = $Matches[2]
          Use-Zip $zr
          # FM5 models placed in a car or wheel zip need the same conversion as whole FM5 car zips
          if ($from -notmatch '^fh2:' -and $entry -like '*.modelbin' -and $zr -like 'cars\*' -and $fm5CarZips -notcontains $zr) { $fm5CarZips += $zr }
          $target = Join-Path $zips[$zr] $entry
          New-Item -ItemType Directory (Split-Path $target) -Force | Out-Null
          Copy-Item -Force $tmp $target
        } elseif ($dest -like '*.zip') {
          $imports[$dest] = $tmp
          Use-Zip $dest
          if ($dest -like 'cars\*.zip' -and $fm5CarZips -notcontains $dest) { $fm5CarZips += $dest }
        } else {
          $target = Join-Path "$build\media" $dest
          New-Item -ItemType Directory (Split-Path $target) -Force | Out-Null
          Copy-Item -Force $tmp $target
        }
      }
    }

    # zip overlays. <entry>.set files patch an existing ini entry key by key ("key value" lines) instead of replacing
    # it, so several mods can change different keys of one file (e.g. CameraSettings.ini)
    foreach ($zd in Get-ChildItem -Recurse -Directory $modMedia | Where-Object { $_.Name -like '*.zip' }) {
      $rel = $zd.FullName.Substring($modMedia.Length + 1)
      Use-Zip $rel
      Copy-Item -Recurse -Force "$($zd.FullName)\*" $zips[$rel] -Exclude '*.set'
      foreach ($set in Get-ChildItem -Recurse -File $zd.FullName -Filter *.set) {
        $entry = Join-Path $zips[$rel] ($set.FullName.Substring($zd.FullName.Length + 1) -replace '\.set$', '')
        if (-not (Test-Path $entry)) { throw "$m\$($set.Name): $rel has no entry to patch" }
        Set-IniKeys $entry $set.FullName "$m\$rel\$($set.Name -replace '\.set$', '')"
      }
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

    # loose files (outside any *.zip / *.slt folder); <file>.set patches the game's (or the installed) file key by key
    foreach ($f in Get-ChildItem -Recurse -File $modMedia) {
      $rel = $f.FullName.Substring($modMedia.Length + 1)
      if ($rel -match '(^|\\)[^\\]+\.(zip|slt)\\') { continue }
      if ($f.Name -like '*.set') {
        $target = $rel -replace '\.set$', ''
        $dest = Join-Path "$build\media" $target
        if (-not (Test-Path $dest)) { New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null; Get-Stock $target $dest }
        Set-IniKeys $dest $f.FullName "$m\$target"
        continue
      }
      Write-Host "FILE     $m\$rel"
      $dest = Join-Path "$build\media" $rel
      New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
      Copy-Item -Force $f.FullName $dest
    }
  }
  if ($zips.Count) { Get-Stock 'zipmanifest.xml' "$build\media\zipmanifest.xml" }
  if ($fm5CarZips.Count) {
    # the converter reads FH2's material and shader libraries to learn what each mesh's shader needs
    foreach ($lib in 'cars\_library\Materials.zip', '_library\Shaders.zip') { Get-Stock $lib (Join-Path $work "stock\$lib") }
  }
} finally { }

# FM5 car models: add the vertex inputs FH2's shaders read (tangents, extra UV sets); without them glass,
# light lenses, decals and badges aren't drawn
if ($fm5CarZips.Count) {
  # the model code is shared with Add-CarLights, which may run in the same session: both load all three
  if (-not ('BurgBlob' -as [type])) {
    $cs = 'ForzaModel.cs', 'Fm5ModelConverter.cs', 'CarLights.cs' | ForEach-Object { Join-Path $PSScriptRoot "..\fm5-import\$_" }
    Add-Type -Path $cs -ReferencedAssemblies System.Core, System.IO.Compression, System.IO.Compression.FileSystem
  }
  foreach ($rel in $fm5CarZips) {
    $src = $zips[$rel]; $carName = [IO.Path]::GetFileNameWithoutExtension($rel)
    $files = New-Object 'System.Collections.Generic.Dictionary[string,byte[]]'
    Get-ChildItem -Recurse -File $src | ForEach-Object { $files[$_.FullName.Substring($src.Length + 1).Replace('\', '/')] = [IO.File]::ReadAllBytes($_.FullName) }
    $resolver = New-Object Fh2ShaderResolver((Join-Path $work 'stock'), $files, $carName)
    try {
      $inputs = [Func[string, System.Collections.Generic.HashSet[string]]] { param($p) $resolver.Inputs($p) }
      $replacement = [Func[string, string]] { param($p) $resolver.LibraryReplacement($p) }
      $converted = 0
      foreach ($k in @($files.Keys | Where-Object { $_ -like '*.modelbin' })) {
        $log = New-Object 'System.Collections.Generic.List[string]'
        try { $out = [Fm5ModelConverter]::Convert($files[$k], $inputs, $replacement, $log) }
        catch { throw "Converting $carName\$k failed: $($_.Exception.InnerException.Message)" }
        if (-not $out) { continue }
        $problems = [ForzaModelCheck]::Check($out)
        if ($problems.Count) { throw "Converted $k fails validation: $($problems -join '; ')" }
        [IO.File]::WriteAllBytes((Join-Path $src $k.Replace('/', '\')), $out)
        Write-Host "MODEL    $carName\$k"; $log | ForEach-Object { Write-Host "         $_" }
        $converted++
      }
      Write-Host "MODELS   $carName`: $converted converted"
      $resolver.Log | Select-Object -Unique | ForEach-Object { Write-Warning "$carName`: $_" }
    } finally { $resolver.Dispose() }
  }
}

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

# install.json + Install.ps1/Uninstall.ps1. Mods install into Mount\mediapc, Extra Options' override folder: the
# game reads it before Mount\media and doesn't filter it by Mount\hash.manifest, so new files need no index entry
# and the game's own files stay untouched. Every payload file is listed with its hash and the hash of what its
# target holds now ($null = nothing; with -Layer, what earlier mods installed there).
function Get-Sha([byte[]]$b) { -join ([Security.Cryptography.SHA256]::Create().ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) }
$payload = @(Get-ChildItem -Recurse -File "$build\media" | ForEach-Object { $_.FullName.Substring($build.Length + 1) })
try {
  $files = foreach ($p in $payload) {
    [ordered]@{ source = $p; target = (Get-InstalledPath $p); sha256 = Get-Sha ([IO.File]::ReadAllBytes((Join-Path $build $p))); base_sha256 = (Get-BaseHash $p) }
  }
  $gameSha = Get-StockHash 'forza_durango_release_final.exe'
} finally { Close-StockSource }
$version = if ((Get-Content (Join-Path $PSScriptRoot 'stock-hashes.json') -Raw | ConvertFrom-Json).game -match '(\d+\.\d+\.\d+\.\d+)') { $Matches[1] } else { 'unknown' }
[ordered]@{
  name = $Name; mods = $Mod; layered = [bool]$Layer; game_version = $version; game_exe_sha256 = $gameSha
  install_folder = 'mediapc'; requires = 'FH2 Extra Options (Azimuth 0.9.10 build, or 0.2.74+ on 0.9.9) with [Files] EnableMediaOverrides=1'
  files = @($files)
} | ConvertTo-Json -Depth 4 | Set-Content "$build\install.json" -Encoding UTF8
Copy-Item (Join-Path $PSScriptRoot '..\release\Install.ps1'), (Join-Path $PSScriptRoot '..\release\Uninstall.ps1') $build
$installText = @"


INSTALL (automatic)
-------------------
Needs FH2 Extra Options (it reads mods from Mount\mediapc): for Azimuth 0.9.10, winmm.dll beside azimuth.exe; for
0.9.9, 0.2.74 or later in data\bin. Close Azimuth, then in PowerShell from this folder:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -GameRoot "<folder containing Mount>" -AzimuthRoot "<folder containing azimuth.exe>"

It checks your game version, puts the mod's files in Mount\mediapc (the game's own files aren't changed), turns
on Extra Options' EnableMediaOverrides if it's off, and refuses to overwrite files another mod put there (unless
you add -Force), backing up anything it replaces. It prints the backup folder. To undo:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -BackupRoot "<printed backup folder>"

With several mods installed, uninstall them newest first.
"@
Add-Content "$build\README.txt" $installText

$out = Join-Path $dist "$Name.zip"
if (Test-Path $out) { Remove-Item $out }
Compress-Archive -Path "$build\*" -DestinationPath $out
Write-Host "Built $out"
