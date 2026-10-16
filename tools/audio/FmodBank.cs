// FH2 car sound banks (FMOD Studio, Mount\media\audio\fmodanthem\durango\PG_<car>.bank): finds the sounds the game
// plays for forced induction and changes their volume.
//
// A bank is RIFF "FEV " > LIST PROJ > one LIST per record kind (PRMS parameters, PMLS parameter sheets, EVIS event
// instruments, EVTS events, MBSS event master tracks, ...); a record's GUID is the first 16 bytes of its first
// sub-chunk. The game sets three parameters from the car's upgrades (1-3 = the part's level):
//   TurboUpgradeLevel  the turbo (single and twin alike), DSCUpgradeLevel  a positive-displacement supercharger,
//   CSCUpgradeLevel    a centrifugal supercharger.
// Each event has a sheet per parameter (PMLO > PMLB: the parameter GUID twice, the event GUID, then 24-byte items:
// instrument GUID, start, length). The items are event instruments (EVIT > EVIB: own GUID, then the GUID of the
// event it plays); those nested events hold the turbo / supercharger sounds. Their master track (the EVNT's GUID at
// 64) is an MBUS whose 19-byte BUS chunk keeps its volume in dB as a float at byte 11, which nothing automates:
// that is the volume this changes.
//
// Blow-off valve (BOV): the samples named bov / Blowoff / DumpValve (names in the bank's FSB5 sample table; a WAV
// record is a GUID and the sample index at byte 22) play from multi-instruments on tracks of their own: event
// group buses (GBUS) with the same 19-byte BUS volume. An instrument's track is the GUID after 0x18 0x00 at byte 81
// of its INST chunk (a multi-instrument's children have none; the multi-instrument has it). Tracks holding only
// blow-off samples are the BOV sounds; a track that mixes in anything else is left alone.
using System; using System.Collections.Generic; using System.IO; using System.Linq; using System.Text;
using System.Text.RegularExpressions;

public class FmodBankSound {
  public string Kind;          // Turbo, DSC, CSC or BOV
  public string Range;         // the upgrade levels it plays at, e.g. "1-3" (BOV: "")
  public int VolumeOffset;     // file offset of the master track's volume (float, dB)
  public float StockVolume;    // dB
}

// One placed sound layer (an instrument on a parameter sheet or an event timeline), for the inspector.
public class FmodLayer {
  public int Event;              // the event's number in the bank (1-based, bank order)
  public string Sheet;           // the parameter whose sheet it's on (EngineRPM, Throttle, ...), or "timeline"
  public float Start, End;       // where on the sheet it plays (parameter values; RPM on EngineRPM)
  public string Type;            // WAIT (one sample), MUIT (a random pick of several), EVIT (a nested event), ...
  public string[] Samples;       // sample names it plays (through a multi-instrument's children)
  public string Category;        // the samples' common name without numbers (Exhaust, BackFire, bov, ...)
  public int VolumeOffset;       // file offset of the instrument's volume (float, dB)
  public float Volume;
  public bool VolumeAutomated;   // a parameter drives the volume (the value above is then ignored)
}

public class FmodBank {
  public static readonly string[] Kinds = { "Turbo", "DSC", "CSC" };   // the upgrade-level parameters (BOV is by sample)
  static readonly Regex BovSample = new Regex("bov|blow|dump", RegexOptions.IgnoreCase);
  public byte[] Data;
  public List<FmodBankSound> Sounds = new List<FmodBankSound>();
  public List<string> Skipped = new List<string>();   // sheets items that weren't the expected shape

  struct Chunk { public string Id; public int Offset, Size; }   // Offset: the chunk header

  public FmodBank(byte[] data) { Data = data; Find(); }

