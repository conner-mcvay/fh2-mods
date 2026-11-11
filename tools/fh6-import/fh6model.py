# FH6 (burG 1.1, Mesh v1.12) and FH2 (burG 1, Mesh v1.7) modelbin readers, for converting FH6 wheels to FH2.
import struct, math
import burg

def u32(d, o): return struct.unpack_from('<I', d, o)[0]
def i32(d, o): return struct.unpack_from('<i', d, o)[0]
def f32(d, o): return struct.unpack_from('<f', d, o)[0]

def meta(b, tag):
    for t, m in b['meta']:
        if t == tag: return m
    return None

def blob_id(b):
    m = meta(b, 'Id  ')
    return struct.unpack('<i', m)[0] if m is not None and len(m) == 4 else None

class Layout:
    def __init__(s, d):
        s.raw = d; p = 0; nn = struct.unpack_from('<H', d, p)[0]; p += 2; s.names = []
        for _ in range(nn):
            ln = u32(d, p); p += 4; s.names.append(d[p:p+ln].decode()); p += ln
        ne = struct.unpack_from('<H', d, p)[0]; p += 2; s.elems = []
        for _ in range(ne):
            sem, idx, slot, pad, fmt, off, cls = struct.unpack_from('<HHHHIII', d, p); p += 20
            s.elems.append(dict(sem=s.names[sem], idx=idx, slot=slot, pad=pad, fmt=fmt, off=off, cls=cls))
        for e in s.elems: e['code'] = u32(d, p); p += 4
        s.mask = u32(d, p); p += 4; s.tail = d[p:]

FMT_SIZE = {6: 12, 10: 8, 13: 8, 35: 4, 37: 4, 24: 4, 28: 4, 2: 16, 16: 8, 41: 4}

def slot_offsets(L, slot):
    o = 0; res = {}
    for e in L.elems:
        if e['slot'] == slot: res[(e['sem'], e['idx'])] = (o, e['fmt']); o += FMT_SIZE[e['fmt']]
    return res, o

class VerB:
    def __init__(s, d):
        s.count, s.size = struct.unpack_from('<II', d, 0); s.stride, s.nel = struct.unpack_from('<HH', d, 8); s.first = u32(d, 12)
        s.bytes = d[16:16+s.size]

class Mesh:
    # fields shared by v1.7 (FH2) and v1.12 (FH6)
    def __init__(s, b):
        d = b['data']; s.blob = b; s.name = (meta(b, 'Name') or b'').decode('latin1'); s.bbox = meta(b, 'BBox')
        if b['min'] >= 12:
            s.material = struct.unpack_from('<h', d, 2)[0]
            s.flags = d[8:8+12] + d[8+15:0x22]          # = FH2 bytes 2..0x19
            o = 0x22
        else:
            s.material = struct.unpack_from('<h', d, 0)[0]
            s.flags = d[2:0x19]; o = 0x19
        s.istart, s.base, s.icount, s.prims = struct.unpack_from('<iiii', d, o); s.lodscale = f32(d, o + 16); s.vcount = i32(d, o + 20); o += 24
        s.remap = []
        if b['min'] >= 12:
            n = u32(d, o); o += 4; s.remap = list(struct.unpack_from('<%dI' % n, d, o)); o += 4 * n
        s.layout, s.nstreams = struct.unpack_from('<ii', d, o); o += 8
        ssz = 20 if b['min'] >= 12 else 16
        s.streams = []
        for k in range(2):
            s.streams.append(struct.unpack_from('<iiii', d, o)); o += ssz
        s.morph = d[o:o+16]; o += 16
        s.uvx = d[o:o+80]; o += 80
        s.tail = d[o:]
        s.pos_scale = s.pos_offset = None
        if b['min'] >= 12 and len(s.tail) >= 32:
            v = struct.unpack_from('<8f', s.tail, 0); s.pos_scale = v[0:4]; s.pos_offset = v[4:8]

class Model:
    def __init__(s, path):
        s.data = open(path, 'rb').read(); s.f = burg.read(s.data); s.blobs = s.f['blobs']
        s.layouts = {blob_id(b): Layout(b['data']) for b in s.blobs if b['tag'] == 'VLay'}
        s.vbs = {blob_id(b): VerB(b['data']) for b in s.blobs if b['tag'] == 'VerB'}
        s.mbufs = {blob_id(b): VerB(b['data']) for b in s.blobs if b['tag'] == 'MBuf'}
        s.meshes = [Mesh(b) for b in s.blobs if b['tag'] == 'Mesh']
        ib = [b for b in s.blobs if b['tag'] == 'IndB'][0]['data']
        s.icount, s.isize = struct.unpack_from('<II', ib, 0); s.istride = struct.unpack_from('<H', ib, 8)[0]
        s.ibhdr = ib[:16]; s.ibytes = ib[16:16+s.isize]
        s.mats = {}
        for b in s.blobs:
            if b['tag'] == 'MatI':
                inner = burg.read(b['data']); mati = [c for c in inner['blobs'] if c['tag'] == 'MATI'][0]['data']
                ln = mati[0]; path = mati[1:1+ln].decode('latin1')
                s.mats[blob_id(b)] = dict(name=(meta(b, 'Name') or b'').decode('latin1'), path=path, blob=b)

    def index(s, i):
        return struct.unpack_from('<I' if s.istride == 4 else '<H', s.ibytes, i * s.istride)[0]

def h2f(h): return struct.unpack('<e', struct.pack('<H', h))[0]

def decode(fmt, d, o):
    if fmt == 6: return list(struct.unpack_from('<3f', d, o))
    if fmt == 10: return [h2f(x) for x in struct.unpack_from('<4H', d, o)]
    if fmt == 13: return [max(x / 32767.0, -1.0) for x in struct.unpack_from('<4h', d, o)]
    if fmt == 35: return [x / 65535.0 for x in struct.unpack_from('<2H', d, o)]
    if fmt == 37: return [max(x / 32767.0, -1.0) for x in struct.unpack_from('<2h', d, o)]
    if fmt == 24:
        v = u32(d, o); return [(v & 1023) / 1023.0, ((v >> 10) & 1023) / 1023.0, ((v >> 20) & 1023) / 1023.0, (v >> 30) / 3.0]
    if fmt == 28: return [x / 255.0 for x in d[o:o+4]]
    raise ValueError(fmt)

def oct_decode(x, y):
    z = 1.0 - abs(x) - abs(y)
    if z < 0: x, y = (1.0 - abs(y)) * (1 if x >= 0 else -1), (1.0 - abs(x)) * (1 if y >= 0 else -1)
    l = math.sqrt(x * x + y * y + z * z) or 1.0
    return [x / l, y / l, z / l]
