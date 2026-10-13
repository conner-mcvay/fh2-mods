<#
.SYNOPSIS
  Gives an imported FM5 car night lights, transplanted from a similar FH2 car.

.DESCRIPTION
  FH2 cars carry two light files that FM5 cars don't have (FM5 has no night):
    Lights.bin        the car's lamp meshes (each with a light id) and its light sources: per light a kind (headlight,
                      tail/brake, reverse, CHMSL ...), the lamp mesh it belongs to, and two poses (position + rotation,
                      car space)
    LightPresets.bin  beam shapes, intensities and projection textures (nothing car-specific)
  This copies both from a donor and fits them to the imported car: the donor's lamp meshes are matched by role
  (left/right headlight, taillight, CHMSL, fog light; glass, bulbs or housing) to the car's own, and each light is
  moved by the offset between its donor lamp and the matching lamp of the car. Lamps on pop-up or other animated
  parts are modelled in their bone's space, so those lights are placed relative to the front/rear bumper instead.
  Pick a donor of the same shape, with pop-ups if the car has them (e.g. PON_TransAmGTA_87 for the 2002 Trans Am,
  CHE_CorvetteZR1_95 for the 2002 Corvette). Installed as one more layer (undo with its backup's Uninstall.ps1).

.EXAMPLE
  .\tools\fm5-import\Add-CarLights.ps1 -Car PON_TransAm_02 -Donor PON_TransAmGTA_87
.EXAMPLE
  .\tools\fm5-import\Add-CarLights.ps1 -Car PON_TransAm_02,CHE_CorvetteZ06_02 -Donor PON_TransAmGTA_87,CHE_CorvetteZR1_95 -NoInstall
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]]$Car,      # imported cars (MediaName)
  [Parameter(Mandatory)][string[]]$Donor,    # FH2 light donor per car
  [string[]]$GraphFrom,                      # per car, optional: a car whose animation graph (.gsf) to use, e.g. when
                                             #   the car's own doesn't raise its pop-ups in FH2 ("" = keep its own)
  [string]$GameRoot, [string]$AzimuthRoot,
  [string]$Name = 'car-lights',
  [string]$Sqlite = $env:FH2_SQLITE,
  [switch]$NoInstall
)
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot; $root = Split-Path (Split-Path $tools); $bin = Join-Path (Split-Path $tools) 'bin'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (-not ('LightsFile' -as [type])) { Add-Type -Path (Join-Path $tools 'ForzaModel.cs'), (Join-Path $tools 'CarLights.cs') -ReferencedAssemblies System.Core }
$settingsPath = Join-Path $env:LOCALAPPDATA 'fh2-mods\import-fm5-cars.json'
$saved = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $GameRoot) { $GameRoot = $saved.GameRoot }; if (-not $AzimuthRoot) { $AzimuthRoot = $saved.AzimuthRoot }
if (-not $GameRoot) { throw 'Pass -GameRoot (or run Import-Fm5Cars once so it''s remembered)' }
if (-not $NoInstall -and -not $AzimuthRoot) { throw 'Pass -AzimuthRoot' }
if ($Donor.Count -ne $Car.Count) { throw '-Donor needs one entry per -Car' }
if ($GraphFrom -and $GraphFrom.Count -ne $Car.Count) { throw '-GraphFrom needs one entry per -Car (use "" for none)' }
if (-not $Sqlite) { $Sqlite = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Source }
if (-not $Sqlite -and (Test-Path "$bin\sqlite3.exe")) { $Sqlite = "$bin\sqlite3.exe" }
$cars = Join-Path $GameRoot 'Mount\media\cars'

function Read-Entries([string]$zip) {   # entry name (lowercase, '/') -> bytes, for the light files and exterior models
  $z = [IO.Compression.ZipFile]::OpenRead($zip); $h = @{}
  try {
    foreach ($e in $z.Entries) {
      if ($e.FullName -notmatch '(?i)^(Lights\.bin|LightPresets\.bin|scene/exterior/.+\.modelbin|scene/[^/]+_skeleton\.modelbin)$') { continue }
      $ms = New-Object IO.MemoryStream; $s = $e.Open(); $s.CopyTo($ms); $s.Close(); $h[$e.FullName.ToLower()] = $ms.ToArray()
    }
  } finally { $z.Dispose() }
  $h
}
function Bounds([hashtable]$entries, [string]$name) {   # [minx,miny,minz,maxx,maxy,maxz] of a model, cached
  if (-not $entries.ContainsKey($name)) { return $null }
  $k = "bounds:$name"; if (-not $entries.ContainsKey($k)) { $entries[$k] = [ModelBounds]::Of($entries[$name]) }; $entries[$k]
}
function Center($b) { @((($b[0] + $b[3]) / 2), (($b[1] + $b[4]) / 2), (($b[2] + $b[5]) / 2)) }

