// Included by fh2wheels.c after menu.c. Different rims on the rear axle, chosen through a "Rear Rim Style" tile beside
// the game's Rim Style (which still fits all four) under Tires & Rims, and kept in the garage's unused TireBrand column
// (in the save, beside WheelStyle).
//
// Loading: an aftermarket rim is loaded by 1411B0FB0 (this = the car's wheel object, rdx = the rim's MediaName): it
// builds the rim's model and AO texture paths, "GAME:\Media\Cars\_library\scene\wheels\<name>\<name>_wheelLF.modelbin"
// and "...\<name>\Textures\AO\<name>_wheelLF_AO.swatchbin" (and _wheelRF, falling back to LF when the rim has no
// right-side files), into two lists of four, one entry per corner in the order LF, RF, RR, LR (left-side files for LF
// and LR, right-side ones for RF and RR), and hands both lists (its rbp+0x100 and rbp+0x80, std::strings 0x20 apart) to
// 1411B9DA0, which loads each corner from its own path. rims_stub runs just before (1411B1545) and points corners at
// other rims' files.
//
// The rear rim of a car: the car's looks are set up by 140F592D0 (r13 = the parts after the car Id: TireBrand at +0,
// WheelStyle at +4); seen_stub (140F599FF) notes TireBrand by WheelStyle (rear_of). Rim Ids and MediaNames come from the
// game database file (gamedb.c).
//
// Choosing: both tiles (PartEnum 43; the rear one is REAR_TYPE, made by make_gamedb.py) open the wheel shop, which is
// told only the PartEnum. A tile is opened by 140EBF960 (this = the type list screen, edx = the row clicked), which
// reads the row's PartEnum from the screen's result set ([this+0x420]+0xA0; vtable +0xA0: the int in a row's named
// column); click_stub, at its entry, reads the row's id the same way and notes whether it is REAR_TYPE. rims_sql notes
// when the shop opens (its WheelCategories list), taking that as the shop's mode, and closes (a type list).
// From the Rear Rim Style tile (rear mode):
//  - previews (the shop loads the highlighted rim as the car's rim): the front corners keep the front rim and the rear
//    ones show the highlighted rim;
//  - fitting: 1402CD090 (the change list of a part) stores a rim in the parts' TireBrand instead of WheelStyle
//    (change_stub at 1402CD0F2, only for a car in the garage: the part set's garage Id, at parts+0x274, is set) and
//    1402F6BC0 saves it to TireBrand instead of WheelStyle (column_stub at 1402F6DF2). The Stock tile (-1) clears it.
// A rear rim shows only with an aftermarket front rim: with the stock one the car draws its own wheels.

#define REAR_TYPE 64

typedef struct { union { char buf[16]; char *ptr; }; size_t size, cap; } GameString;   // the game's std::string
typedef GameString *(*GameStringAssign)(GameString *s, const char *text, size_t length);
typedef int (*GameFileExists)(void *files, GameString *path);
#define GAME_STRING_ASSIGN ((GameStringAssign)0x14022C300)
#define GAME_FREE ((void (*)(void *))0x14031C7B0)
#define GAME_FILES (*(void **)0x1436614F0)   // the file system object; vtable +0xE8: does a file exist
#define WHEELS_DIR "GAME:\\Media\\Cars\\_library\\scene\\wheels\\"

void *g_rimsBack = (void *)0x1411B154C, *g_seenBack = (void *)0x140F59A04;
void *g_rearChangeBack = (void *)0x1402CD0FB, *g_rearChangeDone = (void *)0x1402CD357, *g_rearColumnBack = (void *)0x1402F6E03;
void *g_tireBrandName = (void *)0x141E08F90, *g_wheelStyleName = (void *)0x141E08FA0;   // "TireBrand", "WheelStyle"
void *g_clickBack = (void *)0x140EBF965;
volatile int g_shopOpen, g_rearMode;   // the wheel shop is open; from the rear tile
static volatile int g_clickedRear, g_shopFrontId = -1, g_shopRear, g_shopRearSet;   // the tile last opened; the front rim; a rear fitted

