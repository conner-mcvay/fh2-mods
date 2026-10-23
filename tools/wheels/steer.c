// Included by fh2wheels.c after rims.c. A "Steering Angle" slider in the tuning menu's Alignment tab (under Front
// Caster): the car's steering lock, from STEER_MIN to STEER_MAX degrees.
//
// The tuning screen (Scenes/Anthem/A_TuningOptions.xaml in UI.zip; mods\fh2wheels adds the row) binds to a model
// object whose properties the game registers once, by 140E98E10, as nodes {descriptor, next} pushed onto the model
// class's list (14155EE30(0x143540E40, node)). Each slider property's descriptor (as CasterFront's, built by
// 140EA5020: base init 14143EB80, getter at +0x28, name +0x40, type +0x48 = the slider type 0x143540950, vtable
// 0x142C6F1E8) has a getter (rcx = out, r8 = the model) that returns a slider object, reference-counted at +0x10.
// register_stub (at 140E98E10's epilogue, 140E9967B) pushes a "SteerAngle" node the same way.
//
// Slider objects: made by 140E74490 (out, &id, &flag, &flag; id 0x15 = caster's, which also picks the text format:
// radians shown as degrees), subscribed to the model's change callback (a functor made by 140E70080 around
// 140E93100, given to the slider's +0x68 interface, method 0) as the model's constructor does, and bound by
// 140E9A620 (slider, &normalized value, read-only, min, max, small step, large step; the value is a 0-1 float the
// slider writes as it moves, and 140EA1370 remakes its text). One slider per model (a tuning screen session).
// bind_stub runs at the end of the Alignment tab's bind (140E9AD30, epilogue 140E9AF02: rsi = the model, dil = read
// only), binds ours to the car's angle and tells the screen (140E92AF0(model, descriptor)).
//
// The car: the bind's second argument (rbx at its end) is the car's setup, which starts (+0x18) with its parts' Ids;
// most belong to the car (car Id * 1000 + level; an engine swap's are the engine's), so the car Id is the one most
// of them carry. Angles are kept per car model, in
// data\bin\fh2wheels-steering.ini ([steering] <car Id>=<degrees>), written as the screen binds again after Apply and
// when the game saves the car's tuning ("UPDATE ...Career_Garage SET Tuning_...", seen by steer_sql). Two garage cars
// of one model share an angle. The save itself is left alone.
//
// Applying: the car build (141056210) loads the steering data through 141061070 and 1410622C0, which stores
// SteerMaxAngle at [rbx] and SteerMaxAngleFiltered (the assisted lock) at [rbx+4] (141062688-14106268F);
// loaded_stub runs right after and puts the tuned angle in both for a tuned car (g_buildCar, from slots_stub).

#define STEER_MIN 20.0f
#define STEER_MAX 75.0f
#define STEER_STEP 0.5f
#define DEG2RAD 0.017453292f

#define MAKE_SLIDER ((void **(*)(void **, int *, BYTE *, BYTE *))0x140E74490)
#define SLIDER_BIND ((void (*)(void *, float *, char, float, float, float, float))0x140E9A620)
#define MODEL_CHANGED ((void (*)(void *, void *))0x140E92AF0)
#define DESC_INIT ((void (*)(void *))0x14143EB80)
#define CLASS_ADD ((void (*)(void *, void *))0x14155EE30)
#define MAKE_FUNCTOR ((void **(*)(void **, void *, void *))0x140E70080)
#define GAME_RELEASE ((void (*)(void *))0x140257730)
#define MODEL_CLASS ((void *)0x143540E40)

void *g_bindBack = (void *)0x140E9AF0E, *g_loadedBack = (void *)0x14106268F;

static __attribute__((aligned(16))) BYTE g_steerDesc[0x80];
static struct { void *desc, *next; } g_steerNode;
static int g_steerRegistered;

static struct { BYTE *model, *slider; float norm; int car; } g_steerModels[16];
static int g_lastSlot = -1;   // the model slot last bound
static int g_steerModelNext;
static struct { int car; float deg; } g_steerTuned[512];
static int g_steerTunedCount;
static struct { int car; float max; } g_steerStock[64];
static int g_steerStockNext;
static CRITICAL_SECTION g_steerLock;
static char g_steerIni[MAX_PATH];

