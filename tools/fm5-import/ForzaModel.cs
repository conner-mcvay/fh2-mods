// Reader/writer for Forza (FM5/FH2) .modelbin files ("burG" bundles) and the vertex-layout conversion FM5 -> FH2.
//
// Bundle: "burG", u16 version, u16 blobCount, u32 dataStart, u32 totalSize; then blobCount 24-byte entries
// (tag reversed, u8 major, u8 minor, u16 metaCount, u32 metaOffset, u32 dataOffset, u32 dataSize, u32 dataSize2),
// then the metadata area (kept verbatim), then blob data, each blob 4-byte aligned.
using System; using System.Collections.Generic; using System.IO; using System.Linq; using System.Text;

public class BurgBlob {
  public string Tag; public byte Major, Minor; public ushort MetaCount; public uint MetaOffset; public byte[] Data;
  public int? Id;   // from the blob's "Id  " metadata entry; meshes refer to layouts and vertex buffers by this
}

public class BurgFile {
  public ushort Version; public List<BurgBlob> Blobs = new List<BurgBlob>(); public byte[] Meta; public uint DataStart;

  public static BurgFile Read(byte[] d) {
    if (d[0] != 'b' || d[1] != 'u' || d[2] != 'r' || d[3] != 'G') throw new InvalidDataException("not a burG bundle");
    var f = new BurgFile { Version = BitConverter.ToUInt16(d, 4), DataStart = BitConverter.ToUInt32(d, 8) };
    int n = BitConverter.ToUInt16(d, 6), metaStart = 16 + 24 * n;
    for (int i = 0; i < n; i++) {
      int o = 16 + 24 * i;
      var b = new BurgBlob { Tag = "" + (char)d[o + 3] + (char)d[o + 2] + (char)d[o + 1] + (char)d[o], Major = d[o + 4], Minor = d[o + 5],
        MetaCount = BitConverter.ToUInt16(d, o + 6), MetaOffset = BitConverter.ToUInt32(d, o + 8) };
      uint off = BitConverter.ToUInt32(d, o + 12), size = BitConverter.ToUInt32(d, o + 16);
      b.Data = new byte[size]; Array.Copy(d, off, b.Data, 0, size); f.Blobs.Add(b);
      // metadata entries: tag (reversed), u16 (payloadLength << 4), u16 payload offset relative to the entry
      for (int m = 0; m < b.MetaCount; m++) {
        int me = (int)b.MetaOffset + 8 * m;
        string mt = "" + (char)d[me + 3] + (char)d[me + 2] + (char)d[me + 1] + (char)d[me];
        int len = BitConverter.ToUInt16(d, me + 4) >> 4, po = me + BitConverter.ToUInt16(d, me + 6);
        if (mt == "Id  " && len == 4) b.Id = BitConverter.ToInt32(d, po);
      }
    }
    f.Meta = new byte[f.DataStart - metaStart]; Array.Copy(d, metaStart, f.Meta, 0, f.Meta.Length);
    return f;
  }

  public byte[] Write() {
    int n = Blobs.Count, metaStart = 16 + 24 * n;
    if (metaStart + Meta.Length != DataStart) throw new InvalidOperationException("metadata area size changed");
    var offsets = new uint[n]; uint pos = DataStart;
    for (int i = 0; i < n; i++) { pos = (pos + 3) & ~3u; offsets[i] = pos; pos += (uint)Blobs[i].Data.Length; }
    pos = (pos + 3) & ~3u;   // file length is padded to 4 too
    var o = new byte[pos];
    Encoding.ASCII.GetBytes("burG").CopyTo(o, 0);
    BitConverter.GetBytes(Version).CopyTo(o, 4); BitConverter.GetBytes((ushort)n).CopyTo(o, 6);
    BitConverter.GetBytes(DataStart).CopyTo(o, 8); BitConverter.GetBytes(pos).CopyTo(o, 12);
    for (int i = 0; i < n; i++) {
      var b = Blobs[i]; int e = 16 + 24 * i;
      o[e] = (byte)b.Tag[3]; o[e + 1] = (byte)b.Tag[2]; o[e + 2] = (byte)b.Tag[1]; o[e + 3] = (byte)b.Tag[0];
      o[e + 4] = b.Major; o[e + 5] = b.Minor; BitConverter.GetBytes(b.MetaCount).CopyTo(o, e + 6); BitConverter.GetBytes(b.MetaOffset).CopyTo(o, e + 8);
      BitConverter.GetBytes(offsets[i]).CopyTo(o, e + 12); BitConverter.GetBytes((uint)b.Data.Length).CopyTo(o, e + 16); BitConverter.GetBytes((uint)b.Data.Length).CopyTo(o, e + 20);
      Array.Copy(b.Data, 0, o, offsets[i], b.Data.Length);
    }
    Array.Copy(Meta, 0, o, metaStart, Meta.Length);
    return o;
  }