static const char *game_string_text(const GameString *s) { return s->cap >= 16 ? s->ptr : s->buf; }
static void game_string_init(GameString *s) { memset(s, 0, sizeof *s); s->cap = 15; }
static void game_string_free(GameString *s) { if (s->cap >= 16) GAME_FREE(s->ptr); game_string_init(s); }
static void game_string_set(GameString *s, const char *text) { GAME_STRING_ASSIGN(s, text, strlen(text)); }

static int game_file_exists(const char *path) {
  GameString s; game_string_init(&s); game_string_set(&s, path);
  void *files = GAME_FILES;
  int ok = files && ((GameFileExists)(*(void ***)files)[0xE8 / 8])(files, &s);
  game_string_free(&s);
  return ok;
}

static CRITICAL_SECTION g_rimLock;

// A tile of the type list opened (see the top): note whether it is the Rear Rim Style one.
void __attribute__((used)) rims_click(BYTE *screen, int row) {
  BYTE *list = *(BYTE **)(screen + 0x420); void *result = list ? *(void **)(list + 0xA0) : NULL;
  if (!result) return;
  GameString col; game_string_init(&col); game_string_set(&col, "id");
  int id = ((int (*)(void *, int, GameString *, int))(*(void ***)result)[0xA0 / 8])(result, row, &col, 0);
  game_string_free(&col);
  g_clickedRear = id == REAR_TYPE;
  if (g_clickedRear) logf("wheel shop: rear rim style");
}

// TireBrand per car, as last set up, by its front rim (WheelStyle): the loader's car looks aren't the set-up ones (a
// copy), so a loaded rim finds its car's rear rim through the last car set up with that front rim. The game doesn't
// bring TireBrand back from the save into the parts (a restarted game sets cars up with -1), so the garage's rear rims
// are also read from the save at start (rims_seed) and kept until the game sets one or the shop fits one.
static struct { int front, rear, seeded; } g_rearOf[64];
static int g_rearOfNext;
static int rear_slot(int front) {   // under g_rimLock
  int i;
  for (i = 0; i < 64 && g_rearOf[i].front != front; i++) ;
  if (i == 64) { i = g_rearOfNext; g_rearOfNext = (g_rearOfNext + 1) % 64; g_rearOf[i].front = front; g_rearOf[i].rear = -1; g_rearOf[i].seeded = 0; }
  return i;
}
static void rear_set(int front, int rear, int seeded) {
  int i = rear_slot(front);
  g_rearOf[i].rear = rear; g_rearOf[i].seeded = seeded;
}
void __attribute__((used)) rims_seen(BYTE *looks, const int *parts) {
  (void)looks;
  if (parts[1] <= 0) return;
  EnterCriticalSection(&g_rimLock);
  int i = rear_slot(parts[1]);
  if (!(g_rearOf[i].seeded && parts[0] == -1)) rear_set(parts[1], parts[0], 0);   // not the game's -1 over the save's rim
  LeaveCriticalSection(&g_rimLock);
}
// From the save: a front rim's rear rim when every garage car with that front rim has the same one.
static struct { int front, rear; } g_saved[512];
static int g_savedCount;
static void rims_saved(int front, int rear) {
  if (front <= 0 || g_savedCount == 512) return;
  g_saved[g_savedCount].front = front; g_saved[g_savedCount].rear = rear; g_savedCount++;
}
static void rims_seed(void) {
  garage_read_save(g_dllDir, rims_saved);
  for (int i = 0; i < g_savedCount; i++) {
    int front = g_saved[i].front, rear = g_saved[i].rear, same = rear > 0, j;
    for (j = 0; j < g_savedCount && same; j++) if (g_saved[j].front == front && g_saved[j].rear != rear) same = 0;
    for (j = 0; j < i && same; j++) if (g_saved[j].front == front) same = 0;   // done already
    if (!same) continue;
    rear_set(front, rear, 1);
    logf("rims: saved rear rim %d (%s) on front rim %d (%s)", rear, rim_lookup(rear) ? rim_lookup(rear) : "?", front, rim_lookup(front) ? rim_lookup(front) : "?");
  }
}
static int rear_of(int front) {
  int rear = 0;
  EnterCriticalSection(&g_rimLock);
  for (int i = 0; i < 64; i++) if (front > 0 && g_rearOf[i].front == front) { rear = g_rearOf[i].rear; break; }
  LeaveCriticalSection(&g_rimLock);
  return rear;
}

