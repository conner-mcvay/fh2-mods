<#
.SYNOPSIS
  Imports Forza Motorsport 5 cars into Forza Horizon 2 (PC / Azimuth) from your own FM5 and FH2 installs.

.DESCRIPTION
  Ships no game files: everything is read from your FM5 folder and your (stock) FH2 folder. For each car you pick, it
  generates the database rows, converts the car's models for FH2's shaders, builds one combined install and installs it
  with backups (Install.ps1).

  Run it with no parameters (or double-click Import-Fm5Cars.cmd) to be asked for everything: your folders (remembered),
  the FM5 cars to import (search by name), and per car an FH2 data donor (FH2-only car data and Autoshow group - pick
  something similar) and a sound donor (an FH2 car whose engine sound it uses).

  Each run replaces the previous import (it uninstalls it first), so the car list is always the full set you want;
  interactive mode offers to keep the cars already imported. Requires FH2 1.0.0.64 on Azimuth 0.9.7 and FM5 1.0.0.20.
  sqlite3.exe is downloaded from sqlite.org (hash-checked) if it isn't on PATH.

.EXAMPLE
  .\tools\Import-Fm5Cars.ps1
.EXAMPLE
  .\tools\Import-Fm5Cars.ps1 -Fm5Root "D:\Forza_1.0.0.20_x64__8wekyb3d8bbwe" -GameRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe" `
      -AzimuthRoot "D:\azimuth" -Car PON_TransAm_02,AST_DBS_09 -Donor PON_TransAmGTA_87,AST_DBSTF_08 -SoundCar CHE_CorvetteZR1_95,""
.EXAMPLE
  .\tools\Import-Fm5Cars.ps1 -ListFm5Only    # FM5 cars FH2 doesn't have
#>
[CmdletBinding()]
param(
  [string]$Fm5Root,                          # FM5 folder containing Mount
  [string]$GameRoot,                         # FH2 folder containing Mount (default: Azimuth's game_folder)
  [string]$AzimuthRoot,                      # folder containing azimuth.exe
  [string[]]$Car,                            # FM5 MediaNames or Ids (omit to be asked)
  [string[]]$Donor,                          # FH2 data donor per car (MediaName or Id); "" = automatic (same make, nearest year)
  [string[]]$SoundCar,                       # FH2 car per car whose engine sound to use; "" = the data donor's
  [string[]]$EngineSound,                    # or the FH2 engine MediaName directly
  [string]$Name = 'fm5-cars',                # install name (backups are mod-backups\<Name>-<time>)
  [string]$Sqlite = $env:FH2_SQLITE,
  [switch]$ListFm5Only,                      # just list the FM5 cars FH2 doesn't have
  [switch]$NoInstall                         # build only (output in build\<Name>)
)
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot; $root = Split-Path $tools
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
$interactive = -not $Car -and -not $ListFm5Only

