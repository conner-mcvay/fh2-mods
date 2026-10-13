FORZA HORIZON 2 (PC) - PHOTO MODE UNBOUND
=========================================

Lifts photo mode's limits so it works as a free camera: fly anywhere with the
controller (photo mode's own controls), with no height cap, no 100 m leash
around the car, no ceiling or floor and no collision.

Built for game version 1.0.0.64 (Anthem_1.0.0.64_x64__8wekyb3d8bbwe).

What it changes in Camera.zip\CameraSettings.ini (only these keys; other mods
changing other keys of the file, like cockpit-fov, still apply):
  PhotoModeCam\MaxHeight                         2 -> 1000
  PhotoModeCam\BoundaryCylinderRadius          100 -> 100000
  PhotoModeCam\BoundaryCeilingHeight            30 -> 5000
  PhotoModeCam\BoundaryFloorDepth               30 -> 5000
  PhotoModeCam\CollisionFixIterations            5 -> 0
  PhotoModeCam\CollisionSphereRadius           0.5 -> 0.01
  PhotoModeCam\CarBoundingBox...Expansion      0.5 -> 0
