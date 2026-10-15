// Included by fh2net.c. Scripted controller input for automated tests: with [input] Script=<file> (relative
// to the DLL's folder), Azimuth's XInputGetState (which it resolves with GetProcAddress) is wrapped, and the
// buttons the script presses are merged into controller 0's state (a missing controller reads as connected).
// Script lines: "wait <ms>", "press <button> [hold ms]" (A B X Y START BACK LB RB LS RS UP DOWN LEFT RIGHT;
// each press is followed by a 400 ms gap), "trigger L|R <0-255>" and "stick LX|LY|RX|RY <-32768..32767>" (held
// until changed), "release" (triggers and sticks back to 0), "label" and "loop" (go back to the label, forever),
// "# comment". An empty script still makes a missing controller read as connected, so the game doesn't pause.

typedef struct { WORD wButtons; BYTE bLeftTrigger, bRightTrigger; SHORT sThumbLX, sThumbLY, sThumbRX, sThumbRY; } XPad;
typedef struct { DWORD dwPacketNumber; XPad Gamepad; } XState;
typedef DWORD (WINAPI *XInputGetState_t)(DWORD, XState *);
static XInputGetState_t o_XInputGetState;
static volatile LONG g_injectButtons, g_injectPacket;
static volatile LONG g_axis[6];          // held by the script: left trigger, right trigger, LX, LY, RX, RY
static wchar_t g_inputScript[MAX_PATH];
static int g_hideRealPad;                // [input] HideRealController=1: controller 0 is the script's alone

static DWORD WINAPI h_XInputGetState(DWORD user, XState *s) {
  DWORD rc = o_XInputGetState ? o_XInputGetState(user, s) : ERROR_DEVICE_NOT_CONNECTED;
  if (user != 0 || !g_inputScript[0]) return rc;
  if (rc != ERROR_SUCCESS || g_hideRealPad) { memset(s, 0, sizeof *s); rc = ERROR_SUCCESS; }
  WORD b = (WORD)g_injectButtons;
  if (b) s->Gamepad.wButtons |= b;
  if (g_axis[0]) s->Gamepad.bLeftTrigger = (BYTE)g_axis[0];
  if (g_axis[1]) s->Gamepad.bRightTrigger = (BYTE)g_axis[1];
  if (g_axis[2]) s->Gamepad.sThumbLX = (SHORT)g_axis[2];
  if (g_axis[3]) s->Gamepad.sThumbLY = (SHORT)g_axis[3];
  if (g_axis[4]) s->Gamepad.sThumbRX = (SHORT)g_axis[4];
  if (g_axis[5]) s->Gamepad.sThumbRY = (SHORT)g_axis[5];
  s->dwPacketNumber += (DWORD)g_injectPacket * 0x10000;   // the reading changes whenever an injected press does
  static LONG calls; LONG c = InterlockedIncrement(&calls);
  if (c % 500 == 1) logf("input: XInputGetState #%ld from %p: packet %lu buttons %04x LT %u RT %u LX %d", c, __builtin_return_address(0),
                         s->dwPacketNumber, s->Gamepad.wButtons, s->Gamepad.bLeftTrigger, s->Gamepad.bRightTrigger, s->Gamepad.sThumbLX);
  return rc;
}

typedef FARPROC (WINAPI *GetProcAddress_t)(HMODULE, LPCSTR);
static GetProcAddress_t o_GetProcAddress;
static FARPROC WINAPI h_GetProcAddress(HMODULE m, LPCSTR name) {
  FARPROC p = o_GetProcAddress(m, name);
  if (p && (ULONG_PTR)name > 0xFFFF && !strcmp(name, "XInputGetState")) {
    o_XInputGetState = (XInputGetState_t)p;
    logf("input: Azimuth's XInputGetState wrapped");
    return (FARPROC)h_XInputGetState;
  }
  return p;
}

static WORD button_bit(const char *n) {
  static const struct { const char *n; WORD b; } t[] = {
    { "UP", 0x0001 }, { "DOWN", 0x0002 }, { "LEFT", 0x0004 }, { "RIGHT", 0x0008 }, { "START", 0x0010 }, { "BACK", 0x0020 },
    { "LS", 0x0040 }, { "RS", 0x0080 }, { "LB", 0x0100 }, { "RB", 0x0200 }, { "A", 0x1000 }, { "B", 0x2000 }, { "X", 0x4000 }, { "Y", 0x8000 } };
  for (size_t i = 0; i < sizeof t / sizeof *t; i++) if (!_stricmp(n, t[i].n)) return t[i].b;
  return 0;
}

