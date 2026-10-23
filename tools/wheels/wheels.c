// Included by fh2wheels.c. Applies the fitted offset and profile parts (menu.c) when the game builds a car, plus
// per-model offsets from fh2wheels.ini, added to the parts':
//   [offsets]
//   2155=40,20          <Data_Car Id>=<front mm>,<rear mm>: how far each wheel moves out, per side (negative: in)
// The lines are read again on every car build, so the file can be edited with the game running (re-enter the garage).
//
// The car build (141056210: rcx car, rdx, r8 parts, r9 the car's model data; rbp = entry rsp - 0xDA8, rsp = rbp -
// 0x100):
//  - its parts argument (kept in its home slot at rbp+0xDC0) is the car Id, two other ints, then one PartId per
//    PartEnum 0-42 (+0xC). The build works on a copy at rbp+0x920 (PartEnum 0 at +0x928), made at 141056770 or by
//    14104D5F0, both going on at 1410567F3, where the forced-induction slots are reduced to one and then (141056884)
//    every part is loaded. Our parts must not get that far (their rows belong to no engine or car: the engine code
//    crashed on a restrictor plate it couldn't match, and a quad turbo would push out the real turbo), so slots_stub
//    empties our four slots in the copy right there. Our values are read from the argument, which stays as it was.
//  - the tire fitter (141058A20, called from the build at 141057DA1) keeps each tire's stock overall diameter and
//    works out the aspect for the fitted width and rim, then stores width, aspect and rim (1412E3240) for the front
//    (141058F32) and the rear (141059113). tire_stub adds the fitted profile part's aspect points just before. The
//    fitter's frame is fixed (7 pushes, sub rsp 0x150, nothing pushed in its body), so the build's rbp is the
//    fitter's rsp + 0x150 + 0x38 + 8 (return address) + 0x100 = rsp + 0x290.
//  - at 14105863D it stores ModelRearTrackOuter (+0xF8), right after ModelFrontTrackOuter (+0xF4), in the model
//    data; wheels_stub adds the offsets there (twice the per-side value: the columns are full track widths). The
//    car Id is at [rsp+0x60] and the Data_CarBody Id at [rsp+0x68] (written at 141056272 and 141056CD6).

void *g_wheelsBack = (void *)0x141058645, *g_slotsBack = (void *)0x1410567FB;
void *g_tireFrontBack = (void *)0x141058F32, *g_tireRearBack = (void *)0x141059113;

static const int *build_parts(BYTE *frame) { return (const int *)(*(BYTE **)(frame + 0xDC0) + 0xC); }

__attribute__((naked, used)) static void slots_stub(void) {
  __asm__ volatile(
    "push %%rax\n\t"
    "mov 0xdc0(%%rbp), %%rax\n\t mov (%%rax), %%eax\n\t mov %%eax, g_buildCar(%%rip)\n\t"   // the car Id, for steer.c
    "mov 0x980(%%rbp), %%eax\n\t sub $91000000, %%eax\n\t cmp $2000, %%eax\n\t jae 1f\n\t movl $-1, 0x980(%%rbp)\n"   // 22: front offset
    "1:\n\t mov 0x9d0(%%rbp), %%eax\n\t sub $92000000, %%eax\n\t cmp $2000, %%eax\n\t jae 2f\n\t movl $-1, 0x9d0(%%rbp)\n"  // 42: rear offset
    "2:\n\t mov 0x990(%%rbp), %%eax\n\t sub $93000000, %%eax\n\t cmp $2000, %%eax\n\t jae 3f\n\t movl $-1, 0x990(%%rbp)\n"  // 26: front profile
    "3:\n\t mov 0x934(%%rbp), %%eax\n\t sub $94000000, %%eax\n\t cmp $2000, %%eax\n\t jae 4f\n\t movl $-1, 0x934(%%rbp)\n"  // 3: rear profile
    "4:\n\t movabs $0x141E18B10, %%rax\n\t vmovdqa (%%rax), %%xmm0\n\t"   // the replaced vmovdqa xmm0, [rip+0xdc2315]
    "pop %%rax\n\t"
    "jmp *g_slotsBack(%%rip)\n\t" ::: "memory");
}