// Points two corners (front: LF, RF; rear: RR, LR) at a rim's files; 0 when the rim has none.
static int set_corners(BYTE *frame, const char *rim, int rear) {
  char lf[256], rf[256], aoL[256], aoR[256];
  snprintf(lf, sizeof lf, WHEELS_DIR "%s\\%s_wheelLF.modelbin", rim, rim);
  snprintf(rf, sizeof rf, WHEELS_DIR "%s\\%s_wheelRF.modelbin", rim, rim);
  snprintf(aoL, sizeof aoL, WHEELS_DIR "%s\\Textures\\AO\\%s_wheelLF_AO.swatchbin", rim, rim);
  snprintf(aoR, sizeof aoR, WHEELS_DIR "%s\\Textures\\AO\\%s_wheelRF_AO.swatchbin", rim, rim);
  if (!game_file_exists(lf)) { logf("rim %s: %s not found", rim, lf); return 0; }
  if (!game_file_exists(rf)) strcpy(rf, lf);   // as the game does: right side from the left-side files
  if (!game_file_exists(aoL)) aoL[0] = 0;
  if (!game_file_exists(aoR)) strcpy(aoR, aoL);
  GameString *models = (GameString *)(frame + 0x100), *ao = (GameString *)(frame + 0x80);
  int left = rear ? 3 : 0, right = rear ? 2 : 1;
  game_string_set(&models[left], lf); game_string_set(&models[right], rf);
  game_string_set(&ao[left], aoL); game_string_set(&ao[right], aoR);
  return 1;
}

void __attribute__((used)) rims_on_load(BYTE *frame, const GameString *loading) {
  const char *name = game_string_text(loading), *front = rim_lookup(g_shopFrontId), *rear;
  if (g_rearMode && front && _stricmp(front, name)) {   // the shop previews a rear rim: the front keeps its own
    if (set_corners(frame, front, 0) && set_corners(frame, name, 1)) logf("rims: front %s, rear %s (preview)", front, name);
    return;
  }
  int rearId = g_shopOpen && g_shopRearSet ? g_shopRear : rear_of(rim_id_of(name));   // fitted in the open shop, or as set up
  rear = rim_lookup(rearId);
  if (!rear || !_stricmp(rear, name)) return;
  if (set_corners(frame, rear, 1)) logf("rims: front %s, rear %s", name, rear);
}

// Saves and restores what a call from the middle of game code may change; CALL_SAVED(call) makes the call.
#define CALL_SAVED(call) \
  "push %%rax\n\t push %%rcx\n\t push %%rdx\n\t push %%r8\n\t push %%r9\n\t push %%r10\n\t push %%r11\n\t" \
  "sub $0x88, %%rsp\n\t"                    /* entered at 0 mod 16: 7 pushes + 0x88 keep it; shadow space + xmm0-5 */ \
  "movups %%xmm0, 0x20(%%rsp)\n\t movups %%xmm1, 0x30(%%rsp)\n\t movups %%xmm2, 0x40(%%rsp)\n\t" \
  "movups %%xmm3, 0x50(%%rsp)\n\t movups %%xmm4, 0x60(%%rsp)\n\t movups %%xmm5, 0x70(%%rsp)\n\t" \
  call "\n\t" \
  "movups 0x20(%%rsp), %%xmm0\n\t movups 0x30(%%rsp), %%xmm1\n\t movups 0x40(%%rsp), %%xmm2\n\t" \
  "movups 0x50(%%rsp), %%xmm3\n\t movups 0x60(%%rsp), %%xmm4\n\t movups 0x70(%%rsp), %%xmm5\n\t" \
  "add $0x88, %%rsp\n\t" \
  "pop %%r11\n\t pop %%r10\n\t pop %%r9\n\t pop %%r8\n\t pop %%rdx\n\t pop %%rcx\n\t pop %%rax\n\t"

