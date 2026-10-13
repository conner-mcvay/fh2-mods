# fh2-mods

Monorepo for mods for Forza Horizon 2 on PC (game version 1.0.0.64, `Anthem_1.0.0.64_x64__8wekyb3d8bbwe`).

| Mod | Description |
|---|---|
| [cockpit-fov](mods/cockpit-fov) | Cockpit/driver camera FOV 48 → 70 |
| [dlc-unlock](mods/dlc-unlock) | DLC and bonus cars can be bought in the Autoshow without the Xbox Live license check |
| [fm5-pon-transam-02](mods/fm5-pon-transam-02) | FM5's 2002 Pontiac Trans Am as a new car; sound borrowed from the '95 Corvette ZR-1. Name shows blank; night lighting unchecked |

## Layout

```
mods/<name>/
  README.txt                              shipped in the release zip ({{MANIFEST_VALUES}} is filled in by the build)
  media/...                               changes only, mirroring the game's media folder:
    <Archive>.zip/<entry>                   a folder named like a zip holds replacement/new entries for that zip
    stripped/gamedbRC.slt/<patch>.sql       a folder named like a .slt holds SQL patches, applied in name order
    <path>/<file>                           anything else is a loose file, copied as-is
  imports.txt                             FM5 files to copy in: "<FH2 media path> <- <FM5 media path>" (a .zip segment = entry inside it)
  index-donors.txt                        for each new file, the stock file whose hash.manifest metadata it reuses
tools/
  Repack-ForzaZip.ps1                     repacks a media zip in FH2's native format and updates zipmanifest.xml
  Build-Mod.ps1                           builds dist/<name>.zip from stock game files + one or more mods
  Export-Fm5Car.ps1                       generates an FM5 car import mod (SQL patch, imports, index donors, README)
  Patch-Azimuth.ps1                       makes a copy of the stock Azimuth 0.9.7 launcher that accepts a given hash.manifest
  ForzaPathKey.cs                         the hash.manifest path key
  ForzaModel.cs                           .modelbin (burG) reader/writer + structure check
  Fm5ModelConverter.cs                    converts FM5 car models/materials for FH2's shaders
  release/Install.ps1, Uninstall.ps1      bundled into every release zip
```

Game files aren't committed. Builds read stock files from the game package, so they never depend on an already-modded install.

Database mods are SQL patches, not modified copies of the database. Each build starts from the stock `gamedbRC.slt` and runs every patch in a transaction, so database mods combine instead of overwriting each other.

## Building

```powershell
.\tools\Build-Mod.ps1 -Mod cockpit-fov -Package G:\FH2-1\Anthem_1.0.0.64_x64__8wekyb3d8bbwe.zip
.\tools\Build-Mod.ps1 -Mod cockpit-fov,dlc-unlock -Name my-setup     # several mods in one install
```

