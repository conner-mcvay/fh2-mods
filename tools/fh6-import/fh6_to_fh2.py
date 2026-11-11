# Converts an FH6 wheel (.modelbin burG 1.1 / Mesh v1.12, AO .swatchbin) to FH2's formats (burG 1 / Mesh v1.7).
# The output model still has FH6's vertex inputs (all UV sets, two tangents); Fm5ModelConverter then fits each layout
# to the inputs of its FH2 shader, as for FM5 imports.
#   py -3 fh6_to_fh2.py <FH6 wheel zip> <FH2 media folder> <out dir> [material map json]
import sys, os, struct, math, zipfile, glob, json, collections
import burg
from fh6model import Model, Mesh, Layout, VerB, meta, blob_id, decode, slot_offsets
import gcntile

def base_color(mtpr):
    # the first opaque RGB colour in an FH6 material's parameters (wheelpaint's base colour), or None
    for i in range(len(mtpr) - 15):
        if mtpr[i + 12:i + 16] == b'\x00\x00\x80\x3f':
            c = struct.unpack_from('<3f', mtpr, i)
            if all(0 <= x <= 1.0001 for x in c): return c
    return None

def choose_material(name, path, mtpr, brand):
    # FH6 material instance -> FH2 library material (cars\_library\materials\...), by FH6 material type: part names
    # mean different things on different wheels. None drops the meshes using it.
    stem = path.replace('\\', '/').split('/')[-1].lower()[:-len('.materialbin')]
    if stem.startswith('wheelblur'): return 'specificuse/wheel_blur'
    if stem in ('blackframe', 'blackhole'): return 'specificuse/zeroblack'
    if stem.startswith('screw'): return 'basematerials/screw_003'
    if stem in ('chrome_ch1', 'mfr_badge_ch1', 'mfr_wheel_badge_ch1'):
        # decals: their UVs fit FH6's texture. Only <brand>_badge_002 is laid out like FH2's <brand>_badge_001;
        # others (wel_badge_003, weldracing_001: embossed lettering) would cut pieces out of an unrelated texture
        if f'{brand}_badge_002'.encode() in mtpr.lower(): return f'badges/{brand}_badge_001'
        if b'_alpha' not in mtpr.lower(): return 'wheelmaterials/chrome'   # solid part with only a normal-map pattern
        return None
    if stem == 'wheelpaint_ch1': return None          # pattern decals; FH2 has nothing like them
    if stem == 'paintedmetal_ch1' and 'cap' in name.lower(): return f'badges/{brand}_badge_001'   # RimStudio's cap logo
    if stem == 'rubber': return 'wheelmaterials/paint_matteblack'
    if stem == 'chrome': return 'wheelmaterials/chrome'
    if stem == 'aluminum': return 'basematerials/aluminum_machined'
    if stem == 'wheelpaint':
        if 'valve' in name.lower(): return 'wheelmaterials/paint_matteblack'
        c = base_color(mtpr) or (0, 0, 0)
        if max(c) < 0.1: return 'wheelmaterials/paint_glossblack'
        if c[0] > c[1] > c[2] and c[0] - c[2] > 0.05: return 'wheelmaterials/brass_machined_satin'
        return 'wheelmaterials/metalicpaint_silver'
    raise SystemExit(f"no FH2 material for FH6 material '{name}' ({path}); add it to choose_material or the map file")
DISC = (0.053326, 0.893466, 0.054056, 0.893483)   # <brand>_badge_002's UV transform (FH6 M77 cap): the disc in FH2's badge texture
PASS_OPAQUE_SHADOW, PASS_OPAQUE, PASS_SHADOW = 0x19, 0x11, 0x09

def h(x): return struct.unpack('<H', struct.pack('<e', x))[0]

def lib_path(p): return 'Game:\\Media\\cars\\_library\\materials\\' + p.replace('/', '\\') + '.materialbin'

