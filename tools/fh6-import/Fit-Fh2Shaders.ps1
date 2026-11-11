# Fits a converted model's vertex layouts to its FH2 shaders (Fm5ModelConverter) and validates it.
param([Parameter(Mandatory)][string]$Model, [Parameter(Mandatory)][string]$Fh2Media, [string]$Repo)
$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = Split-Path (Split-Path $PSScriptRoot) }   # $PSScriptRoot is empty in 5.1 parameter defaults
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (-not ('BurgBlob' -as [type])) {
  $cs = 'ForzaModel.cs', 'Fm5ModelConverter.cs', 'CarLights.cs' | ForEach-Object { Join-Path $Repo "tools\fm5-import\$_" }
  Add-Type -Path $cs -ReferencedAssemblies System.Core, System.IO.Compression, System.IO.Compression.FileSystem
}
$bytes = [IO.File]::ReadAllBytes($Model)
$pre = [ForzaModelCheck]::Check($bytes)
if ($pre.Count) { throw "input fails validation: $($pre -join '; ')" }
$files = New-Object 'System.Collections.Generic.Dictionary[string,byte[]]'
$resolver = New-Object Fh2ShaderResolver($Fh2Media, $files, 'none')
try {
  $inputs = [Func[string, System.Collections.Generic.HashSet[string]]] { param($p) $resolver.Inputs($p) }
  $log = New-Object 'System.Collections.Generic.List[string]'
  $out = [Fm5ModelConverter]::Convert($bytes, $inputs, $log)
  $log | ForEach-Object { Write-Host $_ }
  $resolver.Log | Select-Object -Unique | ForEach-Object { Write-Warning $_ }
  if ($out) {
    $problems = [ForzaModelCheck]::Check($out)
    if ($problems.Count) { throw "fitted model fails validation: $($problems -join '; ')" }
    [IO.File]::WriteAllBytes($Model, $out); Write-Host "fitted: $Model ($($out.Length) bytes)"
  } else { Write-Host 'layouts already match their shaders' }
} finally { $resolver.Dispose() }