  public List<BurgBlob> All(string tag) { return Blobs.Where(b => b.Tag == tag).ToList(); }
}

public class VertexElement { public string Semantic; public int Index, Slot, Pad; public uint Format, Offset, Class, Code; }

public class VertexLayout {
  public List<string> Names = new List<string>(); public List<VertexElement> Elements = new List<VertexElement>(); public uint Mask; public byte[] Tail;

  public static VertexLayout Parse(byte[] d) {
    var l = new VertexLayout(); int p = 0, nn = BitConverter.ToUInt16(d, p); p += 2;
    for (int i = 0; i < nn; i++) { int len = BitConverter.ToInt32(d, p); p += 4; l.Names.Add(Encoding.ASCII.GetString(d, p, len)); p += len; }
    int ne = BitConverter.ToUInt16(d, p); p += 2;
    for (int i = 0; i < ne; i++, p += 20)
      l.Elements.Add(new VertexElement { Semantic = l.Names[BitConverter.ToUInt16(d, p)], Index = BitConverter.ToUInt16(d, p + 2), Slot = BitConverter.ToUInt16(d, p + 4),
        Pad = BitConverter.ToUInt16(d, p + 6), Format = BitConverter.ToUInt32(d, p + 8), Offset = BitConverter.ToUInt32(d, p + 12), Class = BitConverter.ToUInt32(d, p + 16) });
    foreach (var e in l.Elements) { e.Code = BitConverter.ToUInt32(d, p); p += 4; }
    l.Mask = BitConverter.ToUInt32(d, p); p += 4;
    l.Tail = new byte[d.Length - p]; Array.Copy(d, p, l.Tail, 0, l.Tail.Length);
    return l;
  }

  public byte[] Build() {
    var ms = new MemoryStream(); var w = new BinaryWriter(ms);
    w.Write((ushort)Names.Count);
    foreach (var n in Names) { w.Write(n.Length); w.Write(Encoding.ASCII.GetBytes(n)); }
    w.Write((ushort)Elements.Count);
    foreach (var e in Elements) { w.Write((ushort)Names.IndexOf(e.Semantic)); w.Write((ushort)e.Index); w.Write((ushort)e.Slot); w.Write((ushort)e.Pad); w.Write(e.Format); w.Write(e.Offset); w.Write(e.Class); }
    foreach (var e in Elements) w.Write(e.Code);
    w.Write(Mask); w.Write(Tail);
    return ms.ToArray();
  }

  public static int FormatSize(uint fmt) {
    switch (fmt) { case 6: return 12; case 10: return 8; case 35: return 4; case 37: return 4; case 28: return 4; case 2: return 16; case 16: return 8; case 41: return 4;
      default: throw new NotSupportedException("vertex format " + fmt); }
  }
  public int Stride(int slot) { return Elements.Where(e => e.Slot == slot).Sum(e => FormatSize(e.Format)); }
  public bool Has(string sem, int idx) { return Elements.Any(e => e.Semantic == sem && e.Index == idx); }
  public string Signature() { return string.Join(" ", Elements.Select(e => e.Semantic + e.Index + "@" + e.Slot + ":" + e.Format)); }
}

// VerB: u32 vertexCount, u32 byteSize, u16 stride, u16 elementCount, u32 firstFormat, data
public class VertexBuffer {
  public int Count, Stride, Elements; public uint First; public byte[] Bytes;
  public static VertexBuffer Parse(byte[] d) {
    var v = new VertexBuffer { Count = BitConverter.ToInt32(d, 0), Stride = BitConverter.ToUInt16(d, 8), Elements = BitConverter.ToUInt16(d, 10), First = BitConverter.ToUInt32(d, 12) };
    int size = BitConverter.ToInt32(d, 4); v.Bytes = new byte[size]; Array.Copy(d, 16, v.Bytes, 0, size); return v;
  }
  public byte[] Build() {
    var o = new byte[16 + Bytes.Length];
    BitConverter.GetBytes(Count).CopyTo(o, 0); BitConverter.GetBytes(Bytes.Length).CopyTo(o, 4); BitConverter.GetBytes((ushort)Stride).CopyTo(o, 8);
    BitConverter.GetBytes((ushort)Elements).CopyTo(o, 10); BitConverter.GetBytes(First).CopyTo(o, 12); Bytes.CopyTo(o, 16); return o;
  }
}

