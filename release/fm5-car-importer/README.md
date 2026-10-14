# FM5 Car Importer for Forza Horizon 2 (PC)

Brings cars from **Forza Motorsport 5** into **Forza Horizon 2** running on PC through Azimuth. Pick the cars, answer a few questions, and they show up in the Autoshow: buyable, drivable, upgradable and paintable, with an engine sound, night lights and their wheels added to the wheel shop.

This package contains **no game files**. Everything is read from your own FM5 and FH2 installs and converted on your machine.

## What you need

| | |
|---|---|
| Forza Horizon 2 | version 1.0.0.64 (`Anthem_1.0.0.64_x64__8wekyb3d8bbwe`), running on **Azimuth 0.9.7** |
| Forza Motorsport 5 | version 1.0.0.20 (`Forza_1.0.0.20_x64__8wekyb3d8bbwe`), any folder (it isn't run, only read) |
| Windows | 10 or 11, with the built-in Windows PowerShell 5.1 |
| Internet | once, to download `sqlite3.exe` from sqlite.org (checked against its known hash) |
| Disk | about 20-80 MB per imported car, plus backups |

## Quick start

1. Extract this zip anywhere (for example `C:\FH2-Mods\fm5-car-importer`). Keep the folders together.
2. Close Azimuth / the game.
3. Double-click **`Import-Fm5Cars.cmd`**.
4. Answer the questions (see below). Enter accepts the suggested answer.
5. Start the game through `azimuth.exe`. Your cars are in the Autoshow.

The first run asks where Azimuth, FH2 and FM5 are and remembers them. If Azimuth already knows your FH2 folder, that's suggested.

## The questions, per car

| Question | What to answer |
|---|---|
| **FM5 car to add** | Type part of the name (`transam`, `corvette 2002`, `mustang 1995`) and pick a number from the matches. Only cars FH2 doesn't already have are offered. Add as many as you like; press Enter on an empty line when done. |
| **Data donor** | An FH2 car of the same kind (era, body style, drivetrain). It supplies the bits of car data FH2 has and FM5 doesn't. A same-make, nearest-year car is suggested. |
| **Sound donor** | An FH2 car whose engine sound the import uses (FM5's own engine sounds don't play in FH2). Pick a car with a similar engine: a V8 for a V8. |
| **Autoshow group** | Where the car is listed (Retro Muscle, Modern Muscle, Super GT, ...). Enter keeps the data donor's group. It also decides which wheel-shop category the car's wheels go in. |
| **Light donor** | An FH2 car with similar lamps whose night lights are fitted to the import (FM5 has no night, so its cars come without lighting data). Use a car with pop-up headlights for a pop-up car. Type `none` to skip. |
| **Use whiter headlights?** | Asked when the light donor has warm, orange-ish halogen headlights. Yes gives a whiter halogen. |

Then it shows the plan, asks to proceed, converts the cars (about a minute each) and installs them.

## What it installs, and how to undo it

Each run is installed as a **layer** on top of whatever is already in your game, with its own backup folder in `<FH2 folder>\mod-backups\`:

- `fm5-cars-<date-time>` - the cars of that run (their car list is in `cars.json`)
- `fm5-cars-lights-<date-time>` - their night lights, if you picked light donors

To undo a layer, run the `Uninstall.ps1` inside its backup folder (right-click > Run with PowerShell, or see the guide). **Undo layers newest first**: the uninstaller refuses to touch files that a later layer changed.

Imports stack: run the importer again any time to add more cars; the cars you already imported stay.

## Good to know

- The importer edits the game's database, car and wheel archives, `zipmanifest.xml` and Azimuth's file index (`Mount\hash.manifest`), and patches `azimuth.exe` so it accepts the new index. Everything it changes is backed up first.
- Imported car **names show blank** in menus (FH2 has no text for them).
- Engine **sounds are borrowed** from the sound donor.
- Night lights are transplanted from the light donor and fitted to the car; they are close but not always perfect. Some lens glass glows warmer than it should.
- Some cars' pop-up headlights don't rise. See the guide for the fix that worked for the 2002 Trans Am.
- Keep this folder: you need it to add more cars later. Your settings are remembered in `%LOCALAPPDATA%\fh2-mods\import-fm5-cars.json`.

The full walkthrough, advanced options (tuning lights, adding wheels for older imports, command-line use) and troubleshooting are in **[GUIDE.md](GUIDE.md)**.
