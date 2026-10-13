param([string[]]$Addrs)
if (-not ('MemScan' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'MemScan.cs') }
$p = Get-Process | Where-Object { $_.Path -like 'G:\FH2-1\azimuth\*' } | Select-Object -First 1
$h = [MemScan]::Open($p.Id)
$vals = [uint64[]]@($Addrs | ForEach-Object { [Convert]::ToUInt64($_, 16) })
foreach ($x in [MemScan]::Find($h, $vals)) { "{0:X} -> {1:X}" -f $x[0], $x[1] }