# --- folders: parameters, then remembered values / Azimuth's own settings, then ask ---
$settingsPath = Join-Path $env:LOCALAPPDATA 'fh2-mods\import-fm5-cars.json'
$saved = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
function Ask([string]$prompt) { $a = Read-Host $prompt; if ($null -eq $a) { throw 'Input ended' }; $a.Trim() }
function Get-Folder([string]$label, [string]$value, [string]$default, [scriptblock]$valid, [string]$hint) {
  if ($value) { if (& $valid $value) { return (Resolve-Path $value).Path }; throw "$label isn't valid: $value ($hint)" }
  if (-not $interactive -and $default -and (& $valid $default)) { return $default }
  if (-not $interactive) { throw "Pass -$($label -replace ' ', '') ($hint)" }
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

if ($interactive) { Write-Host "`nFM5 -> FH2 car importer`n" -ForegroundColor Cyan }
if (-not $NoInstall -or $AzimuthRoot) { $AzimuthRoot = Get-Folder 'Azimuth folder' $AzimuthRoot $saved.AzimuthRoot $isAzimuth 'the folder containing azimuth.exe' }
$iniGame = $null
if ($AzimuthRoot -and (Test-Path "$AzimuthRoot\data\azimuth.ini")) {
  $m = [regex]::Match((Get-Content "$AzimuthRoot\data\azimuth.ini" -Raw), '(?m)^game_folder=(.+?)\s*$'); if ($m.Success) { $iniGame = $m.Groups[1].Value }
}
$GameRoot = Get-Folder 'FH2 game folder' $GameRoot $(if ($iniGame) { $iniGame } else { $saved.GameRoot }) $isFh2 'the folder containing Mount\forza_durango_release_final.exe'
$Fm5Root = Get-Folder 'FM5 game folder' $Fm5Root $saved.Fm5Root $isFm5 'the folder containing Mount\media\db\gamedb.slt'
New-Item -ItemType Directory (Split-Path $settingsPath) -Force | Out-Null
[pscustomobject]@{ AzimuthRoot = $AzimuthRoot; GameRoot = $GameRoot; Fm5Root = $Fm5Root } | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
$fm5Media = Join-Path $Fm5Root 'Mount\media'

# --- sqlite3: PATH, -Sqlite, tools\bin, or download the official build ---
if (-not $Sqlite) { $Sqlite = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Source }
if (-not $Sqlite -and (Test-Path "$tools\bin\sqlite3.exe")) { $Sqlite = "$tools\bin\sqlite3.exe" }
if (-not $Sqlite) {
  $url = 'https://www.sqlite.org/2024/sqlite-tools-win-x64-3470200.zip'; $zipSha = '8c7fffbf4eec1f43e63153cca6deb018e4360d4d6b0d99bbdd2a541c53b7fa1c'
  Write-Host "Downloading sqlite3 from $url"
  New-Item -ItemType Directory "$tools\bin" -Force | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile "$tools\bin\sqlite-tools.zip" -UseBasicParsing
  if ((Sha "$tools\bin\sqlite-tools.zip") -ne $zipSha) { Remove-Item "$tools\bin\sqlite-tools.zip"; throw 'sqlite download failed its hash check' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::OpenRead("$tools\bin\sqlite-tools.zip")
  try { [IO.Compression.ZipFileExtensions]::ExtractToFile(($z.Entries | Where-Object Name -eq 'sqlite3.exe'), "$tools\bin\sqlite3.exe", $true) } finally { $z.Dispose() }
  Remove-Item "$tools\bin\sqlite-tools.zip"; $Sqlite = "$tools\bin\sqlite3.exe"
}

# --- car lists. Cars this tool imported before don't count as FH2 cars (they're replaced on every run) ---
# this tool's previous import still in place? (its backup's restore.json matches the installed files)
$prev = Get-ChildItem (Join-Path $GameRoot 'mod-backups') -Directory -Filter "$Name-*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending |
  Where-Object { $_.Name -notlike '*-uninstalled' -and (Test-Path (Join-Path $_.FullName 'restore.json')) } |
  Where-Object { $r = Get-Content (Join-Path $_.FullName 'restore.json') -Raw | ConvertFrom-Json; -not ($r.files | Where-Object { $t = Join-Path $GameRoot "Mount\$($_.target)"; -not (Test-Path $t) -or (Sha $t) -ne $_.installed_sha256 }) } |
  Select-Object -First 1
$statePath = Join-Path $GameRoot "mod-backups\$Name-cars.json"
$state = @(if ($prev -and (Test-Path $statePath)) { Get-Content $statePath -Raw | ConvertFrom-Json | ForEach-Object { $_ } })
$importedIds = @($state | ForEach-Object { $_.id }) + -1
$fhDb = (Join-Path $GameRoot 'Mount\media\stripped\gamedbRC.slt').Replace('\', '/'); $fmDb = (Join-Path $fm5Media 'db\gamedb.slt').Replace('\', '/')
function Q([string]$sql) {   # rows as arrays of fields; no double quotes in $sql (PowerShell 5.1 native argument quirk)
  $out = & $Sqlite -bail -list -separator '|' ':memory:' "ATTACH 'file:$fmDb`?immutable=1' AS fm;" "ATTACH 'file:$fhDb`?immutable=1' AS fh;" $sql
  if ($LASTEXITCODE -ne 0) { throw "sqlite3 failed: $sql" }
  , @($out | ForEach-Object { , ($_.TrimEnd("`r").Split('|')) })   # always a list of rows, even for one row
}
$notImported = "Id NOT IN ($($importedIds -join ','))"
$fm5Only = Q "SELECT Id, MediaName, Year, MakeID FROM fm.Data_Car WHERE (Id NOT IN (SELECT Id FROM fh.Data_Car WHERE $notImported) AND MediaName NOT IN (SELECT MediaName FROM fh.Data_Car WHERE $notImported)) ORDER BY MediaName"
if ($ListFm5Only) { $fm5Only | ForEach-Object { '{0,5}  {1,-30} {2}' -f $_[0], $_[1], $_[2] }; return }
$fh2Cars = Q "SELECT Id, MediaName, Year, MakeID FROM fh.Data_Car WHERE $notImported ORDER BY MediaName"
function Engine-Of([string]$fh2Car) {   # stock engine sound (engine MediaName) of an FH2 car (MediaName or Id)
  $w = if ($fh2Car -match '^\d+$') { "c.Id = $fh2Car" } else { "c.MediaName = '$($fh2Car.Replace("'", ''))' COLLATE NOCASE" }
  $r = Q "SELECT e.MediaName FROM fh.Data_Car c JOIN fh.List_UpgradeEngine u ON u.Ordinal = c.Id JOIN fh.Data_Engine e ON e.EngineID = u.EngineID WHERE $w ORDER BY u.IsStock DESC, u.Level LIMIT 1"
  if (-not $r) { throw "FH2 has no car $fh2Car (or it has no engine)" }
  $r[0][0]
}

function Pick([object[]]$rows, [string]$prompt, [object]$default, [switch]$AllowDone) {
  # search by part of the name; a number picks from the last list shown; Enter takes the default (or finishes)
  $shown = @()
  while ($true) {
    $p = if ($default) { "$prompt [$($default[1])]" } elseif ($AllowDone) { "$prompt (Enter when done)" } else { $prompt }
    $a = Ask $p
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
    Write-Host "`nCurrently imported:"
    $state | ForEach-Object { Write-Host ("  {0,-26} data donor {1,-24} sound {2}" -f $_.car, $_.donor, $_.soundCar) }
    $keep = Ask 'Keep these in the import? [Y/n]'
    if ($keep -notmatch '^(n|no)$') { $plan += @($state | ForEach-Object { @{ id = $_.id; car = $_.car; donor = $_.donor; soundCar = $_.soundCar; engine = $_.engine } }) }
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
    $plan += @{ id = $c[0]; car = $c[1]; donor = $d[1]; soundCar = $s[1]; engine = (Engine-Of $s[1]) }
  }
  if (-not $plan.Count) { Write-Host 'Nothing to import.'; return }
  Write-Host "`nImport plan:" -ForegroundColor Cyan
  $plan | ForEach-Object { Write-Host ("  {0,-26} data donor {1,-24} sound {2} ({3})" -f $_.car, $_.donor, $_.soundCar, $_.engine) }
  if ((Ask "`nProceed? [Y/n]") -match '^(n|no)$') { Write-Host 'Cancelled.'; return }
} else {
  if ($Donor -and $Donor.Count -ne $Car.Count) { throw '-Donor needs one entry per -Car' }
  if ($SoundCar -and $SoundCar.Count -ne $Car.Count) { throw '-SoundCar needs one entry per -Car (use "" for the data donor''s)' }
  if ($EngineSound -and $EngineSound.Count -ne $Car.Count) { throw '-EngineSound needs one entry per -Car (use "" for the data donor''s)' }
  for ($i = 0; $i -lt $Car.Count; $i++) {
    $row = @($fm5Only | Where-Object { $_[1] -ieq $Car[$i] -or $_[0] -eq $Car[$i] })
    if (-not $row) { throw "FM5 car $($Car[$i]) not found, or FH2 already has it (see -ListFm5Only)" }
    $e = if ($EngineSound -and $EngineSound[$i]) { $EngineSound[$i] } elseif ($SoundCar -and $SoundCar[$i]) { Engine-Of $SoundCar[$i] } else { $null }
    $plan += @{ id = $row[0][0]; car = $row[0][1]; donor = $(if ($Donor) { $Donor[$i] } else { '' }); soundCar = $(if ($SoundCar) { $SoundCar[$i] } else { '' }); engine = $e }
  }
}
if (-not $AzimuthRoot -and -not $NoInstall) { throw 'Pass -AzimuthRoot <folder containing azimuth.exe>' }

# --- undo this tool's previous import, so the build starts from stock files ---
if (-not $NoInstall) {

  if ($prev) {
    Write-Host "`nUninstalling previous import ($($prev.Name))"
    & (Join-Path $prev.FullName 'Uninstall.ps1') -BackupRoot $prev.FullName
    Rename-Item $prev.FullName ($prev.Name + '-uninstalled')
    if (Test-Path $statePath) { Remove-Item $statePath }
  }
}

# --- generate one mod per car in a private workspace, build one combined install ---
$ws = Join-Path $root "build\.import-$Name"
if (Test-Path $ws) { Remove-Item -Recurse -Force $ws }
New-Item -ItemType Directory $ws | Out-Null
$env:FH2_MODS_ROOT = $ws
try {
  $mods = @()
  for ($i = 0; $i -lt $plan.Count; $i++) {
    $p = $plan[$i]
    $mod = 'car' + ($i + 1) + '-' + ($p.car -replace '[^\w-]', '').ToLower()
    $a = @{ Car = $p.car; Mod = $mod; Fm5Media = $fm5Media; Game = $GameRoot; Sqlite = $Sqlite }
    if ($p.donor) { $a.Donor = $p.donor }
    if ($p.engine) { $a.EngineSound = $p.engine }
    Write-Host ''
    # (the scripts report with Write-Host: filter the information stream to the useful lines)
    & (Join-Path $tools 'Export-Fm5Car.ps1') @a 6>&1 | Where-Object { "$_" -match '^(Exporting|Donor|  (thumb|bucket|sound|SOUND|BUCKET|CONFLICT|MISSING))' } | ForEach-Object { Write-Host "$_" }
    $mods += $mod
  }
  Write-Host "`nBuilding (converting models for FH2 takes a minute per car)..."
  & (Join-Path $tools 'Build-Mod.ps1') -Mod $mods -Name $Name -Game $GameRoot -Fm5Media $fm5Media -Sqlite $Sqlite 6>&1 3>&1 |
    Where-Object { "$_" -match '^(MODELS|Built)' -or $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { Write-Host "$_" }
} finally { Remove-Item Env:FH2_MODS_ROOT }

$release = Join-Path $root "build\$Name"
if ($NoInstall) { Write-Host "Built $release (not installed)"; return }
Write-Host ''
& (Join-Path $release 'Install.ps1') -GameRoot $GameRoot -AzimuthRoot $AzimuthRoot
# remember what's imported (for the next run's "keep these?")
ConvertTo-Json -InputObject @($plan | ForEach-Object { [pscustomobject]@{ id = $_.id; car = $_.car; donor = $_.donor; soundCar = $_.soundCar; engine = $_.engine } }) | Set-Content $statePath -Encoding UTF8
Write-Host "`nDone. Start the game through azimuth.exe; the cars are in the Autoshow."
