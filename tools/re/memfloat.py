# Floats in the running game (Azimuth's process): find, show, change. For finding which runtime values drive a
# behaviour: search for a value the game loaded (or a run of consecutive ones), look at what's around each copy, change
# one and watch the game.
#   memfloat.py find 2.194 2.194 0.51 0.48        consecutive float32s (exact, as the game converts the database's)
#   memfloat.py find 2.194 --tol 0.0005           one value, approximately
#   memfloat.py show 0x1f3da668000 [count]        floats (and the int / pointer view) around an address
#   memfloat.py set 0x1f3da668000 2.5             write a float (the old value is printed so it can be put back)
# Only committed read-write memory is searched. Add --pid if more than one azimuth.exe runs.
import argparse, ctypes, ctypes.wintypes as wt, struct, subprocess, sys

k32 = ctypes.WinDLL('kernel32', use_last_error=True)
class MBI(ctypes.Structure):
    _fields_ = [('BaseAddress', ctypes.c_uint64), ('AllocationBase', ctypes.c_uint64), ('AllocationProtect', wt.DWORD), ('_a', wt.DWORD),
                ('RegionSize', ctypes.c_uint64), ('State', wt.DWORD), ('Protect', wt.DWORD), ('Type', wt.DWORD), ('_b', wt.DWORD)]
k32.OpenProcess.restype = wt.HANDLE
k32.VirtualQueryEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.POINTER(MBI), ctypes.c_size_t]
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.WriteProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]

def find_pid():
    out = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq azimuth.exe', '/FO', 'CSV', '/NH'], capture_output=True, text=True).stdout
    pids = [int(l.split('","')[1]) for l in out.splitlines() if l.startswith('"azimuth.exe"')]
    if len(pids) != 1: sys.exit(f'{len(pids)} azimuth.exe processes; pass --pid')
    return pids[0]

def regions(h):
    a, m = 0, MBI()
    while k32.VirtualQueryEx(h, ctypes.c_void_p(a), ctypes.byref(m), ctypes.sizeof(m)):
        if m.State == 0x1000 and m.Protect & 0x04 and not m.Protect & 0x100 and m.RegionSize < (1 << 34):   # committed RW, not guard
            yield m.BaseAddress, m.RegionSize
        a = m.BaseAddress + m.RegionSize
        if a >= 1 << 47: break

def read(h, addr, n):
    buf = ctypes.create_string_buffer(n); got = ctypes.c_size_t()
    return buf.raw[:got.value] if k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, n, ctypes.byref(got)) else b''

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=['find', 'show', 'set'])
    ap.add_argument('args', nargs='+')
    ap.add_argument('--pid', type=int); ap.add_argument('--tol', type=float, default=0); ap.add_argument('--max', type=int, default=200)
    a = ap.parse_args()
    pid = a.pid or find_pid()
    h = k32.OpenProcess(0x0438, False, pid)   # query, read, write, operation
    if not h: sys.exit(f'OpenProcess failed ({ctypes.get_last_error()})')
    if a.cmd == 'find':
        vals = [float(x) for x in a.args]
        hits = 0
        for base, size in regions(h):
            for off in range(0, size, 1 << 24):
                b = read(h, base + off, min(1 << 24, size - off))
                if not b: continue
                if a.tol and len(vals) == 1:   # approximate: scan aligned floats
                    import array
                    arr = array.array('f'); arr.frombytes(b[:len(b) // 4 * 4])
                    for i, v in enumerate(arr):
                        if abs(v - vals[0]) <= a.tol:
                            print(f'{base + off + 4 * i:#x}  {v:.6g}'); hits += 1
                            if hits >= a.max: return
                else:
                    pat = struct.pack(f'<{len(vals)}f', *vals); i = b.find(pat)
                    while i >= 0:
                        if i % 4 == 0:
                            print(f'{base + off + i:#x}'); hits += 1
                            if hits >= a.max: return
                        i = b.find(pat, i + 1)
        print(f'{hits} hit(s)', file=sys.stderr)
    elif a.cmd == 'show':
        addr = int(a.args[0], 16); n = int(a.args[1]) if len(a.args) > 1 else 32
        start = addr - 4 * (n // 2); b = read(h, start, 4 * n)
        for i in range(len(b) // 4):
            f, = struct.unpack_from('<f', b, 4 * i); u, = struct.unpack_from('<I', b, 4 * i)
            q = struct.unpack_from('<Q', b, 4 * i)[0] if i % 2 == 0 and 4 * i + 8 <= len(b) else None
            mark = '>>' if start + 4 * i == addr else '  '
            print(f'{mark} {start + 4 * i:#x} {i * 4 - 4 * (n // 2):+5d}  {f:>14.6g}  {u:>11}' + (f'  {q:#x}' if q and 0x10000 < q < 1 << 47 else ''))
    else:
        addr = int(a.args[0], 16); v = float(a.args[1])
        old, = struct.unpack('<f', read(h, addr, 4))
        data = struct.pack('<f', v); n = ctypes.c_size_t()
        ok = k32.WriteProcessMemory(h, ctypes.c_void_p(addr), data, 4, ctypes.byref(n))
        print(f'{addr:#x}: {old:.6g} -> {v:.6g}' + ('' if ok else f'  FAILED ({ctypes.get_last_error()})'))

if __name__ == '__main__':
    main()
