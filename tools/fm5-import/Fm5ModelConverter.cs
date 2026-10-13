// Converts FM5 car .modelbin files so every mesh's vertex layout provides what its FH2 shader reads.
// FH2's shaders read inputs FM5's didn't (e.g. car_windsheild: TANGENT1, TANGENT4, TEXCOORD4); a mesh whose layout
// lacks an input its vertex shader declares isn't drawn. For each layout we add the missing TEXCOORDs (copied from the
// nearest existing UV set) and TANGENTs (computed from positions, normals and that UV set), then rebuild the vertex
// buffers and fix every mesh's stride/offset. Geometry, indices, positions and morph buffers are untouched.
using System; using System.Collections.Generic; using System.IO; using System.IO.Compression; using System.Linq; using System.Text; using System.Text.RegularExpressions;

public static class ShaderSignature {
  // Input semantics (e.g. "TANGENT4") from every DXBC container in the bytes
  public static HashSet<string> Inputs(byte[] b) {
    var res = new HashSet<string>();
    for (int i = 0; i + 32 <= b.Length; i++) {
      if (b[i] != 'D' || b[i + 1] != 'X' || b[i + 2] != 'B' || b[i + 3] != 'C') continue;
      int total = BitConverter.ToInt32(b, i + 24), chunks = BitConverter.ToInt32(b, i + 28);
      for (int c = 0; c < chunks; c++) {
        int co = i + BitConverter.ToInt32(b, i + 32 + 4 * c);
        if (co + 12 > b.Length) break;
        string tag = Encoding.ASCII.GetString(b, co, 4); if (tag != "ISGN") continue;
        int data = co + 8, n = BitConverter.ToInt32(b, data);
        for (int k = 0; k < n; k++) {
          int e = data + 8 + k * 24, s = data + BitConverter.ToInt32(b, e); var sb = new StringBuilder(); while (b[s] != 0) sb.Append((char)b[s++]);
          res.Add(sb.ToString().ToUpperInvariant() + BitConverter.ToInt32(b, e + 4));
        }
      }
      i += Math.Max(total, 4) - 1;
    }
    return res;
  }
}

// Resolves FH2 materials and shaders: shared library zips plus the car's own zip (car-local materials/shaders)
public class Fh2ShaderResolver : IDisposable {
  ZipArchive materials, shaders; Dictionary<string, byte[]> car; string carName;
  Dictionary<string, HashSet<string>> cache = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
  public List<string> Log = new List<string>();
  public Fh2ShaderResolver(string fh2Media, Dictionary<string, byte[]> carFiles, string carMediaName) {
    materials = ZipFile.OpenRead(Path.Combine(fh2Media, @"cars\_library\Materials.zip")); shaders = ZipFile.OpenRead(Path.Combine(fh2Media, @"_library\Shaders.zip"));
    car = new Dictionary<string, byte[]>(carFiles, StringComparer.OrdinalIgnoreCase); carName = carMediaName.ToLowerInvariant();
  }
  public void Dispose() { materials.Dispose(); shaders.Dispose(); }