static void release_obj(BYTE *o) { if (o && InterlockedDecrement((volatile LONG *)(o + 0x10)) == 0) GAME_RELEASE(o); }

static float steer_stock(int car) {   // under g_steerLock; SteerMaxAngle as last loaded, else the usual 42
  for (int i = 0; i < 64; i++) if (g_steerStock[i].car == car && car) return g_steerStock[i].max;
  return 42.0f;
}
static int steer_tuned(int car, float *deg) {   // under g_steerLock
  for (int i = 0; i < g_steerTunedCount; i++) if (g_steerTuned[i].car == car) { *deg = g_steerTuned[i].deg; return 1; }
  return 0;
}
static void steer_write_ini(void);
static void steer_set(int car, float deg) {   // under g_steerLock; stock (or near it) removes the entry
  float stock = steer_stock(car);
  deg = (float)(int)(deg / STEER_STEP + 0.5f) * STEER_STEP;
  int i;
  for (i = 0; i < g_steerTunedCount && g_steerTuned[i].car != car; i++) ;
  int had = i < g_steerTunedCount;
  if (deg > stock - 0.25f && deg < stock + 0.25f) {
    if (!had) return;
    g_steerTuned[i] = g_steerTuned[--g_steerTunedCount];
    logf("steering: car %d back to stock %.1f deg", car, stock);
  } else {
    if (had && g_steerTuned[i].deg == deg) return;
    if (!had && i == 512) return;
    if (!had) g_steerTunedCount++;
    g_steerTuned[i].car = car; g_steerTuned[i].deg = deg;
    logf("steering: car %d set to %.1f deg", car, deg);
  }
  steer_write_ini();
}

// The model's slider (made and subscribed the first time).
static BYTE *steer_slider(BYTE *model, int *slot) {
  for (int i = 0; i < 16; i++) if (g_steerModels[i].model == model && g_steerModels[i].slider) { if (slot) *slot = i; return g_steerModels[i].slider; }
  int id = 0x15; BYTE flagA = 1, flagB = 1; void *s = NULL;
  MAKE_SLIDER(&s, &id, &flagA, &flagB);
  if (!s) return NULL;
  struct { void *fn; LONG_PTR adj; } __attribute__((aligned(16))) memfn = { (void *)0x140E93100, 0 };   // model->140E93100
  void *cb = NULL;
  MAKE_FUNCTOR(&cb, model, &memfn);
  if (cb) {
    BYTE *iface = (BYTE *)s + 0x68;
    ((void (*)(void *, void *))(*(void ***)iface)[0])(iface, cb);
    release_obj(cb);
  }
  int i = g_steerModelNext; g_steerModelNext = (g_steerModelNext + 1) % 16;
  g_steerModels[i].model = model; g_steerModels[i].slider = s; g_steerModels[i].norm = 0.5f; g_steerModels[i].car = 0;
  if (slot) *slot = i;
  logf("steering: slider %p for tuning model %p", s, model);
  return s;
}

// The property's getter (rcx = out, r8 = the model): the model's slider, with a reference for the caller.
static void **steer_get(void **out, void *unused, BYTE *model) {
  (void)unused;
  EnterCriticalSection(&g_steerLock);
  BYTE *s = steer_slider(model, NULL);
  LeaveCriticalSection(&g_steerLock);
  *out = s;
  if (s) InterlockedIncrement((volatile LONG *)(s + 0x10));
  return out;
}

void __attribute__((used)) steer_register(void) {
  if (g_steerRegistered) return;
  g_steerRegistered = 1;
  DESC_INIT(g_steerDesc);
  *(void **)(g_steerDesc + 0x28) = (void *)steer_get;
  *(void **)(g_steerDesc + 0x30) = NULL;
  *(void **)(g_steerDesc + 0x38) = NULL;
  *(const char **)(g_steerDesc + 0x40) = "SteerAngle";
  *(void **)(g_steerDesc + 0x48) = (void *)0x143540950;   // the slider type
  g_steerDesc[0x50] &= 0xF0;
  *(void **)g_steerDesc = (void *)0x142C6F1E8;
  g_steerNode.desc = g_steerDesc;
  CLASS_ADD(MODEL_CLASS, &g_steerNode);
  logf("steering: Tuning.SteerAngle registered");
}

