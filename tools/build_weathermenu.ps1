$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ "/out:$PSScriptRoot\FH2WeatherMenu.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "$PSScriptRoot\FH2WeatherMenu.cs"
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
