<#
.SYNOPSIS
  Imports Forza Motorsport 5 cars into Forza Horizon 2 (PC / Azimuth) from your own FM5 and FH2 installs.

.DESCRIPTION
  Ships no game files: everything is read from your FM5 folder and your FH2 folder. For each car you pick, it
  generates the database rows, converts the car's models for FH2's shaders, builds one install on top of your current
  game files and installs it with backups (Install.ps1).

  Run it with no parameters (or double-click Import-Fm5Cars.cmd) to be asked for everything: your folders (remembered),
  the FM5 cars to import (search by name), and per car an FH2 data donor (FH2-only car data - pick something similar),
  a sound donor (an FH2 car whose engine sound it uses), the Autoshow group to list it in (default: the donor's) and a
  light donor (an FH2 car with similar lamps whose night lights are fitted to it; Add-CarLights.ps1, as a second layer).

  Imports stack: each run adds its cars on top of whatever is installed (earlier imports, a modded gamedb, other
  mods), and cars the game already has aren't offered. Each run gets its own backup folder (mod-backups\<Name>-<time>)
  with an Uninstall.ps1; undo runs newest first. The cars install into Mount\mediapc, which FH2 Extra Options makes
  the game read before Mount\media; the game's own files aren't changed. Requires FH2 1.0.0.64 on Azimuth 0.9.10
  with Extra Options (winmm.dll beside azimuth.exe) or 0.9.9 with Extra Options 0.2.74+, and FM5 1.0.0.20.
  sqlite3.exe is downloaded from sqlite.org (hash-checked) if it isn't on PATH.

.EXAMPLE
  .\tools\fm5-import\Import-Fm5Cars.ps1
.EXAMPLE
  .\tools\fm5-import\Import-Fm5Cars.ps1 -Fm5Root "D:\Forza_1.0.0.20_x64__8wekyb3d8bbwe" -GameRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe" `
      -AzimuthRoot "D:\azimuth" -Car PON_TransAm_02,AST_DBS_09 -Donor PON_TransAmGTA_87,AST_DBSTF_08 -SoundCar CHE_CorvetteZR1_95,"" `
      -Group 'Retro Muscle',"" -LightDonor PON_TransAmGTA_87,AST_DBSTF_08 -WhiterHeadlights
.EXAMPLE
  .\tools\fm5-import\Import-Fm5Cars.ps1 -ListFm5Only    # FM5 cars FH2 doesn't have
#>
[CmdletBinding()]
param(
  [string]$Fm5Root,                          # FM5 folder containing Mount
  [string]$GameRoot,                         # FH2 folder containing Mount (default: the one Azimuth is set to)
  [string]$AzimuthRoot,                      # folder containing azimuth.exe
  [string[]]$Car,                            # FM5 MediaNames or Ids (omit to be asked)
  [string[]]$Donor,                          # FH2 data donor per car (MediaName or Id); "" = automatic (same make, nearest year)
  [string[]]$SoundCar,                       # FH2 car per car whose engine sound to use; "" = the data donor's
  [string[]]$EngineSound,                    # or the FH2 engine MediaName directly
  [string[]]$Group,                          # Autoshow group per car ('Modern Muscle', or its CarBuckets Id); "" = the data donor's
  [string[]]$LightDonor,                     # FH2 car per car whose night lights to fit (Add-CarLights.ps1); "" = none
  [switch]$WhiterHeadlights,                 # light donors with the warm HALOGEN_B headlights get the '87 GTA's whiter ones
  [string]$Name = 'fm5-cars',                # install name (backups are mod-backups\<Name>-<time>)
  [string]$Sqlite = $env:FH2_SQLITE,
  [switch]$ListFm5Only,                      # just list the FM5 cars FH2 doesn't have
  [string]$ExportList,                       # write the imported cars installed here to this file (for -FromList elsewhere)
  [string]$FromList,                         # import the cars in a file written by -ExportList (ones already here are skipped)
  [switch]$Yes,                              # -FromList: don't ask before importing
  [switch]$NoInstall                         # build only (output in build\<Name>)
)
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot; $root = Split-Path (Split-Path $tools); $bin = Join-Path (Split-Path $tools) 'bin'   # tools\fm5-import; downloads in tools\bin
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
if ($FromList -and $Car) { throw 'Pass -Car or -FromList, not both' }
$interactive = -not $Car -and -not $ListFm5Only -and -not $FromList -and -not $ExportList
$askFolders = $interactive -or $FromList -or $ExportList   # run by hand: confirm the folders

# --- folders: parameters, then remembered values / Azimuth's own settings, then ask ---
$settingsPath = Join-Path $env:LOCALAPPDATA 'fh2-mods\import-fm5-cars.json'
$saved = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
function Ask([string]$prompt) { $a = Read-Host $prompt; if ($null -eq $a) { throw 'Input ended' }; $a.Trim() }
function Get-Folder([string]$label, [string]$value, [string]$default, [scriptblock]$valid, [string]$hint) {
  if ($value) { if (& $valid $value) { return (Resolve-Path $value).Path }; throw "$label isn't valid: $value ($hint)" }
  if (-not $askFolders -and $default -and (& $valid $default)) { return $default }
  if (-not $askFolders) { throw "Pass -$($label -replace ' ', '') ($hint)" }
  while ($true) {
    $prompt = if ($default) { "$label [$default]" } else { $label }
    $a = (Ask $prompt).Trim('"')
    if (-not $a) { $a = $default }
    if ($a -and (Test-Path -LiteralPath $a) -and (& $valid $a)) { return (Resolve-Path -LiteralPath $a).Path }
    Write-Host "  Not valid: $hint" -ForegroundColor Yellow
  }
}
$isAzimuth = { param($p) Test-Path (Join-Path $p 'azimuth.exe') }
$isFh2 = { param($p) Test-Path (Join-Path $p 'Mount\forza_durango_release_final.exe') }
$isFm5 = { param($p) Test-Path (Join-Path $p 'Mount\media\db\gamedb.slt') }

if ($askFolders) { Write-Host "`nFM5 -> FH2 car importer`n" -ForegroundColor Cyan }
if (-not $NoInstall -or $AzimuthRoot) { $AzimuthRoot = Get-Folder 'Azimuth folder' $AzimuthRoot $saved.AzimuthRoot $isAzimuth 'the folder containing azimuth.exe' }
$iniGame = $null
if ($AzimuthRoot -and (Test-Path "$AzimuthRoot\data\azimuth.ini")) {
  # game_folder= (older Azimuth), or folder= in the FH2 title's section [title-1a96545b] (0.9.9+)
  $m = [regex]::Match((Get-Content "$AzimuthRoot\data\azimuth.ini" -Raw), '(?m)^game_folder=(.+?)\s*$|(?ms)^\[title-1a96545b\][^\[]*?^folder=(.+?)\s*$')
  if ($m.Success) { $iniGame = $(if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }) }
}
$GameRoot = Get-Folder 'FH2 game folder' $GameRoot $(if ($iniGame) { $iniGame } else { $saved.GameRoot }) $isFh2 'the folder containing Mount\forza_durango_release_final.exe'

# --- cars imported by earlier runs that are still installed (each run's backup folder has cars.json) ---
$layers = @(Get-ChildItem (Join-Path $GameRoot 'mod-backups') -Directory -ErrorAction SilentlyContinue | Sort-Object Name |
  Where-Object { $_.Name -notlike '*-uninstalled' -and (Test-Path (Join-Path $_.FullName 'cars.json')) -and -not (Test-Path (Join-Path $_.FullName 'uninstalled.txt')) })
$state = @($layers | ForEach-Object { $l = $_; (Get-Content (Join-Path $l.FullName 'cars.json') -Raw | ConvertFrom-Json) | ForEach-Object { $_ | Add-Member -NotePropertyName layer -NotePropertyValue $l.FullName -PassThru } })
$importedIds = @($state | ForEach-Object { $_.id }) + -1
. (Join-Path $tools '..\build\StockSource.ps1')   # Get-GameMediaFile: what the game reads (Mount\mediapc first)
Add-Type -AssemblyName System.IO.Compression.FileSystem

# night lights (FM5 cars have none): which FH2 cars have light data, and is their headlight the warm HALOGEN_B
$lightInfo = @{}
function Light-Info([string]$fh2Car) {
  if ($lightInfo.ContainsKey($fh2Car)) { return $lightInfo[$fh2Car] }
  $zp = Get-GameMediaFile $GameRoot "cars\$fh2Car.zip"; $r = [pscustomobject]@{ Has = $false; Warm = $false }
  if ($zp) {
    $z = [IO.Compression.ZipFile]::OpenRead($zp.FullName)
    try {
      $r.Has = [bool]($z.Entries | Where-Object FullName -eq 'Lights.bin')
      $dbg = $z.Entries | Where-Object FullName -eq 'LightPresets.bin_debug'
      if ($dbg) { $sr = New-Object IO.StreamReader($dbg.Open(), [Text.Encoding]::ASCII); $r.Warm = $sr.ReadToEnd() -match 'PG_Function_Headlight_HALOGEN_B'; $sr.Close() }
    } finally { $z.Dispose() }
  }
  $lightInfo[$fh2Car] = $r; $r
}
$whiterFrom = 'PON_TransAmGTA_87'   # HALOGEN_A headlights (1.0, 0.8, 0.6), same preset layout
function Text-Of($v) { if ($v -is [string] -and $v) { $v } else { $null } }   # cars.json from PowerShell 5.1 can hold {} for an empty value

# --- -ExportList: the installed imports, as they are in the game (lights and headlight colour read from the cars) ---
if ($ExportList) {
  $list = @($state | ForEach-Object {
    $lit = Light-Info $_.car; $ld = Text-Of $_.lightDonor
    if (-not $lit.Has) { $ld = $null }   # its lights were never fitted (or were undone)
    [pscustomobject]@{ car = $_.car; donor = (Text-Of $_.donor); soundCar = (Text-Of $_.soundCar); engine = (Text-Of $_.engine)
      group = (Text-Of $_.group); groupId = $_.groupId; lightDonor = $ld
      whiter = [bool]($ld -and -not (Text-Of $_.presetFrom) -and -not $lit.Warm -and (Light-Info $ld).Warm)
      headlightStyle = $(if ($ld) { Text-Of $_.headlightStyle } else { $null }); presetFrom = $(if ($ld) { Text-Of $_.presetFrom } else { $null })
      headlightColor = $(if ($ld) { Text-Of $_.headlightColor } else { $null }); graphFrom = $(if ($ld) { Text-Of $_.graphFrom } else { $null }) }
  })
  if (-not $list.Count) { Write-Host "No imported cars are installed in $GameRoot."; return }
  # cars imported by hand (Export-Fm5Car / Build-Mod) or lights fitted by running Add-CarLights.ps1 yourself aren't
  # in any cars.json: add them to the file (same fields) before importing it elsewhere
  ConvertTo-Json -InputObject $list | Set-Content -LiteralPath $ExportList -Encoding UTF8
  Write-Host "Wrote $($list.Count) cars to $((Resolve-Path -LiteralPath $ExportList).Path):"
  $list | ForEach-Object { Write-Host ("  {0,-26} data donor {1,-24} sound {2}, lights {3}" -f $_.car, $_.donor, $_.soundCar, $(if ($_.lightDonor) { $_.lightDonor + $(if ($_.whiter) { ' (whiter)' }) } else { 'none' })) }
  Write-Host "On the other PC: Import-Fm5Cars.cmd -FromList <this file>"
  return
}

$Fm5Root = Get-Folder 'FM5 game folder' $Fm5Root $saved.Fm5Root $isFm5 'the folder containing Mount\media\db\gamedb.slt'
New-Item -ItemType Directory (Split-Path $settingsPath) -Force | Out-Null
[pscustomobject]@{ AzimuthRoot = $AzimuthRoot; GameRoot = $GameRoot; Fm5Root = $Fm5Root } | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
$fm5Media = Join-Path $Fm5Root 'Mount\media'

# --- sqlite3: PATH, -Sqlite, tools\bin, or download the official build ---
if (-not $Sqlite) { $Sqlite = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Source }
if (-not $Sqlite -and (Test-Path "$bin\sqlite3.exe")) { $Sqlite = "$bin\sqlite3.exe" }
if (-not $Sqlite) {
  $url = 'https://www.sqlite.org/2024/sqlite-tools-win-x64-3470200.zip'; $zipSha = '8c7fffbf4eec1f43e63153cca6deb018e4360d4d6b0d99bbdd2a541c53b7fa1c'
  Write-Host "Downloading sqlite3 from $url"
  New-Item -ItemType Directory "$bin" -Force | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile "$bin\sqlite-tools.zip" -UseBasicParsing
  if ((Sha "$bin\sqlite-tools.zip") -ne $zipSha) { Remove-Item "$bin\sqlite-tools.zip"; throw 'sqlite download failed its hash check' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::OpenRead("$bin\sqlite-tools.zip")
  try { [IO.Compression.ZipFileExtensions]::ExtractToFile(($z.Entries | Where-Object Name -eq 'sqlite3.exe'), "$bin\sqlite3.exe", $true) } finally { $z.Dispose() }
  Remove-Item "$bin\sqlite-tools.zip"; $Sqlite = "$bin\sqlite3.exe"
}

# --- car lists. Every run adds a layer on top of the installed game (earlier imports and other mods stay) ---
$fhDb = (Get-GameMediaFile $GameRoot 'stripped\gamedbRC.slt').FullName.Replace('\', '/'); $fmDb = (Join-Path $fm5Media 'db\gamedb.slt').Replace('\', '/')
function Q([string]$sql) {   # rows as arrays of fields; no double quotes in $sql (PowerShell 5.1 native argument quirk)
  $out = & $Sqlite -bail -list -separator '|' ':memory:' "ATTACH 'file:$fmDb`?immutable=1' AS fm;" "ATTACH 'file:$fhDb`?immutable=1' AS fh;" $sql
  if ($LASTEXITCODE -ne 0) { throw "sqlite3 failed: $sql" }
  , @($out | ForEach-Object { , ($_.TrimEnd("`r").Split('|')) })   # always a list of rows, even for one row
}
# FM5 cars the game doesn't have yet (stock or imported); donors are FH2's own cars
$fm5Only = Q "SELECT Id, MediaName, Year, MakeID FROM fm.Data_Car WHERE Id NOT IN (SELECT Id FROM fh.Data_Car) AND MediaName NOT IN (SELECT MediaName FROM fh.Data_Car) ORDER BY MediaName"
if ($ListFm5Only) { $fm5Only | ForEach-Object { '{0,5}  {1,-30} {2}' -f $_[0], $_[1], $_[2] }; return }
$fh2Cars = Q "SELECT Id, MediaName, Year, MakeID FROM fh.Data_Car WHERE Id NOT IN ($($importedIds -join ',')) ORDER BY MediaName"
function Engine-Of([string]$fh2Car) {   # stock engine sound (engine MediaName) of an FH2 car (MediaName or Id)
  $w = if ($fh2Car -match '^\d+$') { "c.Id = $fh2Car" } else { "c.MediaName = '$($fh2Car.Replace("'", ''))' COLLATE NOCASE" }
  $r = Q "SELECT e.MediaName FROM fh.Data_Car c JOIN fh.List_UpgradeEngine u ON u.Ordinal = c.Id JOIN fh.Data_Engine e ON e.EngineID = u.EngineID WHERE $w ORDER BY u.IsStock DESC, u.Level LIMIT 1"
  if (-not $r) { throw "FH2 has no car $fh2Car (or it has no engine)" }
  $r[0][0]
}

# Autoshow groups (CarBuckets under a top-level group), names from FH2's English string table
. (Join-Path $tools 'WheelSwap.ps1')
$bucketNames = Read-StringTable (Get-GameMediaFile $GameRoot 'stripped\stringtables\EN.zip').FullName 'CarBuckets.str'
$groupRows = Q 'SELECT b.Id, b.Name, p.Name, (SELECT COUNT(*) FROM fh.Data_Car_Buckets x WHERE x.CarBucket = b.Id), (SELECT c.MediaName FROM fh.Data_Car_Buckets x JOIN fh.Data_Car c ON c.Id = x.CarId WHERE x.CarBucket = b.Id ORDER BY c.Id LIMIT 1) FROM fh.CarBuckets b JOIN fh.CarBuckets p ON p.Id = b.ParentBucketId ORDER BY p.SortPriority, p.Id, b.SortPriority, b.Id'
$groups = @($groupRows | ForEach-Object {
  $n = Resolve-String $bucketNames $_[1]; if (-not $n) { $n = "(no name, e.g. $($_[4]))" }   # the game has a group without an English name
  [pscustomobject]@{ Id = [int]$_[0]; Name = $n; Parent = (Resolve-String $bucketNames $_[2]); Cars = [int]$_[3] }
})
function Group-Of([string]$fh2Car) {   # the Autoshow group of an FH2 car (MediaName)
  $r = Q "SELECT b.CarBucket FROM fh.Data_Car c JOIN fh.Data_Car_Buckets b ON b.CarId = c.Id WHERE c.MediaName = '$($fh2Car.Replace("'", ''))' COLLATE NOCASE"
  if ($r) { $groups | Where-Object Id -eq ([int]$r[0][0]) }
}
function Find-Group([string]$g) {   # by Id, name, or "Parent > Name"
  $hit = @($groups | Where-Object { "$($_.Id)" -eq $g -or $_.Name -ieq $g -or "$($_.Parent) > $($_.Name)" -ieq $g })
  if ($hit.Count -ne 1) { throw "Unknown Autoshow group '$g'. Groups: $(($groups | ForEach-Object { "$($_.Id) $($_.Name)" }) -join ', ')" }
  $hit[0]
}
function Pick-Group([object]$default) {   # numbered list; Enter keeps $default
  $i = 0
  foreach ($g in $groups) { $i++; Write-Host ('  {0,3}) {1,-16} {2,-28} {3,3} cars' -f $i, $g.Parent, $g.Name, $g.Cars) }
  while ($true) {
    $a = Ask "  Autoshow group [$(if ($default) { "$($default.Parent) > $($default.Name)" })]"
    if (-not $a -and $default) { return $default }
    if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -le $groups.Count) { return $groups[[int]$a - 1] }
    $hit = @($groups | Where-Object { $_.Name -like "*$a*" })
    if ($hit.Count -eq 1) { return $hit[0] }
    Write-Host '  Type a number from the list (or a unique part of a group name).' -ForegroundColor Yellow
  }
}

