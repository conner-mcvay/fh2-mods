// Included by sql.c (wheels.c uses it too, and is included after). Wheel offsets and tire profiles as upgrade parts
// under Tires & Rims.
//
// The game has a fixed set of part slots (PartEnum 0-44, one Career_Garage column each), so these borrow four slots
// no ordinary car uses: Restrictor Plate (22; 19 rows, 7 engines) and Motor Parts (42; the one electric car) for the
// front and rear offsets, Quad Turbo (26; no rows) and Motor (3; the electric car's own) for the front and rear
// profiles. Our parts are told apart from real ones by IsException = 1:
//  - gamedb (mods\fh2wheels, made by make_gamedb.py): UpgradeTypes rows for the categories (AreaId 4,
//    IsException 1), Upgrades rows naming each option level, and the part rows (no engine / car / motor, neutral
//    values), which the game looks up when a part is bought or fitted. (Answering those lookups by rewriting them to
//    a subquery crashed the game: its query wrapper needs a plain table name.)
//  - here: the parts, added to the per-car View_UpgradeParts the game creates when a car is loaded (the part lists
//    and the categories with anything to offer are queries on it), and the front/rear marks of the Tires & Rims
//    category list.
// A fitted option's PartId encodes its value (KIND_PART), so the car build only has to read the slots (wheels.c),
// which it keeps the game itself from loading.

#define KIND_PART(base, v) ((base) + 1000 + (v))
#define OFFSET_PRICE 500
#define PROFILE_PRICE 600

typedef struct {
  int part, base, price;
  const int *values; int count;   // index = Level; values[0] = 0 is the stock option
} Kind;

static const int g_offsetMm[] = { 0, -20, -15, -10, -5, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 75, 100, 150 };   // mm a side
static const int g_profileDelta[] = { 0, -30, -25, -20, -15, -10, -5, 5, 10, 15, 20, 25, 30, 35 };   // aspect points
#define COUNT(a) ((int)(sizeof a / sizeof *a))

enum { FRONT_OFFSET, REAR_OFFSET, FRONT_PROFILE, REAR_PROFILE, KINDS };
static const Kind g_kinds[KINDS] = {
  { 22, 91000000, OFFSET_PRICE, g_offsetMm, COUNT(g_offsetMm) },
  { 42, 92000000, OFFSET_PRICE, g_offsetMm, COUNT(g_offsetMm) },
  { 26, 93000000, PROFILE_PRICE, g_profileDelta, COUNT(g_profileDelta) },
  { 3, 94000000, PROFILE_PRICE, g_profileDelta, COUNT(g_profileDelta) },
};

// The value a slot's PartId stands for, or 0 when it isn't one of ours or no longer an option (a part fitted from an
// earlier option list stays harmless).
static int kind_value(int part, int kind) {
  const Kind *K = &g_kinds[kind];
  if (part < K->base || part >= K->base + 2000) return 0;
  for (int i = 0; i < K->count; i++) if (K->values[i] == part - K->base - 1000) return K->values[i];
  return 0;
}

// "CREATE VIEW <profile>View_UpgradeParts AS SELECT ... WHERE Ordinal = <car> UNION ..." + our rows.
static char *menu_parts_view(const char *s, int n) {
  const char *o = strstr(s, "WHERE Ordinal = ");
  int ordinal = o ? atoi(o + 16) : 0;
  size_t cap = n + 64 * KINDS * 128 + 1;
  char *out = malloc(cap);
  if (!out) return NULL;
  memcpy(out, s, n); size_t len = n;
  for (int k = 0; k < KINDS; k++) {
    const Kind *K = &g_kinds[k];
    for (int lv = 0; lv < K->count; lv++)
      len += snprintf(out + len, cap - len, " UNION SELECT %d, %d, %d, %d, %d, 0, %d, 1", K->part,
                      KIND_PART(K->base, K->values[lv]), ordinal, lv == 0, lv, lv == 0 ? 0 : K->price);
  }
  out[len] = 0;
  return out;
}

// Replaces the first `from` in s (length n) by `to`; NULL when there is none.
static char *replace_once(const char *s, int n, const char *from, const char *to) {
  const char *at = NULL; size_t k = strlen(from), t = strlen(to);
  for (int i = 0; i + (int)k <= n; i++) if (!memcmp(s + i, from, k)) { at = s + i; break; }
  if (!at) return NULL;
  char *out = malloc(n - k + t + 1);
  if (!out) return NULL;
  size_t a = at - s;
  memcpy(out, s, a); memcpy(out + a, to, t); memcpy(out + a + t, at + k, n - a - k); out[n - k + t] = 0;
  return out;
}

