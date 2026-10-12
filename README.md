# fh2-mods

Monorepo for mods for Forza Horizon 2 on PC (game version 1.0.0.64, `Anthem_1.0.0.64_x64__8wekyb3d8bbwe`).

| Mod | Description |
|---|---|
| [cockpit-fov](mods/cockpit-fov) | Cockpit/driver camera FOV 48 → 70 |
| [dlc-unlock](mods/dlc-unlock) | DLC and bonus cars can be bought in the Autoshow without the Xbox Live license check |

## Layout

```
mods/<name>/
  README.txt                              shipped in the release zip ({{MANIFEST_VALUES}} is filled in by the build)
  media/...                               changes only, mirroring the game's media folder:
    <Archive>.zip/<entry>                   a folder named like a zip holds replacement/new entries for that zip
    stripped/gamedbRC.slt/<patch>.sql       a folder named like a .slt holds SQL patches, applied in name order
    <path>/<file>                           anything else is a loose file, copied as-is
tools/
  Repack-ForzaZip.ps1                     repacks a media zip in FH2's native format and updates zipmanifest.xml
  Build-Mod.ps1                           builds dist/<name>.zip from stock game files + one or more mods
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

## How FH2 loads media zips

Editing a zip with WinRAR/7-Zip/Windows doesn't work; the game silently falls back to defaults. Two things must match:

1. **Zip layout.** Every entry is deflated, version 10, with zeroed time/date/attributes, no local-header extra field, and a central-directory extra field with ID `0x1123` holding the absolute offset of the entry's compressed data.
2. **`media\zipmanifest.xml`.** Each zip's `dirstart` (central-directory offset), `dirsize` (central-directory size **+ 22** for the end-of-central-directory record) and `direntries`.

`Repack-ForzaZip.ps1` handles both. It copies unchanged entries' compressed bytes verbatim; repacking an untouched stock zip reproduces it byte-for-byte.

## The game database

`media\stripped\gamedbRC.slt` is a plain SQLite 3 database (cars, upgrades, events, store offers). The game loads the whole file into memory at startup, so changes need a restart. It isn't a zip and has no `zipmanifest.xml` entry.

- `Data_Car.ContentId = 99` marks a car as license-gated (DLC/bonus); `0` means freely available.
- `ContentOffers` / `ContentOffersMapping` (`ContentType = 1` = car) link cars to store offers; `OnDiscContent` lists base-game content. A car doesn't need to appear in any of them to be buyable.
