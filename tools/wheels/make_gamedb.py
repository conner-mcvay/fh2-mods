# Writes fh2wheels' gamedb half:
#  - mods\fh2wheels\media\stripped\gamedbRC.slt\01-fh2wheels.sql:
#    - wheel offsets and tire profiles (menu.c): the Tires & Rims categories, the option names and the part rows;
#    - rim sizes: every car's front and rear rims from 13" to 26" (made in SQL from the stock rows, so it covers
#      whatever cars the gamedb it is applied to has, imported ones included);
#    - a wider ride height tuning range for adjustable springs;
#  (the wider camber tuning range is mods\fh2wheels\media\physics\PhysicsSettings.ini.set)
#  - tools\wheels\strings.h: the text of those names. The game shows gamedb text only through its string tables
#    ("_&<id>": table in the high 16 bits, key in the low 16), so the rows refer to keys in STRING_RANGES, which no
#    string table uses, and fh2wheels answers the game's lookups of them (text.c).
# OFFSETS / PROFILES must match menu.c's g_offsetMm / g_profileDelta (index = Level).
import os
OFFSETS = [0, -20, -15, -10, -5, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 75, 100, 150]
RIDE_LOWER, RIDE_HIGHER, RIDE_MIN = 0.10, 0.15, 0.02   # m more ride height range down / up for adjustable springs
TYPES = [(60, 22, 7, 'Front Wheel Offset', 'front'), (61, 42, 8, 'Rear Wheel Offset', 'rear')]   # id, PartEnum, DisplayOrder
PRICE = 500   # menu.c's OFFSET_PRICE
ICON = 'GAME:\\Media\\UI\\Textures\\Data_Bound\\Upgrade_Parts\\'
STRING_RANGES = [(59750, 67), (3212, 64)]   # (first key, count): free in every stringtables\*.zip table (all languages)
TABLE_UPGRADETYPES, TABLE_UPGRADES = 0xF0AF, 0x7091   # high 16 bits of those tables' own ids

# Rim sizes from RIM_MIN to RIM_MAX for every car, besides the sizes it already offers. The part list is ordered by
# Level: the game's own sizes (levels 0-8), then larger ones (Level = RIM_LARGER_LEVEL + diameter, smallest first),
# then smaller ones (Level = RIM_SMALLER_LEVEL - diameter, largest first). Each inch from stock weighs
# RIM_MASS_PER_INCH, as the game's larger sizes do.
RIM_MIN, RIM_MAX, RIM_MASS_PER_INCH = 13, 26, 1.36
RIM_LARGER_LEVEL, RIM_LARGER_PRICE = 30, 1200     # levels 44..56
RIM_SMALLER_LEVEL, RIM_SMALLER_PRICE = 100, 400   # levels 75..87
RIM_TYPES = [('22', 'List_UpgradeRimSizeFront', 'FrontWheelDiameter', 'front'), ('56', 'List_UpgradeRimSizeRear', 'RearWheelDiameter', 'rear')]

strings = []   # in key order through STRING_RANGES
def key_of(i):
    for base, count in STRING_RANGES:
        if i < count: return base + i
        i -= count
    raise ValueError('out of free string keys')
def text(table, s):
    if s not in strings: strings.append(s)
    return f"'_&{(table << 16) | key_of(strings.index(s))}'"