function Pick([object[]]$rows, [string]$prompt, [object]$default, [switch]$AllowDone, [switch]$AllowNone) {
  # search by part of the name; a number picks from the last list shown; Enter takes the default (or finishes);
  # with -AllowNone, "none" returns 'none'
  $shown = @()
  while ($true) {
    $p = if ($default) { "$prompt [$($default[1])]" } elseif ($AllowDone) { "$prompt (Enter when done)" } else { $prompt }
    $a = Ask $p
    if ($AllowNone -and $a -ieq 'none') { return 'none' }
    if (-not $a) { if ($default) { return $default }; if ($AllowDone) { return $null }; continue }
    if ($a -match '^\d+$' -and $shown.Count -and [int]$a -ge 1 -and [int]$a -le $shown.Count) { return $shown[[int]$a - 1] }
    $exact = @($rows | Where-Object { $_[1] -ieq $a -or $_[0] -eq $a })
    if ($exact.Count -eq 1) { return $exact[0] }
    $terms = $a -split '\s+'
    $hits = @($rows | Where-Object { $n = "$($_[1]) $($_[2])"; -not ($terms | Where-Object { $n -notlike "*$_*" }) })
    if ($hits.Count -eq 0) { Write-Host '  No match. Try part of the name, e.g. "transam" or "mustang 2013".' -ForegroundColor Yellow; continue }
    if ($hits.Count -eq 1) { return $hits[0] }
    $shown = @($hits | Select-Object -First 30)
    for ($i = 0; $i -lt $shown.Count; $i++) { Write-Host ('  {0,3}) {1,-30} {2}' -f ($i + 1), $shown[$i][1], $shown[$i][2]) }
    if ($hits.Count -gt 30) { Write-Host "  ... $($hits.Count - 30) more; type more of the name" }
  }
}

