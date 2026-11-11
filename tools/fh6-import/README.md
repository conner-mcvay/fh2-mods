# Forza Horizon 6 wheels for FH2

Converts FH6 wheel zips (`media\Cars\_library\scene\wheels\<wheel>.zip`, from your own FH6 install) into FH2 wheel zips. Python 3 scripts, standard library only; the shader fit uses `tools\fm5-import`'s converter. Nothing from either game is committed.

## Converting one wheel

```powershell
# 1. FH6 zip -> FH2 model + AO texture in <out>\<wheel>\ (the same file names FH2 uses)
py -3 tools\fh6-import\fh6_to_fh2.py <FH6 wheel zip> <FH2 Mount\media> <out>\<wheel> [material map .json]
# 2. fit the vertex layouts to FH2's shaders (in place) and validate
.\tools\fh6-import\Fit-Fh2Shaders.ps1 -Model <out>\<wheel>\<wheel>_wheelLF.modelbin -Fh2Media <FH2 Mount\media>
```

Then make a mod of it: `mods\<name>\media\cars\_library\scene\wheels\<wheel>.zip\` holding the two files, and a SQL patch adding a `List_Wheels` row (a new ID, `MediaName` = the zip name) and a `WheelAnnotations` row (the shop category), e.g. copied from the brand's existing wheels. Build and install it as any mod (`Build-Mod.ps1 -Layer`). A wheel that FH2 already has (same zip name) replaces FH2's.

What the converter does:

- **Model**: FH6's burG 1.1 / Mesh v1.12 to FH2's burG 1 / Mesh v1.7 (`burg.py`, `fh6model.py`). Packed positions to floats; FH6's LODS level becomes FH2's top level; shadow meshes are generated; morph targets (rim size and width) are copied as they are (the format is the same).
- **Materials**: picked by FH6 material type, not part name (`choose_material`): wheel paint by its colour, chrome, aluminium, screws, blur, black. Badges: only `<brand>_badge_002` is laid out like FH2's `<brand>_badge_001`; other decals with an alpha texture are dropped, since they'd cut pieces out of an unrelated texture.
- **Spindle** (where the wheel mounts): the back of the hub, as in FH2's own wheels. For models whose spokes reach as deep as the hub (RimStudio), 0.05 behind the spokes, so FH2's calipers clear them.
- **AO texture**: FH6's linear R8 (256, 512 or 1024; 256 is upscaled to 512) tiled into FH2's GPU layout with mips (`gcntile.py`).

### Material map

The optional `.json` overrides by FH6 material name. `"<name>": "<FH2 library material>"` (as `wheelmaterials/aluminum_polished`, `badges/ame_badge_001`; `null` drops it), and `"uv0:<name>": [offset u, scale u, offset v, scale v]` sets that material's UV transform. For example, the American Racing VN205's cap logo is FH6's `ame_badge_011`, which FH2 doesn't have. It goes on FH2's own badge with the transform FH2's Torq-Thrust uses for it:

```json
{"wheel_badge": "badges/ame_badge_001", "uv0:wheel_badge": [0.0215, 0.9616, 0.0173, 0.9616]}
```

## Other tools

| Script | |
|---|---|
| `glb2obj.py <in.glb> <out dir>` | a .glb model to .obj/.mtl with its textures, for RimStudio |
| `add_blur.py <target> <donor> <out>` | copies the motion-blur meshes of a converted wheel into one without (RimStudio's output has none, so the wheel disappears at speed) |
| `squash_cap.py <model> <r> <seat> <factor>` | shortens a centre cap: geometry inside radius `r` and in front of `seat` (the lug-nut tips) keeps `factor` of its protrusion |
| `flatten_face.py <model> <d> [face_r lip_r x_max]` | less dish: the face moves `d` towards the lip, the dish between them is blended, the lip, barrel and spindle stay (the morphs keep working: they're offsets) |

Distances are in FH2's normalised wheel space: x from 0 (lip front) to 1 (back of the barrel), radius about 0.14 at the barrel.

### A RimStudio wheel (the Weld ProStar)

RimStudio (a separate tool) makes FH6 wheel zips from an .obj. Its output then goes through the converter like an FH6 wheel, plus blur meshes from a real FH6 wheel:

```powershell
py -3 fh6_to_fh2.py <RimStudio WEL_S72.zip> <FH2 media> out\WEL_S72 prostar.json   # {"rim2": "wheelmaterials/aluminum_polished"}
py -3 squash_cap.py out\WEL_S72\WEL_S72_wheelLF.modelbin 0.031 0.072 0.35
py -3 fh6_to_fh2.py <FH6 WEL_S72.zip> <FH2 media> out\donor_S72                   # the blur donor
py -3 add_blur.py out\WEL_S72\WEL_S72_wheelLF.modelbin out\donor_S72\WEL_S72_wheelLF.modelbin out\blur.modelbin
.\Fit-Fh2Shaders.ps1 -Model out\blur.modelbin -Fh2Media <FH2 media>   # then use it as WEL_S72_wheelLF.modelbin
# low-dish copy (renamed WEL_ProStar_LD): py -3 flatten_face.py <copy> 0.04
```
