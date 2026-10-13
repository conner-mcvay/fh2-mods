// Key used in Mount\hash.manifest (Azimuth's file index): ASCII path relative to Mount ("media\..."),
// lowercased, backslashes. DJB2-style mix run twice over the path; pass 1 gives the low 32 bits, pass 2 the high.
// Algorithm from the GT500 patch guide (game exe RVA 0x126E0D0); verified against the stock index.
public static class ForzaPathKey {
  public static ulong Compute(string path) {
    byte[] b = System.Text.Encoding.ASCII.GetBytes(path.ToLowerInvariant());
    uint h = 5381, low = 0;
    for (int cycle = 0; cycle < 2; cycle++) {
      foreach (byte c in b) h ^= unchecked((h << 5) + (h >> 2) + c);
      if (cycle == 0) low = h;
    }
    return low | ((ulong)h << 32);
  }
}
