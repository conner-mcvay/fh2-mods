<#
.SYNOPSIS
  Installs this mod into a Forza Horizon 2 (PC / Azimuth) game folder, with backups.

.DESCRIPTION
  Reads install.json next to this script. The mod's files go into Mount\mediapc, Extra Options' override folder:
  the game reads it before Mount\media and doesn't filter it by Mount\hash.manifest, so the game's own files and
  azimuth.exe stay untouched. Needs FH2 Extra Options (winmm.dll beside azimuth.exe for Azimuth 0.9.10, or 0.2.74+
  in data\bin for 0.9.9); turns its [Files] EnableMediaOverrides on if it's off.

  Checks the game version, refuses to overwrite files another mod already put in Mount\mediapc (unless -Force; a
  layered package expects exactly the files it was built on), backs up every file it replaces, and copies the
  mod's files in. Prints the backup folder; pass it to Uninstall.ps1 to undo (with several mods installed, newest
  first).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -GameRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe" -AzimuthRoot "D:\azimuth"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$GameRoot,      # folder containing Mount
  [Parameter(Mandatory)][string]$AzimuthRoot,   # folder containing azimuth.exe
  [switch]$Force                                # overwrite files another mod put in Mount\mediapc
)
$ErrorActionPreference = 'Stop'
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
# writes a new file and swaps it in, so a target that is a hard link (e.g. a test copy of a game folder) is
# replaced rather than written through to the file it shares data with
function Set-File([string]$src, [string]$dst) { $tmp = "$dst.fh2-new"; Copy-Item -LiteralPath $src -Destination $tmp -Force; Move-Item -LiteralPath $tmp -Destination $dst -Force }

$pkg = $PSScriptRoot
$m = Get-Content -LiteralPath (Join-Path $pkg 'install.json') -Raw | ConvertFrom-Json
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path; $AzimuthRoot = (Resolve-Path -LiteralPath $AzimuthRoot).Path
$mount = Join-Path $GameRoot 'Mount'
$exe = Join-Path $mount 'forza_durango_release_final.exe'
if (-not (Test-Path -LiteralPath $exe) -or (Sha $exe) -ne $m.game_exe_sha256) { throw "Unsupported game: needs FH2 $($m.game_version) (Mount\forza_durango_release_final.exe SHA-256 $($m.game_exe_sha256))" }
if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($AzimuthRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }) { throw 'Close Azimuth first.' }
if ($m.install_folder -ne 'mediapc') { throw 'This package was made for an older installer (it patches azimuth.exe); build it again with the current fh2-mods tools.' }

