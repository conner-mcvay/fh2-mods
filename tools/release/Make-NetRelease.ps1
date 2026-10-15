<#
.SYNOPSIS
  Packages fh2net and its server as a release zip: dist\fh2net-<Version>.zip.

.DESCRIPTION
  Builds fh2net.dll (tools\online\probe\build.ps1, unless -NoBuild), then collects it with the user docs and
  installer (release\fh2net) and the server's Python files. No game files and no captures or server data are
  included.

.EXAMPLE
  .\tools\release\Make-NetRelease.ps1 -Version 0.1.0
#>
param(
  [Parameter(Mandatory)][string]$Version,
  [switch]$NoBuild   # package the existing tools\online\probe\out\fh2net.dll
)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$probe = Join-Path $root 'tools\online\probe'
if (-not $NoBuild) { & (Join-Path $probe 'build.ps1'); if ($LASTEXITCODE) { throw 'fh2net build failed' } }
$dll = Join-Path $probe 'out\fh2net.dll'
if (-not (Test-Path $dll)) { throw "Missing $dll" }
$name = "fh2net-$Version"
$stage = Join-Path $root "build\release\$name"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory (Join-Path $stage 'server') -Force | Out-Null

Copy-Item $dll, (Join-Path $root 'LICENSE') $stage
Copy-Item (Join-Path $root 'release\fh2net\*') $stage -Recurse
foreach ($f in 'fh2srv.py', 'relay.py', 'nerd.py', 'xls.py') { Copy-Item (Join-Path $root "tools\online\server\$f") (Join-Path $stage 'server') }
Set-Content (Join-Path $stage 'VERSION.txt') "fh2net $Version" -Encoding ASCII

$zip = Join-Path $root "dist\$name.zip"
New-Item -ItemType Directory (Split-Path $zip) -Force | Out-Null
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Write-Host ("Built {0} ({1:N0} KB, {2} files)`nSHA-256 {3}" -f $zip, ((Get-Item $zip).Length / 1KB), (Get-ChildItem -Recurse -File $stage).Count, $sha)