  IEnumerable<Chunk> Chunks(int o, int end) {
    while (o + 8 <= end) {
      int z = BitConverter.ToInt32(Data, o + 4);
      yield return new Chunk { Id = Encoding.ASCII.GetString(Data, o, 4), Offset = o, Size = z };
      o += 8 + z + (z & 1);
    }
  }
  string ListType(Chunk c) { return Encoding.ASCII.GetString(Data, c.Offset + 8, 4); }
  List<Chunk> Kids(Chunk c) { return Chunks(c.Offset + 12, c.Offset + 8 + c.Size).ToList(); }
  string Guid16(int o) { return BitConverter.ToString(Data, o, 16); }
  string RecordGuid(Chunk c) {   // a record (LIST or plain chunk): its own GUID
    if (c.Id == "LIST") { var k = Kids(c)[0]; return Guid16(k.Offset + 8); }
    return Guid16(c.Offset + 8);
  }
  bool Contains(Chunk c, byte[] s) {
    int end = c.Offset + 8 + c.Size - s.Length;
    for (int i = c.Offset; i <= end; i++) { int j = 0; while (j < s.Length && Data[i + j] == s[j]) j++; if (j == s.Length) return true; }
    return false;
  }

  void Find() {
    var riff = Chunks(0, Data.Length).First();
    if (riff.Id != "RIFF" || ListType(riff) != "FEV ") throw new InvalidDataException("not an FMOD Studio bank");
    var proj = Kids(riff).First(c => c.Id == "LIST" && ListType(c) == "PROJ");
    var sections = new Dictionary<string, List<Chunk>>();
    foreach (var s in Kids(proj).Where(c => c.Id == "LIST")) sections[ListType(s)] = Kids(s).Where(c => c.Id != "LCNT").ToList();
    Func<string, List<Chunk>> sec = n => sections.ContainsKey(n) ? sections[n] : new List<Chunk>();

    var paramKind = new Dictionary<string, string>();   // parameter GUID -> kind
    foreach (var p in sec("PRMS"))
      foreach (var k in Kinds)
        if (Contains(p, Encoding.ASCII.GetBytes(k + "UpgradeLevel"))) paramKind[RecordGuid(p)] = k;
    var evit = new Dictionary<string, Chunk>(); foreach (var c in sec("EVIS")) evit[RecordGuid(c)] = c;
    var evnt = new Dictionary<string, Chunk>(); foreach (var c in sec("EVTS")) evnt[RecordGuid(c)] = c;
    var mbus = new Dictionary<string, Chunk>(); foreach (var c in sec("MBSS")) mbus[RecordGuid(c)] = c;

    var seen = new HashSet<int>();
    foreach (var sheet in sec("PMLS")) {
      var pmlb = Kids(sheet)[0];
      string kind; if (pmlb.Id != "PMLB" || !paramKind.TryGetValue(Guid16(pmlb.Offset + 8), out kind)) continue;
      int body = pmlb.Offset + 8, end = body + pmlb.Size;
      for (int i = body + 48; i + 16 <= end; i++) {   // the items follow the two parameter GUIDs and the event GUID
        Chunk inst; if (!evit.TryGetValue(Guid16(i), out inst)) continue;
        float start = i + 24 <= end ? BitConverter.ToSingle(Data, i + 16) : 0, len = i + 24 <= end ? BitConverter.ToSingle(Data, i + 20) : 0;
        string range = (int)Math.Round(start + 0.2) + "-" + (int)Math.Round(start + len - 0.2);
        var evib = Kids(inst)[0]; Chunk ev, mb;
        if (evib.Id != "EVIB" || !evnt.TryGetValue(Guid16(evib.Offset + 8 + 16), out ev)) { Skipped.Add(kind + " " + range + ": not an event instrument"); continue; }
        if (ev.Size < 80 || !mbus.TryGetValue(Guid16(ev.Offset + 8 + 64), out mb)) { Skipped.Add(kind + " " + range + ": event without a master track"); continue; }
        var bus = Kids(mb).FirstOrDefault(c => c.Id == "BUS ");
        if (bus.Id != "BUS " || bus.Size != 19) { Skipped.Add(kind + " " + range + ": master track with effects or automation"); continue; }
        int at = bus.Offset + 8 + 11;
        if (!seen.Add(at)) continue;   // the same nested event on more than one sheet: changed once
        Sounds.Add(new FmodBankSound { Kind = kind, Range = range, VolumeOffset = at, StockVolume = BitConverter.ToSingle(Data, at) });
        i += 23;
      }
    }
    FindBlowOff(sec);
  }