# --- interactive selection ---
$plan = @()   # @{ id; car; donor; soundCar; engine }
if ($interactive) {
  if ($state.Count) {
    Write-Host "`nAlready imported (they stay; the new cars are added on top):"
    $state | ForEach-Object { Write-Host ("  {0,-26} data donor {1,-24} sound {2}" -f $_.car, $_.donor, $_.soundCar) }
  }
  Write-Host "`nPick FM5 cars to import. Type part of a name (e.g. transam, 'mustang 2005'); a number picks from the list."
  while ($true) {
    $chosen = @($plan | ForEach-Object { $_.id })
    $c = Pick @($fm5Only | Where-Object { $chosen -notcontains $_[0] }) "`nFM5 car to add" $null -AllowDone:($plan.Count -gt 0)
    if (-not $c) { break }
    $suggest = $fh2Cars | Where-Object { $_[3] -eq $c[3] } | Sort-Object { [math]::Abs([int]$_[2] - [int]$c[2]) } | Select-Object -First 1
    if (-not $suggest) { $suggest = $fh2Cars | Sort-Object { [math]::Abs([int]$_[2] - [int]$c[2]) } | Select-Object -First 1 }
    Write-Host "  $($c[1]) ($($c[2]))" -ForegroundColor Green
    Write-Host '  Data donor: an FH2 car of the same kind (FH2-only car data, Autoshow group).'
    $d = Pick $fh2Cars '  Data donor' $suggest
    Write-Host '  Sound donor: an FH2 car whose engine sound to use.'
    $s = Pick $fh2Cars '  Sound donor' $d
    Write-Host '  Autoshow group: where the car is listed (also picks its wheel''s shop category). Enter keeps the data donor''s.'
    $g = Pick-Group (Group-Of $d[1])
    Write-Host '  Light donor: an FH2 car with similar lamps whose night lights to fit (pop-ups for a pop-up car); "none" to skip.'
    $ls = if ((Light-Info $d[1]).Has) { $d } else { $fh2Cars | Where-Object { $_[3] -eq $c[3] -and (Light-Info $_[1]).Has } | Sort-Object { [math]::Abs([int]$_[2] - [int]$c[2]) } | Select-Object -First 1 }
    $l = Pick $fh2Cars '  Light donor' $ls -AllowNone
    while ($l -ne 'none' -and -not (Light-Info $l[1]).Has) { Write-Host "  $($l[1]) has no light data; pick another." -ForegroundColor Yellow; $l = Pick $fh2Cars '  Light donor' $ls -AllowNone }
    $white = $false
    if ($l -ne 'none' -and (Light-Info $l[1]).Warm) { $white = (Ask "  $($l[1])'s headlights are a warm, orange-ish halogen. Use whiter ones? [Y/n]") -notmatch '^(n|no)$' }
    $plan += @{ id = $c[0]; car = $c[1]; donor = $d[1]; soundCar = $s[1]; engine = (Engine-Of $s[1]); group = $g.Id; groupName = $g.Name
                lightDonor = $(if ($l -ne 'none') { $l[1] }); whiter = $white }
  }
} elseif ($FromList) {
  # a list from -ExportList (another PC's imports): the same choices, minus the cars this game already has
  $list = @((Get-Content -LiteralPath $FromList -Raw | ConvertFrom-Json) | ForEach-Object { $_ })   # (5.1: unroll the array)
  $haveFh2 = @((Q 'SELECT MediaName FROM fh.Data_Car') | ForEach-Object { $_[0].ToLowerInvariant() })
  foreach ($e in $list) {
    $row = @($fm5Only | Where-Object { $_[1] -ieq $e.car })
    if (-not $row) {
      if ($haveFh2 -contains "$($e.car)".ToLowerInvariant()) { Write-Host "  $($e.car): already in the game, skipped"; continue }
      throw "FM5 car $($e.car) isn't in this FM5 (Mount\media\db\gamedb.slt)"
    }
    $g = if ($e.groupId) { Find-Group "$($e.groupId)" } elseif (Text-Of $e.group) { Find-Group $e.group } else { $null }
    $ld = Text-Of $e.lightDonor
    if ($ld -and -not (Light-Info $ld).Has) { throw "Light donor $ld (for $($e.car)) has no light data here" }
    $snd = Text-Of $e.soundCar
    $plan += @{ id = $row[0][0]; car = $row[0][1]; donor = (Text-Of $e.donor); soundCar = $snd
                engine = $(if (Text-Of $e.engine) { $e.engine } elseif ($snd) { Engine-Of $snd } else { $null })
                group = $(if ($g) { $g.Id }); groupName = $(if ($g) { $g.Name }); lightDonor = $ld; whiter = [bool]$e.whiter
                headlightStyle = (Text-Of $e.headlightStyle); presetFrom = (Text-Of $e.presetFrom); headlightColor = (Text-Of $e.headlightColor); graphFrom = (Text-Of $e.graphFrom) }
  }
} else {
  if ($Donor -and $Donor.Count -ne $Car.Count) { throw '-Donor needs one entry per -Car' }
  if ($SoundCar -and $SoundCar.Count -ne $Car.Count) { throw '-SoundCar needs one entry per -Car (use "" for the data donor''s)' }
  if ($EngineSound -and $EngineSound.Count -ne $Car.Count) { throw '-EngineSound needs one entry per -Car (use "" for the data donor''s)' }
  if ($Group -and $Group.Count -ne $Car.Count) { throw '-Group needs one entry per -Car (use "" for the data donor''s)' }
  if ($LightDonor -and $LightDonor.Count -ne $Car.Count) { throw '-LightDonor needs one entry per -Car (use "" for none)' }
  foreach ($ld in @($LightDonor | Where-Object { $_ })) { if (-not (Light-Info $ld).Has) { throw "Light donor $ld has no light data (or isn't an FH2 car)" } }
  for ($i = 0; $i -lt $Car.Count; $i++) {
    $row = @($fm5Only | Where-Object { $_[1] -ieq $Car[$i] -or $_[0] -eq $Car[$i] })
    if (-not $row) { throw "FM5 car $($Car[$i]) not found, or FH2 already has it (see -ListFm5Only)" }
    $e = if ($EngineSound -and $EngineSound[$i]) { $EngineSound[$i] } elseif ($SoundCar -and $SoundCar[$i]) { Engine-Of $SoundCar[$i] } else { $null }
    $g = if ($Group -and $Group[$i]) { Find-Group $Group[$i] } else { $null }
    $plan += @{ id = $row[0][0]; car = $row[0][1]; donor = $(if ($Donor) { $Donor[$i] } else { '' }); soundCar = $(if ($SoundCar) { $SoundCar[$i] } else { '' }); engine = $e
                group = $(if ($g) { $g.Id }); groupName = $(if ($g) { $g.Name })
                lightDonor = $(if ($LightDonor -and $LightDonor[$i]) { $LightDonor[$i] }); whiter = [bool]$WhiterHeadlights }
  }
}
if ($interactive -or $FromList) {
  if (-not $plan.Count) { Write-Host 'Nothing to import.'; return }
  Write-Host "`nImport plan:" -ForegroundColor Cyan
  $plan | ForEach-Object { Write-Host ("  {0,-26} data donor {1,-24} sound {2} ({3}), group {4}, lights {5}" -f $_.car, $_.donor, $_.soundCar, $_.engine, $_.groupName,
    $(if ($_.lightDonor) { $_.lightDonor + $(if ($_.whiter) { ' (whiter headlights)' }) } else { 'none' })) }
  if (-not $Yes -and (Ask "`nProceed? [Y/n]") -match '^(n|no)$') { Write-Host 'Cancelled.'; return }
}
if (-not $AzimuthRoot -and -not $NoInstall) { throw 'Pass -AzimuthRoot <folder containing azimuth.exe>' }

