"""vtname.py <vtable va> [slots]: class name of a vtable (via its CompleteObjectLocator) and its first slots."""
import sys, struct
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fh2re import data, BASE, off_of
vt = int(sys.argv[1], 16); n = int(sys.argv[2]) if len(sys.argv) > 2 else 24
col = struct.unpack_from('<Q', data, off_of(vt - 8 - BASE))[0]
td = struct.unpack_from('<I', data, off_of(col - BASE) + 12)[0]
o = off_of(td + 0x10); e = data.find(b'\0', o)
print('class', data[o:e].decode())
for i in range(n):
    print(f'  slot {i:2} (+0x{8*i:X}): {struct.unpack_from("<Q", data, off_of(vt - BASE) + 8 * i)[0]:X}')
