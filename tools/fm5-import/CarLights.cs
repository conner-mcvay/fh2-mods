// Car light data (Lights.bin) and model bounds, for giving imported cars night lights from a donor car.
//
// Lights.bin: u32 0xDEADBEEF, u32 version (1), u32 meshCount, then per mesh: u32 length, ASCII path
// ("game:\media\cars\<car>\scene\exterior\...modelbin"), u16 light id; then the light records (format below).
using System; using System.Collections.Generic; using System.IO; using System.Linq; using System.Text;

public class LightMesh { public string Path; public ushort Id; }

public class LightsFile {
  public uint Magic, Version; public List<LightMesh> Meshes = new List<LightMesh>(); public byte[] Rest;

  public static LightsFile Read(byte[] d) {
    var f = new LightsFile { Magic = BitConverter.ToUInt32(d, 0), Version = BitConverter.ToUInt32(d, 4) };
    if (f.Magic != 0xDEADBEEF) throw new InvalidDataException("not a Lights.bin");
    int n = BitConverter.ToInt32(d, 8), p = 12;
    for (int i = 0; i < n; i++) {
      int len = BitConverter.ToInt32(d, p);
      f.Meshes.Add(new LightMesh { Path = Encoding.ASCII.GetString(d, p + 4, len), Id = BitConverter.ToUInt16(d, p + 4 + len) });
      p += 4 + len + 2;
    }
    f.Rest = new byte[d.Length - p]; Array.Copy(d, p, f.Rest, 0, f.Rest.Length);
    return f;
  }

  public byte[] Write() {
    var ms = new MemoryStream(); var w = new BinaryWriter(ms);
    w.Write(Magic); w.Write(Version); w.Write(Meshes.Count);
    foreach (var m in Meshes) { var b = Encoding.ASCII.GetBytes(m.Path); w.Write(b.Length); w.Write(b); w.Write(m.Id); }
    w.Write(Rest); return ms.ToArray();
  }
}

// Skel blob of a *_skeleton.modelbin: u16 bone count, then per bone: u32 name length, ASCII name, i16 parent,
// i16 first child, i16 next sibling, 4x4 float matrix (row-major, translation in the last row) relative to the parent
public class Bone { public string Name; public int Parent; public float[] Local = new float[16]; public float[] World; }
public static class Skeleton {
  public static List<Bone> Read(byte[] model) {
    var skel = BurgFile.Read(model).All("Skel")[0].Data;
    int n = BitConverter.ToUInt16(skel, 0), p = 2; var bones = new List<Bone>();
    for (int i = 0; i < n; i++) {
      int len = BitConverter.ToInt32(skel, p); var b = new Bone { Name = Encoding.ASCII.GetString(skel, p + 4, len) }; p += 4 + len;
      b.Parent = BitConverter.ToInt16(skel, p); p += 6;
      for (int k = 0; k < 16; k++) b.Local[k] = BitConverter.ToSingle(skel, p + 4 * k); p += 64;
      bones.Add(b);
    }
    foreach (var b in bones) World(bones, b);
    return bones;
  }
  static float[] World(List<Bone> bones, Bone b) {
    if (b.World != null) return b.World;
    if (b.Parent < 0 || b.Parent >= bones.Count) return b.World = b.Local;
    var pw = World(bones, bones[b.Parent]); var r = new float[16];
    for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) { float s = 0; for (int k = 0; k < 4; k++) s += b.Local[i * 4 + k] * pw[k * 4 + j]; r[i * 4 + j] = s; }
    return b.World = r;
  }
}