def fh2_wheels(media):
    # every FH2 wheel model: (MatI blobs by library path, TRef set, material path set)
    res = []
    for z in sorted(glob.glob(os.path.join(media, 'cars', '_library', 'scene', 'wheels', '*.zip'))):
        zf = zipfile.ZipFile(z); n = [x for x in zf.namelist() if x.endswith('.modelbin')]
        if not n: continue
        f = burg.read(zf.read(n[0])); mats = {}
        for b in f['blobs']:
            if b['tag'] != 'MatI': continue
            inner = burg.read(b['data']); mati = [c for c in inner['blobs'] if c['tag'] == 'MATI'][0]['data']
            p = mati[1:1 + mati[0]].decode('latin1').lower().replace('\\', '/').split('/materials/')[-1][:-len('.materialbin')]
            mats[p] = b
        modl = [b for b in f['blobs'] if b['tag'] == 'Modl'][0]; t = meta(modl, 'TRef'); c = struct.unpack_from('<I', t, 0)[0]
        res.append((os.path.basename(z), mats, set(t[4 + 4 * i:8 + 4 * i] for i in range(c)), f))
    return res

def mesh_bytes(material, flags, istart, base, icount, prims, lodscale, vcount, layout, nstreams, s0, s1, morph, uvx):
    d = struct.pack('<h', material) + flags + struct.pack('<iiiifi', istart, base, icount, prims, lodscale, vcount)
    d += struct.pack('<ii', layout, nstreams) + struct.pack('<iiii', *s0) + struct.pack('<iiii', *s1) + morph + uvx
    assert len(d) == 185, len(d)
    return d

def layout_bytes(elems, mask, tail=b''):
    names = []
    for e in elems:
        if e['sem'] not in names: names.append(e['sem'])
    d = struct.pack('<H', len(names))
    for n in names: d += struct.pack('<I', len(n)) + n.encode()
    d += struct.pack('<H', len(elems))
    for e in elems: d += struct.pack('<HHHHIII', names.index(e['sem']), e['idx'], e['slot'], 0, e['fmt'], 0xFFFFFFFF, 0)
    for e in elems: d += struct.pack('<I', e['code'])
    return d + struct.pack('<I', mask) + tail

def verb_bytes(count, stride, nel, first, data):
    return struct.pack('<IIHHI', count, len(data), stride, nel, first) + data

