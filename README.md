# fh2-mods

Monorepo for mods for Forza Horizon 2 on PC (game version 1.0.0.64, `Anthem_1.0.0.64_x64__8wekyb3d8bbwe`).

| Mod | Description |
|---|---|
| [cockpit-fov](mods/cockpit-fov) | Cockpit/driver camera FOV 48 → 70 |

## Layout

```
mods/<name>/
  README.txt                       shipped in the release zip ({{MANIFEST_VALUES}} is filled in by the build)
  media/<Archive>.zip/<entry>      changed files only, mirroring the game's media folder;
                                   a folder named Foo.zip holds replacement entries for media\Foo.zip
tools/
  Repack-ForzaZip.ps1              repacks a media zip in FH2's native format and updates zipmanifest.xml
  Build-Mod.ps1                    builds dist/<name>.zip from stock game files + the mod's changes
```

Game files aren't committed. Builds read stock zips from the game package, so they never depend on an already-modded install.

## Building

```powershell
.\tools\Build-Mod.ps1 -Mod cockpit-fov -Package G:\FH2-1\Anthem_1.0.0.64_x64__8wekyb3d8bbwe.zip
```

`-Package` can also be set once via the `FH2_PACKAGE` environment variable. Output goes to `dist/`.

## How FH2 loads media zips

Editing a zip with WinRAR/7-Zip/Windows doesn't work; the game silently falls back to defaults. Two things must match:

1. **Zip layout.** Every entry is deflated, version 10, with zeroed time/date/attributes, no local-header extra field, and a central-directory extra field with ID `0x1123` holding the absolute offset of the entry's compressed data.
2. **`media\zipmanifest.xml`.** Each zip's `dirstart` (central-directory offset), `dirsize` (central-directory size **+ 22** for the end-of-central-directory record) and `direntries`.

`Repack-ForzaZip.ps1` handles both. It copies unchanged entries' compressed bytes verbatim; repacking an untouched stock zip reproduces it byte-for-byte.