// Returns rewritten SQL (malloc'd, never freed: see sql_on_prepare) or NULL to leave the statement alone.
static char *menu_rewrite(const char *s, int n) {
  if (n < 0) n = (int)strlen(s);
  if (n > 40 && !memcmp(s, "CREATE VIEW ", 12) && contains(s, n, "View_UpgradeParts AS SELECT")) return menu_parts_view(s, n);
  if (contains(s, n, "AS FrontRearIndicator FROM") && contains(s, n, "AreaId = 4")) {
    // (and the Rear Rim Style tile, rims.c's REAR_TYPE)
    char *a = replace_once(s, n, "WHEN PartEnum = 6 OR PartEnum = 38 OR PartEnum = 10",
                           "WHEN PartEnum = 6 OR PartEnum = 38 OR PartEnum = 10 OR PartEnum = 22 OR PartEnum = 26");
    if (!a) return NULL;
    char *b = replace_once(a, (int)strlen(a), "WHEN PartEnum = 7 OR PartEnum = 39 OR PartEnum = 11",
                           "WHEN PartEnum = 7 OR PartEnum = 39 OR PartEnum = 11 OR PartEnum = 42 OR PartEnum = 3 OR id = 64");
    if (b) { free(a); return b; }
    return a;
  }
  return NULL;
}

// The part-select screen, for our categories:
//  - camera: 140ED04C0 (this, AreaId, PartEnum) picks the preset ("Upgrades_" + name); under Tires & Rims (4) it
//    knows 8, 10/38 (WheelStyle_Front) and 11/39 (WheelStyle_Rear). Our front parts are passed on as 10, the rear
//    ones as 11.
//  - performance graph: 140EC3FB5 stores IsPerformanceGraphVisible (+0x4EA), on for engine-group parts such as the
//    restrictor plate and the quad turbo; it is cleared when the screen's PartEnum (+0x464) is one of ours (only
//    under Tires & Rims could it be: the real parts of these slots belong to no car we show them for).
void *g_cameraBack = (void *)0x140ED04C6, *g_graphBack = (void *)0x140EC3FBC;

__attribute__((naked, used)) static void camera_stub(void) {
  __asm__ volatile(
    "cmp $4, %%edx\n\t jne 1f\n\t"
    "cmp $22, %%r8d\n\t je 3f\n\t cmp $26, %%r8d\n\t je 3f\n\t"
    "cmp $42, %%r8d\n\t je 2f\n\t cmp $3, %%r8d\n\t jne 1f\n"
    "2:\n\t mov $11, %%r8d\n\t jmp 1f\n"
    "3:\n\t mov $10, %%r8d\n"
    "1:\n\t mov %%rsp, %%rax\n\t push %%rbp\n\t push %%r14\n\t"   // the replaced instructions
    "jmp *g_cameraBack(%%rip)\n\t" ::: "memory");
}

__attribute__((naked, used)) static void graph_stub(void) {
  __asm__ volatile(
    "cmpl $22, 0x464(%%rsi)\n\t je 1f\n\t cmpl $42, 0x464(%%rsi)\n\t je 1f\n\t"
    "cmpl $26, 0x464(%%rsi)\n\t je 1f\n\t cmpl $3, 0x464(%%rsi)\n\t jne 2f\n"
    "1:\n\t xor %%r12b, %%r12b\n"
    "2:\n\t mov %%r12b, 0x4ea(%%rsi)\n\t"                       // the replaced instruction
    "jmp *g_graphBack(%%rip)\n\t" ::: "memory");
}

// Fitting a part (and previewing one) goes through 1402F6BC0 (this = the car's part set, PartEnum, PartId), which
// first has 1402CD090 work out every change the part brings (a list of {value, ?, PartEnum, PartId}), then applies
// them. Two of the slots we borrow carry rules of their own there:
//  - Motor (3) is a conversion: 1402CD090 resets the motor parts (42: the rear offset) for the new motor, and
//    1402F6BC0 takes the new MotorID (ours: -1) and applies the conversion.
//  - Quad Turbo (26) is forced induction: 1402CD090 empties the other forced-induction slots (a real turbo or
//    supercharger) and may drop the intercooler, and 1402F6BC0 then runs 1402FC2B0 on it.
// For our parts: rules_change_stub (1402CD26C, right after 1402CD090 records the part in its copy) goes straight to
// adding the change; rules_conversion_stub (1402F6DA6) sends our Motor part down the ordinary-part path, which saves
// it like any upgrade; rules_induction_stub (1402F6DC7) skips 1402FC2B0 for our Quad Turbo part.
void *g_ruleChangeBack = (void *)0x1402CD272, *g_ruleChangeAdd = (void *)0x1402CD41C;
void *g_ruleConversion = (void *)0x1402F6DAB, *g_ruleOrdinary = (void *)0x1402F6DC7;
void *g_ruleInductionBack = (void *)0x1402F6DCC, *g_ruleInductionSkip = (void *)0x1402F6DDE;