// Where a lamp's lens is and which way it faces, in the model's own space: centre of the lens vertices and their
// average normal. Lens parts are those whose material path looks like glass/lens; a model without any uses all parts.
public static class LensFrame {
  public static float[] Of(byte[] model) {
    var f = BurgFile.Read(model);
    var mats = new Dictionary<int, string>();
    foreach (var b in f.All("MatI")) { var m = System.Text.RegularExpressions.Regex.Match(Encoding.ASCII.GetString(b.Data), @"(?i)game:\\media\\[^\x00]+?\.materialbin"); if (b.Id.HasValue && m.Success) mats[b.Id.Value] = m.Value.ToLower(); }
    var layouts = f.All("VLay").ToDictionary(b => b.Id.Value, b => VertexLayout.Parse(b.Data));
    var buffers = f.All("VerB").ToDictionary(b => b.Id.Value, b => VertexBuffer.Parse(b.Data));
    var meshes = f.All("Mesh").Select(MeshInfo.Parse).Where(m => m.Material != 0xFFFF).ToList();
    Func<MeshInfo, bool> isLens = m => { string p; return mats.TryGetValue(m.Material, out p) && System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(p), @"gls|glass|lens"); };
    var use = meshes.Where(isLens).ToList(); if (use.Count == 0) use = meshes;
    double[] c = new double[3], n = new double[3]; int count = 0;
    foreach (var m in use) {
      VertexLayout l; VertexBuffer pb, nb;
      if (!layouts.TryGetValue(m.LayoutIndex, out l) || !buffers.TryGetValue(m.VbIndex[0], out pb) || !buffers.TryGetValue(m.VbIndex[1], out nb)) continue;
      var pe = l.Elements.FirstOrDefault(e => e.Semantic == "POSITION" && e.Slot == 0);
      var ne = l.Elements.FirstOrDefault(e => e.Semantic == "NORMAL" && e.Slot == 1);
      if (pe == null || ne == null || pe.Format != 6 || ne.Format != 10) continue;
      int poff = Offset(l, pe), noff = Offset(l, ne);
      int p0 = m.VbOffset[0] / Math.Max(1, m.VbStride[0]), n0 = m.VbOffset[1] / Math.Max(1, m.VbStride[1]);
      for (int i = 0; i < m.VertexCount; i++) {
        int pp = (p0 + i) * pb.Stride + poff, np = (n0 + i) * nb.Stride + noff;
        if (pp + 12 > pb.Bytes.Length || np + 8 > nb.Bytes.Length) break;
        for (int k = 0; k < 3; k++) { c[k] += BitConverter.ToSingle(pb.Bytes, pp + 4 * k); n[k] += VertexMath.Half(BitConverter.ToUInt16(nb.Bytes, np + 2 * k)); }
        count++;
      }
    }
    if (count == 0) return null;
    double len = Math.Sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]); if (len < 1e-6) len = 1;
    return new[] { (float)(c[0] / count), (float)(c[1] / count), (float)(c[2] / count), (float)(n[0] / len), (float)(n[1] / len), (float)(n[2] / len) };
  }
  static int Offset(VertexLayout l, VertexElement x) { int o = 0; foreach (var e in l.Elements.Where(e => e.Slot == x.Slot)) { if (e == x) break; o += VertexLayout.FormatSize(e.Format); } return o; }
}

