"""disp.py <hexdisp> [<hexdisp>...]: instructions in .text using [reg + disp] with that displacement."""
import sys, struct
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fh2re
from fh2re import data, text, BASE, md, ann
t0 = text.PointerToRawData; seg = data[t0:t0 + text.SizeOfRawData]; tv = BASE + text.VirtualAddress
for d in sys.argv[1:]:
    pat = struct.pack('<I', int(d, 16)); print(f'=== +0x{int(d,16):X}')
    p = seg.find(pat); seen = set()
    while p >= 0:
        for back in range(2, 9):   # the displacement sits 2..8 bytes into the instruction
            s = p - back
            for insn in md.disasm(seg[s:s + 16], tv + s):
                if insn.address == tv + s and f'0x{int(d,16):x}]' in insn.op_str and insn.address not in seen:
                    seen.add(insn.address); print('  ' + ann(insn))
                break
        p = seg.find(pat, p + 1)
