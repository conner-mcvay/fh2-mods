# FM5 Car Importer - Guide

1. [Installing the importer](#1-installing-the-importer)
2. [Importing cars, step by step](#2-importing-cars-step-by-step)
3. [Picking good donors](#3-picking-good-donors)
4. [What happens to your game](#4-what-happens-to-your-game)
5. [Undoing an import](#5-undoing-an-import)
6. [Night lights: tuning and fixes](#6-night-lights-tuning-and-fixes)
7. [Wheels in the wheel shop](#7-wheels-in-the-wheel-shop)
8. [Command-line use](#8-command-line-use)
9. [Troubleshooting](#9-troubleshooting)
10. [Known limitations](#10-known-limitations)
11. [What's in this package](#11-whats-in-this-package)

---

## 1. Installing the importer

1. **Unblock the zip** before extracting: right-click the downloaded zip > *Properties* > tick **Unblock** > *OK*. (Windows marks downloaded files; unblocking avoids security prompts for each script.)
2. **Extract** it to a folder you'll keep, e.g. `C:\FH2-Mods\fm5-car-importer`. Don't run it from inside the zip.
3. Have ready:
   - your **Azimuth** folder (the one with `azimuth.exe`, version 0.9.7)
   - your **FH2** game folder (the one with `Mount\forza_durango_release_final.exe`, FH2 1.0.0.64)
   - your **FM5** game folder (the one with `Mount\media\db\gamedb.slt`, FM5 1.0.0.20)

Nothing is installed into Windows. The importer is a set of PowerShell scripts run by `Import-Fm5Cars.cmd`. On first use it downloads `sqlite3.exe` (the official sqlite-tools build, checked against its known SHA-256) into `tools\bin`.

## 2. Importing cars, step by step

**Close Azimuth first** (the game and the launcher): the installer refuses to change files the game is using.

Double-click `Import-Fm5Cars.cmd`. A console window opens:

```
FM5 -> FH2 car importer

Azimuth folder [C:\Games\azimuth]:
FH2 game folder [C:\Games\Anthem_1.0.0.64_x64__8wekyb3d8bbwe]:
FM5 game folder:
```

Paste or type each folder (quotes are fine) or press Enter to accept the suggestion in brackets. These are remembered for next time.

If you've imported cars before, they're listed first ("Already imported"); they stay installed.

**Pick a car.** Type part of its name; you get a numbered list of matches:

```
FM5 car to add: camaro
    1) CHE_Camaro35thAnniversary_02   2002
    2) CHE_CamaroZ28_79                1979
FM5 car to add: 1
  CHE_Camaro35thAnniversary_02 (2002)
```

Typing the exact name (e.g. `PON_TransAm_02`) or its FM5 car Id picks it directly. Only FM5 cars FH2 doesn't already have are offered.

**Answer the per-car questions** (Enter takes the suggestion in brackets; for donors you can search the same way as for cars):

```
  Data donor [CHE_CorvetteZR1_09]:
  Sound donor [CHE_CorvetteZR1_09]:
  Autoshow group [Modern Muscle > Retro Muscle]:
  Light donor [CHE_CamaroIROCZ_90]:
  CHE_CamaroIROCZ_90's headlights are a warm, orange-ish halogen. Use whiter ones? [Y/n]
```

- **Autoshow group** shows a numbered list of all groups with how many cars each has; type the number or part of the name.
- **Light donor**: type `none` for no night lights.

Add more cars the same way, then press Enter on an empty "FM5 car to add" line. The importer shows the plan:

```
Import plan:
  CHE_Camaro35thAnniversary_02 data donor CHE_CorvetteZR1_09  sound CHE_CorvetteZR1_09 (...), group Retro Muscle, lights CHE_CamaroIROCZ_90 (whiter headlights)
Proceed? [Y/n]
```

It then exports each car, converts its models for FH2 (about a minute per car), installs the cars, and fits their night lights as a second step. When it says **Done**, start the game through `azimuth.exe` and look in the Autoshow under the group you chose.

## 3. Picking good donors

| Donor | Pick | Why |
|---|---|---|
| Data donor | Same era and type: muscle for muscle, JDM for JDM, a hatchback for a hatchback | Fills FH2-only car data and the default Autoshow group |
| Sound donor | Similar engine (V8 for V8, flat-six for flat-six, turbo four for turbo four) | FM5 engine sounds don't play in FH2; the car uses this one |
| Light donor | Similar lamps and shape. **Pop-up headlights need a pop-up donor** | Lights are transplanted and fitted to your car's lamps |

Good pairs found so far:

| FM5 car | Light donor | Notes |
|---|---|---|
| 2002 Pontiac Trans Am (`PON_TransAm_02`) | `PON_TransAmGTA_87` | pop-ups need the animation graph fix, see [6](#pop-ups-dont-rise) |
| 2002 Corvette Z06 (`CHE_CorvetteZ06_02`) | `CHE_CorvetteZR1_95` | `-HeadlightStyle outer-bulb` for the low-beam-only glow |
| 2002 Camaro 35th Anniversary (`CHE_Camaro35thAnniversary_02`) | `CHE_CamaroIROCZ_90` | `-HeadlightStyle outer-bulb`, whiter headlights |

## 4. What happens to your game

For each run, in your FH2 folder:

| Changed | How |
|---|---|
| `Mount\media\stripped\gamedbRC.slt` | the cars' rows (car, engines, upgrades, Autoshow group, wheel) are added; nothing existing is changed |
| `Mount\media\cars\<car>.zip` | new: the FM5 car, converted for FH2's shaders |
| `Mount\media\cars\_library\scene\wheels\<wheel>.zip` | new: the car's wheel for the wheel shop |
| `Mount\media\stripped\RC0.zip` | the car's thumbnail, when FM5 has one |
| `Mount\media\zipmanifest.xml` | entries for the new and changed archives |
| `Mount\hash.manifest` | Azimuth's file index, with the new files added (otherwise the game can't see them) |
| `azimuth.exe` | patched to accept the new index (any Azimuth 0.9.7, stock or already patched) |

Every replaced file is backed up first, to `<FH2 folder>\mod-backups\<layer>-<date-time>\`, together with a `restore.json` and an `Uninstall.ps1`. Nothing else on your PC is touched, and FM5 is only read.

Each run builds on top of what's installed, so imports stack with each other and with other mods made the same way (installed through their own `Install.ps1`).

## 5. Undoing an import

Open `<FH2 folder>\mod-backups\`. Each run left one or two folders:

```
fm5-cars-20261013-221123          the cars (cars.json lists them)
fm5-cars-lights-20261013-221300   their night lights
```

**Always undo the newest layer first.** Right-click its `Uninstall.ps1` > *Run with PowerShell*, or from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<FH2 folder>\mod-backups\fm5-cars-lights-20261013-221300\Uninstall.ps1" -BackupRoot "<FH2 folder>\mod-backups\fm5-cars-lights-20261013-221300"
```

The uninstaller restores the backed-up files and `azimuth.exe`, deletes the files the layer added, and marks the backup as used (`uninstalled.txt`). If a newer layer changed the same files it refuses ("Changed since installation ... uninstall mods newest first"): undo that newer layer first.

To remove a car that isn't in the newest layer, undo layers back to it, then re-import the cars you want to keep.

## 6. Night lights: tuning and fixes

The importer runs `tools\fm5-import\Add-CarLights.ps1`. You can run it yourself to redo or tune a car's lights. It installs as its own layer (`car-lights-<date-time>`), so **first undo the car's current lights layer** if it has one.

From PowerShell in the importer folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\fm5-import\Add-CarLights.ps1 -Car CHE_CorvetteZ06_02 -Donor CHE_CorvetteZR1_95 -HeadlightStyle outer-bulb -PresetFrom PON_TransAmGTA_87
```

Several cars at once: comma-separated lists, one entry per car (`""` for the default):

```powershell
... -Car PON_TransAm_02,CHE_CorvetteZ06_02 -Donor PON_TransAmGTA_87,CHE_CorvetteZR1_95 -HeadlightStyle '','outer-bulb'
```

| Option | Use |
|---|---|
| `-HeadlightStyle glass` (default) | the whole headlight lens glows |
| `-HeadlightStyle bulbs` | only the bulbs glow |
| `-HeadlightStyle outer-bulb` | only the outer bulb glows, for twin-reflector headlights (low beam) |
| `-PresetFrom <FH2 car>` | use that car's headlight colour and beam pattern, e.g. `PON_TransAmGTA_87` for a whiter halogen |
| `-HeadlightColor r,g,b` | set the headlight colour directly (0-1), e.g. `1,0.95,0.85`. FH2's own halogens are `1,0.8,0.6`, `1,0.7,0.4` and `1,0.5,0.3` |
| `-GraphFrom <car>` | use another car's animation graph (see below) |
| `-NoInstall` | build only, to `build\car-lights` |

### Pop-ups don't rise

Some FM5 cars' animation graphs don't raise their pop-up headlights in FH2 (the 2002 Trans Am's doesn't, the 2002 Corvette's does). Giving the car another FM5 import's graph fixed it for the Trans Am:

```powershell
... -Car PON_TransAm_02 -Donor PON_TransAmGTA_87 -GraphFrom CHE_CorvetteZ06_02
```

The Corvette must be imported for this. The tool checks that the car has all the animations the graph uses; a warning about a missing bone (like `boneGauges`) only means a dash needle won't move.

## 7. Wheels in the wheel shop

Every imported car's stock wheel is added to the wheel shop (under its brand, in the category of its Autoshow group), so it can be fitted to any car. Thumbnails are blank.

Cars imported **before** this feature (or by hand) can get theirs with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\fm5-import\Add-ImportedCarWheels.ps1
```

It finds every imported car whose wheel isn't in the shop yet and installs them as one layer (`fm5-wheels-<date-time>`).

## 8. Command-line use

Everything the questions ask can be passed as parameters (one entry per car; `""` = the default):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\fm5-import\Import-Fm5Cars.ps1 `
  -Fm5Root "D:\Forza_1.0.0.20_x64__8wekyb3d8bbwe" -GameRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe" -AzimuthRoot "D:\azimuth" `
  -Car PON_TransAm_02,CHE_CorvetteZ06_02 -Donor PON_TransAmGTA_87,"" -SoundCar CHE_CorvetteZR1_95,"" `
  -Group 'Retro Muscle',"" -LightDonor PON_TransAmGTA_87,CHE_CorvetteZR1_95 -WhiterHeadlights
```

| Parameter | |
|---|---|
| `-ListFm5Only` | list the FM5 cars FH2 doesn't have, and stop |
| `-Car` | FM5 car names (`MediaName`) or Ids |
| `-Donor` | data donors; `""` = automatic (same make, nearest year) |
| `-SoundCar` / `-EngineSound` | sound donor car, or an FH2 engine name directly |
| `-Group` | Autoshow group name (`'Retro Muscle'`) or Id |
| `-LightDonor`, `-WhiterHeadlights` | night lights |
| `-Name` | layer name (default `fm5-cars`) |
| `-NoInstall` | build only, to `build\<Name>` (lights need the cars installed, so they're skipped) |
| `-Sqlite` | use this `sqlite3.exe` instead of downloading one |

## 9. Troubleshooting

| Message / problem | Fix |
|---|---|
| A window flashes and closes, or "running scripts is disabled" | Run `Import-Fm5Cars.cmd` (it starts PowerShell with `-ExecutionPolicy Bypass`), not the `.ps1` directly. Unblock the zip (section 1). |
| `Close Azimuth first.` | Quit the game and Azimuth, then run again. |
| `Can't read Mount\...; close the game first.` | Same: the game has the file open. |
| `Unsupported game version` / `Unsupported game: needs FH2 1.0.0.64` | Only FH2 1.0.0.64 (`Anthem_1.0.0.64_x64__8wekyb3d8bbwe`) is supported. |
| `Needs the Azimuth 0.9.7 launcher (stock, or patched by another mod)` / `Not an Azimuth 0.9.7 launcher` | Use Azimuth 0.9.7's `azimuth.exe` (stock or patched by these tools). Other versions check the file index differently. |
| `sqlite download failed its hash check` | The download was blocked or changed. Download `sqlite-tools-win-x64-3470200.zip` from sqlite.org yourself, put `sqlite3.exe` in `tools\bin`, and run again. |
| `FM5 car ... not found, or FH2 already has it` | Check the name with `-ListFm5Only`. Cars already in FH2 (stock or imported) can't be imported again. |
| `Donor ... has no engine sound bank` | Pick a different sound donor. |
| `Light donor ... has no light data` | Pick another FH2 car (a few have no lighting data). |
| `These game files changed since this package was built on top of them` | Something changed the game between building and installing. Run the importer again. |
| `Changed since installation, not restoring: ...` when uninstalling | A newer layer changed that file: undo the newer layer first. |
| The game crashes at start after an import | Undo the newest layer and report the car. A car the game can't open makes it crash at start-up. |
| A car is invisible or has missing glass/lights in the Autoshow | Report the car; its models may use shaders the converter doesn't handle yet. |
| No sound | Choose a different sound donor and re-import. |
| Lights in the wrong place, glow too orange, pop-ups down | See section 6. |

## 10. Known limitations

Known bugs:

1. **Dirt mapping needs work**: dirt and grime don't build up on imported cars like on FH2's own.
2. **Lights may be slightly buggy**: night lights are transplanted, close but not exact; some lens glass glows warmer than real; some pop-up headlights need the animation-graph fix (section 6).
3. **Car names need work**: imported cars have no name in menus.
4. **Autoshow thumbnails don't work**; the car's thumbnail does show in the garage.

Other limitations:

- Engine sounds are **borrowed** from an FH2 car.
- Wheel-shop thumbnails for imported wheels are blank.
- Only FM5 1.0.0.20 and FH2 1.0.0.64 on Azimuth 0.9.7 are supported.
- FM5-only interior or livery features that FH2 doesn't have aren't carried over.

## 11. What's in this package

```
Import-Fm5Cars.cmd            double-click to import cars
README.md, GUIDE.md, CHANGELOG.md, LICENSE (MIT)
tools\
  fm5-import\                 the importer
    Import-Fm5Cars.ps1          the questions and the whole run
    Export-Fm5Car.ps1           one car's database rows, files and wheel
    Add-CarLights.ps1           night lights from a donor car
    Add-ImportedCarWheels.ps1   wheels for older imports
    WheelSwap.ps1, CarLights.cs, ForzaModel.cs, Fm5ModelConverter.cs
  build\                      builds an installable layer from the generated mods
    Build-Mod.ps1, StockSource.ps1, Repack-ForzaZip.ps1, ForzaPathKey.cs
    stock-hashes.json, stock-cars.txt   checksums and the stock car list (no game data)
  azimuth\Patch-Azimuth.ps1   lets azimuth.exe accept the extended file index
  release\Install.ps1, Uninstall.ps1    the installer/uninstaller each layer uses
  bin\                        sqlite3.exe goes here (downloaded on first use)
build\                        created while importing (working files; safe to delete between runs)
```

No game files are included or downloaded: cars, models and data come from your own FM5 and FH2 installs.
