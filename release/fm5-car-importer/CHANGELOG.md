# Changelog

## 1.0.0 (2026-10-14)

First release.

- Interactive importer (`Import-Fm5Cars.cmd`): pick FM5 cars by name, a data donor, sound donor, Autoshow group and light donor per car; folders remembered.
- FM5 car models converted for FH2's shaders (vertex layouts, tangents, window glass, light lenses).
- Engine sound borrowed from an FH2 car.
- Imports stack as layers on top of the installed game (and other mods), each with a backup and an uninstaller; Azimuth 0.9.7's file index and launcher are extended and patched automatically.
- Each imported car's stock wheel is added to the wheel shop, filed under its brand and category.
- Night lights transplanted from an FH2 donor and fitted to the car: lamp meshes matched by role, lights placed by lamp assembly or re-aimed onto pop-up lenses; optional whiter headlights, outer-bulb-only glow, headlight colour and animation-graph swap (`Add-CarLights.ps1`).
- `Add-ImportedCarWheels.ps1` adds wheels for cars imported earlier.
