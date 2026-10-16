<#
.SYNOPSIS
  Sliders for a car's sound in Forza Horizon 2 (PC / Azimuth): exhaust, engine and intake volume, idle, highs, lows
  and grit, the low-frequency layer, backfires, turbo, superchargers and blow-off valve.

.DESCRIPTION
  Pick a car, move the sliders (each adds to the car's stock sound; 0 = stock) and Apply with the game closed. The
  car's bank is rebuilt from the game's own every time and written to Mount\mediapc (tools\audio\FmodBank.cs has what
  each slider changes; CarSound.ps1 the writing). Settings are kept per car, shared with Set-BoostVolume.ps1.

.EXAMPLE
  .\tools\audio\Tune-CarSound.ps1
#>
param([string]$GameRoot, [string]$AzimuthRoot)
$ErrorActionPreference = 'Stop'
# draw at the screen's real resolution (system DPI aware, which Windows Forms scales to; without this Windows stretches
# a 96-DPI bitmap, blurry on 4K)
Add-Type -Namespace FH2Tuner -Name Dpi -MemberDefinition '[DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v); [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
try { [void][FH2Tuner.Dpi]::SetProcessDpiAwareness(1) } catch { [void][FH2Tuner.Dpi]::SetProcessDPIAware() }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
# the layout is in 96-DPI pixels, scaled here to the screen's DPI (fonts, in points, scale by themselves)
$script:k = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96
function P([double]$x, [double]$y) { New-Object Drawing.Point([int]($x * $script:k), [int]($y * $script:k)) }
function Sz([double]$w, [double]$h) { New-Object Drawing.Size([int]($w * $script:k), [int]($h * $script:k)) }
try { . (Join-Path $PSScriptRoot 'CarSound.ps1'); $ctx = Resolve-CarSoundFolders $GameRoot $AzimuthRoot }
catch { [void][Windows.Forms.MessageBox]::Show("$_", 'FH2 car sound tuner'); return }   # (run from Tune-CarSound.cmd, there's no console)

# slider: setting, label, tab, minimum, maximum (in the setting's units), what it does
$sliders = @(
  @('ExhaustVolume', 'Volume', 'Exhaust', -24, 24, 'Every exhaust layer (all RPM), in dB.'),
  @('ExhaustIdle', 'Idle', 'Exhaust', -24, 24, 'The exhaust layer recorded at the lowest RPM (the idle), in dB, on top of Volume. Much past +20 the idle distorts.'),
  @('ExhaustHighs', 'Highs', 'Exhaust', -24, 24, 'The high band of the EQs on the exhaust tracks, in dB (EQ limit +10 dB). Brighter, more crackle.'),
  @('ExhaustLows', 'Lows', 'Exhaust', -24, 24, 'The low band of the exhaust group''s EQ, in dB (EQ limit +10 dB). Less or more boom.'),
  @('ExhaustGrit', 'Grit', 'Exhaust', -20, 20, 'The exhaust saturator''s drive. More grit and rasp.'),
  @('EngineVolume', 'Volume', 'Engine', -24, 24, 'Every engine layer (all RPM), in dB.'),
  @('EngineIdle', 'Idle', 'Engine', -24, 24, 'The engine layer recorded at the lowest RPM, in dB, on top of Volume.'),
  @('EngineHighs', 'Highs', 'Engine', -24, 24, 'The high band of the engine EQs, in dB (EQ limit +10 dB).'),
  @('EngineLows', 'Lows', 'Engine', -24, 24, 'The low band of the engine EQ, in dB (EQ limit +10 dB).'),
  @('EngineGrit', 'Grit', 'Engine', -20, 20, 'The engine saturator''s drive.'),
  @('IntakeVolume', 'Volume', 'Intake', -24, 24, 'Every intake layer (all RPM), in dB.'),
  @('IntakeIdle', 'Idle', 'Intake', -24, 24, 'The intake layer recorded at the lowest RPM, in dB, on top of Volume.'),
  @('IntakeHighs', 'Highs', 'Intake', -24, 24, 'The high band of the intake EQs, in dB (EQ limit +10 dB).'),
  @('IntakeLows', 'Lows', 'Intake', -24, 24, 'The low band of the intake EQ, in dB (EQ limit +10 dB).'),
  @('IntakeGrit', 'Grit', 'Intake', -20, 20, 'The intake saturator''s drive.'),
  @('Turbo', 'Turbo', 'Turbo & other', -24, 24, 'The turbo sounds on the turbo''s upgrade levels (single and twin), in dB. The spool whistle is Boost whistle.'),
  @('Whistle', 'Boost whistle', 'Turbo & other', -24, 24, 'The spool whistle and intake air that follow boost (WhistleLooping, AirLooping), in dB.'),
  @('DSC', 'Supercharger (DSC)', 'Turbo & other', -24, 24, 'Positive-displacement supercharger whine, in dB.'),
  @('CSC', 'Supercharger (CSC)', 'Turbo & other', -24, 24, 'Centrifugal supercharger whine, in dB.'),
  @('BOV', 'Blow-off valve', 'Turbo & other', -24, 24, 'Blow-off valve, in dB (on top of Turbo where it''s part of the turbo sound).'),
  @('Backfire', 'Backfires', 'Turbo & other', -24, 24, 'Backfire pops, in dB.'),
  @('LowFreq', 'Low-frequency layer', 'Turbo & other', -24, 24, 'The separate sub-bass layer some cars have (LFE), in dB. Lower it if the car is boomy.')
)

$form = New-Object Windows.Forms.Form -Property @{ Text = 'FH2 car sound tuner'; Size = (Sz 920 640); StartPosition = 'CenterScreen'; MinimumSize = (Sz 820 560) }
$font = New-Object Drawing.Font('Segoe UI', 9); $form.Font = $font; $form.AutoScaleMode = 'None'   # (scaled by P / Sz)
$tip = New-Object Windows.Forms.ToolTip -Property @{ AutoPopDelay = 15000 }

$search = New-Object Windows.Forms.TextBox -Property @{ Location = (P 12 34); Size = (Sz 250 24) }
$searchLabel = New-Object Windows.Forms.Label -Property @{ Text = 'Car (type part of a name):'; Location = (P 12 12); AutoSize = $true }
$list = New-Object Windows.Forms.ListBox -Property @{ Location = (P 12 62); Size = (Sz 250 480); Anchor = 'Top,Bottom,Left'; IntegralHeight = $false }
$title = New-Object Windows.Forms.Label -Property @{ Location = (P 280 10); AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold); Text = 'Pick a car' }
$info = New-Object Windows.Forms.Label -Property @{ Location = (P 282 36); Size = (Sz 610 20); Anchor = 'Top,Left,Right'; ForeColor = [Drawing.Color]::DimGray;
  Text = 'Each slider adds to the car''s stock sound (0 = stock). Hover a slider''s name for what it does.' }