__attribute__((naked, used)) static void rules_change_stub(void) {   // ebx = PartEnum, edx = PartId
  __asm__ volatile(
    "mov %%edx, 8(%%rsi,%%rbx,4)\n\t"                         // the replaced store
    "push %%rax\n\t"
    "cmp $3, %%ebx\n\t jne 1f\n\t mov %%edx, %%eax\n\t sub $94000000, %%eax\n\t cmp $2000, %%eax\n\t jb 2f\n"
    "1:\n\t cmp $26, %%ebx\n\t jne 3f\n\t mov %%edx, %%eax\n\t sub $93000000, %%eax\n\t cmp $2000, %%eax\n\t jb 2f\n"
    "3:\n\t pop %%rax\n\t test %%ecx, %%ecx\n\t"               // the replaced test, for the jne that follows
    "jmp *g_ruleChangeBack(%%rip)\n"
    "2:\n\t pop %%rax\n\t jmp *g_ruleChangeAdd(%%rip)\n\t" ::: "memory");
}

__attribute__((naked, used)) static void rules_conversion_stub(void) {   // ecx = PartEnum, [rdi+4] = PartId
  __asm__ volatile(
    "cmp $3, %%ecx\n\t jne 1f\n\t"
    "push %%rax\n\t mov 4(%%rdi), %%eax\n\t sub $94000000, %%eax\n\t cmp $2000, %%eax\n\t pop %%rax\n\t jb 1f\n\t"
    "jmp *g_ruleConversion(%%rip)\n"
    "1:\n\t jmp *g_ruleOrdinary(%%rip)\n\t" ::: "memory");
}

__attribute__((naked, used)) static void rules_induction_stub(void) {   // ecx = PartEnum, [rdi+4] = PartId
  __asm__ volatile(
    "cmp $26, %%ecx\n\t jne 1f\n\t"
    "push %%rax\n\t mov 4(%%rdi), %%eax\n\t sub $93000000, %%eax\n\t cmp $2000, %%eax\n\t pop %%rax\n\t jb 2f\n"
    "1:\n\t movabs $0x1410592D0, %%rax\n\t call *%%rax\n\t"   // the replaced call
    "jmp *g_ruleInductionBack(%%rip)\n"
    "2:\n\t jmp *g_ruleInductionSkip(%%rip)\n\t" ::: "memory");
}

static DWORD WINAPI menu_install(LPVOID p) {
  (void)p;
  static const BYTE change[] = { 0x89, 0x54, 0x9E, 0x08, 0x85, 0xC9 };       // mov [rsi+rbx*4+8], edx / test ecx, ecx
  static const BYTE conversion[] = { 0x83, 0xF9, 0x03, 0x75, 0x1C };         // cmp ecx, 3 / jne 1402F6DC7
  static const BYTE induction[] = { 0xE8, 0x04, 0x25, 0xD6, 0x00 };          // call 1410592D0
  hook_jmp(GAME_BASE + (0x1402CD26C - 0x140000000ULL), change, sizeof change, (void *)rules_change_stub, "part rules (changes)");
  hook_jmp(GAME_BASE + (0x1402F6DA6 - 0x140000000ULL), conversion, sizeof conversion, (void *)rules_conversion_stub, "part rules (conversion)");
  hook_jmp(GAME_BASE + (0x1402F6DC7 - 0x140000000ULL), induction, sizeof induction, (void *)rules_induction_stub, "part rules (forced induction)");
  static const BYTE cam[] = { 0x48, 0x8B, 0xC4, 0x55, 0x41, 0x56 };          // mov rax, rsp / push rbp / push r14
  static const BYTE graph[] = { 0x44, 0x88, 0xA6, 0xEA, 0x04, 0x00, 0x00 };  // mov [rsi+0x4ea], r12b
  hook_jmp(GAME_BASE + (0x140ED04C0 - 0x140000000ULL), cam, sizeof cam, (void *)camera_stub, "upgrade camera");
  hook_jmp(GAME_BASE + (0x140EC3FB5 - 0x140000000ULL), graph, sizeof graph, (void *)graph_stub, "performance graph");
  return 0;
}