# --- generate one mod per car in a private workspace, build one install on top of the current game files ---
$ws = Join-Path $root "build\.import-$Name"
if (Test-Path $ws) { Remove-Item -Recurse -Force $ws }
New-Item -ItemType Directory $ws | Out-Null
$env:FH2_MODS_ROOT = $ws
try {
  $mods = @()
  for ($i = 0; $i -lt $plan.Count; $i++) {
    $p = $plan[$i]
    $mod = 'car' + ($i + 1) + '-' + ($p.car -replace '[^\w-]', '').ToLower()
    $a = @{ Car = $p.car; Mod = $mod; Fm5Media = $fm5Media; Game = $GameRoot; Layer = $true; Sqlite = $Sqlite }
    if ($p.donor) { $a.Donor = $p.donor }
    if ($p.engine) { $a.EngineSound = $p.engine }
    if ($p.group) { $a.Bucket = $p.group }
    Write-Host ''
    # (the scripts report with Write-Host: filter the information stream to the useful lines)
    & (Join-Path $tools 'Export-Fm5Car.ps1') @a 6>&1 | Where-Object { "$_" -match '^(Exporting|Donor|  (thumb|bucket|sound|wheel|SOUND|BUCKET|WHEEL|CONFLICT|MISSING))' } | ForEach-Object { Write-Host "$_" }
    $mods += $mod
  }
  Write-Host "`nBuilding (converting models for FH2 takes a minute per car)..."
  & (Join-Path $tools '..\build\Build-Mod.ps1') -Mod $mods -Name $Name -Game $GameRoot -Layer -Fm5Media $fm5Media -Sqlite $Sqlite 6>&1 3>&1 |
    Where-Object { "$_" -match '^(MODELS|Built)' -or $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { Write-Host "$_" }
} finally { Remove-Item Env:FH2_MODS_ROOT }

$release = Join-Path $root "build\$Name"
if ($NoInstall) { Write-Host "Built $release (not installed)"; return }
Write-Host ''
$installed = @(& (Join-Path $release 'Install.ps1') -GameRoot $GameRoot -AzimuthRoot $AzimuthRoot)
$installed | ForEach-Object { Write-Host "$_" }
$backup = ($installed | Where-Object { "$_" -like 'Backup: *' } | Select-Object -First 1) -replace '^Backup: '
# remember what this layer imported (for later runs and for undoing it)
ConvertTo-Json -InputObject @($plan | ForEach-Object { [pscustomobject]@{ id = $_.id; car = $_.car; donor = $_.donor; soundCar = $_.soundCar; engine = $_.engine; group = $_.groupName; groupId = $_.group; lightDonor = $_.lightDonor; whiter = [bool]$_.whiter
  headlightStyle = $_.headlightStyle; presetFrom = $_.presetFrom; headlightColor = $_.headlightColor; graphFrom = $_.graphFrom } }) | Set-Content (Join-Path $backup 'cars.json') -Encoding UTF8

# night lights: fitted to the installed (converted) car models, so they go on as their own layer after the cars
$lit = @($plan | Where-Object { $_.lightDonor })
if ($lit.Count) {
  Write-Host "`nFitting night lights..."
  $la = @{ Car = @($lit | ForEach-Object car); Donor = @($lit | ForEach-Object lightDonor); GameRoot = $GameRoot; AzimuthRoot = $AzimuthRoot; Sqlite = $Sqlite; Name = "$Name-lights"
           PresetFrom = @($lit | ForEach-Object { if ($_.presetFrom) { $_.presetFrom } elseif ($_.whiter -and (Light-Info $_.lightDonor).Warm) { $whiterFrom } else { '' } })
           HeadlightStyle = @($lit | ForEach-Object { "$($_.headlightStyle)" }); HeadlightColor = @($lit | ForEach-Object { "$($_.headlightColor)" })
           GraphFrom = @($lit | ForEach-Object { "$($_.graphFrom)" }) }
  & (Join-Path $tools 'Add-CarLights.ps1') @la 6>&1 3>&1 | Where-Object { "$_" -match '(<- lights of|lights placed|^Installed|^Backup|preset PG_Function_Headlight)' -or $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { Write-Host "$_" }
}
Write-Host "`nDone. Start the game through azimuth.exe; the cars are in the Autoshow."
Write-Host "Each import (and its lights) is undone separately, newest first, with the Uninstall.ps1 in its backup folder."