// Mesh v1.7 (185 bytes); field offsets decoded from FM5/FH2 car models
public class MeshInfo {
  public BurgBlob Blob; public int Material, LayoutIndex, IndexStart, IndexCount, VertexCount, StreamCount;
  public int BaseVertex; public int[] VbIndex = new int[2], VbSlot = new int[2], VbStride = new int[2], VbOffset = new int[2];
  public const int OffMaterial = 0x00, OffIndexStart = 0x19, OffBaseVertex = 0x1D, OffIndexCount = 0x21, OffVertexCount = 0x2D, OffLayout = 0x31, OffStreamCount = 0x35, OffStreams = 0x39;
  public const int OffUvTransforms = 0x69;   // 16 bytes (4 floats) per UV set, TEXCOORD0..4
  public static MeshInfo Parse(BurgBlob b) {
    var d = b.Data; var m = new MeshInfo { Blob = b, Material = BitConverter.ToUInt16(d, OffMaterial), IndexStart = BitConverter.ToInt32(d, OffIndexStart),
      BaseVertex = BitConverter.ToInt32(d, OffBaseVertex), IndexCount = BitConverter.ToInt32(d, OffIndexCount), VertexCount = BitConverter.ToInt32(d, OffVertexCount),
      LayoutIndex = BitConverter.ToInt32(d, OffLayout), StreamCount = BitConverter.ToInt32(d, OffStreamCount) };
    for (int s = 0; s < 2; s++) { int o = OffStreams + 16 * s;
      m.VbIndex[s] = BitConverter.ToInt32(d, o); m.VbSlot[s] = BitConverter.ToInt32(d, o + 4); m.VbStride[s] = BitConverter.ToInt32(d, o + 8); m.VbOffset[s] = BitConverter.ToInt32(d, o + 12); }
    return m;
  }
}