void __attribute__((used)) steer_bind(BYTE *model, int readOnly, const BYTE *setup) {
  if (!g_steerRegistered) return;
  int part = 0;
  SIZE_T got = 0;
  int ids[0x28] = {0}, car = 0, best = 0;   // the part Ids at +0x18..+0xB8; the car Id most of them carry
  if (setup && ReadProcessMemory(GetCurrentProcess(), setup + 0x18, ids, sizeof ids, &got)) {
    for (int i = 0; i < 0x28; i++) {
      if (ids[i] < 1000 || ids[i] >= 100000000) continue;
      int c = ids[i] / 1000, k = 0;
      for (int j = 0; j < 0x28; j++) if (ids[j] >= 1000 && ids[j] < 100000000 && ids[j] / 1000 == c) k++;
      if (k > best) { best = k; car = c; part = ids[i]; }
    }
  }
  if (best < 4) {
    logf("steering: no car Id in the car setup (%p: %d parts agree); slider left out", setup, best);
    return;
  }
  EnterCriticalSection(&g_steerLock);
  int slot = 0;
  BYTE *s = steer_slider(model, &slot);
  float stock = steer_stock(car), deg = stock;
  if (g_steerModels[slot].car == car)   // bound again on this screen (after Apply): the slider's value is the setting
    steer_set(car, STEER_MIN + (STEER_MAX - STEER_MIN) * g_steerModels[slot].norm);
  int tuned = steer_tuned(car, &deg);
  if (deg < STEER_MIN) deg = STEER_MIN;
  if (deg > STEER_MAX) deg = STEER_MAX;
  g_steerModels[slot].norm = (deg - STEER_MIN) / (STEER_MAX - STEER_MIN);
  g_steerModels[slot].car = car;
  g_lastSlot = slot;
  LeaveCriticalSection(&g_steerLock);
  if (!s) return;
  SLIDER_BIND(s, &g_steerModels[slot].norm, (char)(readOnly & 1), STEER_MIN * DEG2RAD, STEER_MAX * DEG2RAD, STEER_STEP * DEG2RAD, -1.0f);
  MODEL_CHANGED(model, g_steerDesc);
  logf("steering: car %d (part %d): %.1f deg (%s, stock %.1f)%s", car, part, deg, tuned ? "tuned" : "stock", stock, readOnly & 1 ? ", read only" : "");
}

static void steer_write_ini(void) {   // under g_steerLock
  WritePrivateProfileStringA("steering", NULL, NULL, g_steerIni);   // the section, cleared
  char key[16], val[48];
  for (int i = 0; i < g_steerTunedCount; i++) {
    snprintf(key, sizeof key, "%d", g_steerTuned[i].car);
    snprintf(val, sizeof val, "%.1f", g_steerTuned[i].deg);
    WritePrivateProfileStringA("steering", key, val, g_steerIni);
  }
}

// The game saving a garage car's tuning: keep the angle of the slider last bound.
static void steer_sql(const char *s, int n) {
  if (n < 0) n = (int)strlen(s);
  if (!contains(s, n, "Career_Garage SET Tuning_")) return;
  EnterCriticalSection(&g_steerLock);
  int slot = g_lastSlot;
  if (slot >= 0 && g_steerModels[slot].slider && g_steerModels[slot].car)
    steer_set(g_steerModels[slot].car, STEER_MIN + (STEER_MAX - STEER_MIN) * g_steerModels[slot].norm);
  LeaveCriticalSection(&g_steerLock);
}

static void steer_loaded_impl(float *steer);
void __attribute__((used)) steer_loaded(float *steer) { PROF_BEGIN; steer_loaded_impl(steer); PROF_END(P_STEER_LOAD); }
static void steer_loaded_impl(float *steer) {
  int car = g_buildCar;
  EnterCriticalSection(&g_steerLock);
  int i;
  for (i = 0; i < 64 && g_steerStock[i].car != car; i++) ;
  if (i == 64) { i = g_steerStockNext; g_steerStockNext = (g_steerStockNext + 1) % 64; g_steerStock[i].car = car; }
  g_steerStock[i].max = steer[0];
  float deg;
  int tuned = car && steer_tuned(car, &deg);
  LeaveCriticalSection(&g_steerLock);
  static int seen; if (seen < 3 || tuned) { seen++; logf("car %d steering data: lock %.1f, assisted %.1f%s", car, steer[0], steer[1], tuned ? "" : " (not tuned)"); }
  if (!tuned) return;
  logf("car %d steering lock %.1f / %.1f -> %.1f deg", car, steer[0], steer[1], deg);
  steer[0] = steer[1] = deg;
}

