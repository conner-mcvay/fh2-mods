<#
.SYNOPSIS
  Repacks a Forza Horizon 2 media zip in the game's native layout and updates zipmanifest.xml.

.DESCRIPTION
  FH2 zips use a specific layout:
    - every entry deflated (method 8), version 10, zeroed time/date/attributes
    - no local-header extra field
    - a central-directory extra field with ID 0x1123 holding the absolute offset of the entry's compressed data
  zipmanifest.xml also caches each zip's central-directory offset, size (+22 for the EOCD record) and entry count.

  Files in -SourceDir whose content matches the existing entry keep their original compressed bytes;
  changed or new files are recompressed. Entry order follows the existing zip, new files are appended.
  The original zip is backed up once as <zip>.orig.

.EXAMPLE
  .\Repack-ForzaZip.ps1 -Zip G:\...\media\Camera.zip -SourceDir G:\FH2-1\modtools\work\Camera
#>
param(
  [Parameter(Mandatory)][string]$Zip,
  [Parameter(Mandatory)][string]$SourceDir,
  [string]$Manifest
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$Zip = (Resolve-Path $Zip).Path
$SourceDir = (Resolve-Path $SourceDir).Path.TrimEnd('\')

# --- CRC32 ---
if (-not ('ForzaCrc32' -as [type])) {
  Add-Type -TypeDefinition @'
public static class ForzaCrc32 {
  static readonly uint[] T = new uint[256];
  static ForzaCrc32() {
    for (uint i = 0; i < 256; i++) { uint c = i; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1; T[i] = c; }
  }
  public static uint Compute(byte[] d) {
    uint c = 0xFFFFFFFFu;
    foreach (byte b in d) c = T[(c ^ b) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
  }
}
'@
}
function Get-Crc32([byte[]]$data) { [ForzaCrc32]::Compute($data) }
function Deflate([byte[]]$data) {
  $ms = New-Object IO.MemoryStream
  $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionLevel]::Optimal)
  $ds.Write($data, 0, $data.Length); $ds.Close()
  return ,$ms.ToArray()
}

# --- read existing zip ---
$src = [IO.File]::ReadAllBytes($Zip)
$eocd = -1
for ($i = $src.Length - 22; $i -ge 0; $i--) { if ([BitConverter]::ToUInt32($src, $i) -eq 0x06054b50) { $eocd = $i; break } }
if ($eocd -lt 0) { throw "No end-of-central-directory record in $Zip" }
$p = [BitConverter]::ToUInt32($src, $eocd + 16)
$existing = [ordered]@{}
while ([BitConverter]::ToUInt32($src, $p) -eq 0x02014b50) {
  $n = [BitConverter]::ToUInt16($src, $p + 28); $x = [BitConverter]::ToUInt16($src, $p + 30); $cm = [BitConverter]::ToUInt16($src, $p + 32)
  $lo = [BitConverter]::ToUInt32($src, $p + 42)
  $name = [Text.Encoding]::ASCII.GetString($src, $p + 46, $n)
  $ln = [BitConverter]::ToUInt16($src, $lo + 26); $lx = [BitConverter]::ToUInt16($src, $lo + 28)
  $csize = [BitConverter]::ToUInt32($src, $p + 20)
  $existing[$name] = @{
    Method = [BitConverter]::ToUInt16($src, $p + 10)
    Crc    = [BitConverter]::ToUInt32($src, $p + 16)
    CSize  = $csize
    USize  = [BitConverter]::ToUInt32($src, $p + 24)
    Data   = [byte[]]$src[($lo + 30 + $ln + $lx)..($lo + 30 + $ln + $lx + $csize - 1)]
  }
  $p += 46 + $n + $x + $cm
}

# --- collect source files ---
$files = @{}
Get-ChildItem -Recurse -File $SourceDir | ForEach-Object {
  $files[$_.FullName.Substring($SourceDir.Length + 1).Replace('\', '/')] = $_.FullName
}
$order = @($existing.Keys | Where-Object { $files.ContainsKey($_) }) + @($files.Keys | Where-Object { -not $existing.Contains($_) } | Sort-Object)
foreach ($k in $existing.Keys) { if (-not $files.ContainsKey($k)) { Write-Warning "Not in SourceDir, dropping: $k" } }

# --- build new zip ---
$out = New-Object IO.MemoryStream
$bw = New-Object IO.BinaryWriter($out)
$central = New-Object IO.MemoryStream
$cw = New-Object IO.BinaryWriter($central)
foreach ($name in $order) {
  $raw = [IO.File]::ReadAllBytes($files[$name])
  $crc = Get-Crc32 $raw
  $e = $existing[$name]
  if ($e -and $e.Method -eq 8 -and $e.Crc -eq $crc -and $e.USize -eq $raw.Length) {
    $comp = $e.Data; $status = 'kept'
  } else {
    $comp = [byte[]](Deflate $raw); $status = if ($e) { 'CHANGED' } else { 'NEW' }
  }
  $nameBytes = [Text.Encoding]::ASCII.GetBytes($name)
  $localOff = [uint32]$out.Position
  $dataOff = [uint32]($localOff + 30 + $nameBytes.Length)

  $bw.Write([uint32]0x04034b50); $bw.Write([uint16]10); $bw.Write([uint16]0); $bw.Write([uint16]8)
  $bw.Write([uint16]0); $bw.Write([uint16]0)
  $bw.Write([uint32]$crc); $bw.Write([uint32]$comp.Length); $bw.Write([uint32]$raw.Length)
  $bw.Write([uint16]$nameBytes.Length); $bw.Write([uint16]0)
  $bw.Write($nameBytes); $bw.Write($comp)

  $cw.Write([uint32]0x02014b50); $cw.Write([uint16]10); $cw.Write([uint16]10); $cw.Write([uint16]0); $cw.Write([uint16]8)
  $cw.Write([uint16]0); $cw.Write([uint16]0)
  $cw.Write([uint32]$crc); $cw.Write([uint32]$comp.Length); $cw.Write([uint32]$raw.Length)
  $cw.Write([uint16]$nameBytes.Length); $cw.Write([uint16]8); $cw.Write([uint16]0)
  $cw.Write([uint16]0); $cw.Write([uint16]0); $cw.Write([uint32]0); $cw.Write([uint32]$localOff)
  $cw.Write($nameBytes)
  $cw.Write([uint16]0x1123); $cw.Write([uint16]4); $cw.Write([uint32]$dataOff)

  if ($status -ne 'kept') { Write-Host ("{0,-8} {1}" -f $status, $name) }
}
$bw.Flush(); $cw.Flush()
$cdStart = [uint32]$out.Position
$cdBytes = $central.ToArray()
$bw.Write($cdBytes)
$bw.Write([uint32]0x06054b50); $bw.Write([uint16]0); $bw.Write([uint16]0)
$bw.Write([uint16]$order.Count); $bw.Write([uint16]$order.Count)
$bw.Write([uint32]$cdBytes.Length); $bw.Write([uint32]$cdStart); $bw.Write([uint16]0)
$bw.Flush()

# verify every entry decompresses to the expected CRC before replacing anything
$built = $out.ToArray()
$check = New-Object IO.Compression.ZipArchive((New-Object IO.MemoryStream(,$built)), [IO.Compression.ZipArchiveMode]::Read)
foreach ($ent in $check.Entries) {
  $s = $ent.Open(); $ms = New-Object IO.MemoryStream; $s.CopyTo($ms); $s.Close()
  if ((Get-Crc32 $ms.ToArray()) -ne (Get-Crc32 ([IO.File]::ReadAllBytes($files[$ent.FullName])))) { throw "Verification failed for $($ent.FullName); zip not written" }
}
$check.Dispose()

if (-not (Test-Path "$Zip.orig")) { Copy-Item $Zip "$Zip.orig" }
[IO.File]::WriteAllBytes($Zip, $built)
Write-Host ("Wrote {0}: {1} entries, dirstart={2} dirsize={3}" -f $Zip, $order.Count, $cdStart, $cdBytes.Length)

# --- update zipmanifest.xml ---
if (-not $Manifest) {
  $d = Split-Path $Zip
  while ($d -and -not (Test-Path (Join-Path $d 'zipmanifest.xml'))) { $d = Split-Path $d }
  if (-not $d) { Write-Warning 'zipmanifest.xml not found; skipping manifest update'; return }
  $Manifest = Join-Path $d 'zipmanifest.xml'
}
$mediaRoot = Split-Path $Manifest
$gamePath = 'game:\media\' + $Zip.Substring($mediaRoot.Length + 1)
$enc = New-Object Text.UTF8Encoding($true)
$xml = [IO.File]::ReadAllText($Manifest, $enc)
$pattern = '(<Zip [^>]*path="' + [regex]::Escape($gamePath) + '"[^>]*?)dirstart="\d+" dirsize="\d+" direntries="\d+"'
$rx = New-Object Text.RegularExpressions.Regex($pattern, 'IgnoreCase')
if (-not $rx.IsMatch($xml)) { Write-Warning "No manifest entry for $gamePath"; return }
if (-not (Test-Path "$Manifest.bak")) { Copy-Item $Manifest "$Manifest.bak" }
# manifest dirsize covers the central directory plus the 22-byte end-of-central-directory record
$xml = $rx.Replace($xml, ('${1}dirstart="' + $cdStart + '" dirsize="' + ($cdBytes.Length + 22) + '" direntries="' + $order.Count + '"'), 1)
[IO.File]::WriteAllText($Manifest, $xml, $enc)
Write-Host "Updated manifest entry for $gamePath"
