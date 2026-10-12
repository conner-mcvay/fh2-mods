FORZA HORIZON 2 (PC) - COCKPIT FOV MOD
======================================

Changes the first-person (cockpit/driver) camera field of view.

  Driver\FOV = 70   (stock: 48)

Built for game version 1.0.0.64 (Anthem_1.0.0.64_x64__8wekyb3d8bbwe).


CONTENTS
--------
  media\Camera.zip         Modified camera settings
  media\zipmanifest.xml    Updated zip manifest (required, see below)
  tools\Repack-ForzaZip.ps1  Optional: for setting your own FOV value


INSTALL
-------
1. Open your game's "media" folder:
     ...\Anthem_1.0.0.64_x64__8wekyb3d8bbwe\Mount\media
2. BACK UP your original Camera.zip and zipmanifest.xml.
3. Copy both files from this mod's "media" folder into the game's
   media folder and overwrite.
4. Start the game.

To uninstall, restore your two backed-up files.


WHY THE MANIFEST IS NEEDED
--------------------------
zipmanifest.xml stores the position of each zip's internal file index.
If Camera.zip changes but the manifest doesn't, the game silently
ignores the edited settings and uses its defaults.

The included zipmanifest.xml is the stock file for 1.0.0.64 with only the
camera.zip line changed.

ALREADY USING OTHER MODS? Overwriting zipmanifest.xml will undo other
mods' manifest changes. In that case, DON'T copy the manifest. Open
your existing zipmanifest.xml in a text editor, find the line with the
path below, and change its values to match:

{{MANIFEST_VALUES}}


SETTING YOUR OWN FOV
--------------------
Repacking Camera.zip with WinRAR / 7-Zip / Windows WILL NOT WORK. The
game needs a specific zip layout and a matching manifest entry. Use the
included script:

1. Extract Camera.zip (from the game's media folder) to a folder,
   e.g. C:\FH2mod\Camera
2. Edit CameraSettings.ini in that folder and change the line:
     Driver\FOV 70
3. Run in PowerShell (adjust paths):

   powershell -ExecutionPolicy Bypass -File Repack-ForzaZip.ps1 -Zip "<game>\Mount\media\Camera.zip" -SourceDir "C:\FH2mod\Camera"

The script rebuilds Camera.zip in the game's native format, backs up the
existing zip once as Camera.zip.orig and the manifest as
zipmanifest.xml.bak, and updates the camera.zip line in zipmanifest.xml
automatically. It also works for other media zips.
