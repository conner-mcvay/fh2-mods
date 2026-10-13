"""rtti.py <ClassName@Namespace> ...: vtable address(es) of a class from its RTTI (x64 MSVC)."""
import sys, struct
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fh2re import pe, data, BASE, rva_of, off_of

def vtables(name):
    tag = ('.?AV' + name + '@@').encode() + b'\0'
    so = data.find(tag)
    if so < 0: return []
    td_rva = rva_of(so) - 0x10                       # TypeDescriptor: pVFTable, spare, name
    out = []
    p = data.find(struct.pack('<I', td_rva))
    while p >= 0:
        col = p - 12                                  # CompleteObjectLocator: sig, offset, cdOffset, pTypeDescriptor, pClassDescriptor, pSelf
        if col >= 0 and struct.unpack_from('<I', data, col)[0] == 1:
            col_rva = rva_of(col)
            if struct.unpack_from('<I', data, col + 20)[0] == col_rva:
                offset = struct.unpack_from('<I', data, col + 4)[0]
                q = data.find(struct.pack('<Q', BASE + col_rva))
                while q >= 0:
                    out.append((BASE + rva_of(q) + 8, offset)); q = data.find(struct.pack('<Q', BASE + col_rva), q + 1)
        p = data.find(struct.pack('<I', td_rva), p + 1)
    return out

for n in sys.argv[1:]:
    for vt, off in vtables(n):
        first = [struct.unpack_from('<Q', data, off_of(vt - BASE) + 8 * i)[0] for i in range(6)]
        print(f'{n}: vtable {vt:X} (subobject +{off:X}); first slots ' + ' '.join(f'{f:X}' for f in first))