  // GUIDs (as Guid16 strings) found anywhere in a record's bytes, from the given set
  List<string> GuidsIn(Chunk c, ICollection<string> keys) {
    var found = new List<string>(); var keyBytes = new HashSet<string>(keys);
    for (int i = c.Offset + 8; i + 16 <= c.Offset + 8 + c.Size; i++) { string g = Guid16(i); if (keyBytes.Contains(g)) found.Add(g); }
    return found;
  }

  void FindBlowOff(Func<string, List<Chunk>> sec) {
    // sample names (FSB5: version, sample count at 8, sample-header size at 12; names after the 60-byte header and the sample headers)
    int fsb = IndexOf(Encoding.ASCII.GetBytes("FSB5"));
    if (fsb < 0 || BitConverter.ToInt32(Data, fsb + 4) != 1) return;
    int count = BitConverter.ToInt32(Data, fsb + 8), names = fsb + 60 + BitConverter.ToInt32(Data, fsb + 12);
    var sampleName = new string[count];
    for (int k = 0; k < count; k++) {
      int o = names + BitConverter.ToInt32(Data, names + 4 * k), e = Array.IndexOf(Data, (byte)0, o);
      sampleName[k] = Encoding.ASCII.GetString(Data, o, e - o);
    }
    var wav = new Dictionary<string, string>();
    foreach (var w in sec("WAVS")) { int idx = BitConverter.ToInt32(Data, w.Offset + 8 + 22); if (idx >= 0 && idx < count) wav[RecordGuid(w)] = sampleName[idx]; }
    var inst = new Dictionary<string, Chunk>();
    foreach (var s in new[] { "WAIS", "MUIS", "SPIS", "PRIS", "EVIS" }) foreach (var c in sec(s)) inst[RecordGuid(c)] = c;
    var tracks = new Dictionary<string, Chunk>(); foreach (var c in sec("GBSS")) tracks[RecordGuid(c)] = c;

    var memo = new Dictionary<string, HashSet<string>>();
    Func<string, int, HashSet<string>> samples = null;   // sample names an instrument plays (through a multi-instrument's children)
    samples = (g, depth) => {
      HashSet<string> s; if (memo.TryGetValue(g, out s)) return s;
      s = new HashSet<string>(); memo[g] = s;
      var c = inst[g];
      foreach (var w in GuidsIn(c, wav.Keys)) s.Add(wav[w]);
      if (depth < 4) foreach (var child in GuidsIn(c, inst.Keys)) if (child != g) s.UnionWith(samples(child, depth + 1));
      return s;
    };
    var onTrack = new Dictionary<string, HashSet<string>>();
    foreach (var kv in inst) {
      var ic = Kids(kv.Value).FirstOrDefault(k => k.Id == "INST");
      if (ic.Id != "INST" || ic.Size < 99 || Data[ic.Offset + 8 + 81] != 0x18 || Data[ic.Offset + 8 + 82] != 0) continue;
      string t = Guid16(ic.Offset + 8 + 83); if (!tracks.ContainsKey(t)) continue;
      HashSet<string> set; if (!onTrack.TryGetValue(t, out set)) onTrack[t] = set = new HashSet<string>();
      set.UnionWith(samples(kv.Key, 0));
    }
    foreach (var kv in onTrack) {
      var bov = kv.Value.Where(n => BovSample.IsMatch(n)).ToList();
      if (bov.Count == 0) continue;
      if (bov.Count != kv.Value.Count) { Skipped.Add("BOV track also plays " + string.Join(", ", kv.Value.Except(bov))); continue; }
      var bus = Kids(tracks[kv.Key]).FirstOrDefault(c => c.Id == "BUS ");
      if (bus.Id != "BUS " || bus.Size != 19) { Skipped.Add("BOV track with effects or automation"); continue; }
      int at = bus.Offset + 8 + 11;
      Sounds.Add(new FmodBankSound { Kind = "BOV", Range = "", VolumeOffset = at, StockVolume = BitConverter.ToSingle(Data, at) });
    }
  }