  // A car-local material whose shader also ships inside the car was compiled for FM5 and lacks FH2's render scenarios
  // (e.g. SimpleCarLightScenario), so it isn't drawn in some states. Returns the FH2 library material with the same
  // name minus FM5's "CH1"-style tag (gls_limotintCH1_001 -> gls_limotint_001), or null.
  public string LibraryReplacement(string materialPath) {
    var m = Regex.Match(materialPath, @"(?i)^game:\\media\\cars\\" + Regex.Escape(carName) + @"\\materials\\(.+)\\([^\\]+)\.materialbin$");
    if (!m.Success) return null;
    var mat = Media(materialPath); if (mat == null) return null;
    if (!Regex.IsMatch(Encoding.ASCII.GetString(mat), @"(?i)game:\\media\\cars\\" + Regex.Escape(carName) + @"\\shaders?\\")) return null;
    string stem = Regex.Replace(m.Groups[2].Value, @"(?i)ch\d", "");
    string rel = m.Groups[1].Value.Replace('\\', '/') + "/" + stem + ".materialbin";
    var e = materials.Entries.FirstOrDefault(x => string.Equals(x.FullName, rel, StringComparison.OrdinalIgnoreCase));
    return e == null ? null : @"Game:\Media\cars\_library\materials\" + e.FullName.Replace('/', '\\');
  }
  static byte[] Read(ZipArchive z, string entry) {
    var e = z.Entries.FirstOrDefault(x => string.Equals(x.FullName.Replace('\\', '/'), entry, StringComparison.OrdinalIgnoreCase)); if (e == null) return null;
    using (var s = e.Open()) using (var ms = new MemoryStream()) { s.CopyTo(ms); return ms.ToArray(); }
  }
  byte[] Media(string gamePath) {   // "Game:\Media\..." -> bytes, or null
    var p = Regex.Replace(gamePath, @"^(?i)game:\\media\\", "").Replace('\\', '/');
    if (p.StartsWith("cars/_library/materials/", StringComparison.OrdinalIgnoreCase)) return Read(materials, p.Substring("cars/_library/materials/".Length));
    string own = "cars/" + carName + "/";
    if (p.StartsWith(own, StringComparison.OrdinalIgnoreCase)) { byte[] b; return car.TryGetValue(p.Substring(own.Length), out b) ? b : null; }
    return null;
  }
  // Vertex inputs required by the FH2 shader behind a material (union over all of its vertex shader programs)
  public HashSet<string> Inputs(string materialPath) {
    HashSet<string> r; if (cache.TryGetValue(materialPath, out r)) return r;
    var mat = Media(materialPath); r = null;
    if (mat == null) Log.Add("material not found: " + materialPath);
    else {
      var m = Regex.Match(Encoding.ASCII.GetString(mat), @"(?i)game:\\media\\(_library\\shaders|cars\\[^\\]+\\shaders?)\\([^\\\x00]+)\\[^\\\x00]+\.shaderbin");
      if (!m.Success) Log.Add("no shader in material: " + materialPath);
      else {
        string dir = m.Groups[2].Value; r = new HashSet<string>();
        IEnumerable<KeyValuePair<string, byte[]>> progs;
        if (m.Groups[1].Value.StartsWith("_library", StringComparison.OrdinalIgnoreCase))
          progs = shaders.Entries.Where(e => e.FullName.StartsWith(dir + "/", StringComparison.OrdinalIgnoreCase) && e.FullName.EndsWith(".vso", StringComparison.OrdinalIgnoreCase))
            .Select(e => new KeyValuePair<string, byte[]>(e.FullName, Read(shaders, e.FullName)));
        else
          progs = car.Where(kv => Regex.IsMatch(kv.Key, @"(?i)^shaders?/" + Regex.Escape(dir) + "/.*\\.vso$"));
        int n = 0; foreach (var kv in progs) { r.UnionWith(ShaderSignature.Inputs(kv.Value)); n++; }
        if (n == 0) { Log.Add("no vertex shaders for " + dir + " (" + materialPath + ")"); r = null; }
      }
    }
    cache[materialPath] = r; return r;
  }
}

public static class Fm5ModelConverter {
  const uint FmtHalf4 = 10, FmtUnorm16x2 = 35, CodeTexcoord = 0x2E, CodeTangent = 9;

  static float[] ReadElem(byte[] d, int p, uint fmt) {
    switch (fmt) {
      case 6: return new[] { BitConverter.ToSingle(d, p), BitConverter.ToSingle(d, p + 4), BitConverter.ToSingle(d, p + 8) };
      case 10: return new[] { VertexMath.Half(BitConverter.ToUInt16(d, p)), VertexMath.Half(BitConverter.ToUInt16(d, p + 2)), VertexMath.Half(BitConverter.ToUInt16(d, p + 4)), VertexMath.Half(BitConverter.ToUInt16(d, p + 6)) };
      case 35: return new[] { BitConverter.ToUInt16(d, p) / 65535f, BitConverter.ToUInt16(d, p + 2) / 65535f };
      default: throw new NotSupportedException("format " + fmt);
    }
  }
  static int Rank(string sem) { return sem == "NORMAL" ? 0 : sem == "TEXCOORD" ? 1 : sem == "TANGENT" ? 2 : 3; }