// Quaternions as x, y, z, w (the order Lights.bin stores them)
public static class Quat {
  public static float[] Mul(float[] a, float[] b) {   // a * b: rotate by b, then by a
    return new[] { a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1], a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
                   a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3], a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2] };
  }
  public static float[] Between(float[] u, float[] v) {   // shortest rotation taking unit vector u to v
    float d = u[0] * v[0] + u[1] * v[1] + u[2] * v[2];
    if (d < -0.9999f) { var ax = Math.Abs(u[0]) < 0.9f ? new[] { 0f, -u[2], u[1] } : new[] { -u[1], u[0], 0f }; var l = (float)Math.Sqrt(ax[0] * ax[0] + ax[1] * ax[1] + ax[2] * ax[2]); return new[] { ax[0] / l, ax[1] / l, ax[2] / l, 0f }; }
    var q = new[] { u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0], 1 + d };
    var n = (float)Math.Sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]); return new[] { q[0] / n, q[1] / n, q[2] / n, q[3] / n };
  }
  public static float[] Rotate(float[] q, float[] v) { var r = Mul(Mul(q, new[] { v[0], v[1], v[2], 0f }), new[] { -q[0], -q[1], -q[2], q[3] }); return new[] { r[0], r[1], r[2] }; }
  // a row-major 4x4 (row vectors, translation in the last row) applied to a point / a direction
  public static float[] Point(float[] m, float[] p) { return new[] { p[0] * m[0] + p[1] * m[4] + p[2] * m[8] + m[12], p[0] * m[1] + p[1] * m[5] + p[2] * m[9] + m[13], p[0] * m[2] + p[1] * m[6] + p[2] * m[10] + m[14] }; }
  public static float[] Dir(float[] m, float[] d) { var r = new[] { d[0] * m[0] + d[1] * m[4] + d[2] * m[8], d[0] * m[1] + d[1] * m[5] + d[2] * m[9], d[0] * m[2] + d[1] * m[6] + d[2] * m[10] }; var l = (float)Math.Sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2]); return new[] { r[0] / l, r[1] / l, r[2] / l }; }
}

public static class ModelBounds {
  // min x,y,z, max x,y,z over every drawn mesh's positions (slot-0 stream), in the model's own space
  public static float[] Of(byte[] model) {
    var f = BurgFile.Read(model);
    var layouts = f.All("VLay").ToDictionary(b => b.Id.Value, b => VertexLayout.Parse(b.Data));
    var buffers = f.All("VerB").ToDictionary(b => b.Id.Value, b => VertexBuffer.Parse(b.Data));
    var r = new[] { float.MaxValue, float.MaxValue, float.MaxValue, float.MinValue, float.MinValue, float.MinValue };
    foreach (var m in f.All("Mesh").Select(MeshInfo.Parse).Where(m => m.Material != 0xFFFF)) {
      VertexLayout l; VertexBuffer v;
      if (!layouts.TryGetValue(m.LayoutIndex, out l) || !buffers.TryGetValue(m.VbIndex[0], out v)) continue;
      var pe = l.Elements.FirstOrDefault(e => e.Semantic == "POSITION" && e.Slot == 0); if (pe == null) continue;
      int off = 0; foreach (var e in l.Elements.Where(e => e.Slot == 0)) { if (e == pe) break; off += VertexLayout.FormatSize(e.Format); }
      int first = m.VbOffset[0] / Math.Max(1, m.VbStride[0]);
      for (int i = first; i < Math.Min(v.Count, first + m.VertexCount); i++) {
        float[] p = Read(v.Bytes, i * v.Stride + off, pe.Format); if (p == null) break;
        for (int c = 0; c < 3; c++) { r[c] = Math.Min(r[c], p[c]); r[c + 3] = Math.Max(r[c + 3], p[c]); }
      }
    }
    return r[0] == float.MaxValue ? null : r;
  }
  static float[] Read(byte[] d, int p, uint fmt) {
    if (p < 0 || p + 6 > d.Length) return null;
    switch (fmt) {
      case 6: return new[] { BitConverter.ToSingle(d, p), BitConverter.ToSingle(d, p + 4), BitConverter.ToSingle(d, p + 8) };
      case 2: return new[] { BitConverter.ToSingle(d, p), BitConverter.ToSingle(d, p + 4), BitConverter.ToSingle(d, p + 8) };
      case 10: return new[] { VertexMath.Half(BitConverter.ToUInt16(d, p)), VertexMath.Half(BitConverter.ToUInt16(d, p + 2)), VertexMath.Half(BitConverter.ToUInt16(d, p + 4)) };
      case 13: return new[] { BitConverter.ToInt16(d, p) / 32767f, BitConverter.ToInt16(d, p + 2) / 32767f, BitConverter.ToInt16(d, p + 4) / 32767f };
      default: return null;
    }
  }
}