$tabs = New-Object Windows.Forms.TabControl -Property @{ Location = (P 280 62); Size = (Sz 612 420); Anchor = 'Top,Bottom,Left,Right' }
$apply = New-Object Windows.Forms.Button -Property @{ Text = 'Apply'; Location = (P 280 494); Size = (Sz 110 30); Anchor = 'Bottom,Left'; Enabled = $false }
$reset = New-Object Windows.Forms.Button -Property @{ Text = 'Reset to stock'; Location = (P 398 494); Size = (Sz 120 30); Anchor = 'Bottom,Left'; Enabled = $false }
$revert = New-Object Windows.Forms.Button -Property @{ Text = 'Revert'; Location = (P 526 494); Size = (Sz 90 30); Anchor = 'Bottom,Left'; Enabled = $false }
$status = New-Object Windows.Forms.Label -Property @{ Location = (P 280 534); Size = (Sz 612 40); Anchor = 'Bottom,Left,Right' }
$tip.SetToolTip($apply, 'Write the car''s sound with these settings (close the game first). Start the game to hear it.')
$tip.SetToolTip($reset, 'Set every slider to 0 (then Apply to put the car back to stock).')
$tip.SetToolTip($revert, 'Back to what''s applied now.')
$form.Controls.AddRange(@($searchLabel, $search, $list, $title, $info, $tabs, $apply, $reset, $revert, $status))

$rows = @{}   # setting -> @{ Bar; Value; Name; Min }
$pages = [ordered]@{}
foreach ($s in $sliders) {
  $tabName = $s[2]
  if (-not $pages.Contains($tabName)) {
    $p = New-Object Windows.Forms.TabPage -Property @{ Text = $s[2]; AutoScroll = $true; Padding = New-Object Windows.Forms.Padding(8) }
    $tabs.TabPages.Add($p); $pages[$tabName] = @{ Page = $p; Y = 14 }
  }
  $pg = $pages[$tabName]
  $name = New-Object Windows.Forms.Label -Property @{ Text = $s[1]; Location = (P 12 (($pg.Y + 8))); Size = (Sz 150 20) }
  $bar = New-Object Windows.Forms.TrackBar -Property @{ Location = (P 165 $pg.Y); Size = (Sz 270 45); Minimum = $s[3] * 2; Maximum = $s[4] * 2; TickFrequency = 4; SmallChange = 1; LargeChange = 4; Value = 0; Enabled = $false }
  $val = New-Object Windows.Forms.Label -Property @{ Location = (P 445 (($pg.Y + 8))); Size = (Sz 150 20) }
  $tip.SetToolTip($name, $s[5]); $tip.SetToolTip($bar, $s[5])
  $pg.Page.Controls.AddRange(@($name, $bar, $val))
  $bar.Tag = $s[0]
  $rows[$s[0]] = @{ Bar = $bar; Value = $val; Name = $name; Setting = $s[0] }
  $pg.Y += 52
}