// Entered by a jmp from the loader (rbp its frame, rdi the rim's name).
__attribute__((naked, used)) static void rims_stub(void) {
  __asm__ volatile(
    CALL_SAVED("mov %%rbp, %%rcx\n\t mov %%rdi, %%rdx\n\t call rims_on_load")
    "movb $0, 0x190(%%rbx)\n\t"               // the replaced instruction
    "jmp *g_rimsBack(%%rip)\n\t" ::: "memory");
}

// Entered by a jmp from the looks setup (rsi the looks, r13 the parts); the cmp is for the jne that follows.
__attribute__((naked, used)) static void seen_stub(void) {
  __asm__ volatile(
    CALL_SAVED("mov %%rsi, %%rcx\n\t mov %%r13, %%rdx\n\t call rims_seen")
    "cmpl $-1, 4(%%r13)\n\t"                  // the replaced instruction
    "jmp *g_seenBack(%%rip)\n\t" ::: "memory");
}

void __attribute__((used)) rear_fitted(int rim, int front) {
  g_shopRear = rim; g_shopRearSet = 1;
  EnterCriticalSection(&g_rimLock);
  if (front > 0) rear_set(front, rim, 0);
  LeaveCriticalSection(&g_rimLock);
  logf("wheel shop: rear rim %d fitted (front rim %d)", rim, front);
}

// 1402CD090 for a rim (ebx = 43, edx = the rim, rsi = the parts after the car Id: TireBrand +0, WheelStyle +4).
__attribute__((naked, used)) static void change_stub(void) {
  __asm__ volatile(
    "cmpl $0, g_shopOpen(%%rip)\n\t je 1f\n\t"
    "cmpl $0, 0x274(%%rsi)\n\t je 1f\n\t"     // the part set's garage Id: 0 for the shop's preview copy
    "cmpl $0, g_rearMode(%%rip)\n\t je 1f\n\t"
    "mov %%edx, (%%rsi)\n\t"                  // rear mode, a garage car: the rim goes to TireBrand
    CALL_SAVED("mov %%edx, %%ecx\n\t mov 4(%%rsi), %%edx\n\t call rear_fitted")
    "jmp *g_rearChangeDone(%%rip)\n"
    "1:\n\t cmp %%edx, 4(%%rsi)\n\t je 2f\n\t"   // the replaced cmp [rsi+4], edx / je 1402CD357
    "jmp *g_rearChangeBack(%%rip)\n"
    "2:\n\t jmp *g_rearChangeDone(%%rip)\n\t" ::: "memory");
}

// Entered by a jmp from the entry of 140EBF960 (rcx the screen, edx the row): rsp is 8 mod 16 there, so 7 pushes and
// 0x80 (not CALL_SAVED's 0x88) align it for the call.
__attribute__((naked, used)) static void click_stub(void) {
  __asm__ volatile(
    "push %%rax\n\t push %%rcx\n\t push %%rdx\n\t push %%r8\n\t push %%r9\n\t push %%r10\n\t push %%r11\n\t"
    "sub $0x80, %%rsp\n\t"
    "movups %%xmm0, 0x20(%%rsp)\n\t movups %%xmm1, 0x30(%%rsp)\n\t movups %%xmm2, 0x40(%%rsp)\n\t"
    "movups %%xmm3, 0x50(%%rsp)\n\t movups %%xmm4, 0x60(%%rsp)\n\t movups %%xmm5, 0x70(%%rsp)\n\t"
    "call rims_click\n\t"
    "movups 0x20(%%rsp), %%xmm0\n\t movups 0x30(%%rsp), %%xmm1\n\t movups 0x40(%%rsp), %%xmm2\n\t"
    "movups 0x50(%%rsp), %%xmm3\n\t movups 0x60(%%rsp), %%xmm4\n\t movups 0x70(%%rsp), %%xmm5\n\t"
    "add $0x80, %%rsp\n\t"
    "pop %%r11\n\t pop %%r10\n\t pop %%r9\n\t pop %%r8\n\t pop %%rdx\n\t pop %%rcx\n\t pop %%rax\n\t"
    "mov %%rsp, %%rax\n\t push %%rbp\n\t push %%rdi\n\t"   // the replaced instructions
    "jmp *g_clickBack(%%rip)\n\t" ::: "memory");
}