- `-Package` can be set once via the `FH2_PACKAGE` environment variable.
- SQL patches need [sqlite3.exe](https://www.sqlite.org/download.html) (the "sqlite-tools" bundle): pass `-Sqlite <path>`, set `FH2_SQLITE`, or put it on `PATH`.
- Mods apply in the order given; on conflicts the later mod wins. Output goes to `dist/`.
- Mods with an `imports.txt` need the FM5 install: pass `-Fm5Media <FM5 Mount\media>` or set `FH2_FM5_MEDIA`.

Every release zip contains `install.json` (each file with its SHA-256 and the SHA-256 of the base file it replaces), `Install.ps1` and `Uninstall.ps1`. The installer checks the game and Azimuth versions, refuses to overwrite files that differ from the base unless `-Force`, backs up what it replaces, and patches `azimuth.exe` (stock, or already patched by another mod) when the mod ships a `hash.manifest`; the uninstaller restores everything, refusing if files changed since (so with several mods installed, uninstall newest first).

`Build-Mod.ps1 -Layer -Game <folder>` builds on top of what's installed in that game folder (earlier car imports, a modded gamedb) instead of stock files, so mods stack. Such a release installs only onto exactly that state.

## Adding new files (imported cars)

Azimuth only exposes files listed in `Mount\hash.manifest`, its file index. A new file that isn't listed is invisible to the game; a new car zip in `zipmanifest.xml` that the game can't open crashes it at startup. When a build adds files, it also writes `build\<name>\hash.manifest`: the stock index with one 12-byte record appended per new file.

- Record: `u64` path key + `u32` metadata, little endian. The key is a DJB2-style mix run twice over the lowercase `media\...` path (see `tools/ForzaPathKey.cs`). It matches 2,312 of the 2,314 stock files, and the same function gives the same keys in FM5's own index.
- The metadata's meaning is unknown. New files copy it from a similar stock file (`index-donors.txt`), as the working GT500 import did.
- Azimuth 0.9.7 checks the index's exact size and SHA-256. `Patch-Azimuth.ps1` writes both into a copy of the launcher: the SHA-256 as ASCII hex at raw offset `0x252910`, the size as the `imm32` of `cmp qword [rbp-0x48]` at `0x1C06E8`. It accepts the stock launcher or one already patched this way (recognized by its SHA-256 with those two spots blanked). Keep the patched launcher named `azimuth.exe` (FH2_ExtraOptions checks the name). Restore the stock launcher together with the stock index.

The release's `Install.ps1` does this; by hand: install a build's `media\*` into `Mount\media`, its `hash.manifest` into `Mount`, then patch `azimuth.exe`:

```powershell
.\tools\Patch-Azimuth.ps1 -Azimuth <azimuth folder>\azimuth.exe -Index <Mount\hash.manifest> -Out <azimuth folder>\azimuth.exe
```

## Importing FM5 cars (end users)

**Double-click `Import-Fm5Cars.cmd`** (or run `tools\Import-Fm5Cars.ps1` with no parameters) and it asks for everything: your Azimuth, FH2 and FM5 folders (remembered; the FH2 folder is read from Azimuth's settings when possible), then the FM5 cars to import - type part of a name and pick from the matches - and per car a **data donor** (an FH2 car of the same kind; a match is suggested) and a **sound donor** (any FH2 car whose engine sound to use). Imports stack: each run adds its cars on top of whatever is installed (earlier imports, a modded gamedb), and cars the game already has aren't offered. This repo ships no game files: everything is read from your own installs. You need FH2 1.0.0.64 on Azimuth 0.9.7, and FM5 1.0.0.20. `sqlite3.exe` is used from PATH or downloaded from sqlite.org (hash-checked) into `tools\bin`.

```powershell
# which FM5 cars FH2 doesn't have
.\tools\Import-Fm5Cars.ps1 -ListFm5Only -Fm5Root "D:\Forza_1.0.0.20_x64__8wekyb3d8bbwe" -GameRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe"

# or non-interactive: one data donor per car; -SoundCar "" = the data donor's sound
.\tools\Import-Fm5Cars.ps1 -Fm5Root "D:\Forza_1.0.0.20_x64__8wekyb3d8bbwe" -GameRoot "D:\Anthem_1.0.0.64_x64__8wekyb3d8bbwe" -AzimuthRoot "D:\azimuth" `
    -Car PON_TransAm_02,AST_DBS_09 -Donor PON_TransAmGTA_87,AST_DBSTF_08 -SoundCar CHE_CorvetteZR1_95,""
```

It checks the game version, generates each car's mod in a private workspace, builds one install on top of your current game files (models converted for FH2's shaders), and installs it with backups. Each run gets its own backup folder (`mod-backups\fm5-cars-<time>`, with the run's car list in `cars.json`); undo a run with the `Uninstall.ps1` kept there, newest run first. `-NoInstall` builds only.

## Importing FM5 cars (repo mods)

```powershell
.\tools\Export-Fm5Car.ps1 -CarId 1065 -Fm5Media G:\FM5\Forza_1.0.0.20_x64__8wekyb3d8bbwe\Mount\media
```

The exporter walks every gamedb row the car depends on and writes them as INSERTs. It never overwrites an FH2 row; it reports key conflicts instead. Shared engines/drivetrains/bodies only get part rows FH2 has none of. It also lists the FM5 files to import and their index donors. What carries over: the car zip (including the v13 `physicsdefinition.bin`), the audio tuning XML, and the thumbnail (added into `stripped\RC0.zip`). Engine sound: pass `-EngineSound <FH2 engine>` to borrow an FH2 bank (FM5's `<engine>.bank` renamed to `PG_<engine>.bank` was silent for the Trans Am). FH2-only `Data_Car` columns and the `Data_Car_Buckets` row come from a donor FH2 car (default: same make, closest year).

### Model conversion (automatic in the build)

FH2 compiles each shader variant for one vertex format: in FH2's own cars a mesh's vertex layout holds exactly the `TEXCOORD`/`TANGENT` inputs its shader reads (1,074 of 1,082 mesh parts in the '87 GTA; mesh parts reference materials, layouts and buffers by `Id` metadata, not position). FM5 layouts differ, so FM5 glass, lenses, badges and decals render as nothing or garbage. For every FM5 car zip in `imports.txt` the build:

- reads each material's FH2 shader input signature (DXBC `ISGN` of all its `.vso` programs) and rewrites each layout to exactly that set, copying missing UV sets from the nearest one (TEXCOORD4 from TEXCOORD2, with its UV transform) and computing missing tangents (validated against FH2's own tangents: 99/99 and 722/722 vertices match)
- gives FM5 window glass (`gls_window`, `gls_windsheild`, interior variants) FH2's material parameter override (`0xF2FDFE8E` = 0); without it panes aren't drawn
- redirects car-local materials whose shader is FM5-compiled inside the car (missing FH2's `SimpleCarLightScenario`) to the FH2 library material of the same name minus the `CH1` tag (`gls_limotintCH1_001` -> `gls_limotint_001`)
- re-checks every converted model's structure before packing

## How FH2 loads media zips

Editing a zip with WinRAR/7-Zip/Windows doesn't work; the game silently falls back to defaults. Two things must match:

1. **Zip layout.** Every entry is deflated, version 10, with zeroed time/date/attributes, no local-header extra field, and a central-directory extra field with ID `0x1123` holding the absolute offset of the entry's compressed data.
2. **`media\zipmanifest.xml`.** Each zip's `dirstart` (central-directory offset), `dirsize` (central-directory size **+ 22** for the end-of-central-directory record) and `direntries`.

`Repack-ForzaZip.ps1` handles both. It copies unchanged entries' compressed bytes verbatim; repacking an untouched stock zip reproduces it byte-for-byte.

## The game database

`media\stripped\gamedbRC.slt` is a plain SQLite 3 database (cars, upgrades, events, store offers). The game loads the whole file into memory at startup, so changes need a restart. It isn't a zip and has no `zipmanifest.xml` entry.

- `Data_Car.ContentId = 99` marks a car as license-gated (DLC/bonus); `0` means freely available.
- `ContentOffers` / `ContentOffersMapping` (`ContentType = 1` = car) link cars to store offers; `OnDiscContent` lists base-game content. A car doesn't need to appear in any of them to be buyable.
