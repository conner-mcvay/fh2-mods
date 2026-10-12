FORZA HORIZON 2 (PC) - DLC CAR UNLOCK
=====================================

Lets DLC and bonus cars (143 total) be bought in the Autoshow. Without it, the
game tries an Xbox Live license check and won't sell them.

Built for game version 1.0.0.64 (Anthem_1.0.0.64_x64__8wekyb3d8bbwe).

What it changes in gamedbRC.slt:
  - Data_Car.ContentId 99 -> 0 (the license-gate marker) on 143 cars
  - Removes the per-car / car-pack store offers and their car mappings
  - Leaves the Storm Island and Porsche expansion offers alone


INSTALL
-------
1. Open your game's media\stripped folder:
     ...\Anthem_1.0.0.64_x64__8wekyb3d8bbwe\Mount\media\stripped
2. BACK UP your original gamedbRC.slt.
3. Copy media\stripped\gamedbRC.slt from this mod over it.
4. Start the game.

To uninstall, restore your backed-up gamedbRC.slt.

Other mods that change gamedbRC.slt will overwrite this one (and vice versa).
To combine them, build them together from the fh2-mods repo.
