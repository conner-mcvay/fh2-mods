if (-not ('MemScan' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'MemScan.cs') }
$p = Get-Process | Where-Object { $_.Path -like 'G:\FH2-1\azimuth\*' } | Select-Object -First 1
if (-not $p) { 'game not running'; return }
"process $($p.Name) pid $($p.Id)"
$h = [MemScan]::Open($p.Id)
$vt = [ordered]@{ CCamFree = 0x142E78AF0; CCamPhotoMode = 0x142C6C578; CCamFollow = 0x142E783A0; CCamDriver = 0x142E78120; CCamFreeTrack = 0x142E79040 }
$name = @{}; foreach ($k in $vt.Keys) { $name[[uint64]$vt[$k]] = $k }
$hits = [MemScan]::Find($h, [uint64[]]@($vt.Values))
"{0} objects" -f $hits.Count
$objs = @{}
foreach ($x in $hits) { "  {0,-14} at {1:X}" -f $name[$x[1]], $x[0]; $objs[$x[0]] = $name[$x[1]] }
# who points at these camera objects (camera manager / active camera slot)?
$refs = [MemScan]::Find($h, [uint64[]]@($objs.Keys))
"--- references to camera objects"
foreach ($x in $refs) { "  {0:X} -> {1} {2:X}" -f $x[0], $objs[$x[1]], $x[1] }
