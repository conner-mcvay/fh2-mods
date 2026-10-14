"""Xls (Forza LSP) message codec. The schemas are read from the game's own executable (its reflection
descriptors; see tools/re/xlstypes.py), so nothing of the game is shipped here.

Wire format (big-endian), by descriptor kind (from the client's reader, 140EE5880 / 140EE5C30):
  0x0 u8   0x1 u16  0x2 u16  0x3 u32  0x4 i32  0x5 u64  0x6 u64  0x13 u64  0x7 f32  0x11 bool (u8)
  0x12 GUID (16 bytes)    0x9 string (u32 length + bytes)   0x14 blob (u32 length + bytes)
  0x10 DateTime: a string, ISO 8601 'YYYY-MM-DDTHH:MM:SS[.fff][Z|+hh:mm]' (an empty one is an error)
  0xC struct (fields in order)    0xE array (u32 count + elements; element descriptor at x10)
"""
import pefile, re, struct

EXE = r'G:\FH2-1\Anthem_1.0.0.64_x64__8wekyb3d8bbwe\Mount\forza_durango_release_final.exe'
B = 0x140000000


class Schema:
    def __init__(self, exe=EXE):
        pe = pefile.PE(exe, fast_load=True); self.pe = pe; self.d = d = pe.__data__
        text = [x for x in pe.sections if x.Name.rstrip(b'\0') == b'.text'][0]
        seg = d[text.PointerToRawData:text.PointerToRawData + text.SizeOfRawData]; tv = B + text.VirtualAddress
        self.lists = {}
        for m in re.finditer(rb'\x48\x8d\x15(....)\x48\x8d\x0d(....)\x41\xb8(....)\xe9', seg, re.S):
            p = m.start()
            arr = tv + p + 7 + struct.unpack('<i', m.group(1))[0]
            lst = tv + p + 14 + struct.unpack('<i', m.group(2))[0]
            self.lists[lst] = (arr, struct.unpack('<I', m.group(3))[0])
        self.cache = {}

    def _q(self, va, k=0): return struct.unpack_from('<Q', self.d, self.pe.get_offset_from_rva(va - B) + 8 * k)[0]

    def _cs(self, va):
        try: o = self.pe.get_offset_from_rva(va - B)
        except Exception: return None
        e = self.d.find(b'\0', o); return self.d[o:e].decode('latin1')

    def desc(self, va):
        if va in self.cache: return self.cache[va]
        f = [self._q(va, k) for k in range(12)]
        t = {'kind': f[0], 'name': self._cs(f[1]), 'size': f[8], 'fields': [], 'elem': None}
        self.cache[va] = t
        if f[9] in self.lists:
            arr, n = self.lists[f[9]]
            t['fields'] = [self.desc(arr + 0x60 * i) for i in range(n)]
        if t['kind'] == 0xE and f[10]: t['elem'] = self.desc(f[10])
        return t

    def find(self, name):
        so = self.d.find(b'\0' + name.encode() + b'\0') + 1; sva = B + self.pe.get_rva_from_offset(so)
        i = self.d.find(struct.pack('<Q', sva))
        return self.desc(B + self.pe.get_rva_from_offset(i) - 8)


FIXED = {0x0: '>B', 0x1: '>H', 0x2: '>H', 0x3: '>I', 0x4: '>i', 0x5: '>Q', 0x6: '>Q', 0x13: '>Q', 0x7: '>f', 0x11: '>?', 0x12: '16s'}
EPOCH = '2014-01-01T00:00:00'


def decode(t, buf, pos=0):
    k = t['kind']
    if k in FIXED:
        v = struct.unpack_from(FIXED[k], buf, pos)[0]; return v, pos + struct.calcsize(FIXED[k])
    if k in (0x9, 0x10, 0x14):
        n = struct.unpack_from('>I', buf, pos)[0]; raw = buf[pos + 4:pos + 4 + n]
        return (raw.hex() if k == 0x14 else raw.decode('utf-8')), pos + 4 + n
    if k == 0xC:
        out = {}
        for f in t['fields']: out[f['name']], pos = decode(f, buf, pos)
        return out, pos
    if k == 0xE:
        n = struct.unpack_from('>I', buf, pos)[0]; pos += 4; out = []
        for _ in range(n):
            v, pos = decode(t['elem'], buf, pos); out.append(v)
        return out, pos
    raise ValueError(f"kind 0x{k:X} ({t['name']}) not handled")


def encode(t, v):
    k = t['kind']
    if k == 0x12: return bytes.fromhex(v) if isinstance(v, str) else (v or bytes(16))
    if k in FIXED: return struct.pack(FIXED[k], v if v is not None else 0)
    if k in (0x9, 0x10):
        raw = (v or (EPOCH if k == 0x10 else '')).encode('utf-8'); return struct.pack('>I', len(raw)) + raw
    if k == 0x14:
        raw = bytes.fromhex(v) if isinstance(v, str) else (v or b''); return struct.pack('>I', len(raw)) + raw
    if k == 0xC:
        v = v or {}; return b''.join(encode(f, v.get(f['name'])) for f in t['fields'])
    if k == 0xE:
        v = v or []; return struct.pack('>I', len(v)) + b''.join(encode(t['elem'], x) for x in v)
    raise ValueError(f"kind 0x{k:X} ({t['name']}) not handled")


def outline(t, depth=0):
    s = f"{'  ' * depth}{t['name']}: 0x{t['kind']:X}\n"
    for f in t['fields']: s += outline(f, depth + 1)
    if t['elem']: s += outline(t['elem'], depth + 1)
    return s


if __name__ == '__main__':
    import sys, json
    sc = Schema()
    t = sc.find(sys.argv[1])
    if len(sys.argv) > 2:
        buf = open(sys.argv[2], 'rb').read()
        v, end = decode(t, buf)
        print(json.dumps(v, indent=1)); print(f'consumed {end} of {len(buf)} bytes')
    else:
        print(outline(t))
