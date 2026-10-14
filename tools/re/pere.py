"""Small RE helper for any PE (e.g. Mount\\Microsoft.Xbox.Services.dll), with addresses at its image base.
  pere.py <pe> wxref <string>...   code that lea-loads a UTF-16 string
  pere.py <pe> xref <string>...    code that lea-loads an ASCII string
  pere.py <pe> func <va>           disassemble the function containing va (.pdata), annotating string loads
  pere.py <pe> calls <va>          direct call/jmp sites targeting va"""
import sys, re, struct, pefile, capstone

pe = pefile.PE(sys.argv[1], fast_load=True)
pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXCEPTION']])
d = pe.__data__; B = pe.OPTIONAL_HEADER.ImageBase
text = [s for s in pe.sections if s.Characteristics & 0x20000000][0]
seg = d[text.PointerToRawData:text.PointerToRawData + text.SizeOfRawData]; tv = B + text.VirtualAddress
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)

def sat(va):
    try: o = pe.get_offset_from_rva(va - B)
    except Exception: return None
    s = d[o:o + 160]
    if len(s) > 4 and s[1] == 0 and 32 <= s[0] < 127:
        t = s.decode('utf-16le', 'ignore').split('\0')[0]
        if len(t) >= 3: return 'u"' + t + '"'
    t = s.split(b'\0')[0]
    return '"' + t.decode('latin1') + '"' if len(t) >= 3 and all(32 <= c < 127 for c in t) else None

def func_of(va):
    r = va - B
    for e in pe.DIRECTORY_ENTRY_EXCEPTION:
        if e.struct.BeginAddress <= r < e.struct.EndAddress: return B + e.struct.BeginAddress, B + e.struct.EndAddress
    return va, va + 0x200

def lea_refs(target):
    for m in re.finditer(rb'[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]', seg):
        p = m.start()
        if tv + p + 7 + struct.unpack_from('<i', seg, p + 3)[0] == target: yield tv + p

cmd = sys.argv[2]
if cmd in ('xref', 'wxref'):
    for s in sys.argv[3:]:
        enc = s.encode('utf-16le') if cmd == 'wxref' else s.encode()
        o = d.find(enc + (b'\0\0' if cmd == 'wxref' else b'\0'))
        while o >= 0:
            va = B + pe.get_rva_from_offset(o)
            print(f'=== "{s}" at {va:X}')
            for r in lea_refs(va): print(f'  {r:X} (func {func_of(r)[0]:X})')
            o = d.find(enc + (b'\0\0' if cmd == 'wxref' else b'\0'), o + 1)
elif cmd == 'func':
    b, e = func_of(int(sys.argv[3], 16)); print(f'function {b:X}..{e:X}')
    o = pe.get_offset_from_rva(b - B)
    for i in md.disasm(d[o:o + (e - b)], b):
        s = f'{i.address:X}: {i.mnemonic} {i.op_str}'
        m = re.search(r'\[rip ([+-]) 0x([0-9a-f]+)\]', i.op_str)
        if m:
            t = i.address + i.size + int(m.group(2), 16) * (1 if m.group(1) == '+' else -1); st = sat(t)
            s += f'   ; {t:X}' + (f' {st}' if st else '')
        print(s)
elif cmd == 'calls':
    t = int(sys.argv[3], 16)
    p = seg.find(b'\xe8')
    while p >= 0:
        if p + 5 <= len(seg) and tv + p + 5 + struct.unpack_from('<i', seg, p + 1)[0] == t: print(f'  {tv + p:X} (func {func_of(tv + p)[0]:X})')
        p = seg.find(b'\xe8', p + 1)
