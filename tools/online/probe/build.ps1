# Builds fh2net.dll (the probe) with Zig's C compiler: G:\FH2-1\tools\zig, or -Zig <zig.exe>.
param([string]$Zig = 'G:\FH2-1\tools\zig\zig-windows-x86_64-0.13.0\zig.exe')
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'out'; New-Item -ItemType Directory $out -Force | Out-Null
& $Zig cc -target x86_64-windows-gnu -shared -O2 -Wall -o (Join-Path $out 'fh2net.dll') `
  (Join-Path $PSScriptRoot 'fh2net.c') (Join-Path $PSScriptRoot 'fh2net.def') -lws2_32 -lwinhttp -lole32
if ($LASTEXITCODE) { throw "zig cc failed ($LASTEXITCODE)" }
Get-Item (Join-Path $out 'fh2net.dll') | select FullName, Length
