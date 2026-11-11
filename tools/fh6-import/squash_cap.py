# Shortens a converted FH2 wheel's centre cap: geometry inside radius <r> and in front of x = <seat> (the lug-nut
# tips) is pulled towards the seat, keeping <factor> of its protrusion. Mesh bounding boxes are recomputed.
#   py -3 squash_cap.py <model.modelbin> <r> <seat> <factor>
import sys, struct, math
import burg
from fh6model import Model, meta, blob_id

def main(path, rmax, seat, factor):
    rmax, seat, factor = float(rmax), float(seat), float(factor)
    M = Model(path); blobs = M.blobs
    pos_b = [b for b in blobs if b['tag'] == 'VerB' and blob_id(b) == -1][0]
    d = bytearray(pos_b['data']); count = struct.unpack_from('<I', d, 0)[0]
    blur = {mid for mid, m in M.mats.items() if 'wheel_blur' in m['path'].lower()}
    verts = set()
    for m in M.meshes:
        if m.material in blur: continue
        po = m.streams[0][3] // 12
        for k in range(m.istart, m.istart + m.icount): verts.add(M.index(k) + m.base + po)
    moved = 0
    for v in verts:
        x, y, z = struct.unpack_from('<3f', d, 16 + 12 * v)
        if math.hypot(y, z) < rmax and x < seat:
            struct.pack_into('<f', d, 16 + 12 * v, seat - (seat - x) * factor); moved += 1
    pos_b['data'] = bytes(d)
    # bounding boxes: min xyz, max xyz of each mesh's vertices
    for b in blobs:
        if b['tag'] != 'Mesh': continue
        md = b['data']; istart, base, icount = struct.unpack_from('<iii', md, 0x19)
        off = struct.unpack_from('<i', md, 0x39 + 12)[0] // 12
        lo = [9e9] * 3; hi = [-9e9] * 3
        for k in range(istart, istart + icount):
            p = struct.unpack_from('<3f', d, 16 + 12 * (M.index(k) + base + off))
            for c in range(3): lo[c] = min(lo[c], p[c]); hi[c] = max(hi[c], p[c])
        b['meta'] = [(t, struct.pack('<6f', *lo, *hi) if t == 'BBox' else v) for t, v in b['meta']]
    open(path, 'wb').write(burg.write(blobs))
    print(f'cap: {moved} vertices pulled towards x={seat} (keeping {factor:.0%} of their protrusion)')

if __name__ == '__main__':
    main(*sys.argv[1:5])