# lamp role of a model file: kind (head, tail, chmsl, fog, marker, other), side (l, r, c), part (glass, bulbs, main)
function Role([string]$file) {
  $n = [IO.Path]::GetFileNameWithoutExtension($file).ToLower() -replace '_[a-z]$', ''
  $part = if ($n -like 'glass*') { 'glass' } elseif ($n -like '*bulbs*') { 'bulbs' } else { 'main' }
  $n = $n -replace '^glass', '' -replace 'bulbs', ''
  $kind, $side = switch -Regex ($n) {
    'chmsl' { 'chmsl', 'c'; break }
    '^(headlight|)([lr])hl$' { 'head', $Matches[2]; break }
    '^headlight([lr])' { 'head', $Matches[1]; break }
    '^(taillight|)([lr])tl$' { 'tail', $Matches[2]; break }
    '^taillight([lrc])' { 'tail', $Matches[1]; break }
    '^(foglight|)([lr])fl$' { 'fog', $Matches[2]; break }
    '^foglight([lr])' { 'fog', $Matches[1]; break }
    'sidemarker' { 'marker', $(if ($n -match 'sidemarkers?([lr])') { $Matches[1] } else { 'c' }); break }
    default { 'other', 'c' }
  }
  [pscustomobject]@{ Kind = $kind; Side = $side; Part = $part }
}
function Match-Mesh([string]$donorPath, [string[]]$targetModels) {
  # the target model for a donor lamp: same file, else same kind+side preferring the same part (glass > bulbs > main)
  $file = ($donorPath -split '\\')[-1].ToLower()
  $same = @($targetModels | Where-Object { ($_ -split '/')[-1] -eq $file }); if ($same) { return $same[0] }
  $r = Role $file; if ($r.Kind -eq 'other') { return $null }
  $cands = @($targetModels | Where-Object { $x = Role $_; $x.Kind -eq $r.Kind -and $x.Side -eq $r.Side })
  if (-not $cands -and $r.Kind -eq 'marker') { $cands = @($targetModels | Where-Object { (Role $_).Kind -eq 'marker' }) }
  if (-not $cands) { return $null }
  $order = @{ glass = @('glass', 'bulbs', 'main'); bulbs = @('bulbs', 'glass', 'main'); main = @('main', 'glass', 'bulbs') }[$r.Part]
  ($cands | Sort-Object { [array]::IndexOf($order, (Role $_).Part) }, { $_ })[0]
}