$script:bank = $null; $script:car = $null; $script:loading = $false
function Format-Row($row) {
  $v = $row.Bar.Value / 2.0
  if (-not $row.Bar.Enabled) { $row.Value.Text = '(this car has none)'; return }
  $text = '{0:+0.0;-0.0;0}' -f $v
  $t = @($script:bank.Targets() | Where-Object Setting -eq $row.Setting)
  if ($row.Setting -match 'Highs$|Lows$|Grit$' -and $t.Count -eq 1) {   # show the effect's resulting value
    $r = [math]::Max($t[0].Min, [math]::Min($t[0].Max, $t[0].Stock + $v))
    $text += $(if ($row.Setting -match 'Grit$') { "  (drive {0:0.#})" -f $r } else { "  (EQ {0:+0.#;-0.#;0} dB)" -f $r })
  }
  $row.Value.Text = $text
}
function Update-Buttons {
  $dirty = $false
  if ($script:car) { $cur = Get-CarSoundSettings $ctx $script:car; foreach ($k in $rows.Keys) { if ($rows[$k].Bar.Value / 2.0 -ne $cur[$k]) { $dirty = $true } } }
  $apply.Enabled = [bool]$script:car; $revert.Enabled = $dirty; $reset.Enabled = [bool]$script:car
  $title.Text = $(if ($script:car) { $script:car + $(if ($dirty) { '  (not applied)' } elseif ($ctx.Manifest.ContainsKey($script:car)) { '  (tuned)' } else { '  (stock)' }) } else { 'Pick a car' })
}
function Load-Car([string]$c) {
  $script:loading = $true
  try {
    $script:car = $c; $script:bank = Read-CarBank $ctx $c
    $avail = @($script:bank.Available()); $cur = Get-CarSoundSettings $ctx $c
    foreach ($k in $rows.Keys) {
      $row = $rows[$k]; $row.Bar.Enabled = $avail -contains $k; $row.Name.Enabled = $row.Bar.Enabled
      $row.Bar.Value = [math]::Max($row.Bar.Minimum, [math]::Min($row.Bar.Maximum, [int][math]::Round($cur[$k] * 2)))
      Format-Row $row
    }
    $status.Text = ''
  } catch { $status.ForeColor = [Drawing.Color]::Firebrick; $status.Text = "Couldn't read ${c}: $_" }
  finally { $script:loading = $false }
  Update-Buttons
}
foreach ($row in $rows.Values) { $row.Bar.Add_ValueChanged({ if (-not $script:loading) { Format-Row $rows[$this.Tag]; Update-Buttons } }) }

function Fill-List {
  $term = $search.Text.Trim(); $list.BeginUpdate(); $list.Items.Clear()
  $cars = if ($term) { Find-Cars $ctx $term } else { $ctx.Cars }
  foreach ($c in $cars) { [void]$list.Items.Add($(if ($ctx.Manifest.ContainsKey($c)) { "$c  *" } else { $c })) }
  $list.EndUpdate()
}
$search.Add_TextChanged({ Fill-List })
$list.Add_SelectedIndexChanged({ if ($list.SelectedItem) { Load-Car (($list.SelectedItem -replace '\s+\*$', '')) } })

$apply.Add_Click({
  $status.ForeColor = [Drawing.Color]::Firebrick
  if (Test-GameRunning $ctx) {
    $status.Text = 'Not applied: close the game first, then Apply.'
    [void][Windows.Forms.MessageBox]::Show($form, "The game is running, so nothing was written.`n`nClose the game, then press Apply again.", 'FH2 car sound tuner', 'OK', 'Warning')
    return
  }
  $s = @{}; foreach ($k in $rows.Keys) { $s[$k] = $rows[$k].Bar.Value / 2.0 }
  try {
    $form.Cursor = 'WaitCursor'
    $r = Write-CarSound $ctx $script:car $s
    $status.ForeColor = [Drawing.Color]::DarkGreen; $status.Text = "$r. Start the game to hear it."
    $c = $script:car; Fill-List; $i = [array]::IndexOf(@($list.Items | ForEach-Object { $_ -replace '\s+\*$', '' }), $c); if ($i -ge 0) { $list.SelectedIndex = $i }
  } catch { $status.Text = "Not applied: $_"; [void][Windows.Forms.MessageBox]::Show($form, "Not applied:`n`n$_", 'FH2 car sound tuner', 'OK', 'Error') } finally { $form.Cursor = 'Default' }
  Update-Buttons
})
$reset.Add_Click({ foreach ($row in $rows.Values) { $row.Bar.Value = 0 }; $status.Text = 'All sliders at 0: Apply to put the car back to stock.'; $status.ForeColor = [Drawing.Color]::DimGray })
$revert.Add_Click({ Load-Car $script:car })

$status.ForeColor = [Drawing.Color]::DimGray
$form.Text = "FH2 car sound tuner - $($ctx.GameRoot)"
$status.Text = "Game folder: $($ctx.GameRoot)   (* = tuned)"
Fill-List
[void]$form.ShowDialog()