def convert_model(src, media, matmap, log, brand):
    M = Model(src); W = fh2_wheels(media)
    by_path = {}
    for name, mats, tref, f in W:
        for p, b in mats.items(): by_path.setdefault(p, b)
    tmpl = next(f for name, mats, tref, f in W if name.lower() == 'wel_magnumiii.zip')

    # materials: FH6 Id -> FH2 MatI (copied from an FH2 wheel using the same library material), keeping FH6 names/Ids
    keep_ids = {}; matblobs = []; used_paths = []; disc_uv = set(); uv0 = {}
    referenced = {m.material for m in M.meshes}
    for mid in sorted(M.mats):
        m = M.mats[mid]
        if mid not in referenced: continue                # RimStudio lists every slot, used or not
        mtpr = [c for c in burg.read(m['blob']['data'])['blobs'] if c['tag'] == 'MTPR'][0]['data']
        if m['name'] in matmap: p = matmap[m['name']]
        else: p = choose_material(m['name'], m['path'], mtpr, brand)
        if p is None: log.append(f"material {m['name']}: dropped"); continue
        # a badge whose FH6 texture is a whole logo disc over UV 0..1 (not <brand>_badge_002's layout): map that
        # square onto the badge disc of FH2's texture, as <brand>_badge_002's UV transform does
        # ("uv0:<name>" in the map file instead gives that transform outright, e.g. copied from an FH2 wheel using
        # the same badge, for FH6's own whole-disc badge quads, which aren't mirrored)
        if f"uv0:{m['name']}" in matmap: uv0[mid] = matmap[f"uv0:{m['name']}"]
        elif p.startswith('badges/') and f'{brand}_badge_002'.encode() not in mtpr.lower(): disc_uv.add(mid)
        if p not in by_path: raise SystemExit(f'{p}: no FH2 wheel uses this material')
        keep_ids[mid] = len(keep_ids)
        src_blob = by_path[p]
        matblobs.append(dict(tag='MatI', maj=1, min=0, meta=[('Name', m['name'].encode()), ('Id  ', struct.pack('<i', keep_ids[mid]))],
                             data=src_blob['data']))
        used_paths.append(p); log.append(f"material {m['name']}: {m['path'].split(chr(92))[-1].split('/')[-1]} -> {p}")
    # texture refs: per material, what every FH2 wheel using it references; union over the materials
    tref = set()
    for p in set(used_paths):
        sets = [t for name, mats, t, f in W if p in mats]
        tref |= set.intersection(*sets)

    # positions: FH6 snorm16x4 (xyz scaled per mesh, w = normal x) -> float3, one buffer like FH2's
    P = M.vbs[0] if 0 in M.vbs else None
    pos_vb = {m.streams[0][0] for m in M.meshes}; assert len(pos_vb) == 1, pos_vb
    P = M.vbs[pos_vb.pop()]
    scales = {(m.pos_scale, m.pos_offset) for m in M.meshes}; assert len(scales) == 1, scales
    sc, of = scales.pop()
    raw = [decode(13, P.bytes, i * P.stride) for i in range(P.count)]
    pos = [[r[k] * sc[k] + of[k] for k in range(3)] for r in raw]
    nx = [r[3] for r in raw]
    posdata = b''.join(struct.pack('<3f', *p) for p in pos)

    # stream-1 buffers: FH6 VerB id -> FH2 id (0..), vertex -> position index offset, morph buffer
    s1ids = sorted({m.streams[1][0] for m in M.meshes})
    vbmap = {v: i for i, v in enumerate(s1ids)}
    posoff = {}; mbmap = {}; laymap = {}
    for m in M.meshes:
        po = m.streams[0][3] // m.streams[0][2] - m.streams[1][3] // m.streams[1][2]
        assert posoff.setdefault(m.streams[1][0], po) == po, 'buffer used with two position offsets'
        mb = struct.unpack_from('<i', m.morph, 0)[0]
        assert mbmap.setdefault(mb, m.streams[1][0]) == m.streams[1][0]
        assert laymap.setdefault(m.streams[1][0], m.layout) == m.layout
    layids = sorted(set(laymap.values())); laynew = {l: i for i, l in enumerate(layids)}
    POS_LAYOUT = len(layids)

    blobs = []
    sk = [b for b in M.blobs if b['tag'] == 'Skel'][0]['data']
    i = sk.find(b'spindle'); mo = i + 7 + 6
    tx = struct.unpack_from('<f', sk, mo + 48)[0]
    # the spindle is the wheel's mounting face, the back of the hub, in both games (FH2's own wheels: within 0.5 mm).
    # A spindle behind all of the hub (RimStudio) would leave the wheel standing off the car's hub: mount it flush
    hub = 0.0
    for m in M.meshes:
        if not (m.flags[2] & 3) or m.flags[6] == 0x1C: continue
        po = m.streams[0][3] // m.streams[0][2]
        for k in range(m.istart, m.istart + m.icount):
            p = pos[M.index(k) + m.base + po]
            if math.hypot(p[1], p[2]) < 0.06: hub = max(hub, p[0])
    sx = tx
    if tx > hub + 0.002:
        # RimStudio: models without a raised hub pad have spokes as deep as the hub, which FH2's calipers would cut
        # through. Mount 0.05 behind the spokes, about the clearance FH6's own wheels have (S72 0.042, M77 0.06)
        spokes = 0.0
        for m in M.meshes:
            if not (m.flags[2] & 3) or m.flags[6] == 0x1C: continue
            po = m.streams[0][3] // m.streams[0][2]
            for k in range(m.istart, m.istart + m.icount):
                p = pos[M.index(k) + m.base + po]
                if 0.05 < math.hypot(p[1], p[2]) < 0.11: spokes = max(spokes, p[0])
        sx = max(hub, spokes + 0.05)
    sk = bytearray(sk[:-4]); struct.pack_into('<f', sk, mo + 48, sx)
    log.append(f'spindle x {tx:.4f}' + (f' -> {sx:.4f}' if sx != tx else ' (back of the hub)'))
    blobs.append(dict(tag='Skel', maj=0, min=0, meta=[], data=bytes(sk)))
    blobs.append(dict(tag='Mrph', maj=0, min=0, meta=[], data=[b for b in M.blobs if b['tag'] == 'Mrph'][0]['data']))
    blobs += matblobs

    meshes = []; shadows = []
    for m in M.meshes:
        if m.material not in keep_ids: continue
        fl = bytearray(m.flags); lodmask = fl[2]
        if lodmask == 0x02: continue                 # FH6 LOD0: FH2 wheels draw their LODS set at LOD0 too
        if lodmask == 0x01: fl[2], fl[4], fl[5] = 0x03, 0x00, 0xFF
        name = m.name + ('0' if m.name.endswith('_LODS') else '')
        pas = fl[6]
        vb6 = m.streams[1][0]; vb = vbmap[vb6]
        s0 = (-1, 0, 12, (m.streams[0][3] // m.streams[0][2]) * 12)
        st = m.streams[1]
        lay = laynew[m.layout]
        stride1 = None   # filled once the stream-1 layout is known
        morph = struct.pack('<i', vb) + m.morph[4:]
        uvx = m.uvx
        if m.material in disc_uv:   # UV transform per set: offset u, scale u, offset v, scale v
            ou, su, ov, sv = struct.unpack_from('<4f', uvx, 0)
            # u mirrored: the whole-disc logos (RimStudio) are laid out mirrored relative to FH2's badge texture
            uvx = struct.pack('<4f', DISC[0] + DISC[1] * (1 - ou), -DISC[1] * su, DISC[2] + DISC[3] * ov, DISC[3] * sv) + uvx[16:]
        elif m.material in uv0:
            uvx = struct.pack('<4f', *uv0[m.material]) + uvx[16:]
        if pas == PASS_OPAQUE_SHADOW:
            fl[6] = PASS_OPAQUE
            sf = bytearray(fl); sf[6] = PASS_SHADOW
            shadows.append(dict(tag='Mesh', maj=1, min=7, meta=[('Name', b'Shadow'), ('BBox', m.bbox)],
                                data=mesh_bytes(-1, bytes(sf), m.istart, m.base, m.icount, m.icount // 3, m.lodscale, 0, POS_LAYOUT, 1,
                                                s0, (vb, -1, 0, 0), bytes(16), bytes(80))))
        meshes.append((m, name, bytes(fl), keep_ids[m.material], s0, vb, lay, morph, uvx))
    # one detail level only (RimStudio): FH2 would stop drawing the wheel past LOD0, so LOD1-3 reuse the geometry
    if not any(x[2][2] & 0x1C for x in meshes):
        base_m, base_s = list(meshes), list(shadows)
        for lod in (1, 2, 3):
            def at(fl):
                fl = bytearray(fl); fl[2], fl[4], fl[5] = 0x02 << lod, lod, lod; return bytes(fl)
            for x in base_m: meshes.append((x[0], x[1].replace('_LODS0', '_LOD%d' % lod), at(x[2])) + x[3:])
            for b in base_s:
                d = bytearray(b['data']); d[2:2 + 23] = at(d[2:2 + 23]); shadows.append(dict(b, data=bytes(d)))
        log.append('one detail level: added LOD1-3 entries using the same geometry')

    # layouts and stream-1 buffers in FH2 formats
    layblobs = []; strides = {}
    for l6 in layids:
        L = M.layouts[l6]
        elems = [dict(sem='POSITION', idx=0, slot=0, fmt=6, code=3), dict(sem='NORMAL', idx=0, slot=1, fmt=10, code=9)]
        uvs = [e['idx'] for e in L.elems if e['sem'] == 'TEXCOORD']
        tans = [e['idx'] for e in L.elems if e['sem'] == 'TANGENT' and e['idx'] < 2]
        elems += [dict(sem='TEXCOORD', idx=k, slot=1, fmt=35, code=0x2E) for k in uvs]
        elems += [dict(sem='TANGENT', idx=k, slot=1, fmt=10, code=9) for k in tans]
        mask = sum(1 << k for k in uvs) | sum(1 << (5 + k) for k in tans)
        layblobs.append(dict(tag='VLay', maj=1, min=1, meta=[('Id  ', struct.pack('<i', laynew[l6]))], data=layout_bytes(elems, mask)))
        strides[l6] = (uvs, tans, 8 + 4 * len(uvs) + 8 * len(tans))
    pos_lay = [b for b in tmpl['blobs'] if b['tag'] == 'VLay' and blob_id(b) == -1][0]
    layblobs.append(dict(tag='VLay', maj=1, min=1, meta=[('Id  ', struct.pack('<i', -1))], data=pos_lay['data']))

    vbblobs = []; tanstats = collections.Counter()
    for vb6 in s1ids:
        V = M.vbs[vb6]; L = M.layouts[laymap[vb6]]; off, _ = slot_offsets(L, 1)
        uvs, tans, stride = strides[laymap[vb6]]; out = bytearray()
        for v in range(V.count):
            b = v * V.stride; pi = v + posoff[vb6]
            ny, nz = decode(37, V.bytes, b + off[('NORMAL', 0)][0])[:2]
            n = [nx[pi], ny, nz]; ln = math.sqrt(sum(c * c for c in n)) or 1
            out += struct.pack('<4H', h(n[0] / ln), h(n[1] / ln), h(n[2] / ln), 0)
            for k in uvs: o = b + off[('TEXCOORD', k)][0]; out += V.bytes[o:o + 4]
            for k in tans:
                t = decode(24, V.bytes, b + off[('TANGENT', k)][0])
                xyz = [c * 2 - 1 for c in t[:3]]; ln = math.sqrt(sum(c * c for c in xyz)) or 1
                a = round(t[3] * 3); tanstats[a] += 1
                out += struct.pack('<4H', h(xyz[0] / ln), h(xyz[1] / ln), h(xyz[2] / ln), h(1.0 if a >= 2 else -1.0))
        vbblobs.append((vbmap[vb6], dict(tag='VerB', maj=1, min=0, meta=[('Id  ', struct.pack('<i', vbmap[vb6]))],
                                          data=verb_bytes(V.count, stride, 1 + len(uvs) + len(tans), 10, bytes(out)))))
    log.append(f'tangent handedness bits: {dict(tanstats)}')

    for m, name, fl, mat, s0, vb, lay, morph, uvx in meshes:
        uvs, tans, stride = strides[m.layout]
        s1 = (vb, 1, stride, (m.streams[1][3] // m.streams[1][2]) * stride)
        blobs.append(dict(tag='Mesh', maj=1, min=7, meta=[('Name', name.encode()), ('BBox', m.bbox)],
                          data=mesh_bytes(mat, fl, m.istart, m.base, m.icount, m.prims, m.lodscale, m.vcount, lay, 2, s0, s1, morph, uvx)))
    blobs += shadows
    ib = [b for b in M.blobs if b['tag'] == 'IndB'][0]
    blobs.append(dict(tag='IndB', maj=1, min=0, meta=[('Id  ', struct.pack('<i', 0))], data=ib['data']))
    blobs += layblobs
    blobs.append(dict(tag='VerB', maj=1, min=0, meta=[('Id  ', struct.pack('<i', -1))], data=verb_bytes(P.count, 12, 1, 6, posdata)))
    mbufs = {blob_id(b): b for b in M.blobs if b['tag'] == 'MBuf'}
    for new, b in sorted(vbblobs, key=lambda x: x[0]):
        blobs.append(b)
        for mb6, vb6 in mbmap.items():
            if vbmap[vb6] == new and mb6 in mbufs:
                blobs.append(dict(tag='MBuf', maj=1, min=0, meta=[('Id  ', struct.pack('<i', new))], data=mbufs[mb6]['data']))
    nmesh = sum(1 for b in blobs if b['tag'] == 'Mesh'); nbuf = sum(1 for b in blobs if b['tag'] in ('IndB', 'VerB', 'MBuf'))
    nlay = sum(1 for b in blobs if b['tag'] == 'VLay'); nmat = len(matblobs)
    modl6 = [b for b in M.blobs if b['tag'] == 'Modl'][0]
    tail = [b for b in tmpl['blobs'] if b['tag'] == 'Modl'][0]['data'][8:]
    tr = struct.pack('<I', len(tref)) + b''.join(sorted(tref))
    blobs.append(dict(tag='Modl', maj=1, min=1, meta=[('BBox', meta(modl6, 'BBox')), ('TRef', tr)],
                      data=struct.pack('<HHHH', nmesh, nbuf, nlay, nmat) + tail))
    log.append(f'{len(meshes)} meshes + {len(shadows)} shadow meshes, {nbuf} buffers, {nlay} layouts, {nmat} materials, {len(tref)} texture refs')
    return burg.write(blobs)

def convert_ao(src, media):
    d = burg.read(src); px = d['blobs'][0]['data']; W = int(math.isqrt(len(px)))
    assert W * W == len(px) and W in (256, 512, 1024), f'AO is {len(px)} bytes, expected 256, 512 or 1024 square R8'
    if W == 256:   # FH2's wheel AO is 512 or 1024: bilinear upscale (texel centres aligned)
        def at(x, y): return px[min(max(y, 0), 255) * 256 + min(max(x, 0), 255)]
        up = bytearray(512 * 512)
        for y in range(512):
            fy = (y + 0.5) / 2 - 0.5; y0 = math.floor(fy); wy = fy - y0
            for x in range(512):
                fx = (x + 0.5) / 2 - 0.5; x0 = math.floor(fx); wx = fx - x0
                v = (at(x0, y0) * (1 - wx) + at(x0 + 1, y0) * wx) * (1 - wy) + (at(x0, y0 + 1) * (1 - wx) + at(x0 + 1, y0 + 1) * wx) * wy
                up[y * 512 + x] = int(v + 0.5)
        px, W = bytes(up), 512
    t = None
    for z in sorted(glob.glob(os.path.join(media, 'cars', '_library', 'scene', 'wheels', '*.zip'))):
        zf = zipfile.ZipFile(z)
        for n in zf.namelist():
            if n.lower().endswith('_ao.swatchbin'):
                a = zf.read(n); b = burg.read(a)['blobs'][0]
                if b['size'] == gcntile.levels(W)[1]: t = a; break
        if t: break
    hdr = t[:burg.read(t)['blobs'][0]['off']]
    if t is None: raise SystemExit(f'no FH2 {W}x{W} AO texture to take the header from')
    data = gcntile.tile(gcntile.mips(px, W), W)
    return hdr + data

if __name__ == '__main__':
    src_zip, media, out = sys.argv[1:4]
    matmap = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else {}
    zf = zipfile.ZipFile(src_zip); names = zf.namelist()
    mdl = [n for n in names if n.lower().endswith('_wheellf.modelbin')][0]; wheel = mdl.split('/')[-1][:-len('_wheelLF.modelbin')]
    ao = [n for n in names if n.lower() == f'textures/ao/{wheel.lower()}_wheellf_ao.swatchbin']
    if not ao: raise SystemExit(f'{src_zip}: no AO texture')
    os.makedirs(os.path.join(out, 'Textures', 'AO'), exist_ok=True)
    tmp = os.path.join(out, mdl.split('/')[-1] + '.fh6')
    open(tmp, 'wb').write(zf.read(mdl))
    log = []
    open(os.path.join(out, f'{wheel}_wheelLF.modelbin'), 'wb').write(convert_model(tmp, media, matmap, log, wheel.split('_')[0].lower()))
    os.remove(tmp)
    if ao: open(os.path.join(out, 'Textures', 'AO', f'{wheel}_wheelLF_AO.swatchbin'), 'wb').write(convert_ao(zf.read(ao[0]), media)); log.append('AO texture converted')
    print('\n'.join(log))
