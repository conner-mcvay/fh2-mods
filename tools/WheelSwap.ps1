# Puts a car's stock wheel in the wheel shop, like mods\stock-wheel-swap does for FH2's own cars. Dot-source, then
# New-WheelSwapParts per car. The shop loads non-stock wheels from cars\_library\scene\wheels\<wheel>.zip
# (<wheel>_wheelLF.modelbin + Textures\AO\<wheel>_wheelLF_AO.swatchbin) and lists only wheels with a
# WheelAnnotations row; stock wheels only exist inside their car's zip.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

# List_PartManufacturer Id of each car brand, by MediaName prefix (List_CarMake.ManufacturerCode). Not the make Id:
# wheels use the part-manufacturer table (Toyota 255, Chevrolet 35). Brands without a row use 1 ("Stock").
$script:WheelBrands = @{
  ABA = 619; ACU = 99; ALF = 114; AMC = 607; ARI = 636; ARM = 645; AST = 108; AUD = 121; BEN = 115; BMW = 118; BOW = 1
  BRA = 637; BUG = 569; BUI = 18; CAD = 144; CAP = 643; CAT = 638; CHA = 635; CHE = 35; CHR = 156; CIT = 590; DOD = 160
  DON = 1; EAG = 620; FER = 142; FIA = 166; FOR = 167; GMC = 622; HEN = 179; HOL = 629; HON = 180; HUM = 623; HYU = 171
  INF = 185; JAG = 220; JEE = 621; KIA = 605; KOE = 183; KTM = 640; LAM = 54; LAN = 164; LEX = 268; LOC = 1; LOT = 199
  LR = 194; MAS = 192; MAZ = 149; MCL = 193; MER = 25; MG = 632; MIN = 418; MIT = 116; MRC = 610; NIS = 206; NOB = 597
  OLD = 624; PAG = 445; PEU = 239; PLY = 440; PON = 240; POR = 238; RAD = 598; REN = 237; RUF = 631; SAA = 230; SAL = 69
  SCI = 74; SEA = 253; SHE = 235; SPY = 601; SUB = 297; SUZ = 606; TES = 625; TOY = 255; TVR = 260; ULT = 628; VAU = 81
  VIP = 641; VOL = 262; VW = 294
}

function Get-WheelBrand([string]$media) { $p = ($media -split '_')[0].ToUpper(); if ($script:WheelBrands.ContainsKey($p)) { $script:WheelBrands[$p] } else { 1 } }

function Read-StringTable([string]$zip, [string]$name) {
  # stringtables\<lang>.zip\<table>.str (LSB2): u32 count at 0x28, 6-byte entries from 0x32 (u16 = low 16 bits of the
  # "_&<id>" key, u32 offset in UTF-16 chars), then the null-terminated UTF-16 strings
  $z = [IO.Compression.ZipFile]::OpenRead($zip)
  try { $e = $z.Entries | Where-Object Name -eq $name; if (-not $e) { return @{} }; $ms = New-Object IO.MemoryStream; $s = $e.Open(); $s.CopyTo($ms); $s.Close(); $b = $ms.ToArray() } finally { $z.Dispose() }
  $n = [BitConverter]::ToUInt32($b, 0x28); $base = 0x32 + 6 * $n; $h = @{}
  for ($i = 0; $i -lt $n; $i++) {
    $o = 0x32 + 6 * $i; $p = $base + 2 * [BitConverter]::ToUInt32($b, $o + 2); $end = $p
    while ([BitConverter]::ToUInt16($b, $end) -ne 0) { $end += 2 }
    $h[[int][BitConverter]::ToUInt16($b, $o)] = [Text.Encoding]::Unicode.GetString($b, $p, $end - $p)
  }
  $h
}
function Resolve-String([hashtable]$table, [string]$ref) { if ($ref -match '^_&(\d+)$') { $table[[int]([uint64]$Matches[1] -band 0xFFFF)] } else { $ref } }

