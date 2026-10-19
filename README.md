# fh2-mods

Monorepo for mods for Forza Horizon 2 on PC (game version 1.0.0.64, `Anthem_1.0.0.64_x64__8wekyb3d8bbwe`).

Requires **Azimuth 0.9.10** and **[FH2 Extra Options](https://github.com/RokkuDayo/ForzaHorizon2_ExtraOptions)** built for it (`winmm.dll`, `FH2_ExtraOptions.ini` and `Gamerpic.png` beside `azimuth.exe`). Azimuth 0.9.9 with Extra Options 0.2.74 or later (in `data\bin`) also works. Mods install into `Mount\mediapc`, which Extra Options mounts over the game's media folder (`[Files] EnableMediaOverrides=1`). The game's own files, `hash.manifest` and `azimuth.exe` are never changed.

Azimuth 0.9.10 checks the game folder against version 1.0.0.64's own files: point it at a folder with the original `Mount\hash.manifest` (an importer 1.x install changed it). Its saves live in `<Azimuth folder>\data\titles\1A96545B\saves`; moving from 0.9.9, copy that `saves` folder to the same place, and set the launcher's options again (they start at the console's defaults, e.g. Car detail).

| Mod | Description |
|---|---|
| [cockpit-fov](mods/cockpit-fov) | Cockpit/driver camera FOV 48 → 70 |

The earlier dlc-unlock, stock-wheel-swap and photomode-unbound mods are retired: Extra Options does the same things (DLC unlock, stock rims for every car, photo mode limits) without changing game files.

| Tool | Description |
|---|---|
| [FM5 car importer](#importing-fm5-cars) | Brings Forza Motorsport 5 cars into FH2 from your own FM5 install (double-click `Import-Fm5Cars.cmd`). Release package: `tools\release\Make-ImporterRelease.ps1 -Version <x.y.z>`; user docs in `release/fm5-car-importer` |
| [fh2net](tools/online) | Experimental online free roam over a LAN or the internet through a server you run. Release package: `tools\release\Make-NetRelease.ps1 -Version <x.y.z>`; user docs in `release/fh2net` |
| [Car sound tuner](#car-sound-tuner) | Sliders for any car's sound: exhaust, engine and intake volume, idle, highs, lows and grit, the sub-bass layer, backfires, turbo, superchargers, blow-off valve (double-click `Tune-CarSound.cmd`). Release package: `tools\release\Make-SoundTunerRelease.ps1 -Version <x.y.z>`; user docs in `release/car-sound-tuner` |
| [Turbo / supercharger volume](#turbo-and-supercharger-volume) | Makes any car's turbo, positive-displacement (DSC) or centrifugal (CSC) supercharger sound louder or quieter (double-click `Set-BoostVolume.cmd`) |
| [Time and weather menu](#time-and-weather-menu) | Floating in-game menu to set the time of day, freeze the clock and change the weather (by thekkeith55) |
| [fh2wheels](#fh2wheels) | Front/rear wheel offset and tire profile upgrades, a rear rim style, rim sizes from 13" to 24", tire widths from 185 to 395 mm and drag/rally tires for every car under Tires & Rims, wider ride height and camber tuning (an Azimuth DLL plus the `mods/fh2wheels` gamedb mod). Release package: `tools\release\Make-WheelsRelease.ps1 -Version <x.y.z>`; user docs in `release/fh2wheels` |

## Layout

```
mods/<name>/
  README.txt                              shipped in the release zip ({{MANIFEST_VALUES}} is filled in by the build)
  media/...                               changes only, mirroring the game's media folder:
    <Archive>.zip/<entry>                   a folder named like a zip holds replacement/new entries for that zip
    <Archive>.zip/<entry>.set               "key value" lines patched into that ini entry (other keys untouched)
    stripped/gamedbRC.slt/<patch>.sql       a folder named like a .slt holds SQL patches, applied in name order
    <path>/<file>                           anything else is a loose file, copied as-is
    <path>/<file>.set                       "key value" lines patched into the game's loose <file> (e.g. physics/PhysicsSettings.ini)
  imports.txt                             files to copy in: "<FH2 media path> <- <FM5 media path>", or "<- fh2:<path>" to take one from the base game (a .zip segment = entry inside it; missing zips are created)
tools/
  build/
    Build-Mod.ps1                         builds dist/<name>.zip from stock (or installed, -Layer) game files + one or more mods
    StockSource.ps1                       reads base game files from the game package or a game folder (mediapc first)
    Repack-ForzaZip.ps1                   repacks a media zip in FH2's native format and updates zipmanifest.xml
    stock-hashes.json, stock-cars.txt     stock file hashes and car list (no game data)
  release/
    Install.ps1, Uninstall.ps1            bundled into every release zip
    Make-ImporterRelease.ps1              packages the FM5 car importer
    Make-NetRelease.ps1                   packages fh2net and its server
    Make-SoundTunerRelease.ps1            packages the car sound tuner
    Make-WheelsRelease.ps1                packages fh2wheels
  online/
    probe/                                fh2net (the Azimuth DLL; build.ps1 builds it with Zig 0.13)
    server/                               fh2srv.py, the game services + relay server
  fm5-import/
    Import-Fm5Cars.ps1                    the FM5 car importer (Import-Fm5Cars.cmd runs it)
    Export-Fm5Car.ps1                     generates one FM5 car's import mod (SQL patch, imports, README)
    Add-ImportedCarWheels.ps1             puts already-imported cars' wheels in the wheel shop
    WheelSwap.ps1                         shared wheel-shop helper (brands, names, wheel zips)
    ForzaModel.cs                         .modelbin (burG) reader/writer + structure check
    Fm5ModelConverter.cs                  converts FM5 car models/materials for FH2's shaders
  audio/
    Set-BoostVolume.ps1                   turbo / supercharger volume per car (Set-BoostVolume.cmd runs it)
    FmodBank.cs                           finds those sounds in a car's FMOD bank and sets their volume; lists a bank's layers
    Show-CarSound.ps1                     lists what a car's sound is made of (events, sheets, RPM layers, samples, volumes)
    Tune-CarSound.ps1                     the slider window (Tune-CarSound.cmd runs it)
    CarSound.ps1                          shared by the two: folders, car list, writing a tuned bank and car-sound.json
  weather-menu/
    FH2WeatherMenu.cs, build.ps1          the time and weather menu and its build script
  wheels/
    fh2wheels.c, menu.c, wheels.c, ...    fh2wheels (the Azimuth DLL; build.ps1 builds it with Zig 0.13, Install.ps1 installs it)
    make_gamedb.py                        writes mods/fh2wheels' SQL and strings.h (the menus' text)
  re/
    memfloat.py                           find / show / set floats in the running game (reverse engineering)
    FH2-Time-Weather-Menu-Guide.docx      its user guide
  bin/                                    downloaded sqlite3.exe (not committed)
```

Game files aren't committed. Builds read stock files from the game package, so they never depend on an already-modded install.

Database mods are SQL patches, not modified copies of the database. Each build starts from the stock `gamedbRC.slt` and runs every patch in a transaction, so database mods combine instead of overwriting each other.

## Building

```powershell
.\tools\build\Build-Mod.ps1 -Mod cockpit-fov -Package G:\FH2-1\Anthem_1.0.0.64_x64__8wekyb3d8bbwe.zip
.\tools\build\Build-Mod.ps1 -Mod cockpit-fov,my-other-mod -Name my-setup     # several mods in one install
```

- `-Package` can be set once via the `FH2_PACKAGE` environment variable.
- SQL patches need [sqlite3.exe](https://www.sqlite.org/download.html) (the "sqlite-tools" bundle): pass `-Sqlite <path>`, set `FH2_SQLITE`, or put it on `PATH`.
- Mods apply in the order given; on conflicts the later mod wins. Output goes to `dist/`.
- Mods with FM5 sources in `imports.txt` need the FM5 install: pass `-Fm5Media <FM5 Mount\media>` or set `FH2_FM5_MEDIA`.

Every release zip contains `install.json` (each file with its SHA-256 and the SHA-256 of the base file it replaces), `Install.ps1` and `Uninstall.ps1`. The installer checks the game version and that Extra Options is installed in Azimuth (`winmm.dll` beside `azimuth.exe`, or 0.2.74+ in `data\bin`), turns on `[Files] EnableMediaOverrides=1` in `FH2_ExtraOptions.ini`, puts every file under `Mount\mediapc`, refuses to overwrite files that differ from the base unless `-Force`, and backs up what it replaces (`mod-backups\<name>-<time>`); the uninstaller restores everything, refusing if files changed since (so with several mods installed, uninstall newest first).

`Build-Mod.ps1 -Layer -Game <folder>` builds on top of what's installed in that game folder (`Mount\mediapc` first, then `Mount\media`: earlier car imports, a modded gamedb) instead of stock files, so mods stack. Such a release installs only onto exactly that state.

## Adding new files (imported cars)

Azimuth only exposes files listed in `Mount\hash.manifest`, its file index, so new files in `Mount\media` are invisible to the game. Extra Options' media overrides don't have that limit: with `EnableMediaOverrides=1`, a file in `Mount\mediapc` (or `mediaoverride`) replaces or adds to `game:\media`, listed or not. New car zips still need their `zipmanifest.xml` entries (a car zip the game can't open crashes it at startup), so the build ships a full `zipmanifest.xml` into `mediapc` too.

To remove every mod by hand, delete `Mount\mediapc`: the game's own `Mount\media` is untouched.

Earlier releases (importer 1.x, for Azimuth 0.9.7) patched `hash.manifest` and `azimuth.exe` instead; uninstall those with the `Uninstall.ps1` in their `mod-backups` folder before switching.

## Importing FM5 cars

**Double-click `Import-Fm5Cars.cmd`** (or run `tools\fm5-import\Import-Fm5Cars.ps1` with no parameters) and it asks for everything: your Azimuth, FH2 and FM5 folders (remembered; the FH2 folder is read from Azimuth's settings when possible), then the FM5 cars to import - type part of a name and pick from the matches - and per car a **data donor** (an FH2 car of the same kind; a match is suggested) a **sound donor** (any FH2 car whose engine sound to use), and the **Autoshow group** to list it in (Retro Muscle, Modern Muscle, Super GT, ... from a numbered list; Enter keeps the data donor's; the group also decides which wheel-shop category the car's wheel goes in). Imports stack: each run adds its cars on top of whatever is installed (earlier imports, a modded gamedb), and cars the game already has aren't offered. This repo ships no game files: everything is read from your own installs. You need FH2 1.0.0.64 on Azimuth 0.9.10 with its Extra Options build (or 0.9.9 with Extra Options 0.2.74+), and FM5 1.0.0.20. `sqlite3.exe` is used from PATH or downloaded from sqlite.org (hash-checked) into `tools\bin`.

```powershell
# which FM5 cars FH2 doesn't have
.\tools\fm5-import\Import-Fm5Cars.ps1 -ListFm5Only -Fm5Root "D:\Forza_1.0.0.20_x64__8wekyb3d8bbwe" -GameRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe"

# or non-interactive: one data donor per car; -SoundCar "" = the data donor's sound; -Group "" = the data donor's group
.\tools\fm5-import\Import-Fm5Cars.ps1 -Fm5Root "D:\Forza_1.0.0.20_x64__8wekyb3d8bbwe" -GameRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe" -AzimuthRoot "D:\azimuth" `
    -Car PON_TransAm_02,AST_DBS_09 -Donor PON_TransAmGTA_87,AST_DBSTF_08 -SoundCar CHE_CorvetteZR1_95,"" -Group 'Retro Muscle',"" `
    -LightDonor PON_TransAmGTA_87,AST_DBSTF_08 -WhiterHeadlights
```

It checks the game version, generates each car's mod in a private workspace, builds one install on top of your current game files (models converted for FH2's shaders), and installs it with backups. Each run gets its own backup folder (`mod-backups\fm5-cars-<time>`, with the run's car list in `cars.json`); undo a run with the `Uninstall.ps1` kept there, newest run first. `-NoInstall` builds only.

Each imported car's stock wheel is also put in the wheel shop for any car, as Extra Options' stock rims do for FH2's own cars (its own wheel zip, converted from FM5, named from FM5's string table; `tools\fm5-import\WheelSwap.ps1`). `-NoWheelSwap` on `Export-Fm5Car.ps1` skips it. For cars imported before this, run `tools\fm5-import\Add-ImportedCarWheels.ps1`: it finds imported cars (FM5 cars not in `tools\build\stock-cars.txt`) whose wheel isn't in the shop and installs their wheels as one more layer.

### Night lights (experimental)

The importer asks for a **light donor** per car (default: the data donor, or the nearest car of the same make with lights; `none` skips) and, if that donor's headlights are the warm `HALOGEN_B`, whether to use whiter ones (the '87 GTA's `HALOGEN_A`). After the cars are installed it runs `Add-CarLights.ps1` for them as a second layer (`mod-backups\fm5-cars-lights-<time>`); undo that one first. Non-interactive: `-LightDonor` (one per car, `""` = none) and `-WhiterHeadlights`.

FM5 cars have no night lighting data, so imported cars are dark at night. `tools\fm5-import\Add-CarLights.ps1 -Car <imported car> -Donor <FH2 car>` transplants it from a similar FH2 car (one with pop-ups for a pop-up car) and installs it as a layer:

- `Lights.bin` lists the lamp meshes (with light ids) and the light sources (kind: headlight 17, tail/brake/reverse 1/32/69, CHMSL 0; the lamp mesh it belongs to; two poses in car space). The donor's lamp meshes are matched by role (side, headlight/taillight/CHMSL/fog, glass/bulbs/housing) to the car's own. Each light moves by the offset between the donor's lamp and the car's lamp; lights on pop-up headlights (lamp meshes modelled in the `boneHeadlightL/R` bone's space) move by the offset between the two cars' headlight bones; anything else is placed relative to the bumper.
- `LightPresets.bin` (beams, intensities, projection textures) is copied as is.

```powershell
.\tools\fm5-import\Add-CarLights.ps1 -Car PON_TransAm_02,CHE_CorvetteZ06_02 -Donor PON_TransAmGTA_87,CHE_CorvetteZR1_95
```

### One car as a repo mod

For a car you want to ship from the repo as its own mod (the importer is the usual way; the 2002 Trans Am that used to live in `mods/` is just `Import-Fm5Cars.cmd` now):

```powershell
.\tools\fm5-import\Export-Fm5Car.ps1 -CarId 1065 -Fm5Media G:\FM5\Forza_1.0.0.20_x64__8wekyb3d8bbwe\Mount\media
```

The exporter walks every gamedb row the car depends on and writes them as INSERTs. It never overwrites an FH2 row; it reports key conflicts instead. Shared engines/drivetrains/bodies only get part rows FH2 has none of. It also lists the FM5 files to import. What carries over: the car zip (including the v13 `physicsdefinition.bin`), the audio tuning XML, and the thumbnail (added into `stripped\RC0.zip`). Engine sound: pass `-EngineSound <FH2 engine>` to borrow an FH2 bank (FM5's `<engine>.bank` renamed to `PG_<engine>.bank` was silent for the Trans Am). FH2-only `Data_Car` columns and the `Data_Car_Buckets` row come from a donor FH2 car (default: same make, closest year).

### Model conversion (automatic in the build)

FH2 compiles each shader variant for one vertex format: in FH2's own cars a mesh's vertex layout holds exactly the `TEXCOORD`/`TANGENT` inputs its shader reads (1,074 of 1,082 mesh parts in the '87 GTA; mesh parts reference materials, layouts and buffers by `Id` metadata, not position). FM5 layouts differ, so FM5 glass, lenses, badges and decals render as nothing or garbage. For every FM5 car zip in `imports.txt` the build:

- reads each material's FH2 shader input signature (DXBC `ISGN` of all its `.vso` programs) and rewrites each layout to exactly that set, copying missing UV sets from the nearest one (TEXCOORD4 from TEXCOORD2, with its UV transform) and computing missing tangents (validated against FH2's own tangents: 99/99 and 722/722 vertices match)
- gives FM5 window glass (`gls_window`, `gls_windsheild`, interior variants) FH2's material parameter override (`0xF2FDFE8E` = 0); without it panes aren't drawn
- redirects car-local materials whose shader is FM5-compiled inside the car (missing FH2's `SimpleCarLightScenario`) to the FH2 library material of the same name minus the `CH1` tag (`gls_limotintCH1_001` -> `gls_limotint_001`)
- re-checks every converted model's structure before packing

## Car sound tuner

**Double-click `Tune-CarSound.cmd`**: type part of a car's name, pick it, move the sliders and press **Apply** with the game closed. Every slider adds to the car's stock sound (0 = stock; hover a slider for what it does):

| Tab | Sliders |
|---|---|
| Exhaust, Engine, Intake | **Volume** (every layer), **Idle** (the layer recorded at the lowest RPM, e.g. `Exhaust_00720`), **Highs** / **Lows** (the high band of the tracks' 3-band EQs / the low band of the group's EQ; the window shows the resulting EQ gain, at most +10 dB), **Grit** (the Turn10Saturator's drive) |
| Turbo & other | Turbo (its upgrade-level sounds), **Boost whistle** (the spool whistle and air loops on the `Boost` sheet: `WhistleLooping`, `AirLooping`; 318 cars), DSC and CSC superchargers, blow-off valve, backfires, the low-frequency (LFE) layer |

The car's bank is built from the game's own each time and written to `Mount\mediapc`, so Revert / Reset to stock / Apply can be used freely; settings are kept per car in `Mount\mediapc\audio\fmodanthem\durango\car-sound.json` and shared with `Set-BoostVolume`. Found by experiment on the 1968 Dart: one layer much past +20 dB distorts, and so does a few boosted layers that play together (idle exhaust +20 with engine and intake idle +12); a boomy car gets better with the LFE layer down and Lows down, and the exhaust's Highs up adds crackle. Every car's off-throttle burble track is automated (by RPM), so it has no slider yet. Coverage over the 351 car banks: exhaust 349 (EQ 344, grit 323), engine 327, intake 329, backfires 350, LFE layer 96.

## Turbo and supercharger volume

**Double-click `Set-BoostVolume.cmd`**, pick the cars (type part of a name like `mustang` and pick numbers from the list of matches, which shows each car's sounds and current setting; or `all`) and type the dB to add to each sound (Enter keeps the current setting), including the blow-off valve (BOV): turbo, positive-displacement supercharger (DSC), centrifugal supercharger (CSC). +6 dB is about twice as loud; +24 (the most) is loud. Close the game first.

```powershell
.\tools\audio\Set-BoostVolume.ps1 -Car FOR_MustangGT500_13 -DSC 12        # louder supercharger whine
.\tools\audio\Set-BoostVolume.ps1 -Car all -Turbo 6 -DSC 6 -CSC 6          # every car
.\tools\audio\Set-BoostVolume.ps1 -List -Car '*Mustang*'                   # which sounds each car has, what's set
.\tools\audio\Set-BoostVolume.ps1 -Remove                                  # back to stock (or -Remove -Car ...)
```

Each car's sound is an FMOD bank (`Mount\media\audio\fmodanthem\durango\PG_<car>.bank`). The game sets `TurboUpgradeLevel`, `DSCUpgradeLevel` or `CSCUpgradeLevel` (1-3, the fitted part's level) from the car's upgrades; each of the car's events has a sheet per parameter holding nested events, which are the turbo and supercharger sounds. The tool sets those nested events' master-track volume (stock + your dB; `FmodBank.cs` has the format) and writes the bank to `Mount\mediapc`, from your own game's bank each time, so a re-run replaces the change; values you don't pass keep what was set before. FH2 plays the same turbo sounds for single and twin turbos, so `-Turbo` is both. Blow-off sounds (samples named bov / Blowoff / DumpValve) play on tracks of their own; `-BOV` sets those tracks' volume, on top of `-Turbo` where the track is inside a turbo sound (tracks that also play other samples are left alone: 3 cars). Of 351 car banks, 321 have turbo sounds, 312 BOV, 143 DSC and 99 CSC. Imported FM5 cars use the bank of the FH2 car their sound was borrowed from. What the tool wrote is listed in `Mount\mediapc\audio\fmodanthem\durango\boost-volume.json`; banks another mod put there are left alone.

### What a car's sound is made of

`.\tools\audio\Show-CarSound.ps1 -Car dart` lists every layer of a car's bank, per event: the parameter sheet it's on and where (RPM range on `EngineRPM`), its samples, its volume (dB; "auto" when a parameter drives it). Playground's names are the same in every bank: `Exhaust_<rpm>`, `Engine_<rpm>` and `Intake_<rpm>` are loops recorded at that RPM, crossfaded on `EngineRPM` sheets (`Exhaust_00720` is the idle); `Burble_A` plays off throttle (`Throttle` 0-0.1); `BackFire`, `Backfire_V` and `Backfire_POP_LFE` (low-frequency pop) are triggered; `WhistleLooping` / `AirLooping` follow `Boost`; `GTI_Shifter`, `PaddleShifter`, `ClutchPedal` and `TNS_damage` (missed shift) are the drivetrain noises. Other parameters the game sets: `PosTorque` / `NegTorque`, `Gear`, `View` / `Angle` (camera), reverb and wall distances.

## Time and weather menu

By thekkeith55. A small floating window that changes the time of day and the weather in a running FH2 session by editing the game's memory; it doesn't touch any game, launcher or save files. Full guide: [FH2-Time-Weather-Menu-Guide.docx](tools/weather-menu/FH2-Time-Weather-Menu-Guide.docx).

**Build** (uses the .NET Framework compiler that ships with Windows):

```powershell
.\tools\weather-menu\build.ps1      # writes tools\weather-menu\FH2WeatherMenu.exe
```

**Use:**

1. Start FH2 through Azimuth and load into single-player free roam.
2. Run `FH2WeatherMenu.exe` and click **Connect** (it shows the process ID and the game time once attached).
3. **Time:** pick a preset (Dawn 06:00, Noon 12:00, Sunset 19:00, Midnight 00:00) or set decimal hours with the arrows (18.50 = 18:30), then **Set time**. **Freeze time** stops the day/night cycle.
4. **Weather:** **Clear** or **Rain**, or set the atmosphere, rain and environment sliders (0-100%) and **Apply**. **Hold weather override** re-applies them every 200 ms.
5. **F6** shows/hides the menu. **Restore / release** puts back everything the menu changed (also attempted on close); a time you set stays, but the clock resumes.

The menu never takes focus from the game (so FH2 doesn't pause): use the mouse; typing in the time field isn't possible. It checks the game's code signatures and world pointers before writing and disconnects when the world reloads; reconnect after loading. Use it in free roam: races and cutscenes apply their own time and weather. Needs FH2 1.0.0.64 and the same Windows privilege level as Azimuth. The weather buttons are intensity combinations, not the game's named weather presets.

| Problem | Fix |
|---|---|
| Can't connect | Run exactly one Azimuth, load into free roam, Connect again |
| Access denied | Run the menu and Azimuth at the same privilege level |
| Unsupported signature | Only FH2 1.0.0.64 is supported |
| Disconnected after loading | Reconnect once the new world has loaded |
| F6 already in use | Close the other menu or app using F6 |

Ideas for later (not implemented or verified): car repair/clean/headlights, saved positions and teleport, traffic and grip/power testing controls, camera FOV/free camera/HUD, car and engine ID display for mod testing, and saved presets.

## fh2wheels

Wheel and suspension options in the garage, for every car (imported ones included):

- **Front / Rear Wheel Offset** under Tires & Rims: Stock, -20 to +50 mm a side in 5 mm steps, then +75, +100 and +150 mm. Previewed live; the wheel camera, no performance graph.
- **Front / Rear Tire Profile**: aspect ratio -30 to +35 points (a 255/40 with +10 becomes a 255/50 on the same rim).
- **Rear Rim Style**: a different rim on the rear axle, beside the game's Rim Style tile (which fits all four). Kept in the garage's unused `TireBrand` column; at start the DLL reads the rear rims back from the newest save revision, since the game doesn't (a car's rear rim is found by its front rim). Needs an aftermarket front rim.
- **Rim sizes from 13" to 24"** (the most the game draws) and **tire widths from 185 to 395 mm** for every car, front and rear, besides its own (lighter or heavier as the game's own options).
- **Drag and rally tires** for every car that doesn't have them.
- **Tuning**: ride height 10 cm lower and 40 cm higher on adjustable springs, camber -15 to 15 degrees.

It has two halves:

- **`fh2wheels.dll`** (`tools\wheels`): an Azimuth DLL in the `data\bin\azimuth-tls.dll` chain, like fh2net (it forwards to `fh2wheels-next.dll`, fh2net to `azimuth-tls-next.dll`, so they stack in either order). Build with `tools\wheels\build.ps1`, install with `tools\wheels\Install.ps1 -Azimuth <folder>` (`-Uninstall` removes it). The game has a fixed set of part slots, so the offsets and profiles borrow four that ordinary cars don't use (Restrictor Plate, Motor Parts, Quad Turbo, Motor) and the DLL keeps the game from treating them as engine parts; it applies the values when the car is built, adds the parts to the upgrade lists, sets the camera and supplies the menus' text. `fh2wheels.ini` `[offsets]` can add per-model offsets (`<Data_Car Id>=<front mm>,<rear mm>`); `[debug] SqlLog=` logs the game's SQL.
- **`mods/fh2wheels`**: the gamedb rows (categories, option names, neutral part rows, rim sizes, tire widths and drag/rally tires made in SQL from each car's own rows, ride height ranges; safe to apply again on top, which only adds rows for cars that came since) and the camber range (`physics/PhysicsSettings.ini.set`). Regenerate the SQL with `py -3 tools\wheels\make_gamedb.py`; build on your game with `Build-Mod.ps1 -Mod fh2wheels -Game <folder> -Layer` and install as any mod.

Both halves are needed: without the DLL the offset and profile parts do nothing and their text is blank.

## How FH2 loads media zips

Editing a zip with WinRAR/7-Zip/Windows doesn't work; the game silently falls back to defaults. Two things must match:

1. **Zip layout.** Every entry is deflated, version 10, with zeroed time/date/attributes, no local-header extra field, and a central-directory extra field with ID `0x1123` holding the absolute offset of the entry's compressed data.
2. **`media\zipmanifest.xml`.** Each zip's `dirstart` (central-directory offset), `dirsize` (central-directory size **+ 22** for the end-of-central-directory record) and `direntries`.

`Repack-ForzaZip.ps1` handles both. It copies unchanged entries' compressed bytes verbatim; repacking an untouched stock zip reproduces it byte-for-byte.

## The game database

`media\stripped\gamedbRC.slt` is a plain SQLite 3 database (cars, upgrades, events, store offers). The game loads the whole file into memory at startup, so changes need a restart. It isn't a zip and has no `zipmanifest.xml` entry.

- `Data_Car.ContentId = 99` marks a car as license-gated (DLC/bonus); `0` means freely available.
- `ContentOffers` / `ContentOffersMapping` (`ContentType = 1` = car) link cars to store offers; `OnDiscContent` lists base-game content. A car doesn't need to appear in any of them to be buyable.
