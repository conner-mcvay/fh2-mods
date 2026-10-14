"""FH2 exe reverse-engineering helper.
  re.py xref <string> [...]      code that loads the address of an ASCII string (lea/mov rip-relative)
  re.py dis <va> [count] [back]  disassemble from va (hex), optionally starting `back` bytes earlier
  re.py func <va>                disassemble the whole function containing va (via .pdata)
  re.py calls <va> [...]         direct call/jmp rel32 sites targeting va
"""
import sys, re, struct, pefile, capstone

EXE = r'G:\FH2-1\Anthem_1.0.0.64_x64__8wekyb3d8bbwe\Mount\forza_durango_release_final.exe'
pe = pefile.PE(EXE, fast_load=True)
pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXCEPTION']])
data = pe.__data__
BASE = pe.OPTIONAL_HEADER.ImageBase
text = next(s for s in pe.sections if s.Name.rstrip(b'\0') == b'.text')
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64); md.detail = False

def off_of(rva): return pe.get_offset_from_rva(rva)
def rva_of(off): return pe.get_rva_from_offset(off)

def cstr(va):
    try: o = off_of(va - BASE)
    except Exception: return None
    e = o
    while e < len(data) and 0x20 <= data[e] < 0x7f: e += 1
    return data[o:e].decode() if e - o >= 3 and data[e] == 0 else None

def ann(insn):
    s = f'{insn.address:X}: {insn.mnemonic} {insn.op_str}'
    m = re.search(r'\[rip ([+-]) 0x([0-9a-f]+)\]', insn.op_str)
    if m:
        t = insn.address + insn.size + (int(m.group(2), 16) * (1 if m.group(1) == '+' else -1))
        st = cstr(t)
        s += f'   ; {t:X}' + (f' "{st}"' if st else '')
    return s

def xref(s):
    so = data.find(s.encode() + b'\0')
    while so > 0 and data[so - 1] != 0: so = data.find(s.encode() + b'\0', so + 1)
    target = BASE + rva_of(so)
    print(f'=== "{s}" at {target:X}')
    t0, t1 = text.PointerToRawData, text.PointerToRawData + text.SizeOfRawData
    tv = BASE + text.VirtualAddress
    seg = data[t0:t1]
    for m in re.finditer(rb'[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]', seg):
        p = m.start(); disp = struct.unpack_from('<i', seg, p + 3)[0]
        if tv + p + 7 + disp == target: print(f'  {tv + p:X}')

def calls(target):
    """Direct calls/jumps (E8/E9 rel32) to target."""
    t0, t1 = text.PointerToRawData, text.PointerToRawData + text.SizeOfRawData
    tv = BASE + text.VirtualAddress
    seg = data[t0:t1]
    print(f'=== calls to {target:X}')
    for op in (b'\xe8', b'\xe9'):
        p = seg.find(op)
        while p >= 0:
            if p + 5 <= len(seg) and tv + p + 5 + struct.unpack_from('<i', seg, p + 1)[0] == target:
                f, _ = func_of(tv + p); print(f'  {tv + p:X} {"call" if op == b"\xe8" else "jmp "} (in {f:X})')
            p = seg.find(op, p + 1)

def func_of(va):
    rva = va - BASE
    for e in pe.DIRECTORY_ENTRY_EXCEPTION:
        if e.struct.BeginAddress <= rva < e.struct.EndAddress: return BASE + e.struct.BeginAddress, BASE + e.struct.EndAddress
    return va, va + 0x200

def dis(va, count=40, back=0):
    start = va - back; o = off_of(start - BASE)
    for i, insn in enumerate(md.disasm(data[o:o + count * 16], start)):
        if i >= count: break
        print(('>> ' if insn.address == va else '   ') + ann(insn))

if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'xref':
        for s in sys.argv[2:]: xref(s)
    elif cmd == 'dis':
        dis(int(sys.argv[2], 16), int(sys.argv[3]) if len(sys.argv) > 3 else 40, int(sys.argv[4], 16) if len(sys.argv) > 4 else 0)
    elif cmd == 'calls':
        for a in sys.argv[2:]: calls(int(a, 16))
    elif cmd == 'func':
        b, e = func_of(int(sys.argv[2], 16)); print(f'function {b:X}..{e:X}')
        o = off_of(b - BASE)
        for insn in md.disasm(data[o:o + (e - b)], b): print(ann(insn))