  // FH2 sets this parameter override (hash 0xF2FDFE8E = 0, followed by its checksum) on its window glass; FM5 glass has
  // no overrides, and without it the pane isn't drawn. Bytes copied from FH2's own gls_window instances.
  static readonly byte[] GlassParams = { 0x01, 0x02, 0x00, 0x8E, 0xFE, 0xFD, 0xF2, 0x03, 0x00, 0x00, 0x00, 0x00, 0x53, 0x4C, 0xCE, 0x6D, 0, 0, 0, 0, 0, 0, 0, 0 };
  static readonly HashSet<string> GlassMaterials = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "gls_window", "gls_window_interior", "gls_windsheild", "gls_windsheild_interior" };

  static byte[] LengthPrefixed(string s) {   // 7-bit varint length, then ASCII (no terminator)
    var b = Encoding.ASCII.GetBytes(s); var ms = new MemoryStream(); uint n = (uint)b.Length;
    while (n >= 0x80) { ms.WriteByte((byte)(n | 0x80)); n >>= 7; } ms.WriteByte((byte)n);
    ms.Write(b, 0, b.Length); return ms.ToArray();
  }

  // Material-instance fixups: FH2 glass parameter block; car-local FM5 materials redirected to an FH2 library material
  static bool FixMaterial(BurgBlob mi, Func<string, string> replacement, List<string> log) {
    var inner = BurgFile.Read(mi.Data); bool changed = false;
    var mati = inner.Blobs.First(b => b.Tag == "MATI"); var mtpr = inner.Blobs.FirstOrDefault(b => b.Tag == "MTPR");
    var path = Regex.Match(Encoding.ASCII.GetString(mati.Data), @"(?i)game:\\media\\[^\x00]+?\.materialbin").Value;
    var repl = replacement != null ? replacement(path) : null;
    if (!string.IsNullOrEmpty(repl) && path.Length > 0) {   // (a PowerShell delegate returns "" for $null)
      int p = Encoding.ASCII.GetString(mati.Data).IndexOf(path, StringComparison.Ordinal), lenBytes = 1;
      while (p - lenBytes - 1 >= 0 && (mati.Data[p - lenBytes - 1] & 0x80) != 0) lenBytes++;
      var nd = new MemoryStream(); nd.Write(mati.Data, 0, p - lenBytes); var s = LengthPrefixed(repl); nd.Write(s, 0, s.Length);
      int after = p + path.Length; nd.Write(mati.Data, after, mati.Data.Length - after);
      mati.Data = nd.ToArray(); log.Add("  material " + Path.GetFileName(path) + " -> FH2 " + Path.GetFileName(repl)); path = repl; changed = true;
    }
    if (mtpr != null && GlassMaterials.Contains(Path.GetFileNameWithoutExtension(path)) && mtpr.Data.All(x => x == 0)) {
      mtpr.Data = (byte[])GlassParams.Clone(); log.Add("  material " + Path.GetFileName(path) + ": FH2 glass parameter"); changed = true;
    }
    if (changed) mi.Data = inner.Write();
    return changed;
  }

  // Returns the converted model, or null when nothing needed changing. log gets one line per change/problem.
  public static byte[] Convert(byte[] model, Func<string, HashSet<string>> inputsForMaterial, List<string> log) { return Convert(model, inputsForMaterial, null, log); }
  public static byte[] Convert(byte[] model, Func<string, HashSet<string>> inputsForMaterial, Func<string, string> materialReplacement, List<string> log) {
    var f = BurgFile.Read(model);
    bool matsChanged = false;
    foreach (var mi in f.All("MatI")) matsChanged |= FixMaterial(mi, materialReplacement, log);
    // meshes refer to material instances by their Id metadata, not their position
    var mats = new Dictionary<int, string>();
    foreach (var b in f.All("MatI")) { var m = Regex.Match(Encoding.ASCII.GetString(b.Data), @"(?i)game:\\media\\[^\x00]+?\.materialbin"); if (b.Id.HasValue && m.Success) mats[b.Id.Value] = m.Value; }
    var layoutBlobs = f.All("VLay").ToDictionary(b => b.Id.Value); var bufferBlobs = f.All("VerB").ToDictionary(b => b.Id.Value);
    var meshes = f.All("Mesh").Select(MeshInfo.Parse).Where(m => m.Material != 0xFFFF).ToList();
    if (meshes.Count == 0 || f.All("IndB").Count == 0) return matsChanged ? f.Write() : null;   // skeletons etc.: nothing drawn

    // FH2 compiles each shader variant for one vertex format and its own cars' layouts match the shader's inputs
    // exactly (1074 of 1082 mesh parts in the FH2 '87 GTA). So each layout becomes exactly the TEXCOORD/TANGENT set its
    // shader reads: missing elements are added, extra ones dropped.
    var need = new Dictionary<int, HashSet<string>>(); var mixed = new HashSet<int>();
    foreach (var m in meshes) {
      string path; if (!mats.TryGetValue(m.Material, out path)) { log.Add("  mesh material id " + m.Material + " has no material instance"); continue; }
      var req = inputsForMaterial(path); if (req == null) continue;
      var set = new HashSet<string>(req.Where(s => s.StartsWith("TEXCOORD") || s.StartsWith("TANGENT")));
      HashSet<string> s0; if (!need.TryGetValue(m.LayoutIndex, out s0)) need[m.LayoutIndex] = set;
      else if (!s0.SetEquals(set)) { mixed.Add(m.LayoutIndex); s0.UnionWith(set); }
    }
    bool changed = matsChanged;
    var ib = f.All("IndB")[0].Data; int istride = BitConverter.ToUInt16(ib, 8);
    Func<int, int> index = i => istride == 4 ? BitConverter.ToInt32(ib, 16 + 4 * i) : BitConverter.ToUInt16(ib, 16 + 2 * i);

    foreach (var kv in need) {
      var lblob = layoutBlobs[kv.Key]; var L = VertexLayout.Parse(lblob.Data);
      if (!L.Has("NORMAL", 0)) continue;
      Func<string, int> idx = s => int.Parse(s.Substring(s.StartsWith("TEXCOORD") ? 8 : 7));
      var wantUv = kv.Value.Where(s => s.StartsWith("TEXCOORD")).Select(idx).OrderBy(x => x).ToList();
      var wantTan = kv.Value.Where(s => s.StartsWith("TANGENT")).Select(idx).OrderBy(x => x).ToList();
      var haveUv = L.Elements.Where(e => e.Slot == 1 && e.Semantic == "TEXCOORD").Select(e => e.Index).OrderBy(x => x).ToList();
      var haveTan = L.Elements.Where(e => e.Slot == 1 && e.Semantic == "TANGENT").Select(e => e.Index).OrderBy(x => x).ToList();
      if (wantUv.SequenceEqual(haveUv) && wantTan.SequenceEqual(haveTan)) continue;
      if (mixed.Contains(kv.Key)) log.Add("  layout " + kv.Key + ": shared by shaders with different inputs; using their union");
      var users = meshes.Where(m => m.LayoutIndex == kv.Key).ToList();
      var bufIds = users.Select(m => m.VbIndex[1]).Distinct().ToList();
      if (meshes.Any(m => m.LayoutIndex != kv.Key && bufIds.Contains(m.VbIndex[1]))) { log.Add("  layout " + kv.Key + ": buffer shared with another layout, skipped"); continue; }

      // UV source for every wanted/needed UV set: itself if present, else the nearest existing one (TEXCOORD4 follows TEXCOORD2, as in FH2's own data)
      var srcUv = new Dictionary<int, int>();
      foreach (var k in wantUv.Union(wantTan).Distinct()) {
        if (haveUv.Contains(k)) { srcUv[k] = k; continue; }
        if (haveUv.Count == 0) { log.Add("  layout " + kv.Key + ": no UV set to copy for TEXCOORD" + k); continue; }
        srcUv[k] = (k == 4 && haveUv.Contains(2)) ? 2 : haveUv.Where(i => i < k).DefaultIfEmpty(haveUv.Min()).Max();
      }
      wantTan = wantTan.Where(k => srcUv.ContainsKey(k)).ToList(); wantUv = wantUv.Where(k => srcUv.ContainsKey(k)).ToList();

      var N = new VertexLayout { Names = new List<string>(), Elements = new List<VertexElement>(), Mask = 0, Tail = L.Tail };
      foreach (var e in L.Elements.Where(e => e.Slot == 0)) N.Elements.Add(e);
      foreach (var e in L.Elements.Where(e => e.Slot == 1 && e.Semantic == "NORMAL")) N.Elements.Add(e);
      foreach (var k in wantUv) N.Elements.Add(new VertexElement { Semantic = "TEXCOORD", Index = k, Slot = 1, Format = FmtUnorm16x2, Offset = 0xFFFFFFFF, Code = CodeTexcoord });
      foreach (var k in wantTan) N.Elements.Add(new VertexElement { Semantic = "TANGENT", Index = k, Slot = 1, Format = FmtHalf4, Offset = 0xFFFFFFFF, Code = CodeTangent });
      foreach (var e in L.Elements.Where(e => e.Slot > 1 || (e.Slot == 1 && Rank(e.Semantic) == 3))) N.Elements.Add(e);   // anything else stays
      foreach (var k in wantUv) N.Mask |= 1u << k; foreach (var k in wantTan) N.Mask |= 1u << (5 + k);
      foreach (var nm in new[] { "POSITION", "NORMAL", "TEXCOORD", "TANGENT" }) if (N.Elements.Any(e => e.Semantic == nm)) N.Names.Add(nm);
      foreach (var e in N.Elements) if (!N.Names.Contains(e.Semantic)) N.Names.Add(e.Semantic);
      var s1 = N.Elements.Where(e => e.Slot == 1).ToList();
      int oldStride = L.Stride(1), newStride = N.Stride(1);

      foreach (var bid in bufIds) {
        var bblob = bufferBlobs[bid]; var V = VertexBuffer.Parse(bblob.Data); int nv = V.Count;
        var oldOff = new Dictionary<string, int>(); int o = 0;
        foreach (var e in L.Elements.Where(e => e.Slot == 1)) { oldOff[e.Semantic + e.Index] = o; o += VertexLayout.FormatSize(e.Format); }
        // positions + triangles for this buffer, in buffer-vertex numbering
        var pos = new float[nv][]; var tris = new List<int>();
        foreach (var m in users.Where(m => m.VbIndex[1] == bid)) {
          var P = VertexBuffer.Parse(bufferBlobs[m.VbIndex[0]].Data);
          int p0 = m.VbOffset[0] / m.VbStride[0], b0 = m.VbOffset[1] / m.VbStride[1];
          for (int i = m.IndexStart; i < m.IndexStart + m.IndexCount; i++) {
            int raw = index(i) + m.BaseVertex, bv = raw + b0, pv = raw + p0;
            if (bv < 0 || bv >= nv || pv < 0 || pv >= P.Count) throw new InvalidDataException("index out of range in layout " + kv.Key);
            if (pos[bv] == null) pos[bv] = ReadElem(P.Bytes, pv * P.Stride, 6);
            tris.Add(bv);
          }
        }
        for (int v = 0; v < nv; v++) if (pos[v] == null) pos[v] = new float[3];
        var nrm = Enumerable.Range(0, nv).Select(v => ReadElem(V.Bytes, v * oldStride + oldOff["NORMAL0"], FmtHalf4)).ToArray();
        var tangents = new Dictionary<int, float[][]>();
        foreach (var k in wantTan.Where(k => !haveTan.Contains(k))) {
          var uv = Enumerable.Range(0, nv).Select(v => ReadElem(V.Bytes, v * oldStride + oldOff["TEXCOORD" + srcUv[k]], FmtUnorm16x2)).ToArray();
          tangents[k] = VertexMath.Tangents(pos, nrm, uv, tris);
        }
        var nb = new byte[nv * newStride];
        for (int v = 0; v < nv; v++) {
          int p = v * newStride;
          foreach (var e in s1) {
            int sz = VertexLayout.FormatSize(e.Format); string key = e.Semantic + e.Index;
            if (oldOff.ContainsKey(key)) Array.Copy(V.Bytes, v * oldStride + oldOff[key], nb, p, sz);
            else if (e.Semantic == "TEXCOORD") Array.Copy(V.Bytes, v * oldStride + oldOff["TEXCOORD" + srcUv[e.Index]], nb, p, sz);
            else { var t = tangents[e.Index][v]; for (int c = 0; c < 4; c++) BitConverter.GetBytes(VertexMath.ToHalf(t[c])).CopyTo(nb, p + 2 * c); }
            p += sz;
          }
        }
        V.Bytes = nb; V.Stride = newStride; V.Elements = s1.Count; bblob.Data = V.Build();
      }
      // meshes: stream-1 stride and byte offset; a copied UV set also gets its source's scale/offset block
      foreach (var m in users) {
        var d = m.Blob.Data; int so = MeshInfo.OffStreams + 16;
        int first = BitConverter.ToInt32(d, so + 12) / oldStride;
        BitConverter.GetBytes(newStride).CopyTo(d, so + 8); BitConverter.GetBytes(first * newStride).CopyTo(d, so + 12);
        foreach (var k in wantUv.Where(k => srcUv[k] != k)) {
          int dst = MeshInfo.OffUvTransforms + 16 * k, src = MeshInfo.OffUvTransforms + 16 * srcUv[k];
          if (dst + 16 <= d.Length && src + 16 <= d.Length) Array.Copy(d, src, d, dst, 16);
        }
      }
      lblob.Data = N.Build(); changed = true;
      Func<List<int>, string, string> fmt = (l, p) => string.Join(",", l.Select(x => p + x));
      log.Add(string.Format("  layout {0}: [{1}] -> [{2}] (stride {3} -> {4}, {5} buffer(s), {6} mesh(es))", kv.Key,
        fmt(haveUv, "UV") + (haveTan.Count > 0 ? "," + fmt(haveTan, "T") : ""), fmt(wantUv, "UV") + (wantTan.Count > 0 ? "," + fmt(wantTan, "T") : ""), oldStride, newStride, bufIds.Count, users.Count));
    }
    return changed ? f.Write() : null;
  }
}