out = ["-- fh2wheels: per-axle wheel offsets, tire profiles and 13-26 inch rims under Tires & Rims, wider ride height tuning (needs fh2wheels.dll)", '']
uid = 1000
for tid, enum, order, name, axle in TYPES:
    out.append(f'INSERT INTO UpgradeTypes (id, PartEnum, AreaId, IsException, DisplayOrder, EverymanUpgradeDisplayOrder, Name, Description, IconPath, ImagePath) '
               f'VALUES ({tid}, {enum}, 4, 1, {order}, -1, {text(TABLE_UPGRADETYPES, name)}, '
               f'{text(TABLE_UPGRADETYPES, f"Moves the {axle} wheels in or out, for a wider or narrower track.")}, '
               f"'{ICON}Tire_Rims\\rim_size_Icon.swatchbin', '{ICON}Tire_Rims\\rim_size_LG_Icon.swatchbin');")
    for lv, mm in enumerate(OFFSETS):
        if mm == 0:
            n, d, i, il = 'Stock', f'The {axle} wheels where the factory put them.', 'stock_Icon', 'stock_LG_Icon'
        else:
            n = f'{mm:+d} mm'
            d = f'Moves each {axle} wheel {abs(mm)} mm {"out" if mm > 0 else "in"}.'
            k = min(7, max(1, (lv + 1) // 2))
            i, il = f'Tire_Rims\\rim_size_{k}', f'Tire_Rims\\rim_size_LG_{k}'
        out.append(f'INSERT INTO Upgrades (id, TypeId, IsException, Name, Level, Description, IconPath, ImagePath) '
                   f"VALUES ({uid}, '{tid}', 1, {text(TABLE_UPGRADES, n)}, {lv}, {text(TABLE_UPGRADES, d)}, '{ICON}{i}.swatchbin', '{ICON}{il}.swatchbin');")
        uid += 1
    out.append('')

# The offset parts themselves, so the game's lookups of a fitted or bought one find a row (buying needs it): neutral
# values, EngineID / MotorID -1 so no car lists them as its own (fh2wheels adds them to every car's part list).
for base, table, cols in ((91000000, 'List_UpgradeEngineRestrictorPlate', 'Id, EngineID, Level, IsStock, ManufacturerID, MassDiff, Price, TorqueScale'),
                          (92000000, 'List_UpgradeMotorParts', 'Id, MotorID, Level, IsStock, ManufacturerID, MassDiff, WeightDistDiff, Price, TorqueScale')):
    for lv, mm in enumerate(OFFSETS):
        price = 0 if lv == 0 else PRICE
        vals = f'{base + 1000 + mm}, -1, {lv}, {int(lv == 0)}, 0, 0.0, ' + ('0.0, ' if 'WeightDistDiff' in cols else '') + f'{price}, 1.0'
        out.append(f'INSERT INTO {table} ({cols}) VALUES ({vals});')
    out.append('')

# Tire profiles: categories and options (aspect points added to what the fitted width and rim give), then neutral
# part rows in the borrowed tables (Quad Turbo: no engine; Motor: no car, no motor).
PROFILES = [0, -20, -15, -10, -5, 5, 10, 15, 20, 25, 30, 35]
PROFILE_PRICE = 600   # menu.c's PROFILE_PRICE
for tid, enum, order, name, axle in ((62, 26, 9, 'Front Tire Profile', 'front'), (63, 3, 10, 'Rear Tire Profile', 'rear')):
    out.append(f'INSERT INTO UpgradeTypes (id, PartEnum, AreaId, IsException, DisplayOrder, EverymanUpgradeDisplayOrder, Name, Description, IconPath, ImagePath) '
               f'VALUES ({tid}, {enum}, 4, 1, {order}, -1, {text(TABLE_UPGRADETYPES, name)}, '
               f'{text(TABLE_UPGRADETYPES, f"Taller or shorter {axle} tire sidewalls on the same rims: changes the tire aspect ratio.")}, '
               f"'{ICON}Tire_Rims\\tire_width_Icon.swatchbin', '{ICON}Tire_Rims\\tire_width_LG_Icon.swatchbin');")
    for lv, d in enumerate(PROFILES):
        if d == 0:
            n, ds, i, il = 'Stock', 'The tire profile that comes with the fitted width and rim size.', 'stock_Icon', 'stock_LG_Icon'
        else:
            n = f'Aspect {d:+d}'
            ds = (f'Aspect ratio {abs(d)} points {"higher" if d > 0 else "lower"} (a 255/40 becomes a 255/{40 + d}): '
                  f'{"taller" if d > 0 else "shorter"} sidewalls and tires on the same rim.')
            k = min(5, max(1, (lv + 1) // 2))
            i, il = f'Tire_Rims\\tire_width_{k}', f'Tire_Rims\\tire_width_LG_{k}'
        out.append(f'INSERT INTO Upgrades (id, TypeId, IsException, Name, Level, Description, IconPath, ImagePath) '
                   f"VALUES ({uid}, '{tid}', 1, {text(TABLE_UPGRADES, n)}, {lv}, {text(TABLE_UPGRADES, ds)}, '{ICON}{i}.swatchbin', '{ICON}{il}.swatchbin');")
        uid += 1
    out.append('')
for lv, d in enumerate(PROFILES):
    price, stock = (0 if lv == 0 else PROFILE_PRICE), int(lv == 0)
    out.append('INSERT INTO List_UpgradeEngineTurboQuad (Id, EngineID, Level, IsStock, ManufacturerID, Price, MomentInertia, MaxScale, PowerMaxScale, MinScale, '
               'PowerMinScale, RobScale, TorqueDropOffRPM0, TorqueDropOffRPM1, TorqueDropOffScale0, TorqueDropOffScale1) '
               f'VALUES ({93000000 + 1000 + d}, -1, {lv}, {stock}, 0, {price}, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 9000.0, 15000.0, 1.0, 1.0);')
for lv, d in enumerate(PROFILES):
    price, stock = (0 if lv == 0 else PROFILE_PRICE), int(lv == 0)
    out.append('INSERT INTO List_UpgradeMotor (Id, Ordinal, Level, MotorID, IsStock, ManufacturerID, Price, MassDiff, WeightDistDiff) '
               f'VALUES ({94000000 + 1000 + d}, -1, {lv}, -1, {stock}, 0, {price}, 0.0, 0.0);')
out.append('')

# Ride height: the tuning range of every adjustable spring package (the ones whose range isn't a single height)
# goes RIDE_LOWER further down (never below RIDE_MIN) and RIDE_HIGHER further up.
out.append(f'UPDATE List_SpringDamperPhysics SET MinRideHeight = MAX({RIDE_MIN}, MinRideHeight - {RIDE_LOWER}), '
           f'MaxRideHeight = MaxRideHeight + {RIDE_HIGHER} WHERE MaxRideHeight > MinRideHeight;')
out.append('')

# Rim sizes: a row per car and size it doesn't offer yet (Id 900000000 + car * 100 + diameter), below or above its
# stock rim; then the names of those levels (larger ones reuse the game's "Upgraded ... Rim Size" text and icon).
for tid, table, col, axle in RIM_TYPES:
    out.append(f'WITH RECURSIVE sizes(inch) AS (SELECT {RIM_MIN} UNION ALL SELECT inch + 1 FROM sizes WHERE inch < {RIM_MAX}) '
               f'INSERT INTO {table} (Id, Ordinal, Level, IsStock, {col}, Price, MassDiff, DragScale, WindInstabilityScale, RequiresGraphics) '
               f'SELECT 900000000 + s.Ordinal * 100 + z.inch, s.Ordinal, '
               f'CASE WHEN z.inch < s.{col} THEN {RIM_SMALLER_LEVEL} - z.inch ELSE {RIM_LARGER_LEVEL} + z.inch END, 0, z.inch, '
               f'CASE WHEN z.inch < s.{col} THEN {RIM_SMALLER_PRICE} ELSE {RIM_LARGER_PRICE} END, '
               f'ROUND({RIM_MASS_PER_INCH} * (z.inch - s.{col}), 2), 1.0, 1.0, 0 '
               f'FROM {table} AS s JOIN sizes AS z ON z.inch <> s.{col} '
               f'WHERE s.IsStock = 1 AND NOT EXISTS (SELECT 1 FROM {table} AS o WHERE o.Ordinal = s.Ordinal AND o.{col} = z.inch);')
    side = axle.capitalize()
    for inch in range(RIM_MIN, RIM_MAX):   # smaller than some car's stock rim: 13 .. RIM_MAX - 1
        out.append(f'INSERT INTO Upgrades (id, TypeId, IsException, Name, Level, Description, IconPath, ImagePath) '
                   f"VALUES ({uid}, '{tid}', 0, {text(TABLE_UPGRADES, f'Smaller {side} Rim Size')}, {RIM_SMALLER_LEVEL - inch}, "
                   f"{text(TABLE_UPGRADES, f'Install smaller-diameter {axle} rims with taller-profile tires of the same overall size, for more sidewall and a softer edge.')}, "
                   f"'{ICON}Tire_Rims\\rim_size_1.swatchbin', '{ICON}Tire_Rims\\rim_size_LG_1.swatchbin');")
        uid += 1
    for inch in range(RIM_MIN + 1, RIM_MAX + 1):   # larger than some car's stock rim
        out.append(f'INSERT INTO Upgrades (id, TypeId, IsException, Name, Level, Description, IconPath, ImagePath) '
                   f"SELECT {uid}, '{tid}', 0, Name, {RIM_LARGER_LEVEL + inch}, Description, "
                   f"'{ICON}Tire_Rims\\rim_size_7.swatchbin', '{ICON}Tire_Rims\\rim_size_LG_7.swatchbin' "
                   f"FROM Upgrades WHERE TypeId = '{tid}' AND IsException = 0 AND Level = 1;")
        uid += 1
    out.append('')

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
p = os.path.join(root, 'mods', 'fh2wheels', 'media', 'stripped', 'gamedbRC.slt', '01-fh2wheels.sql')
os.makedirs(os.path.dirname(p), exist_ok=True)
open(p, 'w', newline='\n').write('\n'.join(out) + '\n')
open(os.path.join(root, 'mods', 'fh2wheels', 'README.txt'), 'w', newline='\n').write(
    'fh2wheels (gamedb half): Front/Rear Wheel Offset and Tire Profile categories, and rim sizes from 13" to 26",\n'
    'under Tires & Rims; ride height tuning 10 cm lower / 15 cm higher (adjustable springs), camber -15 to 15.\n'
    'Needs fh2wheels.dll (tools\\wheels), which makes the offsets work and supplies the text.\n')
print(p)

def c_wide(s): return 'L"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
h = ['// Generated by make_gamedb.py: the text of fh2wheels\' string keys (text.c), by range of free keys.']
ranges, i = [], 0
for r, (base, count) in enumerate(STRING_RANGES):
    part = strings[i:i + count]; i += count
    if not part: break
    h.append(f'static const wchar_t *const g_strings{r}[] = {{')
    h += [f'  {c_wide(s)},' for s in part]
    h.append('};')
    ranges.append(f'  {{ {base}, {len(part)}, g_strings{r} }},')
h.append('static const struct { unsigned base, count; const wchar_t *const *text; } g_stringRanges[] = {')
h += ranges
h.append('};')
p = os.path.join(here, 'strings.h')
open(p, 'w', newline='\n').write('\n'.join(h) + '\n')
print(p, len(strings), 'strings')