static float tire_aspect_impl(BYTE *frame, int rear, float aspect);
float __attribute__((used)) tire_aspect(BYTE *frame, int rear, float aspect) { PROF_BEGIN; float r = tire_aspect_impl(frame, rear, aspect); PROF_END(P_TIRE); return r; }
static float tire_aspect_impl(BYTE *frame, int rear, float aspect) {
  const BYTE *args = *(BYTE **)(frame + 0xDC0);
  if (!args || *(const int *)args != *(const int *)(frame - 0x100 + 0x60)) {   // the car Id twice: is this the build's frame?
    static LONG once; if (!InterlockedExchange(&once, 1)) logf("tire fitter: build frame not where expected; profiles off");
    return aspect;
  }
  int d = kind_value(build_parts(frame)[g_kinds[rear ? REAR_PROFILE : FRONT_PROFILE].part], rear ? REAR_PROFILE : FRONT_PROFILE);
  if (!d) return aspect;
  float a = aspect + d;
  if (a < 10) a = 10;
  logf("car %d %s tire aspect %.1f -> %.1f", *(const int *)args, rear ? "rear" : "front", aspect, a);
  return a;
}

// Entered by a jmp from the tire fitter, xmm2 = the aspect about to be stored. TIRE_STUB(name, rear, lea, back).
#define TIRE_STUB(name, rear, lea, back) \
  __attribute__((naked, used)) static void name(void) { \
    __asm__ volatile( \
      "push %%rax\n\t push %%rcx\n\t push %%rdx\n\t push %%r8\n\t push %%r9\n\t push %%r10\n\t push %%r11\n\t" \
      "sub $0x88, %%rsp\n\t" \
      "movups %%xmm0, 0x20(%%rsp)\n\t movups %%xmm1, 0x30(%%rsp)\n\t movups %%xmm2, 0x40(%%rsp)\n\t" \
      "movups %%xmm3, 0x50(%%rsp)\n\t movups %%xmm4, 0x60(%%rsp)\n\t movups %%xmm5, 0x70(%%rsp)\n\t" \
      "lea 0x350(%%rsp), %%rcx\n\t"           /* the build's rbp: fitter rsp + 0x290, plus our 0x88 + 7 pushes */ \
      "mov $" #rear ", %%edx\n\t" \
      "call tire_aspect\n\t" \
      "movss %%xmm0, 0x40(%%rsp)\n\t"         /* the new aspect goes back as xmm2 */ \
      "movups 0x20(%%rsp), %%xmm0\n\t movups 0x30(%%rsp), %%xmm1\n\t movups 0x40(%%rsp), %%xmm2\n\t" \
      "movups 0x50(%%rsp), %%xmm3\n\t movups 0x60(%%rsp), %%xmm4\n\t movups 0x70(%%rsp), %%xmm5\n\t" \
      "add $0x88, %%rsp\n\t" \
      "pop %%r11\n\t pop %%r10\n\t pop %%r9\n\t pop %%r8\n\t pop %%rdx\n\t pop %%rcx\n\t pop %%rax\n\t" \
      lea "\n\t"                              /* the replaced instruction */ \
      "jmp *" #back "(%%rip)\n\t" ::: "memory"); \
  }
TIRE_STUB(tire_front_stub, 0, "lea 0xe30(%%r14), %%rcx", g_tireFrontBack)
TIRE_STUB(tire_rear_stub, 1, "lea 0x2318(%%r14), %%rcx", g_tireRearBack)

// The car's looks are set up apart from the build, by 140F592D0, which sizes the visible tires the same way (keeps
// the stock overall diameter, aspect for the fitted width and rim) and stores width / aspect (as a fraction) / rim at
// +0x900 / +0x904 / +0x908 for the front (140F5A963) and +0xA10 / +0xA14 / +0xA18 for the rear (140F5AA51). Its r13
// is the car's parts set after the car Id (wheel style at +4, PartEnum 0 at +8), so the front profile slot (26) is
// at r13+0x70 and the rear one (3) at r13+0x14. The stubs add the profile part's aspect points (as a fraction) to
// xmm1 before the store, never below 0.10 (as tire_aspect). Without them the physics had the profile but the tires
// looked stock whenever the car was loaded rather than rebuilt by the upgrade screen.
void *g_lookFrontBack = (void *)0x140F5A96B, *g_lookRearBack = (void *)0x140F5AA59;
const float g_hundredth = 0.01f, g_minAspect = 0.10f;

#define LOOK_STUB(name, slot, base, store, back) \
  __attribute__((naked, used)) static void name(void) { \
    __asm__ volatile( \
      "push %%rax\n\t" \
      "mov " #slot "(%%r13), %%eax\n\t sub $" #base ", %%eax\n\t add $1000, %%eax\n\t cmp $2000, %%eax\n\t jae 1f\n\t" \
      "sub $1000, %%eax\n\t jz 1f\n\t" \
      "vcvtsi2ss %%eax, %%xmm0, %%xmm0\n\t vmulss g_hundredth(%%rip), %%xmm0, %%xmm0\n\t" \
      "vaddss %%xmm0, %%xmm1, %%xmm1\n\t vmaxss g_minAspect(%%rip), %%xmm1, %%xmm1\n" \
      "1:\n\t pop %%rax\n\t" \
      store "\n\t"                            /* the replaced store */ \
      "jmp *" #back "(%%rip)\n\t" ::: "memory"); \
  }
LOOK_STUB(look_front_stub, 0x70, 93001000, "vmovss %%xmm1, 0x904(%%rsi)", g_lookFrontBack)
LOOK_STUB(look_rear_stub, 0x14, 94001000, "vmovss %%xmm1, 0xa14(%%rsi)", g_lookRearBack)

static void wheels_on_build_impl(BYTE *model, int car, int body, BYTE *frame);
void __attribute__((used)) wheels_on_build(BYTE *model, int car, int body, BYTE *frame) { PROF_BEGIN; wheels_on_build_impl(model, car, body, frame); PROF_END(P_BUILD); }
static void wheels_on_build_impl(BYTE *model, int car, int body, BYTE *frame) {
  float *front = (float *)(model + 0xF4), *rear = (float *)(model + 0xF8);
  const int *parts = build_parts(frame);
  float f = (float)kind_value(parts[g_kinds[FRONT_OFFSET].part], FRONT_OFFSET), r = (float)kind_value(parts[g_kinds[REAR_OFFSET].part], REAR_OFFSET);
  wchar_t key[16], s[64];
  _snwprintf(key, 16, L"%d", car);
  GetPrivateProfileStringW(L"offsets", key, L"", s, 64, g_ini);   // added to the fitted parts' offsets
  float fi = 0, ri = 0;
  if (s[0] && swscanf(s, L"%f , %f", &fi, &ri) < 1) logf("car %d: can't read \"%ls\" (front mm, rear mm)", car, s);
  f += fi; r += ri;
  if (f == 0 && r == 0) { logf("car %d body %d: stock track %.4f / %.4f", car, body, *front, *rear); return; }
  float f0 = *front, r0 = *rear;
  *front += 2 * f / 1000; *rear += 2 * r / 1000;
  logf("car %d body %d: front %.4f -> %.4f (%+g mm a side), rear %.4f -> %.4f (%+g mm a side)", car, body, f0, *front, f, r0, *rear, r);
}

// Entered by a jmp from the build with its frame intact: keep every register the build might still use.
__attribute__((naked, used)) static void wheels_stub(void) {
  __asm__ volatile(
    "vmovss %%xmm0, 0xf8(%%rdi)\n\t"           // the replaced instruction
    "push %%rax\n\t push %%rcx\n\t push %%rdx\n\t push %%r8\n\t push %%r9\n\t push %%r10\n\t push %%r11\n\t"
    "sub $0x88, %%rsp\n\t"                    // 7 pushes + 0x88 keeps rsp 16-aligned; shadow space + xmm0-5
    "movups %%xmm0, 0x20(%%rsp)\n\t movups %%xmm1, 0x30(%%rsp)\n\t movups %%xmm2, 0x40(%%rsp)\n\t"
    "movups %%xmm3, 0x50(%%rsp)\n\t movups %%xmm4, 0x60(%%rsp)\n\t movups %%xmm5, 0x70(%%rsp)\n\t"
    "mov %%rdi, %%rcx\n\t"
    "mov 0x120(%%rsp), %%edx\n\t"             // build frame +0x60: 0x88 + 7*8 = 0xC0 above it
    "mov 0x128(%%rsp), %%r8d\n\t"
    "mov %%rbp, %%r9\n\t"
    "call wheels_on_build\n\t"
    "movups 0x20(%%rsp), %%xmm0\n\t movups 0x30(%%rsp), %%xmm1\n\t movups 0x40(%%rsp), %%xmm2\n\t"
    "movups 0x50(%%rsp), %%xmm3\n\t movups 0x60(%%rsp), %%xmm4\n\t movups 0x70(%%rsp), %%xmm5\n\t"
    "add $0x88, %%rsp\n\t"
    "pop %%r11\n\t pop %%r10\n\t pop %%r9\n\t pop %%r8\n\t pop %%rdx\n\t pop %%rcx\n\t pop %%rax\n\t"
    "jmp *g_wheelsBack(%%rip)\n\t" ::: "memory");
}

static DWORD WINAPI wheels_install(LPVOID p) {
  (void)p;
  static const BYTE slots[] = { 0xC5, 0xF9, 0x6F, 0x05, 0x15, 0x23, 0xDC, 0x00 };   // vmovdqa xmm0, [rip+0xdc2315]
  static const BYTE tireF[] = { 0x49, 0x8D, 0x8E, 0x30, 0x0E, 0x00, 0x00 };          // lea rcx, [r14+0xe30]
  static const BYTE tireR[] = { 0x49, 0x8D, 0x8E, 0x18, 0x23, 0x00, 0x00 };          // lea rcx, [r14+0x2318]
  static const BYTE track[] = { 0xC5, 0xFA, 0x11, 0x87, 0xF8, 0x00, 0x00, 0x00 };   // vmovss [rdi+0xf8], xmm0
  hook_jmp(GAME_BASE + (0x1410567F3 - 0x140000000ULL), slots, sizeof slots, (void *)slots_stub, "car build (part slots)");
  hook_jmp(GAME_BASE + (0x141058F2B - 0x140000000ULL), tireF, sizeof tireF, (void *)tire_front_stub, "tire fitter (front profile)");
  hook_jmp(GAME_BASE + (0x14105910C - 0x140000000ULL), tireR, sizeof tireR, (void *)tire_rear_stub, "tire fitter (rear profile)");
  hook_jmp(GAME_BASE + (0x14105863D - 0x140000000ULL), track, sizeof track, (void *)wheels_stub, "car build (track offsets)");
  static const BYTE lookF[] = { 0xC5, 0xFA, 0x11, 0x8E, 0x04, 0x09, 0x00, 0x00 };   // vmovss [rsi+0x904], xmm1
  static const BYTE lookR[] = { 0xC5, 0xFA, 0x11, 0x8E, 0x14, 0x0A, 0x00, 0x00 };   // vmovss [rsi+0xa14], xmm1
  hook_jmp(GAME_BASE + (0x140F5A963 - 0x140000000ULL), lookF, sizeof lookF, (void *)look_front_stub, "car looks (front profile)");
  hook_jmp(GAME_BASE + (0x140F5AA51 - 0x140000000ULL), lookR, sizeof lookR, (void *)look_rear_stub, "car looks (rear profile)");
  return 0;
}