  // --- inspector -------------------------------------------------------------------------------------------------
  // Parameter records (LIST PARM > PRMB): GUID, then the name's length (u16) at byte 21 and the name (built-in
  // parameters such as distance have none). Instrument records: their INST chunk has the volume in dB (float) at
  // byte 16; PRPS > PROP 0 is the volume's automation (bytes 8-23 of the PROP are zero when there is none).
  // Sheets (PMLO > PMLB) and timelines (TMLN) list their instruments as GUID + start + length.
  public Dictionary<string, string> ParameterNames() {
    var names = new Dictionary<string, string>();
    foreach (var p in Section("PRMS")) {
      var b = Kids(p)[0]; if (b.Id != "PRMB" || b.Size < 23) continue;
      int len = BitConverter.ToUInt16(Data, b.Offset + 8 + 21);
      names[Guid16(b.Offset + 8)] = len > 0 && 23 + len <= b.Size ? Encoding.ASCII.GetString(Data, b.Offset + 8 + 23, len).TrimEnd('\0') : "(built-in)";
    }
    return names;
  }

  List<Chunk> Section(string name) {
    var riff = Chunks(0, Data.Length).First();
    var proj = Kids(riff).First(c => c.Id == "LIST" && ListType(c) == "PROJ");
    var s = Kids(proj).FirstOrDefault(c => c.Id == "LIST" && ListType(c) == name);
    return s.Id == "LIST" ? Kids(s).Where(c => c.Id != "LCNT").ToList() : new List<Chunk>();
  }

  public string[] SampleNames() {
    int fsb = IndexOf(Encoding.ASCII.GetBytes("FSB5"));
    if (fsb < 0 || BitConverter.ToInt32(Data, fsb + 4) != 1) return new string[0];
    int count = BitConverter.ToInt32(Data, fsb + 8), names = fsb + 60 + BitConverter.ToInt32(Data, fsb + 12);
    var r = new string[count];
    for (int k = 0; k < count; k++) {
      int o = names + BitConverter.ToInt32(Data, names + 4 * k), e = Array.IndexOf(Data, (byte)0, o);
      string n = Encoding.ASCII.GetString(Data, o, e - o); int brace = n.IndexOf(" {"); r[k] = brace >= 0 ? n.Substring(0, brace) : n;
    }
    return r;
  }

  public static string CategoryOf(IEnumerable<string> samples) {
    var cats = samples.Select(n => Regex.Replace(n, @"([_ -]?\d+)+([_ -]?[A-Za-z]{0,4}\d*)*$", "")).Where(c => c != "").Distinct().ToList();
    return cats.Count == 0 ? "" : cats.Count == 1 ? cats[0] : string.Join("+", cats.Take(3));
  }

