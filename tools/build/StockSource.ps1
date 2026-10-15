# Base FH2 files for builds: from the game package (.zip of the Anthem_* folder) or from a game folder (the one
# containing Mount). Game-folder files are checked against stock-hashes.json, so a build never starts from a modded
# file - unless -Layer: then the build goes on top of whatever is installed, so mods stack (the game exe must still be
# stock). Mods install into Mount\mediapc (Extra Options' override folder, which the game reads before Mount\media),
# so with -Layer a media\<path> is read from Mount\mediapc\<path> when a mod installed one there.
# Paths are relative to Mount ("media\zipmanifest.xml"). Dot-source, then Open-StockSource.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

function Open-StockSource([string]$Package, [string]$Game, [switch]$Layer) {
  $hashes = @{}
  $table = Get-Content (Join-Path $PSScriptRoot 'stock-hashes.json') -Raw | ConvertFrom-Json
  foreach ($p in $table.files.PSObject.Properties) { $hashes[$p.Name.ToLowerInvariant()] = $p.Value }
  if ($Package) {
    $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $Package).Path)
    $entries = @{}
    foreach ($e in $zip.Entries) { if ($e.Name -and $e.FullName -match '/Mount/(.+)$') { $entries[$Matches[1].Replace('/', '\').ToLowerInvariant()] = $e } }
    $script:Stock = @{ Kind = 'package'; Zip = $zip; Entries = $entries; Hashes = $hashes }
  } elseif ($Game) {
    $mount = Join-Path (Resolve-Path $Game).Path 'Mount'
    if (-not (Test-Path (Join-Path $mount 'forza_durango_release_final.exe'))) { throw "Not an FH2 game folder (no Mount\forza_durango_release_final.exe): $Game" }
    $exe = Join-Path $mount 'forza_durango_release_final.exe'
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hashes['forza_durango_release_final.exe']) { throw "Unsupported game version (Mount\forza_durango_release_final.exe isn't the one this tool knows): $Game" }
    $script:Stock = @{ Kind = 'game'; Mount = $mount; Hashes = $hashes; Verified = @{}; Layer = [bool]$Layer }
  } elseif ($Layer) { throw '-Layer needs -Game' } else { throw 'Pass -Package <Anthem_*.zip> or -Game <folder containing Mount> (or set FH2_PACKAGE / FH2_GAME)' }
}

function Get-LayerPath([string]$rel) {   # where a game-folder file is read from: mediapc's copy first (-Layer)
  if ($script:Stock.Layer -and $rel -match '^media\\(.+)$') {
    $pc = Join-Path $script:Stock.Mount ('mediapc\' + $Matches[1])
    if (Test-Path -LiteralPath $pc -PathType Leaf) { return $pc }
  }
  return Join-Path $script:Stock.Mount $rel
}

function Get-GameMediaFile([string]$GameRoot, [string]$rel) {
  # a media file as the game sees it (FileInfo, or $null): the copy a mod installed in Mount\mediapc, else Mount\media's
  foreach ($d in 'mediapc', 'media') { $p = Join-Path $GameRoot "Mount\$d\$rel"; if (Test-Path -LiteralPath $p -PathType Leaf) { return Get-Item -LiteralPath $p } }
  return $null
}

function Get-InstalledPath([string]$rel) {   # Mount-relative path a mod installs media\<path> to
  if ($rel -match '^media\\(.+)$') { return 'mediapc\' + $Matches[1] }
  return $rel
}

function Close-StockSource {
  if ($script:Stock -and $script:Stock.Archives) { foreach ($a in $script:Stock.Archives.Values) { $a.Dispose() } }
  if ($script:Stock -and $script:Stock.TempFiles) { $script:Stock.TempFiles | Remove-Item -ErrorAction SilentlyContinue }
  if ($script:Stock -and $script:Stock.Zip) { $script:Stock.Zip.Dispose() }
  $script:Stock = $null
}

function Test-StockFile([string]$rel) {   # does the base have this file?
  if ($script:Stock.Kind -eq 'package') { return $script:Stock.Entries.ContainsKey($rel.ToLowerInvariant()) }
  return (Test-Path -LiteralPath (Get-LayerPath $rel) -PathType Leaf)
}

function Copy-StockEntry([string]$zipRel, [string]$entry, [string]$dest) {
  # Copies one entry (path inside the zip, either slash, any case) of a base zip to $dest. Zips stay open until
  # Close-StockSource, so reading many entries of one zip is cheap.
  if (-not $script:Stock.Archives) { $script:Stock.Archives = @{} }
  $k = $zipRel.ToLowerInvariant()
  if (-not $script:Stock.Archives.ContainsKey($k)) {
    if ($script:Stock.Kind -eq 'package' -or -not $script:Stock.Layer) {
      # package: extract the zip first; stock game folder: Copy-StockFile verifies it
      $tmp = Join-Path ([IO.Path]::GetTempPath()) ('fh2-stock-' + [IO.Path]::GetRandomFileName())
      Copy-StockFile $zipRel $tmp
      $script:Stock.TempFiles = @($script:Stock.TempFiles) + $tmp
      $script:Stock.Archives[$k] = [IO.Compression.ZipFile]::OpenRead($tmp)
    } else {
      $script:Stock.Archives[$k] = [IO.Compression.ZipFile]::OpenRead((Get-LayerPath $zipRel))
    }
  }
  $want = $entry.Replace('\', '/')
  $e = $script:Stock.Archives[$k].Entries | Where-Object { $_.FullName -ieq $want } | Select-Object -First 1
  if (-not $e) { throw "Not found in Mount\${zipRel}: $entry" }
  New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
  [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
}

function Get-StockList {   # every path under Mount (lowercase); with -Layer, mediapc's files count as media's
  if ($script:Stock.Kind -eq 'package') { return @($script:Stock.Entries.Keys) }
  $m = $script:Stock.Mount
  $all = @(Get-ChildItem -Recurse -File $m | ForEach-Object { $_.FullName.Substring($m.Length + 1).ToLowerInvariant() })
  if ($script:Stock.Layer) { $all = @($all | ForEach-Object { if ($_ -match '^mediapc\\(.+)$') { 'media\' + $Matches[1] } else { $_ } } | Select-Object -Unique) }
  return $all
}

function Get-StockHash([string]$rel) {   # stock SHA-256 of a file, or $null when unknown / not a stock file
  $k = $rel.ToLowerInvariant()
  if ($script:Stock.Hashes.ContainsKey($k)) { return $script:Stock.Hashes[$k] }
  if ($script:Stock.Kind -eq 'package' -and $script:Stock.Entries.ContainsKey($k)) {
    $s = $script:Stock.Entries[$k].Open(); try { return -join ([Security.Cryptography.SHA256]::Create().ComputeHash($s) | ForEach-Object { $_.ToString('x2') }) } finally { $s.Close() }
  }
  return $null
}

function Get-BaseHash([string]$rel) {   # SHA-256 of what a mod's install target (Get-InstalledPath) holds now, or $null
  # when it's absent: without -Layer the build expects nothing there; with -Layer, what's installed
  if (-not $script:Stock.Layer) { return $null }
  $p = Join-Path $script:Stock.Mount (Get-InstalledPath $rel)
  if (Test-Path -LiteralPath $p) {
    try { return (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
    catch { throw "Can't read Mount\$rel; close the game first. ($($_.Exception.Message))" }
  }
  return $null
}

function Copy-StockFile([string]$rel, [string]$dest) {
  $k = $rel.ToLowerInvariant()
  New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
  if ($script:Stock.Kind -eq 'package') {
    if (-not $script:Stock.Entries.ContainsKey($k)) { throw "Stock file not found in package: Mount\$rel" }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($script:Stock.Entries[$k], $dest, $true); return
  }
  $src = Get-LayerPath $rel
  if (-not (Test-Path $src)) { throw "Stock file not found in game folder: Mount\$rel" }
  $want = $script:Stock.Hashes[$k]
  if ($script:Stock.Layer) { }   # building on top of installed mods: take the file as it is
  elseif (-not $want) { Write-Warning "No stock hash known for Mount\$rel; can't verify it's unmodified" }
  elseif (-not $script:Stock.Verified.ContainsKey($k)) {
    $have = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($have -ne $want) { throw "Mount\$rel isn't the stock file (another mod changed it). Uninstall that mod first, or point -Game at a clean copy." }
    $script:Stock.Verified[$k] = 1
  }
  Copy-Item -LiteralPath $src -Destination $dest -Force
}