// At 140E98E10's epilogue (add rsp, 0xD0 / pop rbx / ret); rsp is 0 mod 16 there.
__attribute__((naked, used)) static void register_stub(void) {
  __asm__ volatile(
    CALL_SAVED("call steer_register")
    "add $0xD0, %%rsp\n\t pop %%rbx\n\t ret\n\t" ::: "memory");
}

// At 140E9AF02 (lea r11, [rsp+0x80] / mov rbx, [r11+0x10]): rsi = the model, dil = read only, rbx = the car's
// setup (the bind's second argument, restored only by the replaced instructions); rsp 0 mod 16.
__attribute__((naked, used)) static void bind_stub(void) {
  __asm__ volatile(
    CALL_SAVED("mov %%rsi, %%rcx\n\t movzx %%dil, %%edx\n\t mov %%rbx, %%r8\n\t call steer_bind")
    "lea 0x80(%%rsp), %%r11\n\t mov 0x10(%%r11), %%rbx\n\t"
    "jmp *g_bindBack(%%rip)\n\t" ::: "memory");
}

// At 14106268A (vmovss [rbx+4], xmm0): rbx = the steering data; rsp 0 mod 16 (5 pushes, sub 0x50).
__attribute__((naked, used)) static void loaded_stub(void) {
  __asm__ volatile(
    "vmovss %%xmm0, 4(%%rbx)\n\t"   // the replaced instruction
    CALL_SAVED("mov %%rbx, %%rcx\n\t call steer_loaded")
    "jmp *g_loadedBack(%%rip)\n\t" ::: "memory");
}

static void steer_read_ini(void) {
  char buf[16384];
  DWORD n = GetPrivateProfileSectionA("steering", buf, sizeof buf, g_steerIni);
  for (char *p = buf; p < buf + n && *p; p += strlen(p) + 1) {
    int car = 0; float deg = 0;
    if (sscanf(p, "%d=%f", &car, &deg) == 2 && car > 0 && !strchr(p, ',') && g_steerTunedCount < 512) {
      g_steerTuned[g_steerTunedCount].car = car; g_steerTuned[g_steerTunedCount].deg = deg;
      g_steerTunedCount++;
    }
  }
  if (g_steerTunedCount) logf("steering: %d tuned cars in %s", g_steerTunedCount, g_steerIni);
}

static DWORD WINAPI steer_install(LPVOID p) {
  (void)p;
  snprintf(g_steerIni, sizeof g_steerIni, "%lsfh2wheels-steering.ini", g_dllDir);
  steer_read_ini();
  static const BYTE registerOrig[] = { 0x48, 0x81, 0xC4, 0xD0, 0x00, 0x00, 0x00, 0x5B, 0xC3 };   // add rsp, 0xD0 / pop rbx / ret
  static const BYTE bindOrig[] = { 0x4C, 0x8D, 0x9C, 0x24, 0x80, 0x00, 0x00, 0x00, 0x49, 0x8B, 0x5B, 0x10 };
  static const BYTE loadedOrig[] = { 0xC5, 0xFA, 0x11, 0x43, 0x04 };   // vmovss [rbx+4], xmm0
  hook_jmp(GAME_BASE + (0x140E9967B - 0x140000000ULL), registerOrig, sizeof registerOrig, (void *)register_stub, "tuning properties (steering)");
  hook_jmp(GAME_BASE + (0x140E9AF02 - 0x140000000ULL), bindOrig, sizeof bindOrig, (void *)bind_stub, "alignment bind (steering)");
  hook_jmp(GAME_BASE + (0x14106268A - 0x140000000ULL), loadedOrig, sizeof loadedOrig, (void *)loaded_stub, "steering data (steering)");
  return 0;
}