  public List<FmodLayer> Layers() {
    var pnames = ParameterNames(); var sampleName = SampleNames();
    var wav = new Dictionary<string, string>();
    foreach (var w in Section("WAVS")) { int idx = BitConverter.ToInt32(Data, w.Offset + 8 + 22); if (idx >= 0 && idx < sampleName.Length) wav[RecordGuid(w)] = sampleName[idx]; }
    var inst = new Dictionary<string, Chunk>();
    foreach (var s in new[] { "WAIS", "MUIS", "SPIS", "PRIS", "EVIS" }) foreach (var c in Section(s)) inst[RecordGuid(c)] = c;
    var events = Section("EVTS"); var evIndex = new Dictionary<string, int>();
    for (int i = 0; i < events.Count; i++) evIndex[RecordGuid(events[i])] = i + 1;
    var timelineEvent = new Dictionary<string, int>();   // TMLN GUID -> event (the EVNT has it at byte 32)
    foreach (var e in events) if (e.Size >= 48) timelineEvent[Guid16(e.Offset + 8 + 32)] = evIndex[RecordGuid(e)];

    var memo = new Dictionary<string, HashSet<string>>();
    Func<string, int, HashSet<string>> samples = null;
    samples = (g, depth) => {
      HashSet<string> s; if (memo.TryGetValue(g, out s)) return s;
      s = new HashSet<string>(); memo[g] = s;
      foreach (var w in GuidsIn(inst[g], wav.Keys)) s.Add(wav[w]);
      if (depth < 4) foreach (var child in GuidsIn(inst[g], inst.Keys)) if (child != g && inst[child].Id == "LIST" && ListType(inst[child]) != "EVIT") s.UnionWith(samples(child, depth + 1));
      return s;
    };
    var layers = new List<FmodLayer>();
    Action<int, int, int, string> place = (body, end, ev, sheet) => {
      for (int i = body; i + 24 <= end; i++) {
        Chunk c; if (!inst.TryGetValue(Guid16(i), out c)) continue;
        var ic = Kids(c).FirstOrDefault(k => k.Id == "INST"); if (ic.Id != "INST" || ic.Size < 20) continue;
        var prps = Kids(c).FirstOrDefault(k => k.Id == "LIST" && ListType(k) == "PRPS");
        bool automated = false;
        if (prps.Id == "LIST")
          foreach (var p in Kids(prps).Where(k => k.Id == "PROP" && k.Size >= 24))
            if (BitConverter.ToInt32(Data, p.Offset + 8) == 0) for (int j = 8; j < 24; j++) if (Data[p.Offset + 8 + j] != 0) automated = true;
        var s = samples(Guid16(i), 0).OrderBy(n => n).ToArray();
        float start = BitConverter.ToSingle(Data, i + 16), len = BitConverter.ToSingle(Data, i + 20);
        layers.Add(new FmodLayer { Event = ev, Sheet = sheet, Start = start, End = start + len, Type = ListType(c), Samples = s,
          Category = ListType(c) == "EVIT" ? "(nested event)" : CategoryOf(s), VolumeOffset = ic.Offset + 8 + 16,
          Volume = BitConverter.ToSingle(Data, ic.Offset + 8 + 16), VolumeAutomated = automated });
        i += 23;
      }
    };
    foreach (var sheet in Section("PMLS")) {
      var b = Kids(sheet)[0]; if (b.Id != "PMLB" || b.Size < 48) continue;
      string pn; if (!pnames.TryGetValue(Guid16(b.Offset + 8), out pn)) pn = "?";
      int ev; evIndex.TryGetValue(Guid16(b.Offset + 8 + 32), out ev);
      place(b.Offset + 8 + 48, b.Offset + 8 + b.Size, ev, pn);
    }
    foreach (var t in Section("TLNS")) {
      int ev; timelineEvent.TryGetValue(RecordGuid(t), out ev);
      foreach (var k in Kids(t).Where(k => k.Id != "LIST" && k.Size > 16)) place(k.Offset + 8 + 16, k.Offset + 8 + k.Size, ev, "timeline");
    }
    return layers;
  }

  // --- tuning ----------------------------------------------------------------------------------------------------
  // Every setting adds to the stock value of what it targets (0 = stock):
  //   Turbo, DSC, CSC        the nested events on the upgrade-level sheets (master volume, dB)
  //   BOV, Backfire          tracks playing only those samples (volume, dB; tracks whose volume is automated are left:
//                          every car's Burble track is, so the off-throttle burble has no setting)
  //   <Sound>Volume          every layer of that sound on its EngineRPM sheet (instrument volume, dB)
  //   <Sound>Idle            its lowest-RPM layer (the RPM in the sample name: Exhaust_00720), on top of Volume
  //   <Sound>Highs / Lows    the high / low band of its 3-band EQs (dB; Highs: the EQs on the tracks the layers play
  //                          into, Lows: the EQ on the group above them; either falls back to the other level)
  //   <Sound>Grit            the drive of its Turn10Saturator (on the group, else the tracks)
  //   LowFreq                the low-frequency layers (samples named LFE) on EngineRPM sheets (dB)
//   Whistle                the layers on Boost sheets (WhistleLooping, AirLooping: the spool whistle and air), dB
  // <Sound> is Exhaust, Engine or Intake. Effects: BEFX > BEFF (BEFB: GUID, FMOD effect type at byte 20; 28 = 3-band
  // EQ) and PEFX > PEFF (PEFB: GUID, name length at 20, name: Turn10Saturator), each with PMEF = count, then per
  // setting u32 type (0 float, 1 int) + value; a bus uses the effects whose GUIDs its record holds. 3-EQ settings:
  // low gain, mid gain, high gain (dB, -80 to 10), low and high crossover (Hz), slope; the saturator's first is the drive.
  public static readonly string[] SoundsTuned = { "Exhaust", "Engine", "Intake" };
  public static readonly string[] Settings = {
    "ExhaustVolume", "ExhaustIdle", "ExhaustHighs", "ExhaustLows", "ExhaustGrit",
    "EngineVolume", "EngineIdle", "EngineHighs", "EngineLows", "EngineGrit",
    "IntakeVolume", "IntakeIdle", "IntakeHighs", "IntakeLows", "IntakeGrit",
    "LowFreq", "Backfire", "Turbo", "Whistle", "DSC", "CSC", "BOV" };