# Extra Options with the override folders, its ini beside its DLL: for Azimuth 0.9.10+ winmm.dll beside azimuth.exe;
# for 0.9.9 (0.2.74+) data\bin\azimuth-tls.dll, or azimuth-tls-next.dll when another DLL (e.g. fh2net) sits in front
$bin = Join-Path $AzimuthRoot 'data\bin'
$eo = @((Join-Path $AzimuthRoot 'winmm.dll'), (Join-Path $bin 'azimuth-tls.dll'), (Join-Path $bin 'azimuth-tls-next.dll') | Where-Object {
  (Test-Path -LiteralPath $_) -and [IO.File]::ReadAllText($_, [Text.Encoding]::ASCII).Contains('game:\mediapc\')
})
if (-not $eo) { throw "Needs FH2 Extra Options in $AzimuthRoot (winmm.dll for Azimuth 0.9.10, or 0.2.74+ in data\bin for 0.9.9): it makes the game read mods from Mount\mediapc." }
$ini = Join-Path (Split-Path $eo[0]) 'FH2_ExtraOptions.ini'
$iniText = if (Test-Path -LiteralPath $ini) { [IO.File]::ReadAllText($ini) } else { '' }
$iniOn = [regex]::IsMatch($iniText, '(?ms)^\s*\[Files\][^\[]*?^\s*EnableMediaOverrides\s*=\s*1\s*$')

# payload integrity
foreach ($f in $m.files) { if ((Sha (Join-Path $pkg $f.source)) -ne $f.sha256) { throw "Corrupt package file: $($f.source)" } }

# targets must hold what the package was built on: nothing for a new file, or for a layered build the files
# earlier mods installed then (unless -Force)
$conflicts = @()
foreach ($f in $m.files) {
  if ($f.target -notmatch '^mediapc\\' -or $f.target -match '(^|\\)\.\.(\\|$)') { throw "Bad target in install.json: $($f.target)" }
  $t = Join-Path $mount $f.target
  if ($f.base_sha256) { if (-not (Test-Path -LiteralPath $t) -or (Sha $t) -ne $f.base_sha256) { $conflicts += $f.target } }
  elseif (Test-Path -LiteralPath $t) { $conflicts += $f.target }
}
if ($conflicts.Count -and -not $Force) {
  if ($m.layered) { throw ("These files changed since this package was built on top of them (installing would undo that):`n  " + ($conflicts -join "`n  ") + "`nBuild it again, or pass -Force.") }
  throw ("Another mod already put these files in Mount\mediapc (installing would undo it):`n  " + ($conflicts -join "`n  ") + "`nUninstall that mod first, build the mods together from the fh2-mods repo, or pass -Force.")
}

# back up, then install
$backup = Join-Path $GameRoot ("mod-backups\" + $m.name + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$record = @()
try {
  foreach ($f in $m.files) {
    $t = Join-Path $mount $f.target; $existed = Test-Path -LiteralPath $t; $saved = $null
    if ($existed) { $saved = Join-Path $backup ('files\' + $f.target); New-Item -ItemType Directory -Path (Split-Path $saved) -Force | Out-Null; Copy-Item -LiteralPath $t -Destination $saved }
    $record += [pscustomobject]@{ target = $f.target; existed = $existed; backup_sha256 = $(if ($existed) { Sha $saved } else { $null }); installed_sha256 = $f.sha256 }
    New-Item -ItemType Directory -Path (Split-Path $t) -Force | Out-Null
    Set-File (Join-Path $pkg $f.source) $t
    if ((Sha $t) -ne $f.sha256) { throw "Install verification failed: $($f.target)" }
  }
  if (-not $iniOn) {   # Extra Options reads the override folders only with [Files] EnableMediaOverrides=1
    if (Test-Path -LiteralPath $ini) { Copy-Item -LiteralPath $ini -Destination (Join-Path $backup 'FH2_ExtraOptions.ini') }
    if ([regex]::IsMatch($iniText, '(?m)^\s*EnableMediaOverrides\s*=')) { $iniText = [regex]::Replace($iniText, '(?m)^(\s*EnableMediaOverrides\s*=\s*)\S*', '${1}1') }
    elseif ([regex]::IsMatch($iniText, '(?m)^\s*\[Files\]')) { $iniText = [regex]::Replace($iniText, '(?m)^(\s*\[Files\][^\r\n]*\r?\n)', "`${1}EnableMediaOverrides=1`r`n") }
    else { $iniText = $iniText.TrimEnd() + "`r`n`r`n[Files]`r`n; Mount\mediaoverride and Mount\mediapc override game:\media (mods install into mediapc)`r`nEnableMediaOverrides=1`r`n" }
    [IO.File]::WriteAllText($ini, $iniText, (New-Object Text.UTF8Encoding $false))
    Write-Host "Turned on Extra Options' EnableMediaOverrides ($ini)"
  }
  [pscustomobject]@{ mod = $m.name; game_root = $GameRoot; azimuth_root = $AzimuthRoot; files = $record } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'restore.json') -Encoding UTF8
  Copy-Item -LiteralPath (Join-Path $pkg 'Uninstall.ps1') -Destination $backup   # undo works without this package
} catch {
  Write-Warning "Install failed; rolling back. $_"
  foreach ($r in $record) {
    $t = Join-Path $mount $r.target
    if ($r.existed) { Set-File (Join-Path $backup ('files\' + $r.target)) $t } elseif (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t }
  }
  throw
}
Write-Output "Installed $($m.name) into $(Join-Path $mount 'mediapc')."
Write-Output "Backup: $backup"
Write-Output "To undo: powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -BackupRoot `"$backup`""
