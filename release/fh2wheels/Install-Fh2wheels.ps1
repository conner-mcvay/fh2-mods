<#
.SYNOPSIS
  Installs fh2wheels into Forza Horizon 2 on Azimuth (or removes it with -Uninstall). Close the game first.
.DESCRIPTION
  Two halves:
  - the game database part (mods\fh2wheels): built on the game's own database as it is now, imported cars
    included (tools\build\Build-Mod.ps1 -Layer), then installed into Mount\mediapc with backups (or Mount\mediaoverride,
    which the game reads first: -MediaFolder, or offered when another mod's game database or physics settings are there)
    (tools\release\Install.ps1; needs FH2 Extra Options, whose EnableMediaOverrides it turns on);
  - fh2wheels.dll, put in Azimuth's data\bin\azimuth-tls.dll chain (tools\wheels\Install.ps1).
  Running it again (an update, or after importing more cars) takes the previous database part out first; when another
  mod went in after it (so it can't come out without undoing that one), the new one goes on top instead, which
  adds the options for cars that came since. sqlite3.exe is downloaded from sqlite.org (hash-checked) when it isn't
  on PATH or in tools\bin.
  Without -AzimuthRoot / -GameRoot it asks for each folder separately, asking again until it's right; for the game
  folder it shows the one Azimuth is set to run (data\azimuth.ini), which Enter takes. A game folder other than
  that one is only used after a warning (the game wouldn't see the mod there), and the two are confirmed before
  anything changes.
.EXAMPLE
  .\Install-Fh2wheels.ps1 -AzimuthRoot C:\Games\azimuth -GameRoot C:\Games\Anthem_1.0.0.64_x64__8wekyb3d8bbwe
.EXAMPLE
  .\Install-Fh2wheels.ps1 -AzimuthRoot C:\Games\azimuth -Uninstall
#>
param([string]$AzimuthRoot, [string]$GameRoot, [string]$Sqlite = $env:FH2_SQLITE, [switch]$Uninstall,
  [ValidateSet('', 'mediapc', 'mediaoverride')][string]$MediaFolder)   # where the database part goes (see above)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Clean([string]$p) { if ($p) { $p.Trim().Trim('"').TrimEnd('\') } else { '' } }
function Has([string]$dir, [string]$file) { try { $dir -and (Test-Path -LiteralPath (Join-Path $dir $file) -PathType Leaf) } catch { $false } }
$isAzimuth = { param($p) Has $p 'azimuth.exe' }
$isGame = { param($p) Has $p 'Mount\forza_durango_release_final.exe' }
$azGame = ''

# Everything shown goes to fh2wheels-install.log beside this script (or in %TEMP% when this folder isn't writable),
# with a report of the setup before and after, so a failed install can be sent along as one file.
$log = Join-Path $here 'fh2wheels-install.log'
try { [IO.File]::AppendAllText($log, '') } catch { $log = Join-Path $env:TEMP 'fh2wheels-install.log' }
try { Start-Transcript -LiteralPath $log -Append -Force | Out-Null } catch { $log = $null }   # every run kept, newest last
$version = if (Test-Path -LiteralPath (Join-Path $here 'VERSION.txt')) { (Get-Content -LiteralPath (Join-Path $here 'VERSION.txt') -TotalCount 1) } else { 'fh2wheels (version unknown)' }
Write-Host "$version installer, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Windows $([Environment]::OSVersion.Version), PowerShell $($PSVersionTable.PSVersion)"
Write-Host "Running from: $here"
function Show-State([string]$when) {
  Write-Host "`n--- setup $when ---"
  try {
    $dllName = { param($p) if (-not (Test-Path -LiteralPath $p)) { return '-' }
      $x = [IO.File]::ReadAllText($p, [Text.Encoding]::ASCII)
      if ($x.Contains('fh2wheels loaded')) { 'fh2wheels' } elseif ($x.Contains('fh2net probe loaded')) { 'fh2net' } elseif ($x.Contains('game:\mediapc\')) { 'Extra Options' } else { "other ($((Get-Item -LiteralPath $p).Length) bytes)" } }
    if ($AzimuthRoot -and (& $isAzimuth $AzimuthRoot)) {
      Write-Host "Azimuth: $AzimuthRoot (azimuth.exe $((Get-Item -LiteralPath (Join-Path $AzimuthRoot 'azimuth.exe')).VersionInfo.FileVersion))"
      Write-Host "  runs the game in: $(if ($azGame) { $azGame } else { '(not set in data\azimuth.ini)' })"
      $eo = Join-Path $AzimuthRoot 'winmm.dll'; $eoIni = Join-Path $AzimuthRoot 'FH2_ExtraOptions.ini'
      $overrides = (Test-Path -LiteralPath $eoIni) -and [regex]::IsMatch([IO.File]::ReadAllText($eoIni), '(?ms)^\s*\[Files\][^\[]*?^\s*EnableMediaOverrides\s*=\s*1\s*$')
      Write-Host "  winmm.dll: $(& $dllName $eo); FH2_ExtraOptions.ini EnableMediaOverrides=1: $overrides"
      foreach ($f in 'azimuth-tls.dll', 'azimuth-tls-next.dll', 'fh2wheels-next.dll') { Write-Host ("  data\bin\{0}: {1}" -f $f, (& $dllName (Join-Path $AzimuthRoot "data\bin\$f"))) }
      $rt = Join-Path $AzimuthRoot 'data\bin\fh2wheels.log'
      if (Test-Path -LiteralPath $rt) {
        Write-Host "  data\bin\fh2wheels.log ($((Get-Item -LiteralPath $rt).LastWriteTime)):"
        $lines = @(Get-Content -LiteralPath $rt | Where-Object { $_ -notmatch '^(sql|,|\[|\))' })
        $lines | Select-Object -First 4 | ForEach-Object { Write-Host "    $_" }
        Write-Host "    ... $(@($lines -match 'applied at').Count) patches applied"
        $lines -match 'game database'| Select-Object -First 1 | ForEach-Object { Write-Host "    $_" }
        $lines -match 'not applied|not found|can''t|isn''t|not where expected|no game folder|no save|PROBLEM' | Select-Object -First 10 | ForEach-Object { Write-Host "    PROBLEM: $($_ -replace 'PROBLEM: ', '')" }
      } else { Write-Host '  data\bin\fh2wheels.log: none (fh2wheels has not run from this Azimuth folder)' }
    }
    if ($GameRoot -and (& $isGame $GameRoot)) {
      Write-Host "Game: $GameRoot"
      $reads = $null   # the game reads the first of these that exists
      foreach ($d in 'mediaoverride', 'mediapc') {
        $db = Join-Path $GameRoot "Mount\$d\stripped\gamedbRC.slt"
        if (-not (Test-Path -LiteralPath $db)) { Write-Host "  Mount\$d\stripped\gamedbRC.slt: none"; continue }
        $has = if ($Sqlite -and (Test-Path -LiteralPath $Sqlite)) { if ((& $Sqlite -readonly $db "SELECT COUNT(*) FROM sqlite_master WHERE name = 'Fh2wheels'") -eq '1') { 'with fh2wheels' } else { 'WITHOUT fh2wheels' } } else { '(not checked: no sqlite3 yet)' }
        Write-Host "  Mount\$d\stripped\gamedbRC.slt: $has$(if (-not $reads) { ' <- the one the game reads' })"
        if (-not $reads) { $reads = $d }
      }
      if (-not $reads) { Write-Host '  the game reads its own database (no database mod installed)' }
      if (Test-Path -LiteralPath (Join-Path $GameRoot 'Mount\mediaoverride')) {
        Write-Host "  Mount\mediaoverride: $(@(Get-ChildItem -LiteralPath (Join-Path $GameRoot 'Mount\mediaoverride') -Recurse -File -ErrorAction SilentlyContinue).Count) files"
      }
      $bk = @(Get-ChildItem -LiteralPath (Join-Path $GameRoot 'mod-backups') -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime | Select-Object -Last 6 |
        ForEach-Object { "$($_.Name)$(if (Test-Path -LiteralPath (Join-Path $_.FullName 'uninstalled.txt')) { ' (uninstalled)' })" })
      if ($bk) { Write-Host "  latest mod backups: $($bk -join ', ')" }
    }
  } catch { Write-Host "  (report failed: $($_.Exception.Message))" }
  Write-Host '---'
}
trap {
  Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host $_.InvocationInfo.PositionMessage
  Show-State 'at the failure'
  if ($log) { Stop-Transcript | Out-Null; Write-Host "`nLog: $log (send this file along when reporting a problem)" -ForegroundColor Yellow }
  break
}
if (-not (Test-Path -LiteralPath (Join-Path $here 'tools\build\Build-Mod.ps1')) -or -not (Test-Path -LiteralPath (Join-Path $here 'fh2wheels.dll'))) {
  throw "The installer's files aren't all here ($here). Extract the whole zip to a folder first (right-click > Extract All), then run Install-Fh2wheels.cmd from that folder."
}

# asks until the answer passes $test; Enter takes $default when there is one
function Ask([string]$prompt, [string]$default, [scriptblock]$test, [string]$bad) {
  while ($true) {
    $q = if ($default) { "$prompt`n  [Enter for $default]" } else { $prompt }
    $a = Clean (Read-Host $q)
    if (-not $a) { $a = $default }
    if (& $test $a) { return $a }
    Write-Host "  $bad" -ForegroundColor Yellow
  }
}
$asked = $false

# --- the Azimuth folder ---
$AzimuthRoot = Clean $AzimuthRoot
if (-not $AzimuthRoot) {
  $AzimuthRoot = Ask 'Azimuth folder (the one with azimuth.exe)' '' $isAzimuth 'No azimuth.exe there; enter the folder azimuth.exe is in.'
  $asked = $true
} elseif (-not (& $isAzimuth $AzimuthRoot)) { throw "No azimuth.exe in $AzimuthRoot" }
if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($AzimuthRoot + '\', [StringComparison]::OrdinalIgnoreCase) }) { throw 'Close Azimuth first.' }

# --- the game folder: asked separately; the one this Azimuth runs ([title-1a96545b] folder= in data\azimuth.ini) is shown ---
$azGame = ''
$ini = Join-Path $AzimuthRoot 'data\azimuth.ini'
if (Test-Path -LiteralPath $ini) {
  $section = ''
  foreach ($line in Get-Content -LiteralPath $ini) {
    if ($line -match '^\s*\[(.+)\]') { $section = $Matches[1] }
    elseif ($section -eq 'title-1a96545b' -and $line -match '^\s*folder\s*=\s*(.+?)\s*$') { $azGame = Clean $Matches[1] }
  }
}
# Azimuth can keep it relative to its own folder, e.g. "(Forza Horizon 2) Anthem_1.0.0.64_x64__8wekyb3d8bbwe\Anthem_..."
if ($azGame -and -not [IO.Path]::IsPathRooted($azGame)) {
  try { $azGame = [IO.Path]::GetFullPath((Join-Path $AzimuthRoot $azGame)).TrimEnd('\') } catch { }
}
$GameRoot = Clean $GameRoot
if (-not $GameRoot) {
  if ($azGame) { Write-Host "This Azimuth is set to run the game in: $azGame" }
  $GameRoot = Ask 'Game folder (the one with the Mount folder in it)' $(if (& $isGame $azGame) { $azGame } else { '' }) $isGame 'No Mount\forza_durango_release_final.exe there; enter the folder that contains Mount.'
  $asked = $true
} elseif (-not (& $isGame $GameRoot)) { throw "No Mount\forza_durango_release_final.exe in $GameRoot" }

try { $GameRoot = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\'); $AzimuthRoot = [IO.Path]::GetFullPath($AzimuthRoot).TrimEnd('\') } catch { }
# the game only sees the mod, and fh2wheels.dll only finds the rims, in the folder Azimuth runs
if (-not $azGame -or -not $GameRoot.Equals($azGame, [StringComparison]::OrdinalIgnoreCase)) {
  $runs = if ($azGame) { $azGame } else { '(not set)' }
  Write-Warning ("This Azimuth runs the game in '$runs', not '$GameRoot'. The game won't see fh2wheels' database part there, " +
    "and rear rims won't work. Pick that game folder in Azimuth first, or enter the folder it runs.")
  if ($asked -and (Read-Host 'Install there anyway? (y/N)') -notmatch '^y') { throw 'Stopped; nothing was changed.' }
}
# --- where the database part goes: Mount\mediapc, or Mount\mediaoverride, which the game reads first. When another mod
# (e.g. a backport of newer Forza titles) puts its own game database or physics settings in mediaoverride, those
# hide anything in mediapc, so fh2wheels has to go into mediaoverride, built on top of that mod's files ---
if (-not $Uninstall -and -not $MediaFolder) {
  $ovr = Join-Path $GameRoot 'Mount\mediaoverride'
  $shadows = @('stripped\gamedbRC.slt', 'physics\PhysicsSettings.ini' | Where-Object { Test-Path -LiteralPath (Join-Path $ovr $_) })
  $MediaFolder = if ($shadows) { 'mediaoverride' } else { 'mediapc' }
  if ($asked -and (Test-Path -LiteralPath $ovr)) {
    Write-Host "`nAnother mod has files in Mount\mediaoverride, which the game reads before Mount\mediapc (where mods usually go)."
    if ($shadows) { Write-Host "It has its own $($shadows -join ' and '), which would hide fh2wheels' in Mount\mediapc, so fh2wheels should go into Mount\mediaoverride, on top of that mod's (its files are backed up and come back on uninstall)." }
    else { Write-Host 'It has no game database or physics settings there, so Mount\mediapc works.' }
    $a = Read-Host "Install into Mount\mediaoverride instead of Mount\mediapc? ($(if ($shadows) { 'Y/n' } else { 'y/N' }))"
    if ($a -match '^y') { $MediaFolder = 'mediaoverride' } elseif ($a -match '^n') { $MediaFolder = 'mediapc' }
  }
}
Write-Host "`nAzimuth: $AzimuthRoot`nGame:    $GameRoot$(if (-not $Uninstall) { "`nInto:    Mount\$MediaFolder" })"
if ($asked -and (Read-Host "$(if ($Uninstall) { 'Uninstall' } else { 'Install' }) fh2wheels here? (Y/n)") -match '^n') { throw 'Stopped; nothing was changed.' }
if (-not $Sqlite -and (Test-Path (Join-Path $here 'tools\bin\sqlite3.exe'))) { $Sqlite = Join-Path $here 'tools\bin\sqlite3.exe' }
Show-State 'before'
function Finish([string]$msg) {
  Show-State 'after'
  Write-Host "`n$msg"
  if ($log) { Stop-Transcript | Out-Null; Write-Host "Log: $log" }
}

# the database parts installed earlier, newest first, not yet uninstalled
$backups = @(Get-ChildItem -LiteralPath (Join-Path $GameRoot 'mod-backups') -Directory -Filter 'fh2wheels-*' -ErrorAction SilentlyContinue |
  Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'restore.json')) -and -not (Test-Path -LiteralPath (Join-Path $_.FullName 'uninstalled.txt')) } |
  Sort-Object Name -Descending)
$uninstallDb = Join-Path $here 'tools\release\Uninstall.ps1'
$wheelsDll = Join-Path $here 'tools\wheels\Install.ps1'

if ($Uninstall) {
  foreach ($b in $backups) {
    try { & $uninstallDb -BackupRoot $b.FullName }
    catch { Write-Warning "Left the database part in $($b.Name): $($_.Exception.Message)"; break }
  }
  try { & $wheelsDll -Azimuth $AzimuthRoot -Uninstall } catch { Write-Warning $_.Exception.Message }
  Finish 'fh2wheels removed.'
  return
}

# --- sqlite3: -Sqlite, PATH, tools\bin, or download the official build ---
$bin = Join-Path $here 'tools\bin'
if (-not $Sqlite) { $Sqlite = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Source }
if (-not $Sqlite -and (Test-Path (Join-Path $bin 'sqlite3.exe'))) { $Sqlite = Join-Path $bin 'sqlite3.exe' }
if (-not $Sqlite) {
  $url = 'https://www.sqlite.org/2024/sqlite-tools-win-x64-3470200.zip'; $zipSha = '8c7fffbf4eec1f43e63153cca6deb018e4360d4d6b0d99bbdd2a541c53b7fa1c'
  Write-Host "Downloading sqlite3 from $url"
  New-Item -ItemType Directory $bin -Force | Out-Null
  $zip = Join-Path $bin 'sqlite-tools.zip'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  if ((Sha $zip) -ne $zipSha) { Remove-Item $zip; throw 'sqlite download failed its hash check' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::OpenRead($zip)
  try { [IO.Compression.ZipFileExtensions]::ExtractToFile(($z.Entries | Where-Object Name -eq 'sqlite3.exe'), (Join-Path $bin 'sqlite3.exe'), $true) } finally { $z.Dispose() }
  Remove-Item $zip; $Sqlite = Join-Path $bin 'sqlite3.exe'
}

# --- the database part: the previous one out (when nothing went in after it), then built on what's there now ---
if ($backups) {
  try { & $uninstallDb -BackupRoot $backups[0].FullName; Write-Host "Took out the previous fh2wheels database part ($($backups[0].Name))." }
  catch { Write-Host "The previous fh2wheels database part stays (another mod went in after it); the new one goes on top." }
}
& (Join-Path $here 'tools\build\Build-Mod.ps1') -Mod fh2wheels -Game $GameRoot -Layer -MediaFolder $MediaFolder -Sqlite $Sqlite
& (Join-Path $here 'build\fh2wheels\Install.ps1') -GameRoot $GameRoot -AzimuthRoot $AzimuthRoot

# --- the DLL ---
& $wheelsDll -Azimuth $AzimuthRoot -Dll (Join-Path $here 'fh2wheels.dll')
Finish ("fh2wheels installed. Start the game from $AzimuthRoot and look under Upgrades > Tires & Rims.`n" +
  "If the options are missing, or their text is blank: data\bin\fh2wheels.log in that folder shows whether fh2wheels ran.")
