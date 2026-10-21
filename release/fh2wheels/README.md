# fh2wheels for Forza Horizon 2 (PC)

More wheel, tire and suspension options in the garage of **Forza Horizon 2** on PC (Azimuth), for every car, imported ones included. They're real upgrades: they show up in Upgrades > Tires & Rims beside the game's own, preview live on the car, are bought and installed like any other part, and are saved with the car.

This package contains **no game files**. The installer builds its database changes on your own game's files and installs them with backups.

## What you get

Under **Upgrades > Tires & Rims**:

| Option | Range |
|---|---|
| **Front / Rear Wheel Offset** | Stock, -20 to +50 mm a side in 5 mm steps, then +75, +100 and +150 mm (way past the fender) |
| **Front / Rear Tire Profile** | aspect ratio -30 to +35 points on the same rim: a 255/40 with +10 becomes a 255/50 |
| **Rear Rim Style** | a different rim on the rear axle (needs an aftermarket front rim); Stock puts the front rims back on |
| **Rim sizes** | 13" to 24", front and rear, besides the car's own sizes (smaller ones lighter, larger ones heavier) |
| **Tire widths** | 185 to 395 mm in 10 mm steps, front and rear, besides the car's own widths |
| **Tire compound** | drag and rally tires for every car |

Under **Tuning**, on cars with adjustable springs: **ride height** 10 cm lower and 40 cm higher than the game allows, **camber** -15 to +15 degrees.

The offset and profile categories use the wheel camera, so the car stays in view while you pick.

## What you need

| | |
|---|---|
| Forza Horizon 2 | version 1.0.0.64 (`Anthem_1.0.0.64_x64__8wekyb3d8bbwe`), running on **Azimuth 0.9.10** |
| FH2 Extra Options | the build for Azimuth 0.9.10: `winmm.dll` (with `FH2_ExtraOptions.ini`) beside `azimuth.exe`. It's what makes the game load the changed database (from `Mount\mediapc`); the installer turns on its `[Files] EnableMediaOverrides=1` setting if it's off. |
| Windows | 10 or 11, with the built-in Windows PowerShell 5.1 (nothing to install). `sqlite3.exe` is downloaded from sqlite.org on first use (hash-checked) unless it's on your PATH. |

## Install

1. **Close the game.**
2. Extract this zip anywhere and keep the folders together.
3. Double-click **`Install-Fh2wheels.cmd`**. It asks for two folders, one after the other:
   - your **Azimuth folder** (the one with `azimuth.exe`);
   - your **game folder** (the one with the `Mount` folder in it, e.g. `Anthem_1.0.0.64_x64__8wekyb3d8bbwe`). It shows the game folder that Azimuth is set to run; press Enter to use it.

   A wrong folder is asked for again. If the game folder isn't the one Azimuth runs, you get a warning first: install into the folder Azimuth runs, or the game won't see the mod. It shows both folders and asks before changing anything.

   If you have **more than one Azimuth folder**, install fh2wheels into the one you start the game from: each Azimuth folder has its own copy of `fh2wheels.dll`.
4. Start the game; the new options are in Upgrades > Tires & Rims.

**Imported cars** (e.g. with the FM5 car importer): the rim sizes, tire widths and drag/rally tires are made from each car's own options when you install. For cars you import later, run `Install-Fh2wheels.cmd` again afterwards. Wheel offsets, tire profiles and rear rims work on every car either way.

**Updating:** extract the new version and run its `Install-Fh2wheels.cmd`. It replaces the old one.

## Uninstall

Close the game and double-click **`Uninstall-Fh2wheels.cmd`**. It restores the game database from the backup and takes `fh2wheels.dll` out of Azimuth.

The installer's backups are kept in `<game folder>\mod-backups\fh2wheels-<date>`. Mods that went in after fh2wheels (for example cars imported afterwards) have to come out first, newest first, before the database backup can be restored; the uninstaller says so when that's the case.

Cars that had fh2wheels parts fitted keep the saved part, which does nothing without the mod. Refit stock in the garage before uninstalling if you plan to share a save.

## Troubleshooting

Two logs tell what happened:

- **`fh2wheels-install.log`**, next to `Install-Fh2wheels.cmd`, written on every install or uninstall (in `%TEMP%` when that folder can't be written). It has everything the installer showed, any error, and a report of your setup before and after: the folders, Azimuth and Extra Options, the DLLs in `data\bin`, whether the game folder has fh2wheels' database part, and the start of `fh2wheels.log`.
- **`fh2wheels.log`** in Azimuth's `data\bin`, rewritten each time the game starts with fh2wheels loaded. If it isn't there or isn't from your last start, the game didn't load fh2wheels.

When reporting a problem, send both, and say which folder you start the game from.

| What you see | Usually |
|---|---|
| "The installer's files aren't all here" | The `.cmd` was run from inside the zip. Extract the whole zip (right-click > Extract All) and run it from the extracted folder. |
| No new options in Tires & Rims | The game was started from a different Azimuth folder, or runs a different game folder than the one installed to. Both are in the install log's report. |
| Options there, but blank text, or the rear rim changes all four wheels | The database part is installed but `fh2wheels.dll` isn't running: no fresh `fh2wheels.log`. Usually the game was started from another Azimuth folder with an older copy (each Azimuth folder has its own). |
| "Close Azimuth first" | The game is still running; close it (check Task Manager for azimuth.exe). |
| "Needs FH2 Extra Options" | Install Extra Options for Azimuth 0.9.10 (`winmm.dll` beside `azimuth.exe`) first. |

## How it works

- **`fh2wheels.dll`** goes into Azimuth's `data\bin` as `azimuth-tls.dll`; the DLL that was there is renamed `fh2wheels-next.dll`, and fh2wheels loads it, so Extra Options and Azimuth keep working. It applies the offsets and profiles when a car is built, shows the rear rims, lets the game sell the new parts, and supplies the menus' text. Settings: `data\bin\fh2wheels.ini`; log: `data\bin\fh2wheels.log`.
- **The game database** (`Mount\mediapc\stripped\gamedbRC.slt`): the new categories and options, each car's rim sizes, tire widths and drag/rally tires, and the ride height ranges. The camber range is in `Mount\mediapc\physics\PhysicsSettings.ini`.

Both halves are needed: without the DLL, the offset and profile options do nothing and their text is blank.

The rear rim is kept in the car's save (in the garage's unused tire brand field). The game has no slot for offsets or profiles, so they borrow four part slots ordinary cars don't use (restrictor plate, motor parts, quad turbo and electric motor); the DLL keeps the game from treating them as engine parts.

### With fh2net

fh2wheels and fh2net both sit in the `azimuth-tls.dll` chain and work together, installed in either order: fh2net always ends up in front (fh2wheels goes behind it when it's already there), and each can be updated or uninstalled on its own.

## Known limits

- A rear rim shows only with an aftermarket front rim: with the stock rims, the car draws its own wheels on all four corners.
- The game doesn't draw rims larger than 24", so the sizes stop there. Cars that come with larger rims keep them.
- Very wide tires and big offsets go through the bodywork; that's the point for some builds.
