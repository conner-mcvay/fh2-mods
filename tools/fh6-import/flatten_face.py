# Takes dish out of a converted FH2 wheel: the face (everything inside radius <face_r>, in front of x = <x_max>) moves
# <d> towards the lip (-x, in FH2's normalised wheel space: the lip front at x = 0, x = 1 the back of the barrel), and
# the dish between the face and the lip (face_r .. lip_r) is blended from <d> to 0, so it stays joined to both. The lip,
# the barrel and the motion-blur meshes stay; so does the spindle, so the tire sits where it did. The rim size and
# width morphs are offsets (width moves only the barrel), so they keep working. Mesh bounding boxes are recomputed.
#   py -3 flatten_face.py <model.modelbin> <d> [face_r 0.115] [lip_r 0.1375] [x_max 0.3]
import sys, struct, math
import burg
from fh6model import Model, blob_id

def main(path, d, face_r='0.115', lip_r='0.1375', x_max='0.3'):
    d, face_r, lip_r, x_max = float(d), float(face_r), float(lip_r), float(x_max)
    M = Model(path); blobs = M.blobs
    pos_b = [b for b in blobs if b['tag'] == 'VerB' and blob_id(b) == -1][0]
    pd = bytearray(pos_b['data'])
    blur = {mid for mid, m in M.mats.items() if 'wheel_blur' in m['path'].lower()}
    verts = set()
    for m in M.meshes:
        if m.material in blur: continue
        po = m.streams[0][3] // 12
        for k in range(m.istart, m.istart + m.icount): verts.add(M.index(k) + m.base + po)
    moved = 0; lo_x = 9e9
    for v in verts:
        x, y, z = struct.unpack_from('<3f', pd, 16 + 12 * v)
        r = math.hypot(y, z)
        if x >= x_max or r >= lip_r: continue
        w = 1.0 if r <= face_r else (lip_r - r) / (lip_r - face_r)
        struct.pack_into('<f', pd, 16 + 12 * v, x - d * w); moved += 1; lo_x = min(lo_x, x - d * w)
    pos_b['data'] = bytes(pd)
    for b in blobs:
        if b['tag'] != 'Mesh': continue
        md = b['data']; istart, base, icount = struct.unpack_from('<iii', md, 0x19)
        off = struct.unpack_from('<i', md, 0x39 + 12)[0] // 12
        lo = [9e9] * 3; hi = [-9e9] * 3
        for k in range(istart, istart + icount):
            p = struct.unpack_from('<3f', pd, 16 + 12 * (M.index(k) + base + off))
            for c in range(3): lo[c] = min(lo[c], p[c]); hi[c] = max(hi[c], p[c])
        if icount: b['meta'] = [(t, struct.pack('<6f', *lo, *hi) if t == 'BBox' else v) for t, v in b['meta']]
    open(path, 'wb').write(burg.write(blobs))
    print(f'face: {moved} vertices moved up to {d} towards the lip; frontmost moved vertex now at x={lo_x:.4f}'
          + (' (in front of the lip!)' if lo_x < 0 else ''))

if __name__ == '__main__':
    main(*sys.argv[1:6])
