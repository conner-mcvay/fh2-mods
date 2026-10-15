<#
.SYNOPSIS
  One automated online test: starts Azimuth, presses Enter in its launcher, lets fh2net's input script
  ([input] Script= in fh2net.ini) play the controller sequence, then closes the game once the script is done.
.DESCRIPTION
  Archives the server's captures to captures\<Tag> first, and deletes the previous fh2net.log so the wait can't
  match an old run. Returns once the game has exited.
#>
param([string]$Azimuth = 'G:\FH2-1\azimuth', [string]$Tag = ('run-' + (Get-Date -Format 'HHmmss')), [int]$TimeoutSec = 300,
      [int]$ShotEverySec = 10, [string]$ShotAfter = 'BACK')
$ErrorActionPreference = 'Stop'
$isRunning = { Get-Process | Where-Object { $_.Path -and $_.Path -like (Join-Path $Azimuth '*') } }
if (& $isRunning) { throw 'The game is already running.' }
$log = Join-Path $Azimuth 'data\bin\fh2net.log'
if (Test-Path $log) { Remove-Item $log }
$cap = Join-Path $PSScriptRoot '..\server\captures'
$old = Join-Path $cap $Tag; New-Item -ItemType Directory $old -Force | Out-Null
Get-ChildItem $cap -File | Move-Item -Destination $old

Add-Type -Namespace Fh2Net -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@ -ErrorAction SilentlyContinue
# Bring a window to the front from a background process: a tapped Alt lets SetForegroundWindow through.
function Focus-Window([IntPtr]$h) {
  if ($h -eq [IntPtr]::Zero) { return }
  [Fh2Net.Win]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [Fh2Net.Win]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  [Fh2Net.Win]::ShowWindow($h, 9) | Out-Null
  [Fh2Net.Win]::BringWindowToTop($h) | Out-Null
  [Fh2Net.Win]::SetForegroundWindow($h) | Out-Null
}
Start-Process -FilePath (Join-Path $Azimuth 'azimuth.exe') -WorkingDirectory $Azimuth
$ws = New-Object -ComObject WScript.Shell
$started = $false
for ($try = 0; $try -lt 3 -and -not $started; $try++) {
  $deadline = (Get-Date).AddSeconds(30)
  do { Start-Sleep 1; $p = & $isRunning | Where-Object { $_.MainWindowHandle -ne 0 } } until ($p -or (Get-Date) -gt $deadline)
  if (-not $p) { throw 'The launcher window did not appear.' }
  Start-Sleep 3
  Focus-Window $p.MainWindowHandle; Start-Sleep -Milliseconds 700; $ws.SendKeys('{ENTER}')
  $deadline = (Get-Date).AddSeconds(20)
  do { Start-Sleep 1 } until ((Test-Path $log) -or (Get-Date) -gt $deadline)
  $started = Test-Path $log
}
if (-not $started) { throw 'The game did not start (no fh2net.log).' }
Write-Host 'game started; waiting for the input script'

# Screenshots every $ShotEverySec seconds once the script presses $ShotAfter, into captures\shots.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Fh2Net.Win]::SetProcessDPIAware() | Out-Null   # else the screen reads at its scaled size and only part is captured
$shots = Join-Path $cap 'shots'; New-Item -ItemType Directory $shots -Force | Out-Null
Get-ChildItem $shots -File | Remove-Item
function Save-Shot([string]$name) {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $small = New-Object System.Drawing.Bitmap $bmp, ([int]($b.Width / 2)), ([int]($b.Height / 2))
  $small.Save((Join-Path $shots "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose(); $small.Dispose()
}
$shotStart = $null; $nextShot = $null
$deadline = (Get-Date).AddSeconds($TimeoutSec)
do {
  Start-Sleep 3; (& $isRunning) | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object { Focus-Window $_.MainWindowHandle }
  if ($ShotEverySec -gt 0) {
    if (-not $shotStart -and (Select-String -Path $log -Pattern "input: press $ShotAfter" -Quiet)) { $shotStart = Get-Date; $nextShot = $shotStart }
    if ($shotStart -and (Get-Date) -ge $nextShot) { Save-Shot ('join+{0:000}s' -f [int]((Get-Date) - $shotStart).TotalSeconds); $nextShot = $nextShot.AddSeconds($ShotEverySec) }
  }
} until ((Select-String -Path $log -Pattern 'input: script done' -Quiet) -or -not (& $isRunning) -or (Get-Date) -gt $deadline)
$p = & $isRunning
if ($p) {
  $p | ForEach-Object { $_.CloseMainWindow() | Out-Null }
  if (-not ($p | ForEach-Object { $_.WaitForExit(30000) })) { Write-Warning 'The game did not close within 30 s.' }
}
Write-Host "done; captures of the previous run are in captures\$Tag"