static DWORD WINAPI input_script(LPVOID p) {
  (void)p;
  FILE *f = _wfopen(g_inputScript, L"rb");
  if (!f) { logf("input: script %ls not found", g_inputScript); return 0; }
  logf("input: running %ls", g_inputScript);
  char line[256];
  long label = -1; int looped = 0;
  for (;;) {
    if (!fgets(line, sizeof line, f)) break;
    char cmd[32] = "", arg[32] = ""; int ms = 0;
    if (sscanf(line, "%31s %31s %d", cmd, arg, &ms) < 1 || cmd[0] == '#') continue;
    if (!_stricmp(cmd, "label")) { label = ftell(f); continue; }
    if (!_stricmp(cmd, "loop")) {
      if (label < 0) { logf("input: loop without a label"); continue; }
      if (!looped) logf("input: looping (later passes aren't logged)");
      looped = 1; fseek(f, label, SEEK_SET); continue;
    }
    if (!_stricmp(cmd, "trigger") || !_stricmp(cmd, "stick")) {
      static const char *names[] = { "L", "R", "LX", "LY", "RX", "RY" };
      int k = -1;
      for (int i = !_stricmp(cmd, "stick") ? 2 : 0; i < (!_stricmp(cmd, "stick") ? 6 : 2); i++) if (!_stricmp(arg, names[i])) k = i;
      if (k < 0) { logf("input: unknown %s %s", cmd, arg); continue; }
      if (!looped) logf("input: %s %s %d", cmd, arg, ms);
      InterlockedExchange(&g_axis[k], ms); InterlockedIncrement(&g_injectPacket);
      continue;
    }
    if (!_stricmp(cmd, "release")) {
      for (int i = 0; i < 6; i++) InterlockedExchange(&g_axis[i], 0);
      InterlockedIncrement(&g_injectPacket);
      continue;
    }
    if (!_stricmp(cmd, "wait")) { int w = atoi(arg); if (!looped) logf("input: wait %d ms", w); Sleep(w); }
    else if (!_stricmp(cmd, "press")) {
      WORD b = button_bit(arg);
      if (!b) { logf("input: unknown button %s", arg); continue; }
      if (!looped) logf("input: press %s", arg);
      InterlockedExchange(&g_injectButtons, b); InterlockedIncrement(&g_injectPacket);
      Sleep(ms > 0 ? ms : 150);
      InterlockedExchange(&g_injectButtons, 0); InterlockedIncrement(&g_injectPacket);
      Sleep(400);
    }
  }
  fclose(f);
  logf("input: script done");
  return 0;
}

// Called from DllMain: hooks azimuth.exe's GetProcAddress import, and starts the script thread.
static void input_install(const wchar_t *dir) {
  wchar_t rel[MAX_PATH] = L"";
  GetPrivateProfileStringW(L"input", L"Script", L"", rel, MAX_PATH, g_ini);
  g_hideRealPad = GetPrivateProfileIntW(L"input", L"HideRealController", 0, g_ini);
  if (!rel[0]) return;
  _snwprintf(g_inputScript, MAX_PATH, L"%ls%ls", dir, rel);
  BYTE *az = (BYTE *)GetModuleHandleW(NULL);
  IMAGE_NT_HEADERS64 *nt = (void *)(az + ((IMAGE_DOS_HEADER *)az)->e_lfanew);
  IMAGE_DATA_DIRECTORY dd = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  for (IMAGE_IMPORT_DESCRIPTOR *d = (void *)(az + dd.VirtualAddress); d->Name; d++) {
    if (_stricmp((const char *)(az + d->Name), "KERNEL32.dll")) continue;
    ULONGLONG *names = (void *)(az + d->OriginalFirstThunk);
    void **iat = (void **)(az + d->FirstThunk);
    for (int k = 0; names[k]; k++) {
      if (IMAGE_SNAP_BY_ORDINAL64(names[k]) || strcmp((const char *)((IMAGE_IMPORT_BY_NAME *)(az + names[k]))->Name, "GetProcAddress")) continue;
      o_GetProcAddress = (GetProcAddress_t)iat[k];
      DWORD old; VirtualProtect(&iat[k], 8, PAGE_READWRITE, &old);
      iat[k] = (void *)h_GetProcAddress;
      VirtualProtect(&iat[k], 8, old, &old);
      logf("input: hooked azimuth.exe GetProcAddress");
    }
  }
  // Azimuth resolves XInputGetState before this DLL loads: replace the pointer it stored (in its writable
  // sections) with the wrapper.
  HMODULE xi = GetModuleHandleW(L"xinput1_4.dll");
  void *real = xi ? (void *)GetProcAddress(xi, "XInputGetState") : NULL;
  if (real) {
    o_XInputGetState = (XInputGetState_t)real;
    int n = 0;
    IMAGE_SECTION_HEADER *sec = IMAGE_FIRST_SECTION(nt);
    for (int s = 0; s < nt->FileHeader.NumberOfSections; s++, sec++) {
      if (!(sec->Characteristics & IMAGE_SCN_MEM_WRITE)) continue;
      void **p = (void **)(az + sec->VirtualAddress), **end = (void **)(az + sec->VirtualAddress + sec->Misc.VirtualSize);
      for (; p < end; p++) if (*p == real) { *p = (void *)h_XInputGetState; n++; }
    }
    logf("input: replaced %d stored XInputGetState pointer(s) in azimuth.exe", n);
  }
  CloseHandle(CreateThread(NULL, 0, input_script, NULL, 0, NULL));
}