// 1402F6BC0 saving a rim: the column name.
__attribute__((naked, used)) static void column_stub(void) {
  __asm__ volatile(
    "mov g_wheelStyleName(%%rip), %%r9\n\t"
    "cmpl $0, g_shopOpen(%%rip)\n\t je 1f\n\t"
    "cmpl $0, g_rearMode(%%rip)\n\t je 1f\n\t"
    "mov g_tireBrandName(%%rip), %%r9\n"
    "1:\n\t jmp *g_rearColumnBack(%%rip)\n\t" ::: "memory");
}

// The upgrade screens' queries (see the top). Returns rewritten SQL or NULL.
static char *rims_sql(const char *s, int n) {
  if (n < 0) n = (int)strlen(s);
  if (contains(s, n, "FROM WheelCategories") && !contains(s, n, "WheelAnnotations") && !contains(s, n, "WHERE 1=2")) {   // the shop opens
    if (!g_shopOpen) { g_rearMode = g_clickedRear; g_shopRearSet = 0; }
    g_shopOpen = 1;
    return NULL;
  }
  if (contains(s, n, "_View_UpgradeTypes AS UpgradeTypes WHERE UpgradeTypes.AreaId = ")) {   // a type list: the shop is closed
    g_shopOpen = 0; g_rearMode = 0; g_shopRearSet = 0;
    return NULL;
  }
  if (g_shopOpen && contains(s, n, "JOIN WheelCategories ON WheelCategories.Id = WheelAnnotations.CategoryId AND ")) {   // a category's rims
    const char *f = strstr(s, "WHEN PartTable.PartId = ");
    if (f) g_shopFrontId = atoi(f + 24);
    return NULL;
  }
  // the shop's header (the PartEnum's first type's name): the game's "Rim Style" for both tiles
  if (n < 160 && !memcmp(s, "SELECT Name FROM ", 17) && contains(s, n, "View_UpgradeTypes AS UpgradeTypes WHERE UpgradeTypes.PartEnum = 43")) {
    char *r = malloc(64); if (r) strcpy(r, "SELECT '_&4038008212' AS Name");
    return r;
  }
  return NULL;
}

static DWORD WINAPI rims_install(LPVOID p) {
  (void)p;
  rims_read_gamedb(g_dllDir);
  rims_seed();
  static const BYTE load[] = { 0xC6, 0x83, 0x90, 0x01, 0x00, 0x00, 0x00 };          // mov byte [rbx+0x190], 0
  static const BYTE seen[] = { 0x41, 0x83, 0x7D, 0x04, 0xFF };                      // cmp dword [r13+4], -1
  static const BYTE change[] = { 0x39, 0x56, 0x04, 0x0F, 0x84, 0x5C, 0x02, 0x00, 0x00 };   // cmp [rsi+4], edx / je 1402CD357
  static const BYTE column[] = { 0x4C, 0x8D, 0x0D, 0xA7, 0x21, 0xB1, 0x01 };        // lea r9, ["WheelStyle"]
  hook_jmp(GAME_BASE + (0x1411B1545 - 0x140000000ULL), load, sizeof load, (void *)rims_stub, "rim loader (rear rims)");
  hook_jmp(GAME_BASE + (0x140F599FF - 0x140000000ULL), seen, sizeof seen, (void *)seen_stub, "car looks (rear rim)");
  hook_jmp(GAME_BASE + (0x1402CD0F2 - 0x140000000ULL), change, sizeof change, (void *)change_stub, "part rules (rear rim)");
  hook_jmp(GAME_BASE + (0x1402F6DF2 - 0x140000000ULL), column, sizeof column, (void *)column_stub, "garage save (rear rim)");
  static const BYTE click[] = { 0x48, 0x8B, 0xC4, 0x55, 0x57 };                     // mov rax, rsp / push rbp / push rdi
  hook_jmp(GAME_BASE + (0x140EBF960 - 0x140000000ULL), click, sizeof click, (void *)click_stub, "upgrade types (rim style tile)");
  return 0;
}
