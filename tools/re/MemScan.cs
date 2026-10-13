using System; using System.Collections.Generic; using System.Diagnostics; using System.Runtime.InteropServices;

// Read-only scanner for the running Azimuth/FH2 process: finds every 8-byte-aligned qword equal to one of the values.
public static class MemScan {
  [StructLayout(LayoutKind.Sequential)] struct MBI { public ulong BaseAddress, AllocationBase; public uint AllocationProtect, __a; public ulong RegionSize; public uint State, Protect, Type, __b; }
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid);
  [DllImport("kernel32.dll")] static extern int VirtualQueryEx(IntPtr h, IntPtr a, out MBI m, int len);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr r);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  public static IntPtr Open(int pid) { return OpenProcess(0x0410, false, pid); }   // query + read
  public static byte[] Read(IntPtr h, ulong addr, int n) { var b = new byte[n]; IntPtr r; return ReadProcessMemory(h, (IntPtr)(long)addr, b, (IntPtr)n, out r) && (long)r == n ? b : null; }
  public static List<ulong[]> Find(IntPtr h, ulong[] values) {
    var hits = new List<ulong[]>(); var set = new HashSet<ulong>(values); ulong a = 0; MBI m;
    while (VirtualQueryEx(h, (IntPtr)(long)a, out m, Marshal.SizeOf(typeof(MBI))) != 0) {
      bool rw = m.State == 0x1000 && (m.Protect & 0x04) != 0 && (m.Protect & 0x100) == 0;   // committed, PAGE_READWRITE, not guard
      if (rw && m.RegionSize < (1UL << 32)) {
        for (ulong o = 0; o < m.RegionSize; o += 1 << 22) {
          int n = (int)Math.Min(1UL << 22, m.RegionSize - o); var b = Read(h, m.BaseAddress + o, n); if (b == null) continue;
          for (int i = 0; i + 8 <= n; i += 8) { ulong v = BitConverter.ToUInt64(b, i); if (set.Contains(v)) hits.Add(new[] { m.BaseAddress + o + (ulong)i, v }); }
        }
      }
      a = m.BaseAddress + m.RegionSize; if (a == 0) break;
    }
    return hits;
  }
}
