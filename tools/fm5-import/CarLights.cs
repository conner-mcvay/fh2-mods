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
