param([string]$Addr, [int]$Len = 0x200)
if (-not ('MemScan' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'MemScan.cs') }
$p = Get-Process | Where-Object { $_.Path -like 'G:\FH2-1\azimuth\*' } | Select-Object -First 1
$h = [MemScan]::Open($p.Id); $a = [Convert]::ToUInt64($Addr, 16)
$b = [MemScan]::Read($h, $a, $Len); if (-not $b) { 'unreadable'; return }
function Str([uint64]$v) { if ($v -lt 0x10000 -or $v -gt 0x7FFFFFFFFFFF) { return '' }; $s = [MemScan]::Read($h, $v, 48); if (-not $s) { return '' }
  $e = 0; while ($e -lt 48 -and $s[$e] -ge 0x20 -and $s[$e] -lt 0x7f) { $e++ }; if ($e -ge 3 -and ($e -eq 48 -or $s[$e] -eq 0)) { '"' + [Text.Encoding]::ASCII.GetString($s, 0, $e) + '"' } else { '' } }
for ($o = 0; $o -lt $Len; $o += 8) {
  $q = [BitConverter]::ToUInt64($b, $o); $f1 = [BitConverter]::ToSingle($b, $o); $f2 = [BitConverter]::ToSingle($b, $o + 4)
  $fl = if ([math]::Abs($f1) -lt 1e6 -and [math]::Abs($f1) -gt 1e-4 -or [math]::Abs($f2) -lt 1e6 -and [math]::Abs($f2) -gt 1e-4) { '{0,10:G5} {1,10:G5}' -f $f1, $f2 } else { '' }
  "{0:X} +{1:X3}: {2:X16}  {3,-22} {4}" -f ($a + $o), $o, $q, $fl, (Str $q)
}
