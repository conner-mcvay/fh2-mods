# Changelog

## 1.0.0 (2026-10-16)

First release.

- Slider window (`Tune-CarSound.cmd`): exhaust, engine and intake volume, idle, highs, lows and grit; turbo, boost whistle, DSC and CSC superchargers, blow-off valve, backfires and the low-frequency layer, per car. Car search by part of a name; Apply / Revert / Reset to stock.
- Works on the game's own sound files (FMOD banks) for any of FH2's 351 car sounds, writing changed copies to `Mount\mediapc`; settings kept per car.
- Asks for the Azimuth folder on first use (remembered; Folders... changes it) and offers to turn on Extra Options' `EnableMediaOverrides`.
- Sharp on high-DPI screens.
- `Set-BoostVolume.cmd` for the turbo / supercharger / blow-off settings from the command line; `Show-CarSound.ps1` lists a car's sound layers.