  public class Target { public string Setting; public int Offset; public float Stock, Min, Max; public string What; }
  List<Target> targets;
  public List<Target> Targets() { if (targets == null) targets = FindTargets(); return targets; }
  public IEnumerable<string> Available() { return Settings.Where(s => Targets().Any(t => t.Setting == s)); }

  // Writes the settings (dB etc. added to stock) into Data, which must be the stock bank; returns how many values changed.
  public int Tune(IDictionary<string, float> settings) {
    var sum = new Dictionary<int, float>(); var lim = new Dictionary<int, Target>();
    foreach (var t in Targets()) {
      float v; if (!settings.TryGetValue(t.Setting, out v) || v == 0) continue;
      float cur; sum[t.Offset] = (sum.TryGetValue(t.Offset, out cur) ? cur : 0) + v; lim[t.Offset] = t;
    }
    foreach (var kv in sum) {
      var t = lim[kv.Key]; float nv = Math.Max(t.Min, Math.Min(t.Max, t.Stock + kv.Value));
      Array.Copy(BitConverter.GetBytes(nv), 0, Data, kv.Key, 4);
    }
    return sum.Count;
  }

  List<Target> FindTargets() {
    var list = new List<Target>();
    foreach (var s in Sounds)   // Turbo / DSC / CSC / BOV, found by Find()
      list.Add(new Target { Setting = s.Kind, Offset = s.VolumeOffset, Stock = s.StockVolume, Min = -80, Max = 30, What = s.Kind + " " + s.Range });

    var lfe = new Regex("(^|_)LFE(_|$)", RegexOptions.IgnoreCase);
    var rpm = new Regex(@"(\d{3,5})(?!.*\d{3})");
    var layers = Layers().Where(l => l.Sheet == "EngineRPM" && (l.Type == "WAIT" || l.Type == "MUIT") && !l.VolumeAutomated && l.Volume > -40).ToList();
    var seen = new HashSet<int>();
    foreach (var l in layers) {
      if (!seen.Add(l.VolumeOffset)) continue;
      string sound = lfe.IsMatch(l.Category) ? "LowFreq" : SoundsTuned.FirstOrDefault(s => l.Category.StartsWith(s, StringComparison.OrdinalIgnoreCase));
      if (sound == null) continue;
      list.Add(new Target { Setting = sound == "LowFreq" ? "LowFreq" : sound + "Volume", Offset = l.VolumeOffset, Stock = l.Volume, Min = -80, Max = 40, What = string.Join(", ", l.Samples) });
    }
    var seenBoost = new HashSet<int>();
    foreach (var l in Layers().Where(l => l.Sheet == "Boost" && (l.Type == "WAIT" || l.Type == "MUIT") && !l.VolumeAutomated && l.Volume > -40))
      if (seenBoost.Add(l.VolumeOffset)) list.Add(new Target { Setting = "Whistle", Offset = l.VolumeOffset, Stock = l.Volume, Min = -80, Max = 40, What = string.Join(", ", l.Samples) });
    foreach (var s in SoundsTuned) {   // idle: the layer recorded at the lowest RPM
      var mine = layers.Where(l => !lfe.IsMatch(l.Category) && l.Category.StartsWith(s, StringComparison.OrdinalIgnoreCase) && l.Samples.Length > 0).ToList();
      Func<FmodLayer, int> at = l => { var m = rpm.Match(l.Samples[0]); return m.Success ? int.Parse(m.Groups[1].Value) : 100000 + (int)l.Start; };
      var idle = mine.OrderBy(at).ThenBy(l => l.Start).FirstOrDefault();
      if (idle != null) list.Add(new Target { Setting = s + "Idle", Offset = idle.VolumeOffset, Stock = idle.Volume, Min = -80, Max = 40, What = idle.Samples[0] });
    }
    FindTrackTargets(list);
    FindEffectTargets(list);
    return list;
  }

