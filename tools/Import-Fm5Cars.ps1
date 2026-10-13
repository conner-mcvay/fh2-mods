<#
.SYNOPSIS
  Imports Forza Motorsport 5 cars into Forza Horizon 2 (PC / Azimuth) from your own FM5 and FH2 installs.

.DESCRIPTION
  Ships no game files: everything is read from your FM5 folder and your (stock) FH2 folder. For each car you name, it
  generates the database rows, converts the car's models for FH2's shaders, builds one combined install and installs it
  with backups (Install.ps1). Each FM5 car needs an FH2 donor car: it supplies FH2-only car data, the Autoshow group and,
  unless overridden, the engine sound - pick something similar (same era, layout, engine).

  Running it again replaces the previous import: it uninstalls the last one first (from its backup), so always pass the
  full list of cars you want. Requires FH2 1.0.0.64 on Azimuth 0.9.7 and FM5 1.0.0.20. sqlite3.exe is downloaded from
  sqlite.org (hash-checked) if it isn't on PATH.

.EXAMPLE
  .\tools\Import-Fm5Cars.ps1 -Fm5Root "D:\Forza_1.0.0.20_x64__8wekyb3d8bbwe" -GameRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe" `
      -AzimuthRoot "D:\azimuth" -Car PON_TransAm_02 -Donor PON_TransAmGTA_87 -EngineSound CHE_CorvetteZR1_95
.EXAMPLE
  .\tools\Import-Fm5Cars.ps1 ... -Car PON_TransAm_02,SHE_GT500_07 -Donor PON_TransAmGTA_87,FOR_MustangGT500_13
.EXAMPLE
  .\tools\Import-Fm5Cars.ps1 -ListFm5Only -Fm5Root ... -GameRoot ...    # FM5 cars FH2 doesn't have
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Fm5Root,    # FM5 folder containing Mount
  [Parameter(Mandatory)][string]$GameRoot,   # FH2 folder containing Mount (stock files, or this tool's previous import)
  [string]$AzimuthRoot,                      # folder containing azimuth.exe
  [string[]]$Car,                            # FM5 MediaNames or Ids
  [string[]]$Donor,                          # FH2 donor per car (MediaName or Id); omit for automatic (same make, nearest year)
  [string[]]$EngineSound,                    # optional FH2 engine sound per car (engine MediaName); default: the donor's
  [string]$Name = 'fm5-cars',                # install name (backups are mod-backups\<Name>-<time>)
  [string]$Sqlite = $env:FH2_SQLITE,
  [switch]$ListFm5Only,                      # just list the FM5 cars FH2 doesn't have
  [switch]$NoInstall                         # build only (output in build\<Name>)
)
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot; $root = Split-Path $tools
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

$fm5Media = Join-Path (Resolve-Path $Fm5Root).Path 'Mount\media'
if (-not (Test-Path (Join-Path $fm5Media 'db\gamedb.slt'))) { throw "Not an FM5 folder (no Mount\media\db\gamedb.slt): $Fm5Root" }
$GameRoot = (Resolve-Path $GameRoot).Path

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

if ($ListFm5Only) {
  $fh = Join-Path $GameRoot 'Mount\media\stripped\gamedbRC.slt'; $fm = Join-Path $fm5Media 'db\gamedb.slt'
  & $Sqlite -readonly -header -column ':memory:' "ATTACH 'file:$($fm.Replace('\','/'))?immutable=1' AS fm;" "ATTACH 'file:$($fh.Replace('\','/'))?immutable=1' AS fh;" `
    "SELECT c.Id, c.MediaName, c.Year FROM fm.Data_Car c WHERE c.Id NOT IN (SELECT Id FROM fh.Data_Car) AND c.MediaName NOT IN (SELECT MediaName FROM fh.Data_Car) ORDER BY c.MediaName;"
  return
}
if (-not $Car) { throw 'Pass -Car <FM5 car>[,<car>...] (see -ListFm5Only)' }
if (-not $AzimuthRoot -and -not $NoInstall) { throw 'Pass -AzimuthRoot <folder containing azimuth.exe>' }
if ($Donor -and $Donor.Count -ne $Car.Count) { throw '-Donor needs one entry per -Car' }
if ($EngineSound -and $EngineSound.Count -ne $Car.Count) { throw '-EngineSound needs one entry per -Car (use "" for the donor''s)' }

# --- undo this tool's previous import, so the build starts from stock files ---
if (-not $NoInstall) {
  $prev = Get-ChildItem (Join-Path $GameRoot 'mod-backups') -Directory -Filter "$Name-*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending |
    Where-Object { Test-Path (Join-Path $_.FullName 'restore.json') } |
    Where-Object { $r = Get-Content (Join-Path $_.FullName 'restore.json') -Raw | ConvertFrom-Json; -not ($r.files | Where-Object { $t = Join-Path $GameRoot "Mount\$($_.target)"; -not (Test-Path $t) -or (Sha $t) -ne $_.installed_sha256 }) } |
    Select-Object -First 1
  if ($prev) {
    Write-Host "Uninstalling previous import ($($prev.Name))"
    & (Join-Path $prev.FullName 'Uninstall.ps1') -BackupRoot $prev.FullName
    Rename-Item $prev.FullName ($prev.Name + '-uninstalled')
  }
}

# --- generate one mod per car in a private workspace ---
$ws = Join-Path $root "build\.import-$Name"
if (Test-Path $ws) { Remove-Item -Recurse -Force $ws }
New-Item -ItemType Directory $ws | Out-Null
$env:FH2_MODS_ROOT = $ws
try {
  $mods = @()
  for ($i = 0; $i -lt $Car.Count; $i++) {
    $mod = 'car' + ($i + 1) + '-' + ($Car[$i] -replace '[^\w-]', '').ToLower()
    $a = @{ Car = $Car[$i]; Mod = $mod; Fm5Media = $fm5Media; Game = $GameRoot; Sqlite = $Sqlite }
    if ($Donor -and $Donor[$i]) { $a.Donor = $Donor[$i] }
    if ($EngineSound -and $EngineSound[$i]) { $a.EngineSound = $EngineSound[$i] }
    # (the scripts report with Write-Host: filter the information stream to the useful lines)
    & (Join-Path $tools 'Export-Fm5Car.ps1') @a 6>&1 | Where-Object { "$_" -match '^(Exporting|Donor|  (thumb|bucket|sound|SOUND|BUCKET|CONFLICT|MISSING))' } | ForEach-Object { Write-Host "$_" }
    $mods += $mod
  }
  & (Join-Path $tools 'Build-Mod.ps1') -Mod $mods -Name $Name -Game $GameRoot -Fm5Media $fm5Media -Sqlite $Sqlite 6>&1 3>&1 |
    Where-Object { "$_" -match '^(MODELS|INDEX|Built|Wrote hash)' -or $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { Write-Host "$_" }
} finally { Remove-Item Env:FH2_MODS_ROOT }

$release = Join-Path $root "build\$Name"
if ($NoInstall) { Write-Host "Built $release (not installed)"; return }
& (Join-Path $release 'Install.ps1') -GameRoot $GameRoot -AzimuthRoot $AzimuthRoot
