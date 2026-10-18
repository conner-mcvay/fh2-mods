# Car Sound Tuner for Forza Horizon 2 (PC)

Sliders for any car's sound in **Forza Horizon 2** on PC (Azimuth): make an idle lope louder, brighten a dull exhaust, take the boom out of a muscle car, turn up a supercharger whine or a blow-off valve. Pick a car, move the sliders, press Apply, start the game.

This package contains **no game files**. It reads your own game's sound files and writes changed copies next to them; the originals are never touched.

## What you need

| | |
|---|---|
| Forza Horizon 2 | version 1.0.0.64 (`Anthem_1.0.0.64_x64__8wekyb3d8bbwe`), running on **Azimuth 0.9.10** (0.9.9 also works) |
| FH2 Extra Options | the build for your Azimuth: for **0.9.10**, `winmm.dll` (with `FH2_ExtraOptions.ini`) beside `azimuth.exe`; for 0.9.9, **0.2.74 or later** in `data\bin`. It's what makes the game load the changed sounds (from `Mount\mediapc`); the tuner offers to turn on its `[Files] EnableMediaOverrides=1` setting when it's off. |
| Windows | 10 or 11, with the built-in Windows PowerShell 5.1 (nothing to install) |

## Quick start

1. Extract this zip anywhere and keep the folders together.
2. Double-click **`Tune-CarSound.cmd`**. The first time, pick your **Azimuth folder** (the one with `azimuth.exe`); the game folder is read from Azimuth's settings (if it can't be, you're asked for that too). It's remembered; **Folders...** changes it. The window's title shows the game folder it's tuning.
3. Type part of a car's name (`mustang`, `dart`, `camaro 69`) and pick it from the list.
4. Move the sliders, **close the game**, press **Apply**.
5. Start the game and drive that car.

**Revert** goes back to what's applied, **Reset to stock** puts every slider at 0 (then Apply). Tuned cars have a `*` in the list.

## The sliders

Every slider **adds** to the car's own sound (0 = stock), in dB for volumes: +6 dB is about twice as loud, +24 is the most. Hover a slider's name for what it does. A greyed-out slider means that car doesn't have that sound.

| Tab | Slider | What it changes |
|---|---|---|
| Exhaust / Engine / Intake | **Volume** | every layer of that sound, all RPM |
| | **Idle** | the layer recorded at the lowest RPM (the idle), on top of Volume |
| | **Highs** | the high band of its EQ: brighter, more crackle (shows the resulting EQ; at most +10 dB) |
| | **Lows** | the low band of its EQ: less or more boom |
| | **Grit** | the drive of its saturator: more rasp |
| Turbo & other | **Turbo** | the turbo sounds (single and twin turbos sound the same in FH2) |
| | **Boost whistle** | the spool whistle and air that rise with boost |
| | **Supercharger (DSC / CSC)** | positive-displacement and centrifugal supercharger whine |
| | **Blow-off valve** | the dump valve on lift-off |
| | **Backfires** | backfire pops |
| | **Low-frequency layer** | the separate sub-bass layer some cars have; lower it if a car sounds boomy |

The turbo, supercharger and blow-off sounds only play when the car has that part fitted (upgrade it in the game). An engine swap brings its engine's sound, tuning included.

### Tips

- **Too much distorts.** One layer much past +20 dB clips, and so do several boosted layers that play together (e.g. Idle on exhaust, engine and intake at once). If it crackles in the wrong way, back off a few dB. To make one sound stand out more, lowering the others (or the game's music / effects volume) works better than pushing it.
- **Boomy?** Low-frequency layer down (-10 to -20) and Lows down.
- **Dull exhaust?** Exhaust Highs up (+6 to +12), a little Grit.
- A tune we liked on the 1968 Dodge Dart: Exhaust Idle +10, Highs +12, Grit +4; Engine Idle +9; Intake Idle +9; Low-frequency layer -20.

## What it changes, and how to undo it

Each car's sound is a file in your game folder, `Mount\media\audio\fmodanthem\durango\PG_<car>.bank`. Apply builds that car's file from the game's own each time and writes it to `Mount\mediapc\audio\fmodanthem\durango\`, which Extra Options makes the game read first. Your settings are kept in `car-sound.json` in that folder.

- **One car back to stock:** Reset to stock, Apply.
- **Everything back to stock:** delete the `PG_*.bank` files and `car-sound.json` in `Mount\mediapc\audio\fmodanthem\durango` (or run `Set-BoostVolume.cmd -Remove`).
- Sound files another mod put in that folder are never overwritten.

Close the game before applying: the tuner refuses while it's running.

## Known limits

- **Off-throttle burble** has no slider: its volume follows an RPM curve in every car, which the tuner doesn't edit yet.
- A handful of cars have no separate Highs / Lows / Grit for the intake or engine (their sliders are greyed out). 96 of 351 cars have a low-frequency layer.
- **Imported FM5 cars** (from the FM5 Car Importer) use the sound of the FH2 car they borrowed it from: tune that car.
- The window scales to your main display's resolution when it opens.

## Command line

`Set-BoostVolume.cmd` does the turbo / supercharger / blow-off settings from a command prompt, for one car or many (`-Car mustang`, `-Car all`), and `-Remove` puts every tuned car back to stock:

```
Set-BoostVolume.cmd -Car FOR_MustangGT500_13 -DSC 12
Set-BoostVolume.cmd -List -Car mustang
Set-BoostVolume.cmd -Remove
```

`powershell -ExecutionPolicy Bypass -File tools\audio\Show-CarSound.ps1 -Car dart` lists everything a car's sound is made of (every RPM layer with its sample and volume).

## Files

```
Tune-CarSound.cmd          the tuner window
Set-BoostVolume.cmd        command-line turbo / supercharger / blow-off volume
tools\audio\               the scripts (FmodBank.cs reads and changes the sound files)
README.md, CHANGELOG.md, LICENSE, VERSION.txt
```