  // the bank's structure for the track and effect targets: instruments, their samples and tracks, the bus tree
  Dictionary<string, Chunk> instrs, buses; Dictionary<string, string> busParent; Dictionary<string, HashSet<string>> onTrack;
  void MapBuses() {
    if (onTrack != null) return;
    var sampleName = SampleNames(); var wav = new Dictionary<string, string>();
    foreach (var w in Section("WAVS")) { int idx = BitConverter.ToInt32(Data, w.Offset + 8 + 22); if (idx >= 0 && idx < sampleName.Length) wav[RecordGuid(w)] = sampleName[idx]; }
    instrs = new Dictionary<string, Chunk>();
    foreach (var s in new[] { "WAIS", "MUIS", "SPIS", "PRIS", "EVIS" }) foreach (var c in Section(s)) instrs[RecordGuid(c)] = c;
    buses = new Dictionary<string, Chunk>(); busParent = new Dictionary<string, string>();
    foreach (var c in Section("GBSS")) { var g = RecordGuid(c); buses[g] = c; var h = Kids(c)[0]; if (h.Size >= 34) busParent[g] = Guid16(h.Offset + 8 + 18); }
    var memo = new Dictionary<string, HashSet<string>>();
    Func<string, int, HashSet<string>> samples = null;
    samples = (g, depth) => {
      HashSet<string> s; if (memo.TryGetValue(g, out s)) return s;
      s = new HashSet<string>(); memo[g] = s;
      foreach (var w in GuidsIn(instrs[g], wav.Keys)) s.Add(wav[w]);
      if (depth < 4) foreach (var child in GuidsIn(instrs[g], instrs.Keys)) if (child != g && ListType(instrs[child]) != "EVIT") s.UnionWith(samples(child, depth + 1));
      return s;
    };
    onTrack = new Dictionary<string, HashSet<string>>();
    foreach (var kv in instrs) {
      var ic = Kids(kv.Value).FirstOrDefault(k => k.Id == "INST");
      if (ic.Id != "INST" || ic.Size < 99 || Data[ic.Offset + 8 + 81] != 0x18 || Data[ic.Offset + 8 + 82] != 0) continue;
      string t = Guid16(ic.Offset + 8 + 83); if (!buses.ContainsKey(t)) continue;
      HashSet<string> set; if (!onTrack.TryGetValue(t, out set)) onTrack[t] = set = new HashSet<string>();
      set.UnionWith(samples(kv.Key, 0));
    }
  }
  bool VolumeAutomated(Chunk record) {
    var prps = Kids(record).FirstOrDefault(k => k.Id == "LIST" && ListType(k) == "PRPS");
    if (prps.Id != "LIST") return false;
    foreach (var p in Kids(prps).Where(k => k.Id == "PROP" && k.Size >= 24))
      if (BitConverter.ToInt32(Data, p.Offset + 8) == 0) for (int j = 8; j < 24; j++) if (Data[p.Offset + 8 + j] != 0) return true;
    return false;
  }

  void FindTrackTargets(List<Target> list) {   // Backfire: tracks of its own (BOV is in Sounds)
    MapBuses();
    var kinds = new Dictionary<string, Regex> { { "Backfire", new Regex("^back_?fire", RegexOptions.IgnoreCase) } };
    foreach (var kv in onTrack) {
      foreach (var k in kinds) {
        if (kv.Value.Count == 0 || !kv.Value.All(n => k.Value.IsMatch(n))) continue;
        var bus = Kids(buses[kv.Key]).FirstOrDefault(c => c.Id == "BUS ");
        if (bus.Id != "BUS " || bus.Size != 19 || VolumeAutomated(buses[kv.Key])) continue;
        int at = bus.Offset + 8 + 11;
        list.Add(new Target { Setting = k.Key, Offset = at, Stock = BitConverter.ToSingle(Data, at), Min = -80, Max = 30, What = k.Key + " track" });
      }
    }
  }

