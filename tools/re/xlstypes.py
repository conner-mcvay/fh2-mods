"""Dump FH2's Xls web-service message types (the reflection descriptors the LSP client serializes with).
  xlstypes.py <type name>...     e.g. ForzaUserLogon_Results
Descriptors are 12 qwords: kind, name, 0, min, max, 0, min, max, size, field list, 0, extra. A struct's
field list (in .data) is filled at startup by `lea rdx, array; lea rcx, list; mov r8d, count; jmp init`,
where array holds `count` inline descriptors."""
import pefile, struct, sys, re
E = r'G:\FH2-1\Anthem_1.0.0.64_x64__8wekyb3d8bbwe\Mount\forza_durango_release_final.exe'
pe = pefile.PE(E, fast_load=True); d = pe.__data__; B = 0x140000000
text = [x for x in pe.sections if x.Name.rstrip(b'\0') == b'.text'][0]
seg = d[text.PointerToRawData:text.PointerToRawData + text.SizeOfRawData]; tv = B + text.VirtualAddress

def cs(va):
    try: o = pe.get_offset_from_rva(va - B)
    except Exception: return None
    e = o
    while e < len(d) and 32 <= d[e] < 127: e += 1
    return d[o:e].decode() if e - o >= 1 and d[e] == 0 else None

def q(va, k=0): return struct.unpack_from('<Q', d, pe.get_offset_from_rva(va - B) + 8 * k)[0]

lists = {}   # list va -> (array va, count)
for m in re.finditer(rb'\x48\x8d\x15(....)\x48\x8d\x0d(....)\x41\xb8(....)\xe9', seg, re.S):
    p = m.start()
    arr = tv + p + 7 + struct.unpack('<i', m.group(1))[0]
    lst = tv + p + 14 + struct.unpack('<i', m.group(2))[0]
    lists[lst] = (arr, struct.unpack('<I', m.group(3))[0])

def desc(va):
    f = [q(va, k) for k in range(12)]
    return {'va': va, 'kind': f[0], 'name': cs(f[1]) or '?', 'min': f[3], 'max': f[4], 'min2': f[6], 'max2': f[7],
            'size': f[8], 'list': f[9], 'x10': f[10], 'x11': f[11]}

def show(va, depth=0, seen=()):
    t = desc(va)
    lim = '' if (t['min'], t['max']) == (0x7FFFFFFF, 0x7FFFFFFF) else f" [{t['min']}..{t['max']}]"
    lim2 = '' if (t['min2'], t['max2']) == (0x7FFFFFFF, 0x7FFFFFFF) else f" <{t['min2']}..{t['max2']}>"
    print(f"{'  ' * depth}{t['name']}: kind 0x{t['kind']:X} size 0x{t['size']:X}{lim}{lim2} x10 {t['x10']:X} x11 {t['x11']:X}  @{va:X}")
    if t['list'] in lists and va not in seen:
        arr, n = lists[t['list']]
        for i in range(n): show(arr + 0x60 * i, depth + 1, seen + (va,))

if __name__ == '__main__':
    for name in sys.argv[1:]:
        so = d.find(b'\0' + name.encode() + b'\0') + 1; sva = B + pe.get_rva_from_offset(so)
        i = d.find(struct.pack('<Q', sva))
        while i >= 0:
            show(B + pe.get_rva_from_offset(i) - 8); i = d.find(struct.pack('<Q', sva), i + 1)