public static class VertexMath {
  public static float Half(ushort h) {
    int s = (h >> 15) & 1, e = (h >> 10) & 0x1F, m = h & 0x3FF; float v;
    if (e == 0) v = (float)(m * Math.Pow(2, -24)); else if (e == 31) v = m == 0 ? float.PositiveInfinity : float.NaN; else v = (float)((1 + m / 1024.0) * Math.Pow(2, e - 15));
    return s == 1 ? -v : v;
  }
  public static ushort ToHalf(float f) {
    uint x = BitConverter.ToUInt32(BitConverter.GetBytes(f), 0);
    uint sign = (x >> 16) & 0x8000; int exp = (int)((x >> 23) & 0xFF) - 127 + 15; uint mant = x & 0x7FFFFF;
    if (exp <= 0) { if (exp < -10) return (ushort)sign; mant |= 0x800000; uint t = (uint)(14 - exp); uint r = mant >> (int)t; if (((mant >> (int)(t - 1)) & 1) != 0) r++; return (ushort)(sign | r); }
    if (exp >= 31) return (ushort)(sign | 0x7C00);
    uint h = sign | ((uint)exp << 10) | (mant >> 13); if ((mant & 0x1000) != 0) h++; return (ushort)h;
  }
  // Per-vertex tangent (xyz, w = handedness) from triangle list. pos/nrm: xyz per vertex; uv: per vertex; tris: vertex indices
  public static float[][] Tangents(float[][] pos, float[][] nrm, float[][] uv, IList<int> tris) {
    int n = pos.Length; var t = new double[n][]; var b = new double[n][];
    for (int i = 0; i < n; i++) { t[i] = new double[3]; b[i] = new double[3]; }
    for (int k = 0; k + 2 < tris.Count; k += 3) {
      int i0 = tris[k], i1 = tris[k + 1], i2 = tris[k + 2];
      double[] e1 = { pos[i1][0] - pos[i0][0], pos[i1][1] - pos[i0][1], pos[i1][2] - pos[i0][2] }, e2 = { pos[i2][0] - pos[i0][0], pos[i2][1] - pos[i0][1], pos[i2][2] - pos[i0][2] };
      double du1 = uv[i1][0] - uv[i0][0], dv1 = uv[i1][1] - uv[i0][1], du2 = uv[i2][0] - uv[i0][0], dv2 = uv[i2][1] - uv[i0][1];
      double det = du1 * dv2 - du2 * dv1; if (Math.Abs(det) < 1e-12) continue; double r = 1.0 / det;
      for (int c = 0; c < 3; c++) {
        double tc = (e1[c] * dv2 - e2[c] * dv1) * r, bc = (e2[c] * du1 - e1[c] * du2) * r;
        t[i0][c] += tc; t[i1][c] += tc; t[i2][c] += tc; b[i0][c] += bc; b[i1][c] += bc; b[i2][c] += bc;
      }
    }
    var res = new float[n][];
    for (int i = 0; i < n; i++) {
      double[] N = { nrm[i][0], nrm[i][1], nrm[i][2] }; double d = N[0] * t[i][0] + N[1] * t[i][1] + N[2] * t[i][2];
      double[] T = { t[i][0] - N[0] * d, t[i][1] - N[1] * d, t[i][2] - N[2] * d }; double len = Math.Sqrt(T[0] * T[0] + T[1] * T[1] + T[2] * T[2]);
      if (len < 1e-9) {   // no usable UV gradient: any unit vector perpendicular to the normal
        T = Math.Abs(N[0]) < 0.9 ? new double[] { 0, -N[2], N[1] } : new double[] { N[2], 0, -N[0] }; len = Math.Sqrt(T[0] * T[0] + T[1] * T[1] + T[2] * T[2]); if (len < 1e-9) { T = new double[] { 1, 0, 0 }; len = 1; }
      }
      double[] C = { N[1] * T[2] - N[2] * T[1], N[2] * T[0] - N[0] * T[2], N[0] * T[1] - N[1] * T[0] };
      double w = (C[0] * b[i][0] + C[1] * b[i][1] + C[2] * b[i][2]) < 0 ? -1 : 1;
      res[i] = new float[] { (float)(T[0] / len), (float)(T[1] / len), (float)(T[2] / len), (float)w };
    }
    return res;
  }
}

public static class ForzaModelCheck {
  // Validates the decoded structure of every mesh in a model; returns problems (empty = consistent)
  public static List<string> Check(byte[] file) {
    var f = BurgFile.Read(file); var probs = new List<string>();
    var round = f.Write(); if (!round.SequenceEqual(file)) probs.Add("round-trip differs");
    foreach (var b in f.All("VLay")) if (!VertexLayout.Parse(b.Data).Build().SequenceEqual(b.Data)) probs.Add("VLay rebuild differs");
    var layouts = f.All("VLay").ToDictionary(b => b.Id ?? int.MinValue, b => VertexLayout.Parse(b.Data));
    var vbs = f.All("VerB").ToDictionary(b => b.Id ?? int.MinValue, b => VertexBuffer.Parse(b.Data));
    foreach (var m in f.All("Mesh").Select(MeshInfo.Parse)) {
      if (m.Material == 0xFFFF) continue;   // placeholder meshes (no material) carry no draw
      VertexLayout l; if (!layouts.TryGetValue(m.LayoutIndex, out l)) { probs.Add("mesh layout id " + m.LayoutIndex + " not found"); continue; }
      for (int s = 0; s < m.StreamCount && s < 2; s++) {
        int stride = l.Stride(m.VbSlot[s]);
        if (stride != m.VbStride[s]) probs.Add(string.Format("mesh stream {0}: stride {1} != layout {2}", s, m.VbStride[s], stride));
        VertexBuffer v; if (!vbs.TryGetValue(m.VbIndex[s], out v)) { probs.Add("mesh stream " + s + ": buffer id " + m.VbIndex[s] + " not found"); continue; }
        if (v.Stride != m.VbStride[s]) probs.Add(string.Format("mesh stream {0}: buffer id {1} stride {2} != {3}", s, m.VbIndex[s], v.Stride, m.VbStride[s]));
        else if (m.VbOffset[s] % m.VbStride[s] != 0 || m.VbOffset[s] / m.VbStride[s] + m.VertexCount > v.Count) probs.Add("mesh stream " + s + ": vertex range outside buffer id " + m.VbIndex[s]);
      }
    }
    return probs;
  }
}
