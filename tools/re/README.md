# Reverse-engineering helpers and notes

Tools for poking at `forza_durango_release_final.exe` (FH2 1.0.0.64; image base `0x140000000`, also where Azimuth maps it, so addresses below are the same in the file and in the running game).

Static (needs Python 3 with `capstone` and `pefile`: `py -3 -m pip install capstone pefile`; run with `py -3 -I` so nothing in the working folder shadows a module):

| Script | Does |
|---|---|
| `fh2re.py xref <string>...` | code that loads the address of an ASCII string (`lea reg, [rip+x]`) |
| `fh2re.py dis <va> [count] [back]` | disassemble, annotating rip-relative strings |
| `fh2re.py func <va>` | the whole function containing `va` (from `.pdata`) |
| `rtti.py <Class@Namespace>...` | a class's vtable(s), from MSVC RTTI |
| `vtname.py <vtable> [n]` | the class of a vtable and its first `n` slots |
| `disp.py <hexdisp>...` | instructions using `[reg + disp]` with that displacement (who reads/writes a field) |

Live (reads the running game through `ReadProcessMemory`, read-only):

| Script | Does |
|---|---|
| `findcams.ps1` | every camera object (by vtable) and what points at them |
| `dump.ps1 <addr> [len]` | qwords, floats and pointed-to strings at an address |
| `refs.ps1 <addr>...` | every qword in the game's memory equal to one of the addresses |
| `MemScan.cs` | the scanner behind them |

## Free camera research (2026-10)

- `Camera.zip\CameraSettings.ini` has a `FreeCam\` section (move/strafe/up-down speed, yaw/pitch/roll speed, FOV range, acceleration) and the `PhotoModeCam\` limits (`mods/photomode-unbound` lifts those).
- Camera classes (RTTI): `CCamFree` (vtable `142E78AF0`), `CCamPhotoMode` (`142C6C578`), `CCamFollow` (`142E783A0`), `CCamDriver` (`142E78120`), `CCamFreeTrack` (`142E79040`), plus `CCamCockpit`, `CCamHood`, `CCamBumperHigh`, `CCamFollowLow/High`, `CCamWheel`, `CCamSide`, `CCamOrtho`, `CCamRearView`, `CCamAnimPlayer`, `CCamFreeTargetCar`.
- `CMultiCam` (vtable `142E70080`, constructor `140FE01F0`) holds the named camera list. Entries are 0x40 bytes: name (std::string), `+0x20` u32 category, `+0x24` u32, `+0x28` u8 flag, `+0x30` shared_ptr camera. Normal cameras (DriverCam, Hood, BumperHigh) are category 1, flag 0; the developer cameras (FreeCam-Old, FreeCam, FPSFreeCam, FreeTargetCar) category 3, flag 1. List order: DriverCam, Hood, BumperHigh, FreeCam-Old, FreeCam, FPSFreeCam, FreeTargetCar, WheelCam, SideCam, OrthoCam, TrackSeg, CarRelativeCams, PreRaceTrackCams, FreeTrack, PhotoMode, RearView. In a running game there are two such lists (world and home space), and all three free cameras are constructed.
- The PhotoMode camera object holds a pointer to the FreeCam object (photo mode is likely built on it).
- Command-line switches (`CForzaCommandLineParameters`, registered around `140F6FD00`): `freecamtoggle` (bool at `+0x2DA8`, defaults to on), `DebugCamEnable`, `DebugCamSpeedMin/Max`, `disablephotomodecollisiondetection`, `bootcam`; read from a `%scmdline.txt` (`14107C373`) unless `ignorecmdlinedottxt`.
- Next: find `CMultiCam`'s current-camera field live (watch it while switching views), then select FreeCam and see what drives it.
