FORZA HORIZON 2 (PC) - STOCK WHEEL SWAP
=======================================

Every car's stock wheels become wheel options for any car: put 2000GT wheels on
a Mustang, F40 wheels on a Golf. They're in the wheel shop next to the
aftermarket brands, filed under the car's brand (Toyota, Ferrari, ...).

Built for game version 1.0.0.64 (Anthem_1.0.0.64_x64__8wekyb3d8bbwe).

What it changes in gamedbRC.slt (List_Wheels, 344 stock wheels):
  - IsStock 1 -> 0, so the wheel shop lists them
  - PartManufacturerID -> the car brand (from the MediaName prefix: TOY -> Toyota,
    POR -> Porsche, ...). Bowler, Donkervoort and Local Motors have no brand
    entry in the game and show as "Stock"
  - DisplayName -> year + the game's own name for the car, e.g. "1969 2000GT"
  - Price -> by weight, on the same scale as the aftermarket wheels
    (3,200 - 3,800 CR)
Each car still starts on its own stock wheels.

Not changed: traffic and placeholder wheels, and 169 leftover wheel entries from
older Forza games whose cars (and wheel models) aren't in FH2.
