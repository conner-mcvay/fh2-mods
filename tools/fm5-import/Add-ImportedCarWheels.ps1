<#
.SYNOPSIS
  Puts the stock wheels of FM5 cars already imported into FH2 in the wheel shop, for any car.

.DESCRIPTION
  Import-Fm5Cars does this for every car it imports. This is for cars imported before that (or by hand): it finds
  the imported cars in the game (FM5 cars stock FH2 doesn't have, per tools\build\stock-cars.txt) whose wheel isn't in the shop
  yet, makes a wheel zip for each from FM5's car zip (converted for FH2's shaders), names, prices and files it in
  the wheel shop, and installs it as one more layer (undo with the Uninstall.ps1 in its backup folder). Extra Options'
  stock rims cover FH2's own cars only; this is what puts imported cars' wheels on the list.
  Folders default to the ones Import-Fm5Cars remembered.

.EXAMPLE
  .\tools\fm5-import\Add-ImportedCarWheels.ps1
.EXAMPLE
  .\tools\fm5-import\Add-ImportedCarWheels.ps1 -Car CHE_CorvetteZ06_02 -NoInstall
#>
[CmdletBinding()]
param(
  [string]$GameRoot, [string]$AzimuthRoot, [string]$Fm5Root,
  [string[]]$Car,                          # FH2 MediaNames; default: every imported car whose wheel isn't in the shop
  [string]$Name = 'fm5-wheels',
  [string]$Sqlite = $env:FH2_SQLITE,
  [switch]$NoInstall
)
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot; $root = Split-Path (Split-Path $tools); $bin = Join-Path (Split-Path $tools) 'bin'   # tools\fm5-import
. (Join-Path $tools 'WheelSwap.ps1')
$settingsPath = Join-Path $env:LOCALAPPDATA 'fh2-mods\import-fm5-cars.json'
$saved = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $GameRoot) { $GameRoot = $saved.GameRoot }; if (-not $AzimuthRoot) { $AzimuthRoot = $saved.AzimuthRoot }; if (-not $Fm5Root) { $Fm5Root = $saved.Fm5Root }
foreach ($p in 'GameRoot', 'Fm5Root') { if (-not (Get-Variable $p -ValueOnly)) { throw "Pass -$p (or run Import-Fm5Cars once so it's remembered)" } }
if (-not $NoInstall -and -not $AzimuthRoot) { throw 'Pass -AzimuthRoot' }
if (-not $Sqlite) { $Sqlite = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Source }
if (-not $Sqlite -and (Test-Path "$bin\sqlite3.exe")) { $Sqlite = "$bin\sqlite3.exe" }
if (-not $Sqlite) { throw 'Need sqlite3.exe: pass -Sqlite, put it on PATH, or run Import-Fm5Cars once (it downloads one)' }
$fm5Media = Join-Path $Fm5Root 'Mount\media'
. (Join-Path $tools '..\build\StockSource.ps1')   # Get-GameMediaFile: what the game reads (Mount\mediapc first)
$fhDb = (Get-GameMediaFile $GameRoot 'stripped\gamedbRC.slt').FullName.Replace('\', '/'); $fmDb = (Join-Path $fm5Media 'db\gamedb.slt').Replace('\', '/')
function Q([string]$sql) {   # rows as arrays of fields; no double quotes in $sql
  $out = & $Sqlite -bail -list -separator '|' ':memory:' "ATTACH 'file:$fmDb`?immutable=1' AS fm;" "ATTACH 'file:$fhDb`?immutable=1' AS fh;" $sql
  if ($LASTEXITCODE -ne 0) { throw "sqlite3 failed: $sql" }
  , @($out | ForEach-Object { , ($_.TrimEnd("`r").Split('|')) })
}

# imported cars (FM5 has them, stock FH2 doesn't: tools\build\stock-cars.txt) whose stock wheel isn't in the shop
$stock = @{}; Get-Content (Join-Path $tools '..\build\stock-cars.txt') | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $stock[$_.ToLower()] = 1 }
$rows = Q "SELECT c.Id, c.MediaName, c.Year, w.MediaName, f.DisplayName FROM fh.Data_Car c JOIN fh.List_Wheels w ON w.ID = c.StockWheelID JOIN fm.Data_Car f ON f.MediaName = c.MediaName COLLATE NOCASE WHERE w.IsStock = 1 ORDER BY c.MediaName"
$cars = @($rows | Where-Object {
  if ($Car) { $Car -contains $_[1] } else { -not $stock.ContainsKey($_[1].ToLower()) -and (Get-GameMediaFile $GameRoot "cars\$($_[1]).zip") }
})
if ($Car) { foreach ($c in $Car) { if (-not ($cars | Where-Object { $_[1] -ieq $c })) { throw "$c isn't in the game, isn't an FM5 car, or its wheel is already in the shop" } } }
if (-not $cars.Count) { Write-Host 'No imported cars with wheels missing from the wheel shop.'; return }

$strings = Read-StringTable (Join-Path $fm5Media 'stringtables\EN.zip') 'Data_Car.str'
$ws = Join-Path $root "build\.wheels-$Name"; if (Test-Path $ws) { Remove-Item -Recurse -Force $ws }
$modDir = Join-Path $ws 'imported-car-wheels'; $sqlDir = Join-Path $modDir 'media\stripped\gamedbRC.slt'
New-Item -ItemType Directory $sqlDir -Force | Out-Null
$sql = @(); $imports = @()
foreach ($r in $cars) {
  $id, $media, $year, $wheel, $dn = $r
  $za = [IO.Compression.ZipFile]::OpenRead((Join-Path $fm5Media "cars\$media.zip"))
  try { $we = Find-CarWheelEntries $za $wheel } finally { $za.Dispose() }
  if (-not $we) { Write-Warning "$media`: no wheel model in FM5's cars\$media.zip; skipped"; continue }
  $label = "$year $(Resolve-String $strings $dn)".Trim()
  $p = New-WheelSwapParts -Car $media -Wheel $wheel -Name $label -CarZip "cars\$media.zip" -SourcePrefix '' -Entries $we
  $sql += $p.Sql; $imports += $p.Imports
  Write-Host ("  {0,-30} wheel {1} -> '{2}'" -f $media, $wheel, $label)
}
[IO.File]::WriteAllText((Join-Path $sqlDir 'imported-car-wheels.sql'), ($sql -join "`r`n"))
Set-Content (Join-Path $modDir 'imports.txt') $imports -Encoding ASCII

$env:FH2_MODS_ROOT = $ws
try {
  & (Join-Path $tools '..\build\Build-Mod.ps1') -Mod 'imported-car-wheels' -Name $Name -Game $GameRoot -Layer -Fm5Media $fm5Media -Sqlite $Sqlite 6>&1 3>&1 |
    Where-Object { "$_" -match '^(MODELS|Built)' -or $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { Write-Host "$_" }
} finally { Remove-Item Env:FH2_MODS_ROOT }
$release = Join-Path $root "build\$Name"
if ($NoInstall) { Write-Host "Built $release (not installed)"; return }
& (Join-Path $release 'Install.ps1') -GameRoot $GameRoot -AzimuthRoot $AzimuthRoot
