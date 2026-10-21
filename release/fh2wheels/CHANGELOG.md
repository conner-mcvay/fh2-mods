# Changelog

## 1.0.4 (2026-10-20)

- `fh2wheels.log` says whether the game database fh2wheels reads at start has fh2wheels' part in it (`game database: fh2wheels part present`, or a `PROBLEM:` line naming the database and the game folder to install into), with that database's full path. A game folder Azimuth keeps relative to its own folder is resolved against the Azimuth folder.
- `fh2wheels-install.log` keeps every run (newest last); before, an uninstall run wiped the log of the install before it.

## 1.0.3 (2026-10-20)

- The installer understands a game folder that Azimuth keeps **relative to its own folder** (e.g. `(Forza Horizon 2) Anthem_1.0.0.64_x64__8wekyb3d8bbwe\Anthem_1.0.0.64_x64__8wekyb3d8bbwe`). It used to offer no default for those setups and warned that the right game folder wasn't the one Azimuth runs.

## 1.0.2 (2026-10-20)

- The installer writes **`fh2wheels-install.log`** (next to it, or in `%TEMP%`): everything it showed, any error with where it happened, and a report of the setup before and after (folders, Azimuth and Extra Options versions and settings, the `data\bin` DLL chain, whether the game folder has fh2wheels' database part, and a summary of `data\bin\fh2wheels.log` with any patch that failed).
- Run from inside the zip without extracting, it now says to extract the whole zip first, instead of failing on missing files.
- README: a troubleshooting section.

## 1.0.1 (2026-10-20)

- The installer asks for the **Azimuth folder and the game folder separately** instead of reading the game folder from Azimuth's settings without asking, which installed into the wrong game for some setups. A folder that isn't right is asked for again. For the game folder it shows the one Azimuth runs (Enter takes it), warns before using a different one, and shows both folders for a yes/no before changing anything.
- The README explains that with several Azimuth folders, fh2wheels goes into the one the game is started from.

## 1.0.0 (2026-10-18)

First release, for Forza Horizon 2 1.0.0.64 on Azimuth 0.9.10 with Extra Options.

- **Front / Rear Wheel Offset** under Tires & Rims: Stock, -20 to +50 mm a side in 5 mm steps, +75, +100 and +150 mm. Live preview with the wheel camera.
- **Front / Rear Tire Profile**: aspect ratio -30 to +35 points on the same rim.
- **Rear Rim Style**: a different rim on the rear axle, kept in the save.
- **Rim sizes** 13" to 24" and **tire widths** 185 to 395 mm for every car, front and rear.
- **Drag and rally tires** for every car.
- **Tuning**: ride height 10 cm lower / 40 cm higher on adjustable springs, camber -15 to +15 degrees.
- Works on imported cars (built on your own game database when installing; run the installer again after importing more cars). Works alongside fh2net.
