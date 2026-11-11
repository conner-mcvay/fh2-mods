import struct, sys

def rtag(b): return b[::-1].decode('latin1')

def read(d):
    assert d[:4] == b'burG', d[:4]
    ver, n, dstart, total = struct.unpack_from('<HHII', d, 4)
    hdr = 16
    if ver >= 0x100: n = struct.unpack_from('<I', d, 16)[0]; hdr = 20
    blobs = []
    for i in range(n):
        o = hdr + 24 * i
        tag = rtag(d[o:o+4]); maj, mnr, mc, mo, off, sz, sz2 = struct.unpack_from('<BBHIIII', d, o + 4)
        meta = []; mflags = []
        for m in range(mc):
            me = mo + 8 * m
            mt = rtag(d[me:me+4]); lf = struct.unpack_from('<H', d, me + 4)[0]; ln = lf >> 4; po = me + struct.unpack_from('<H', d, me + 6)[0]
            meta.append((mt, d[po:po+ln])); mflags.append(lf & 15)
        blobs.append(dict(tag=tag, maj=maj, min=mnr, meta=meta, mflags=mflags, off=off, size=sz, size2=sz2, data=d[off:off+sz]))
    return dict(ver=ver, dstart=dstart, total=total, blobs=blobs)

def dump(path, deep=False):
    d = open(path, 'rb').read(); f = read(d)
    print(f"{path}: ver {f['ver']:#x} blobs {len(f['blobs'])} dstart {f['dstart']:#x} total {f['total']} len {len(d)}")
    for i, b in enumerate(f['blobs']):
        meta = ' '.join(f"{t}={m.hex() if len(m) != 4 else struct.unpack('<i', m)[0]}" for t, m in b['meta'])
        print(f"  {i:3} {b['tag']} v{b['maj']}.{b['min']} size {b['size']:8} {b['size2']:8} {meta}")
        if deep and b['data'][:4] == b'burG':
            inner = read(b['data'])
            for j, c in enumerate(inner['blobs']):
                print(f"       {c['tag']} v{c['maj']}.{c['min']} size {c['size']} : {c['data'][:64].hex()}")

if __name__ == '__main__':
    for p in sys.argv[1:]: dump(p, deep=True)

def write(blobs, version=1, align=4):
    # FH2 bundle (burG version 1): 16-byte header, 24-byte entries, metadata (per blob: 8-byte entries then payloads),
    # then blob data, each 4-byte aligned
    n = len(blobs); meta_start = 16 + 24 * n
    meta = bytearray(); mos = []
    for b in blobs:
        mos.append(meta_start + len(meta))
        ents = b.get('meta', [])
        fl = b.get('mflags') or [0] * len(ents)
        pay_off = 8 * len(ents); hdr = bytearray(); pay = bytearray()
        for i, (t, m) in enumerate(ents):
            rel = pay_off + len(pay) - 8 * i
            hdr += t.encode('latin1')[::-1] + struct.pack('<HH', len(m) << 4 | fl[i], rel); pay += m
        meta += hdr + pay
    a = align - 1
    dstart = (meta_start + len(meta) + a) & ~a
    offs = []; pos = dstart
    for b in blobs:
        pos = (pos + a) & ~a; offs.append(pos); pos += len(b['data'])
    total = (pos + a) & ~a
    out = bytearray(total)
    out[0:16] = b'burG' + struct.pack('<HHII', version, n, dstart, total)
    for i, b in enumerate(blobs):
        e = 16 + 24 * i; ln = len(b['data'])
        out[e:e+24] = b['tag'].encode('latin1')[::-1] + struct.pack('<BBHIIII', b['maj'], b['min'], len(b.get('meta', [])), mos[i], offs[i], ln, ln)
        out[offs[i]:offs[i]+ln] = b['data']
    out[meta_start:meta_start + len(meta)] = meta
    return bytes(out)
