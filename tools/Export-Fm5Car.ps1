<#
.SYNOPSIS
  Generates a mod that imports a Forza Motorsport 5 car into Forza Horizon 2.

.DESCRIPTION
  Walks every gamedb row the FM5 car depends on and writes them as SQL INSERTs for FH2's stock database:
    - Data_Car (FH2-only columns copied from a donor FH2 car; ContentId forced to 0)
    - every table keyed to the car by Ordinal / CarId (upgrades, physics, colours, camera, part positions)
    - the car's engines, drivetrains and bodies (Data_Engine / Data_Drivetrain / Data_CarBody and their part tables)
    - torque curves those parts reference
    - lookup rows (wheels, manufacturers, tire compounds, ...) that FM5 has but FH2 lacks
  Rows FH2 already has with identical content are skipped. Rows whose key exists in FH2 with different content are
  never overwritten; they're reported as conflicts (the FH2 version stays).

  Output: mods\<Mod>\
    imports.txt                                   FM5 files the build copies in (car zip, PG_ sound banks, audio xml, thumbnail)
    README.txt
    media\stripped\gamedbRC.slt\<Id>-<Media>.sql

.EXAMPLE
  .\tools\Export-Fm5Car.ps1 -Car PON_TransAm_02 -Donor PON_TransAmGTA_87 -Fm5Media G:\FM5\Forza_1.0.0.20_x64__8wekyb3d8bbwe\Mount\media
#>
param(
  [string]$Car,                     # FM5 car: MediaName (e.g. PON_TransAm_02) or Id
  [int]$CarId,
  [string]$Fm5Media = $env:FH2_FM5_MEDIA,   # FM5 Mount\media folder (car zip, sound banks, thumbnails, db\gamedb.slt)
  [string]$Fm5Db,                           # default: <Fm5Media>\db\gamedb.slt
  [string]$Mod,
  [string]$Donor,                   # FH2 donor car: MediaName or Id. Supplies FH2-only Data_Car columns, Autoshow bucket,
  [int]$DonorCarId,                 #   index metadata and (by default) the engine sound. Default: same make, nearest year
  [string]$EngineSound,             # FH2 engine MediaName whose sound the car's new engines use; default: the donor's
  [switch]$UseFm5Sound,             # try FM5's own engine banks (renamed PG_<engine>.bank) instead of an FH2 sound
  [string]$Thumbnail,               # Data_Car.Thumbnail override; default: the FM5 thumbnail, else the donor's
  [int]$Bucket,                     # FH2 CarBuckets.Id (Autoshow class group); default: the donor's bucket
  [string]$Package = $env:FH2_PACKAGE,   # stock FH2 source: the game package zip...
  [string]$Game = $env:FH2_GAME,         # ...or a game folder (containing Mount) with stock files
  [string]$Sqlite = $env:FH2_SQLITE
)
$ErrorActionPreference = 'Stop'
if (-not $Fm5Media) { throw 'Pass -Fm5Media <FM5 Mount\media folder> or set FH2_FM5_MEDIA' }
if (-not $Fm5Db) { $Fm5Db = Join-Path $Fm5Media 'db\gamedb.slt' }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
. (Join-Path $PSScriptRoot 'StockSource.ps1')
if (-not $Sqlite) { $Sqlite = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Source }
if (-not $Sqlite) { throw 'Need sqlite3.exe: pass -Sqlite, set FH2_SQLITE, or put it on PATH' }
$root = Split-Path $PSScriptRoot

# --- stock FH2 database; sound banks / audio xml FH2 ships (from the stock file list, so earlier imports don't count) ---
$tmp = Join-Path $root 'build\.export'
New-Item -ItemType Directory $tmp -Force | Out-Null
$fh2Db = Join-Path $tmp 'gamedbRC.slt'
if ($Game) { Open-StockSource -Game $Game } else { Open-StockSource -Package $Package }
try {
  Copy-StockFile 'media\stripped\gamedbRC.slt' $fh2Db
  $banks = @{}; $audioXml = @{}
  foreach ($k in $script:Stock.Hashes.Keys) {
    if ($k -match '^media\\audio\\fmodanthem\\durango\\pg_(.+)\.bank$') { $banks[$Matches[1]] = 1 }
    elseif ($k -match '^media\\audio\\cars\\(.+)\.xml$') { $audioXml[$Matches[1]] = 1 }
  }
} finally { Close-StockSource }

