"""Where the game uses a WinRT interface, and which vtable slots it calls on it.
  iidcalls.py <iid data1 hex>... [--range lo hi]
Finds functions that build the IID on the stack (mov dword [..], data1 followed by the other three dwords) and
prints, per function, the IID-building site and the `call [reg + x]` slots after it (slot = x / 8)."""
import sys, re
sys.path.insert(0, __file__.rsplit('\\', 1)[0])
args = sys.argv[1:]; sys.argv = sys.argv[:1]
import fh2re

lo, hi = 0, 1 << 64
if '--range' in args:
    i = args.index('--range'); lo, hi = int(args[i + 1], 16), int(args[i + 2], 16); args = args[:i]
targets = {int(a, 16) for a in args}
t0 = fh2re.text.PointerToRawData; seg = fh2re.data[t0:t0 + fh2re.text.SizeOfRawData]; tv = fh2re.BASE + fh2re.text.VirtualAddress
import struct
seen = set()
for d1 in targets:
    imm = struct.pack('<I', d1)
    p = seg.find(imm)
    while p >= 0:
        va = tv + p
        if lo <= va < hi:
            f, e = fh2re.func_of(va)
            if (f, d1) not in seen:
                seen.add((f, d1))
                o = fh2re.off_of(f - fh2re.BASE)
                insns = list(fh2re.md.disasm(fh2re.data[o:o + (e - f)], f))
                # the IID's four dwords, from the first mov carrying data1
                k = next((j for j, x in enumerate(insns) if x.address <= va < x.address + x.size), None)
                if k is not None and insns[k].mnemonic == 'mov':
                    parts = [insns[k + j].op_str.split(', ')[-1] for j in range(4)]
                    slots = []
                    for x in insns[k + 4:]:
                        m = re.match(r'qword ptr \[r(?:ax|cx|dx|8|9|10|11) \+ (0x[0-9a-f]+)\]$', x.op_str)
                        if x.mnemonic == 'call' and m: slots.append(f'{x.address:X}:{int(m.group(1), 16) // 8}')
                        elif x.mnemonic == 'call' and x.op_str == 'qword ptr [rax]': slots.append(f'{x.address:X}:0')
                    print(f'{d1:08x} in {f:X} ({" ".join(parts)}) slots {" ".join(slots[:12])}')
        p = seg.find(imm, p + 1)