$ws = Join-Path $root "build\.lights-$Name"; if (Test-Path $ws) { Remove-Item -Recurse -Force $ws }
$modDir = Join-Path $ws 'car-lights'
for ($ci = 0; $ci -lt $Car.Count; $ci++) {
  $c = $Car[$ci]; $dn = $Donor[$ci]
  $tz = Get-ChildItem $cars -Filter "$c.zip" | Select-Object -First 1; $dz = Get-ChildItem $cars -Filter "$dn.zip" | Select-Object -First 1
  if (-not $tz) { throw "$c isn't installed (no media\cars\$c.zip)" }; if (-not $dz) { throw "No FH2 car $dn" }
  $T = Read-Entries $tz.FullName; $D = Read-Entries $dz.FullName
  if (-not $D.ContainsKey('lights.bin')) { throw "$dn has no Lights.bin" }
  if ($T.ContainsKey('lights.bin')) { Write-Warning "$c already has a Lights.bin; replacing it" }
  $targetModels = @($T.Keys | Where-Object { $_ -like 'scene/exterior/*.modelbin' })
  $lf = [LightsFile]::Read($D['lights.bin'])
  Write-Host "$c <- lights of $dn"

  # skeleton bones (name -> index) of both cars: a lamp's id is the index of the bone it hangs on (1 = root,
  # boneHeadlightL/R for pop-ups), and bone order differs between cars
  $boneIndex = { param($entries) $k = $entries.Keys | Where-Object { $_ -match '^scene/[^/]+_skeleton\.modelbin$' } | Select-Object -First 1
    $l = @(); if ($k) { $l = @([Skeleton]::Read($entries[$k]) | ForEach-Object { $_.Name.ToLower() }) }; , $l }
  $donorBoneNames = & $boneIndex $D; $carBoneNames = & $boneIndex $T

  # lamp meshes: same list order (light records refer to it by index), donor paths swapped for the car's own models
  $map = @()
  foreach ($m in $lf.Meshes) {
    $bone = if ($m.Id -lt $donorBoneNames.Count) { $donorBoneNames[$m.Id] } else { '' }
    if ($m.Id -lt $donorBoneNames.Count) {
      $bone = $donorBoneNames[$m.Id]; $ci2 = [array]::IndexOf($carBoneNames, $bone)
      if ($ci2 -lt 0) { throw "$c has no bone $bone (the donor's lamp $($m.Path) hangs on it)" }
      $m.Id = [uint16]$ci2
    }
    $rel = ($m.Path -replace '^game:\\media\\cars\\[^\\]+\\', '').Replace('\', '/').ToLower()
    $lamp = Match-Mesh $m.Path $targetModels   # (not $t: PowerShell names are case-insensitive, $T is the car's files)
    if (-not $lamp) { $lamp = ($targetModels | Where-Object { (Role $_).Kind -eq (Role $rel).Kind } | Select-Object -First 1) }
    if (-not $lamp) { throw "$c has no lamp model for the donor's $rel" }
    $map += [pscustomobject]@{ Donor = $rel; Target = $lamp; Bone = $bone }
    $m.Path = "game:\media\cars\$($c.ToLower())\" + $lamp.Replace('/', '\')
    Write-Host ("  lamp [{0,2}] {1,-44} -> {2}" -f $m.Id, ($rel -replace '^scene/exterior/', ''), ($lamp -replace '^scene/exterior/', ''))
  }
  # a donor headlight glass with no glass on the car (lens modelled into the housing, e.g. the FM5 2002 Trans Am):
  # also list the car's housing on the same bone. Appended, so the light records' mesh indices stay valid.
  $extra = @()
  for ($k = 0; $k -lt $map.Count; $k++) {
    $r = Role $map[$k].Donor
    if ($r.Kind -ne 'head' -or $r.Part -ne 'glass' -or (Role $map[$k].Target).Part -eq 'glass') { continue }
    $housing = $targetModels | Where-Object { $x = Role $_; $x.Kind -eq 'head' -and $x.Side -eq $r.Side -and $x.Part -eq 'main' } | Sort-Object | Select-Object -First 1
    if ($housing -and $housing -ne $map[$k].Target) {
      $extra += New-Object LightMesh -Property @{ Path = "game:\media\cars\$($c.ToLower())\" + $housing.Replace('/', '\'); Id = $lf.Meshes[$k].Id }
      Write-Host ("  lamp [{0,2}] (also)                                       -> {1}" -f $lf.Meshes[$k].Id, ($housing -replace '^scene/exterior/', ''))
    }
  }
  foreach ($e in $extra) { $lf.Meshes.Add($e) }

  # light records: count, then 76 bytes each: u32 index, u16 kind, u16 sub, u32 lamp mesh index, 2 x (pos xyzw, rot xyzw)
  $rest = $lf.Rest; $n = [BitConverter]::ToInt32($rest, 0)
  $front = @{ D = (Bounds $D 'scene/exterior/bumperf/bumperf_a.modelbin'); T = (Bounds $T 'scene/exterior/bumperf/bumperf_a.modelbin') }
  $rear = @{ D = (Bounds $D 'scene/exterior/bumperr/bumperr_a.modelbin'); T = (Bounds $T 'scene/exterior/bumperr/bumperr_a.modelbin') }
  # pop-up headlight hinges: lights on lamps modelled in a bone's space move with that bone
  $boneOf = { param($entries) $k = $entries.Keys | Where-Object { $_ -match '^scene/[^/]+_skeleton\.modelbin$' } | Select-Object -First 1
    $h = @{}; if ($k) { foreach ($b in [Skeleton]::Read($entries[$k])) { $h[$b.Name.ToLower()] = $b.World } }; $h }
  $donorBones = & $boneOf $D; $carBones = & $boneOf $T
  $moved = @{}
  for ($i = 0; $i -lt $n; $i++) {
    $o = 4 + 76 * $i; $mi = [BitConverter]::ToInt32($rest, $o + 8)
    $pz = [BitConverter]::ToSingle($rest, $o + 20)
    $delta = $null; $how = ''
    if ($mi -ge 0 -and $mi -lt $map.Count) {
      $donorLamp = Bounds $D $map[$mi].Donor; $carLamp = Bounds $T $map[$mi].Target
      # lamps modelled in car space (not on a pop-up/animated bone) sit well away from the origin along z
      if ($donorLamp -and $carLamp -and [math]::Abs((Center $donorLamp)[2]) -gt 1.0 -and [math]::Abs((Center $carLamp)[2]) -gt 1.0) {
        $dc = Center $donorLamp; $tc = Center $carLamp; $delta = @(($tc[0] - $dc[0]), ($tc[1] - $dc[1]), ($tc[2] - $dc[2])); $how = 'lamp'
      }
    }
    # pop-up lamps: lights are stored in the closed pose and the game turns them with the bone as it opens, so they
    # are re-aimed from the donor's closed lens (centre + facing, from its normals) onto the car's closed lens
    $frame = $null
    if (-not $delta -and $mi -ge 0 -and $mi -lt $map.Count -and $map[$mi].Bone -like 'boneheadlight*' -and $donorBones.ContainsKey($map[$mi].Bone) -and $carBones.ContainsKey($map[$mi].Bone)) {
      $bn = $map[$mi].Bone
      $carModel = $map[$mi].Target
      if ((Role $carModel).Part -ne 'glass') {   # no lens glass: the lens is part of the housing
        $r0 = Role $carModel; $h = $targetModels | Where-Object { $x0 = Role $_; $x0.Kind -eq 'head' -and $x0.Side -eq $r0.Side -and $x0.Part -eq 'main' } | Sort-Object | Select-Object -First 1
        if ($h) { $carModel = $h }
      }
      $dl = [LensFrame]::Of($D[$map[$mi].Donor]); $tl = [LensFrame]::Of($T[$carModel])
      if ($dl -and $tl) {
        $cd = [Quat]::Point($donorBones[$bn], @($dl[0], $dl[1], $dl[2])); $nd = [Quat]::Dir($donorBones[$bn], @($dl[3], $dl[4], $dl[5]))
        $ct = [Quat]::Point($carBones[$bn], @($tl[0], $tl[1], $tl[2])); $nt = [Quat]::Dir($carBones[$bn], @($tl[3], $tl[4], $tl[5]))
        $frame = @{ Cd = $cd; Ct = $ct; Q = [Quat]::Between($nd, $nt) }; $how = 'pop-up lens'
      }
    }
    foreach ($pose in 0, 32) {
      $p = $o + 12 + $pose
      $x = [BitConverter]::ToSingle($rest, $p); $y = [BitConverter]::ToSingle($rest, $p + 4); $z = [BitConverter]::ToSingle($rest, $p + 8)
      if ($delta) { $x += $delta[0]; $y += $delta[1]; $z += $delta[2] }
      elseif ($frame) {
        $v = [Quat]::Rotate($frame.Q, @(($x - $frame.Cd[0]), ($y - $frame.Cd[1]), ($z - $frame.Cd[2])))
        $x = $frame.Ct[0] + $v[0]; $y = $frame.Ct[1] + $v[1]; $z = $frame.Ct[2] + $v[2]
        $q = @(0..3 | ForEach-Object { [BitConverter]::ToSingle($rest, $p + 16 + 4 * $_) })
        $q2 = [Quat]::Mul($frame.Q, [single[]]$q)
        for ($k = 0; $k -lt 4; $k++) { [BitConverter]::GetBytes([single]$q2[$k]).CopyTo($rest, $p + 16 + 4 * $k) }
      }
      else {
        # relative to the bumper at that end: x and y scaled to its size, z kept at the same distance from its outer face
        $B = if ($pz -ge 0) { $front } else { $rear }
        if (-not $B.D -or -not $B.T) { throw "$c or $dn has no bumper model to place lights against" }
        $dw = ($B.D[3] - $B.D[0]) / 2; $tw = ($B.T[3] - $B.T[0]) / 2
        $x = $x * $tw / $dw
        $y = $B.T[1] + ($y - $B.D[1]) * ($B.T[4] - $B.T[1]) / ($B.D[4] - $B.D[1])
        $z = if ($pz -ge 0) { $z - $B.D[5] + $B.T[5] } else { $z - $B.D[2] + $B.T[2] }
        $how = if ($pz -ge 0) { 'front bumper' } else { 'rear bumper' }
      }
      [BitConverter]::GetBytes([single]$x).CopyTo($rest, $p); [BitConverter]::GetBytes([single]$y).CopyTo($rest, $p + 4); [BitConverter]::GetBytes([single]$z).CopyTo($rest, $p + 8)
    }
    $moved[$how] = 1 + $moved[$how]
  }
  Write-Host ("  {0} lights placed: {1}" -f $n, (($moved.GetEnumerator() | ForEach-Object { "$($_.Value) by $($_.Key)" }) -join ', '))

  $dir = Join-Path $modDir "media\cars\$($tz.Name)"
  New-Item -ItemType Directory $dir -Force | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $dir 'Lights.bin'), $lf.Write())
  [IO.File]::WriteAllBytes((Join-Path $dir 'LightPresets.bin'), $D['lightpresets.bin'])

  if ($GraphFrom -and $GraphFrom[$ci]) {
    # the graph names its animations (.\x.gr2) and bones (root_<bone>); the car must have all of them
    $g = $GraphFrom[$ci]; $gz = Get-ChildItem $cars -Filter "$g.zip" | Select-Object -First 1; if (-not $gz) { throw "No car $g for -GraphFrom" }
    $zz = [IO.Compression.ZipFile]::OpenRead($gz.FullName)
    try { $ge = $zz.Entries | Where-Object { $_.FullName -ieq "Animations/$g.gsf" }; $ms = New-Object IO.MemoryStream; $st = $ge.Open(); $st.CopyTo($ms); $st.Close(); $graph = $ms.ToArray() } finally { $zz.Dispose() }
    $txt = [Text.Encoding]::ASCII.GetString($graph)
    $zz = [IO.Compression.ZipFile]::OpenRead($tz.FullName); try { $have = @($zz.Entries | ForEach-Object { $_.FullName.ToLower() }) } finally { $zz.Dispose() }
    $missing = @([regex]::Matches($txt, '\.\\([A-Za-z0-9_]+\.gr2)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Where-Object { $have -notcontains "animations/$($_.ToLower())" })
    if ($missing) { throw "$c can't use $g's animation graph; it lacks: $($missing -join ', ')" }
    # bones it animates that the car lacks are skipped by the game (FM5's own Z06 graph names a boneGauges it doesn't have)
    $noBone = @([regex]::Matches($txt, 'root_(bone[A-Za-z0-9_]+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Where-Object { $carBoneNames -notcontains $_.ToLower() })
    if ($noBone) { Write-Warning "$c has no $($noBone -join ', ') for $g's animation graph; those animations won't show" }
    New-Item -ItemType Directory (Join-Path $dir 'Animations') -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $dir "Animations\$c.gsf"), $graph)
    Write-Host "  animation graph from $g"
  }
}

$env:FH2_MODS_ROOT = $ws
try {
  $a = @{ Mod = 'car-lights'; Name = $Name; Game = $GameRoot; Layer = $true }; if ($Sqlite) { $a.Sqlite = $Sqlite }
  & (Join-Path $tools '..\build\Build-Mod.ps1') @a 6>&1 3>&1 | Where-Object { "$_" -match '^(Built)' -or $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { Write-Host "$_" }
} finally { Remove-Item Env:FH2_MODS_ROOT }
$release = Join-Path $root "build\$Name"
if ($NoInstall) { Write-Host "Built $release (not installed)"; return }
& (Join-Path $release 'Install.ps1') -GameRoot $GameRoot -AzimuthRoot $AzimuthRoot