$attach = @("ATTACH 'file:$($fh2Db.Replace('\','/'))?immutable=1' AS fh;", "ATTACH 'file:$((Resolve-Path $Fm5Db).Path.Replace('\','/'))?immutable=1' AS fm;")
function Q([string]$sql) {
  # never put double quotes in $sql: PowerShell 5.1 mangles them when passing native arguments
  $out = & $Sqlite -bail -list -separator '|' ':memory:' @attach $sql
  if ($LASTEXITCODE -ne 0) { throw "sqlite3 failed: $sql" }
  @($out | ForEach-Object { $_.TrimEnd("`r") })
}
function Cols([string]$db, [string]$t) { Q "SELECT name FROM pragma_table_info('$t', '$db')" }
function Pk([string]$db, [string]$t) { Q "SELECT name FROM pragma_table_info('$t', '$db') WHERE pk > 0 ORDER BY pk" }
function In([object[]]$v) { if ($v.Count) { '(' + ($v -join ',') + ')' } else { '(NULL)' } }

if ($Car) {
  if ($Car -match '^\d+$') { $CarId = [int]$Car }
  else { $CarId = [int]@(Q "SELECT Id FROM fm.Data_Car WHERE MediaName = '$($Car.Replace("'", ''))' COLLATE NOCASE")[0]; if (-not $CarId) { throw "FM5 has no car named $Car" } }
}
if (-not $CarId) { throw 'Pass -Car <FM5 MediaName or Id>' }
if ($Donor) {
  if ($Donor -match '^\d+$') { $DonorCarId = [int]$Donor }
  else { $DonorCarId = [int]@(Q "SELECT Id FROM fh.Data_Car WHERE MediaName = '$($Donor.Replace("'", ''))' COLLATE NOCASE")[0]; if (-not $DonorCarId) { throw "FH2 has no car named $Donor" } }
}
$carRow = @(Q "SELECT MediaName, MakeID, Year FROM fm.Data_Car WHERE Id = $CarId")
if (-not $carRow) { throw "Car $CarId not found in $Fm5Db" }
$media, $makeId, $year = $carRow[0].Split('|')
if (Q "SELECT 1 FROM fh.Data_Car WHERE Id = $CarId") { throw "Car Id $CarId already exists in FH2 ($(Q "SELECT MediaName FROM fh.Data_Car WHERE Id = $CarId"))" }
if (-not $Mod) { $Mod = 'fm5-' + $media.ToLower().Replace('_', '-') }
Write-Host "Exporting $media (Id $CarId) -> mods\$Mod"

$fhTables = @{}; Q "SELECT name FROM fh.sqlite_master WHERE type = 'table'" | ForEach-Object { $fhTables[$_.ToLower()] = $_ }
$fmTables = Q "SELECT name FROM fm.sqlite_master WHERE type = 'table' ORDER BY name"
$shared = @($fmTables | Where-Object { $fhTables.ContainsKey($_.ToLower()) })
function TablesWith([string]$col) { @($shared | Where-Object { (Cols 'fm' $_) -contains $col }) }

# --- selection: table -> list of WHERE clauses over fm.<table> ---
$sel = [ordered]@{}
function Add-Sel([string]$t, [string]$where) { if (-not $sel.Contains($t)) { $sel[$t] = @() }; $sel[$t] += $where }

Add-Sel 'Data_Car' "Id = $CarId"
$skipCarKeyed = @('RentalCars', 'MiniCareerCars', 'RaceParticipants')   # FM5 career/race listings; would put the car into FH2 events
foreach ($t in $shared) {
  if ($skipCarKeyed -contains $t -or $t -eq 'Data_Car' -or $t -like 'NewProfile_*') { continue }
  foreach ($k in 'Ordinal', 'CarId', 'CarID') { if ((Cols 'fm' $t) -contains $k) { Add-Sel $t "[$k] = $CarId"; break } }
}
$engines = Q "SELECT DISTINCT EngineID FROM fm.List_UpgradeEngine WHERE Ordinal = $CarId"
$drivetrains = Q "SELECT DISTINCT DrivetrainID FROM fm.List_UpgradeDrivetrain WHERE Ordinal = $CarId"
$bodies = Q "SELECT DISTINCT CarBodyID FROM fm.List_UpgradeCarBody WHERE Ordinal = $CarId"
# Engines, drivetrains and bodies can be shared with FH2 cars: only bring in a part table's rows for a parent
# FH2 has no rows for in that table, so existing FH2 cars never gain or lose upgrade options.
foreach ($p in @(@{ Col = 'EngineID'; Ids = $engines; Own = 'List_UpgradeEngine' }, @{ Col = 'DrivetrainID'; Ids = $drivetrains; Own = 'List_UpgradeDrivetrain' }, @{ Col = 'CarBodyID'; Ids = $bodies; Own = 'List_UpgradeCarBody' })) {
  foreach ($t in TablesWith $p.Col) {
    if ($t -eq $p.Own) { continue }
    Add-Sel $t "$($p.Col) IN $(In $p.Ids) AND $($p.Col) NOT IN (SELECT $($p.Col) FROM fh.[$($fhTables[$t.ToLower()])])"
  }
}
Add-Sel 'Data_CarBody' "Id IN $(In $bodies)"

function SelWhere([string]$t) { '(' + ($sel[$t] -join ') OR (') + ')' }

# torque curves referenced by any selected row
$curves = @()
foreach ($t in @($sel.Keys)) {
  foreach ($c in Cols 'fm' $t | Where-Object { $_ -like 'TorqueCurve*ID' }) {
    $curves += Q "SELECT DISTINCT [$c] FROM fm.[$t] WHERE $(SelWhere $t) AND [$c] IS NOT NULL"
  }
}
$curves = @($curves | Sort-Object -Unique)
if ($curves.Count) { Add-Sel 'List_TorqueCurve' "TorqueCurveID IN $(In $curves)" }

# lookups the selected rows point at: column -> (table, key column)
$lookups = @{
  # (keys are case-insensitive, so ManufacturerID also covers ManufacturerId)
  StockWheelID = 'List_Wheels|Id'; MakeID = 'List_CarMake|ID'; ManufacturerID = 'List_PartManufacturer|ID'
  TireCompoundID = 'List_TireCompound|TireCompoundID'; AeroPhysicsID = 'List_AeroPhysics|AeroPhysicsID'; PartsStringId = 'List_PartsStrings|ID'
  FrontBrakeTypeID = 'List_BrakeType|ID'; RearBrakeTypeID = 'List_BrakeType|ID'; DamageModDefID = 'List_DamageModDef|ID'
  SuspensionDamageModDefID = 'List_DamageModDef|ID'; TiresDamageModDefID = 'List_DamageModDef|ID'; ColorClassId = 'List_ColorClass|ID'
  SuspensionPhysicsTypeID = 'List_SuspensionPhysicsType|ID'; VariableTimingID = 'List_VariableTiming|ID'
}
$report = @()
foreach ($t in @($sel.Keys)) {
  foreach ($c in Cols 'fm' $t) {
    if (-not $lookups.ContainsKey($c)) { continue }
    $lt, $lk = $lookups[$c].Split('|')
    if (-not $fhTables.ContainsKey($lt.ToLower())) { continue }
    $lkFh = (Pk 'fh' $lt | Select-Object -First 1); if (-not $lkFh) { $lkFh = $lk }
    $missing = Q "SELECT DISTINCT [$c] FROM fm.[$t] WHERE ($(SelWhere $t)) AND [$c] IS NOT NULL AND [$c] <> 0 AND [$c] NOT IN (SELECT [$lkFh] FROM fh.[$lt])"
    foreach ($v in $missing) {
      if (Q "SELECT 1 FROM fm.[$lt] WHERE [$lkFh] = $v") { Add-Sel $lt "[$lkFh] = $v"; $report += "lookup  $lt $lkFh=$v (from $t.$c) added from FM5" }
      else { $report += "MISSING $lt $lkFh=$v (from $t.$c) exists in neither database" }
    }
  }
}

# --- emit SQL ---
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine("-- Imports FM5 car $media (Id $CarId) into FH2. Generated by tools/Export-Fm5Car.ps1; regenerate rather than hand-edit.")
[void]$sb.AppendLine("-- Source: $(Split-Path $Fm5Db -Leaf)")
[void]$sb.AppendLine()
$counts = [ordered]@{}
foreach ($t in $sel.Keys) {
  $fhName = $fhTables[$t.ToLower()]
  $common = @(Cols 'fm' $t | Where-Object { (Cols 'fh' $fhName) -contains $_ })
  $colList = ($common | ForEach-Object { "[$_]" }) -join ','
  $pk = @(Pk 'fh' $fhName)
  $where = SelWhere $t
  if ($pk.Count) {
    $match = ($pk | ForEach-Object { "x.[$_] = s.[$_]" }) -join ' AND '
    $newCond = "NOT EXISTS (SELECT 1 FROM fh.[$fhName] x WHERE $match)"
    $diff = @(Q "SELECT count(*) FROM (SELECT $colList FROM fm.[$t] s WHERE ($where) AND NOT $newCond EXCEPT SELECT $colList FROM fh.[$fhName])")
    if ([int]$diff[0] -gt 0) { $report += "CONFLICT $t : $($diff[0]) row(s) share a key with different FH2 content; kept FH2's" }
  } else {
    # no primary key: import only if FH2 has nothing matching the selection
    $newCond = "NOT EXISTS (SELECT 1 FROM fh.[$fhName] s WHERE $where)"
  }
  $rows = & $Sqlite -bail ':memory:' @attach '.headers on' ".mode insert $fhName" "SELECT $colList FROM fm.[$t] s WHERE ($where) AND $newCond"
  if ($LASTEXITCODE -ne 0) { throw "export of $t failed" }
  $rows = @($rows | Where-Object { $_ } | ForEach-Object { $_.TrimEnd("`r") })
  if ($rows.Count) {
    $counts[$fhName] = $rows.Count
    [void]$sb.AppendLine("-- $fhName")
    foreach ($r in $rows) { [void]$sb.AppendLine($r) }
    [void]$sb.AppendLine()
  }
}

$importLines = @("cars\$media.zip <- cars\$media.zip")
if (Test-Path (Join-Path $Fm5Media "audio\cars\$media.xml")) { $importLines += "audio\cars\$media.xml <- audio\cars\$media.xml" }

# thumbnail: FM5 keeps Thumbnail_<id>_Big/_Small.swatchbin in ui\textures\data_bound\<folder>.zip; FH2 reads them from stripped\RC0.zip
$fmThumb = @(Q "SELECT Thumbnail FROM fm.Data_Car WHERE Id = $CarId")[0]
if (-not $Thumbnail -and $fmThumb -match '\\Data_Bound\\([^\\]+)\\(Thumbnail_\d+)\.png$') {
  $tz = Join-Path $Fm5Media "ui\textures\data_bound\$($Matches[1]).zip"; $tn = $Matches[2]
  if (Test-Path $tz) {
    $za = [IO.Compression.ZipFile]::OpenRead($tz)
    $have = @($za.Entries | Where-Object { $_.FullName -in "$($tn)_Big.swatchbin", "$($tn)_Small.swatchbin" }).Count -eq 2
    $za.Dispose()
    if ($have) {
      foreach ($s in '_Big', '_Small') { $importLines += "stripped\RC0.zip\$tn$s.swatchbin <- ui\textures\data_bound\$(Split-Path $tz -Leaf)\$tn$s.swatchbin" }
      $Thumbnail = "game:\Media\Stripped\RC0\$tn.png"
      $report += "thumb   FM5 $tn -> stripped\RC0.zip"
    }
  }
}

# Data_Car fix-ups
if (-not $DonorCarId) {
  $DonorCarId = [int]@(Q "SELECT Id FROM fh.Data_Car WHERE MakeID = $makeId ORDER BY abs(Year - $year), Id LIMIT 1")[0]
  if (-not $DonorCarId) { $DonorCarId = [int]@(Q "SELECT Id FROM fh.Data_Car ORDER BY abs(Year - $year), Id LIMIT 1")[0] }
}
$donor = @(Q "SELECT MediaName FROM fh.Data_Car WHERE Id = $DonorCarId")[0]
if (-not $donor) { throw "FH2 has no car with Id $DonorCarId" }
$donorBank = @(Q "SELECT e.MediaName FROM fh.List_UpgradeEngine u JOIN fh.Data_Engine e ON e.EngineID = u.EngineID WHERE u.Ordinal = $DonorCarId ORDER BY u.IsStock DESC, u.Level LIMIT 1")[0]
if (-not $donorBank -or -not $banks.ContainsKey($donorBank.ToLower())) { throw "Donor $donor has no engine sound bank" }
if (-not $EngineSound -and -not $UseFm5Sound) { $EngineSound = $donorBank }
$fhOnly = @(Cols 'fh' 'Data_Car' | Where-Object { (Cols 'fm' 'Data_Car') -notcontains $_ })
if (-not $Thumbnail) { $Thumbnail = @(Q "SELECT Thumbnail FROM fh.Data_Car WHERE Id = $DonorCarId")[0] }
[void]$sb.AppendLine("-- Data_Car fix-ups: FH2-only columns from donor $donor (Id $DonorCarId), no license gate, FH2 thumbnail path")
if ($fhOnly.Count) {
  $set = ($fhOnly | ForEach-Object { "[$_] = (SELECT [$_] FROM Data_Car WHERE Id = $DonorCarId)" }) -join ",`r`n  "
  [void]$sb.AppendLine("UPDATE Data_Car SET`r`n  $set`r`nWHERE Id = $CarId;")
}
[void]$sb.AppendLine("UPDATE Data_Car SET ContentId = 0, Thumbnail = '$($Thumbnail.Replace("'", "''"))' WHERE Id = $CarId;")

# Data_Car_Buckets is FH2-only (Autoshow/class grouping); FM5 has nothing to copy
if (-not $Bucket) { $Bucket = [int]@(Q "SELECT CarBucket FROM fh.Data_Car_Buckets WHERE CarId = $DonorCarId")[0] }
if ($Bucket) {
  [void]$sb.AppendLine("INSERT INTO Data_Car_Buckets (CarId, CarBucket, BucketHero) VALUES ($CarId, $Bucket, 0);   -- bucket of donor unless -Bucket given")
  $report += "bucket  $Bucket"
} else { $report += "BUCKET  donor has no Data_Car_Buckets row; pass -Bucket" }

# engine sounds
foreach ($en in $engines) {
  $em = @(Q "SELECT MediaName FROM fm.Data_Engine WHERE EngineID = $en")[0]
  if (-not $em -or $banks.ContainsKey($em.ToLower())) { continue }
  if ((Q "SELECT 1 FROM fh.Data_Engine WHERE EngineID = $en")) { continue }   # existing FH2 engine: not ours to change
  if ($EngineSound) {
    # FH2 sound (the donor's unless -EngineSound): FM5 banks renamed PG_<engine>.bank turned out silent for the Trans Am
    if (-not $banks.ContainsKey($EngineSound.ToLower())) { throw "FH2 has no PG_$EngineSound.bank to borrow" }
    [void]$sb.AppendLine("UPDATE Data_Engine SET MediaName = '$EngineSound' WHERE EngineID = $en;   -- engine sound borrowed from FH2")
    $report += "sound   engine $en ($em) -> FH2 $EngineSound"
  } elseif (Test-Path (Join-Path $Fm5Media "audio\fmod\durango\$em.bank")) {
    # FH2 loads PG_<engine>.bank; the GT500 import used FM5's bank under that name (not confirmed audible)
    $importLines += "audio\fmodanthem\durango\PG_$em.bank <- audio\fmod\durango\$em.bank"
    $report += "sound   engine $en ($em): FM5 bank imported as PG_$em.bank"
  } else { $report += "SOUND   engine $en ($em): FH2 has no PG_$em.bank; pass -EngineSound to borrow one" }
}

# --- write mod folder ---
$modDir = Join-Path $(if ($env:FH2_MODS_ROOT) { $env:FH2_MODS_ROOT } else { Join-Path $root 'mods' }) $Mod
$sqlDir = Join-Path $modDir 'media\stripped\gamedbRC.slt'
New-Item -ItemType Directory $sqlDir -Force | Out-Null
$sqlPath = Join-Path $sqlDir "$CarId-$media.sql"
[IO.File]::WriteAllText($sqlPath, $sb.ToString())
# Index donors: every new file needs a Mount\hash.manifest record whose 4-byte metadata is copied from a similar stock
# file (meaning unknown; this is what the working GT500 import did). Use the donor car's own files.
$donorBankPath = "audio\fmodanthem\durango\PG_$donorBank.bank"
$donorXmlPath = if ($audioXml.ContainsKey($donor.ToLower())) { "audio\cars\$donor.xml" } else { $donorBankPath }
$donorLines = foreach ($l in $importLines) {
  $dest = ($l -split '\s*<-\s*')[0]
  if ($dest -match '\.zip\\') { continue }   # entries added inside an existing zip need no record
  $d = switch -Wildcard ($dest) { 'cars\*.zip' { "cars\$donor.zip" } '*.bank' { $donorBankPath } 'audio\cars\*.xml' { $donorXmlPath } default { throw "No index donor rule for $dest" } }
  "$dest <- $d"
}
[IO.File]::WriteAllText((Join-Path $modDir 'index-donors.txt'), "# <new media path> <- <stock media path whose hash.manifest metadata it copies>`r`n" + ($donorLines -join "`r`n") + "`r`n")

[IO.File]::WriteAllText((Join-Path $modDir 'imports.txt'), "# <FH2 media path> <- <FM5 media path> (source: -Fm5Media / FH2_FM5_MEDIA); a .zip segment means an entry inside that zip`r`n" + ($importLines -join "`r`n") + "`r`n")

$readmePath = Join-Path $modDir 'README.txt'
if (-not (Test-Path $readmePath)) {
  $title = "FORZA HORIZON 2 (PC) - FM5 CAR IMPORT: $media"
  [IO.File]::WriteAllText($readmePath, @"
$title
$('=' * $title.Length)

Adds the Forza Motorsport 5 $media (car Id $CarId) to Forza Horizon 2 as a new
car in the Autoshow.

Requires FH2 1.0.0.64 (Anthem_1.0.0.64_x64__8wekyb3d8bbwe) on Azimuth 0.9.7.

Known limitations:
  - The car's name shows blank in menus

This mod adds new files to the game, so it also replaces Mount\hash.manifest
(Azimuth's file index) and patches azimuth.exe to accept it. The installer
below does both and keeps your stock launcher.

It replaces zipmanifest.xml, gamedbRC.slt, stripped\RC0.zip and
hash.manifest, so it can't be installed on top of other mods that change
those files. Build the mods together from the fh2-mods repo instead.
"@)
}

Write-Host "Wrote $sqlPath"
$counts.GetEnumerator() | ForEach-Object { Write-Host ("  {0,-40} {1}" -f $_.Key, $_.Value) }
Write-Host "Donor for FH2-only Data_Car columns: $donor (Id $DonorCarId)"
$report | ForEach-Object { Write-Host "  $_" }
