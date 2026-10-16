# FM5 Car Importer for Forza Horizon 2 (PC)

Brings cars from **Forza Motorsport 5** into **Forza Horizon 2** running on PC through Azimuth. Pick the cars, answer a few questions, and they show up in the Autoshow: buyable, drivable, upgradable and paintable, with an engine sound, night lights and their wheels added to the wheel shop.

This package contains **no game files**. Everything is read from your own FM5 and FH2 installs and converted on your machine.

## What you need

| | |
|---|---|
| Forza Horizon 2 | version 1.0.0.64 (`Anthem_1.0.0.64_x64__8wekyb3d8bbwe`), running on **Azimuth 0.9.9** |
| FH2 Extra Options | **0.2.74 or later**, installed in Azimuth (`data\bin\azimuth-tls.dll`, or `azimuth-tls-next.dll` when fh2net is installed). The importer turns on its `[Files] EnableMediaOverrides=1` setting. |
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

## Same cars on another PC

1. On the PC with the cars: `Import-Fm5Cars.cmd -ExportList cars.json` writes every imported car with all its choices (donors, sound, group, lights).
2. Copy `cars.json` to the other PC, next to `Import-Fm5Cars.cmd` there.
3. On the other PC: `Import-Fm5Cars.cmd -FromList cars.json` imports them with the same choices. It needs its own FM5 and FH2. Cars that PC already has are skipped, so it's safe to run again.

Run these from a command prompt in the importer folder.

## Known bugs

1. **Dirt mapping needs work**: dirt and grime don't build up on imported cars the way they do on FH2's own.
2. **Lights may be slightly buggy**: night lights are transplanted from the light donor and fitted to the car, so glows can sit a little off, some lens glass glows warmer than it should, and some cars' pop-up headlights don't rise (see the guide for the fix that worked for the 2002 Trans Am).
3. **Car names need work**: imported cars show a blank name in menus (FH2 has no text for them).
4. **Autoshow thumbnails don't work**, but the car's thumbnail does show in your garage.

## Good to know

- The importer writes only to `<FH2 folder>\Mount\mediapc`, which Extra Options loads over the game's own media: the game database, car and wheel archives and `zipmanifest.xml` go there. The game's `Mount\media`, `hash.manifest` and `azimuth.exe` are never touched. Deleting `Mount\mediapc` removes every import at once.
- **Upgrading from 1.x** (Azimuth 0.9.7, which patched `hash.manifest` and `azimuth.exe`): undo your 1.x layers first with their `Uninstall.ps1` (newest first), or restore the game folder from a clean copy, then re-import with 2.0. See the guide.
- Extra Options 0.2.74 also unlocks DLC cars and adds stock rims for FH2's own cars, so the old dlc-unlock and stock-wheel-swap mods aren't needed. The importer still adds imported cars' wheels itself (Extra Options' rims cover FH2's own cars only).
- Engine **sounds are borrowed** from the sound donor.
- Keep this folder: you need it to add more cars later. Your settings are remembered in `%LOCALAPPDATA%\fh2-mods\import-fm5-cars.json`.

## License

MIT (see `LICENSE`). Forza Horizon 2 and Forza Motorsport 5 are not included and belong to their owners; you need your own copies.

The full walkthrough, advanced options (tuning lights, adding wheels for older imports, command-line use) and troubleshooting are in **[GUIDE.md](GUIDE.md)**.