function Find-CarWheelEntries([IO.Compression.ZipArchive]$archive, [string]$wheel) {
  # a car zip's wheel model and AO texture. Names vary (_wheelLF, _wheel_LF, only LR for staggered sets, 918_Spyder
  # vs 918Spyder, a variant car's own name, scene/Wheel/): front-left first, one named like the wheel first
  $norm = ($wheel -replace '_', '').ToLower()
  $rank = { param($n) $s = 0; if (($n -replace '_', '').ToLower() -like "*$norm*") { $s -= 10 }; if ($n -match '(?i)wheel_?LF') { $s -= 2 } elseif ($n -match '(?i)wheel_?LR') { $s -= 1 }; $s }
  $model = $archive.Entries | Where-Object { $_.FullName -match '(?i)/Wheels?/[^/]+\.modelbin$' } | Sort-Object { & $rank $_.Name } | Select-Object -First 1
  if (-not $model) { return $null }
  $side = if ($model.Name -match '(?i)wheel_?LR') { 'LR' } else { 'LF' }
  $ao = $archive.Entries | Where-Object { $_.FullName -match "(?i)^Textures/AO/[^/]*wheel_?$side`_AO\.swatchbin$" } | Sort-Object { & $rank $_.Name } | Select-Object -First 1
  @{ Model = $model.FullName.Replace('/', '\'); Ao = $(if ($ao) { $ao.FullName.Replace('/', '\') }) }
}

function New-WheelSwapParts([string]$Car, [string]$Wheel, [string]$Name, [string]$CarZip, [string]$SourcePrefix, [hashtable]$Entries) {
  # SQL, imports.txt and index-donors.txt lines that put $Car's stock wheel $Wheel in the shop.
  # $CarZip: the car zip's media path in the source ("cars\X.zip"); $SourcePrefix: "" for FM5 (converted for FH2's
  # shaders by the build), "fh2:" for the base game; $Entries: from Find-CarWheelEntries.
  $dest = "cars\_library\scene\wheels\$Wheel.zip"
  $imports = @("$dest\$($Wheel)_wheelLF.modelbin <- $SourcePrefix$CarZip\$($Entries.Model)")
  if ($Entries.Ao) { $imports += "$dest\Textures\AO\$($Wheel)_wheelLF_AO.swatchbin <- $SourcePrefix$CarZip\$($Entries.Ao)" }
  $w = $Wheel.Replace("'", "''"); $c = $Car.Replace("'", "''")
  $sql = @"
-- $Car's stock wheel in the wheel shop (as mods\stock-wheel-swap): brand, name, price by weight, a shop category by
-- the car's Autoshow group (2 Sport, 3 forged, 4 Specialized)
UPDATE List_Wheels SET IsStock = 0, DisplayName = '$($Name.Replace("'", "''"))', PartManufacturerID = $(Get-WheelBrand $Wheel),
  Price = CASE WHEN Mass < 30.0 THEN 3800 WHEN Mass <= 30.0 THEN 3700 WHEN Mass <= 33.5 THEN 3600 WHEN Mass <= 38.0 THEN 3500
               WHEN Mass <= 41.5 THEN 3400 WHEN Mass <= 46.0 THEN 3300 ELSE 3200 END
WHERE MediaName = '$w' COLLATE NOCASE;
INSERT INTO WheelAnnotations (WheelID, CategoryID, DisplayOrder)
SELECT w.ID, x.cat, (SELECT COALESCE(MAX(DisplayOrder), 0) + 100 FROM WheelAnnotations WHERE CategoryID = x.cat)
FROM List_Wheels w, (
  SELECT CASE
    WHEN b.Id = 39 THEN 3
    WHEN COALESCE(b.ParentBucketId, b.Id) IN (2, 4, 5, 8) THEN 2
    WHEN COALESCE(b.ParentBucketId, b.Id) IN (1, 9) THEN 3
    WHEN COALESCE(b.ParentBucketId, b.Id) IN (3, 6, 7, 10) THEN 4
    WHEN c.Year < 1980 THEN 4 ELSE 2 END AS cat
  FROM Data_Car c LEFT JOIN Data_Car_Buckets cb ON cb.CarId = c.Id LEFT JOIN CarBuckets b ON b.Id = cb.CarBucket
  WHERE c.MediaName = '$c' COLLATE NOCASE) x
WHERE w.MediaName = '$w' COLLATE NOCASE AND w.ID NOT IN (SELECT WheelID FROM WheelAnnotations);
"@
  @{ Sql = $sql; Imports = $imports; Donors = @("$dest <- cars\_library\scene\wheels\VOL_TE37.zip") }
}