  void FindEffectTargets(List<Target> list) {
    MapBuses();
    var eq = new Dictionary<string, int>(); var sat = new Dictionary<string, int>();   // effect GUID -> its PMEF settings' offset
    foreach (var e in Section("BEFX").Concat(Section("PEFX"))) {
      if (e.Id != "LIST") continue;
      var ks = Kids(e); var h = ks[0]; var pm = ks.FirstOrDefault(k => k.Id == "PMEF");
      if (pm.Id != "PMEF" || h.Size < 22) continue;
      int n = BitConverter.ToInt32(Data, pm.Offset + 8);
      if (4 + 8 * n != pm.Size) continue;
      bool floats = Enumerable.Range(0, n).All(i => BitConverter.ToInt32(Data, pm.Offset + 12 + 8 * i) <= 1);
      if (!floats) continue;
      if (h.Id == "BEFB" && h.Size >= 24 && BitConverter.ToInt32(Data, h.Offset + 8 + 20) == 28 && n >= 3) eq[Guid16(h.Offset + 8)] = pm.Offset + 12;
      else if (h.Id == "PEFB") {
        int len = BitConverter.ToUInt16(Data, h.Offset + 8 + 20);
        if (22 + len <= h.Size && Encoding.ASCII.GetString(Data, h.Offset + 8 + 22, len).TrimEnd('\0') == "Turn10Saturator" && n >= 1) sat[Guid16(h.Offset + 8)] = pm.Offset + 12;
      }
    }
    Func<string, HashSet<string>> direct = g => { HashSet<string> s; return onTrack.TryGetValue(g, out s) ? s : new HashSet<string>(); };
    var lfe = new Regex("(^|_)LFE(_|$)", RegexOptions.IgnoreCase);
    Func<string, string, bool> carries = null;   // does the bus (or a bus below it) play this sound?
    carries = (g, sound) => direct(g).Any(n => n.StartsWith(sound, StringComparison.OrdinalIgnoreCase) && !lfe.IsMatch(n))
      || busParent.Where(p => p.Value == g).Any(p => carries(p.Key, sound));
    foreach (var sound in SoundsTuned) {
      var tracks = buses.Keys.Where(g => direct(g).Any(n => n.StartsWith(sound, StringComparison.OrdinalIgnoreCase) && !lfe.IsMatch(n))).ToList();
      var groups = buses.Keys.Where(g => !tracks.Contains(g) && carries(g, sound)).ToList();
      Func<List<string>, Dictionary<string, int>, List<int>> fx = (bs, kind) => bs.SelectMany(g => GuidsIn(buses[g], kind.Keys).Select(e => kind[e])).Distinct().ToList();
      var trackEq = fx(tracks, eq); var groupEq = fx(groups, eq);
      foreach (var o in (trackEq.Count > 0 ? trackEq : groupEq)) list.Add(EffectTarget(sound + "Highs", o + 2 * 8 + 4, -80, 10, "EQ high band"));
      foreach (var o in (groupEq.Count > 0 ? groupEq : trackEq)) list.Add(EffectTarget(sound + "Lows", o + 4, -80, 10, "EQ low band"));
      var groupSat = fx(groups, sat); var trackSat = fx(tracks, sat);
      foreach (var o in (groupSat.Count > 0 ? groupSat : trackSat)) list.Add(EffectTarget(sound + "Grit", o + 4, 0, 40, "saturator drive"));
    }
  }
  Target EffectTarget(string setting, int at, float min, float max, string what) {
    return new Target { Setting = setting, Offset = at, Stock = BitConverter.ToSingle(Data, at), Min = min, Max = max, What = what };
  }

  int IndexOf(byte[] s) {
    for (int i = 0; i + s.Length <= Data.Length; i++) { int j = 0; while (j < s.Length && Data[i + j] == s[j]) j++; if (j == s.Length) return i; }
    return -1;
  }

  // Raises (or lowers) the sounds of each kind by gain[kind] dB from their stock volume; returns how many changed.
  public int Apply(Dictionary<string, float> gain) {
    int n = 0;
    foreach (var s in Sounds) {
      float g; if (!gain.TryGetValue(s.Kind, out g) || g == 0) continue;
      Array.Copy(BitConverter.GetBytes(s.StockVolume + g), 0, Data, s.VolumeOffset, 4); n++;
    }
    return n;
  }
}
