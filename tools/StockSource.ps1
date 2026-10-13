# Stock FH2 files for builds: from the game package (.zip of the Anthem_* folder) or from a game folder (the one
# containing Mount). Game-folder files are checked against stock-hashes.json, so a build never starts from a modded
# file. Paths are relative to Mount ("media\zipmanifest.xml", "hash.manifest"). Dot-source, then Open-StockSource.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

function Open-StockSource([string]$Package, [string]$Game) {
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
    $script:Stock = @{ Kind = 'game'; Mount = $mount; Hashes = $hashes; Verified = @{} }
  } else { throw 'Pass -Package <Anthem_*.zip> or -Game <folder containing Mount> (or set FH2_PACKAGE / FH2_GAME)' }
}

function Close-StockSource { if ($script:Stock -and $script:Stock.Zip) { $script:Stock.Zip.Dispose() }; $script:Stock = $null }

function Get-StockList {   # every stock path under Mount (lowercase)
  if ($script:Stock.Kind -eq 'package') { return @($script:Stock.Entries.Keys) }
  $m = $script:Stock.Mount
  return @(Get-ChildItem -Recurse -File $m | ForEach-Object { $_.FullName.Substring($m.Length + 1).ToLowerInvariant() })
}

function Get-StockHash([string]$rel) {   # stock SHA-256 of a file, or $null when unknown / not a stock file
  $k = $rel.ToLowerInvariant()
  if ($script:Stock.Hashes.ContainsKey($k)) { return $script:Stock.Hashes[$k] }
  if ($script:Stock.Kind -eq 'package' -and $script:Stock.Entries.ContainsKey($k)) {
    $s = $script:Stock.Entries[$k].Open(); try { return -join ([Security.Cryptography.SHA256]::Create().ComputeHash($s) | ForEach-Object { $_.ToString('x2') }) } finally { $s.Close() }
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
  $src = Join-Path $script:Stock.Mount $rel
  if (-not (Test-Path $src)) { throw "Stock file not found in game folder: Mount\$rel" }
  $want = $script:Stock.Hashes[$k]
  if (-not $want) { Write-Warning "No stock hash known for Mount\$rel; can't verify it's unmodified" }
  elseif (-not $script:Stock.Verified.ContainsKey($k)) {
    $have = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($have -ne $want) { throw "Mount\$rel isn't the stock file (another mod changed it). Uninstall that mod first, or point -Game at a clean copy." }
    $script:Stock.Verified[$k] = 1
  }
  Copy-Item -LiteralPath $src -Destination $dest -Force
}
