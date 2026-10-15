// Included by fh2net.c after assoc.c. Code patches in the game and in Azimuth, each checked against the
// original bytes.
//
// [net] SkipWeatherWait=1: the free roam entry (stateflow network.xml initial_entry_common) waits in
// WaitForFullWeatherReady (update 1409641D0) for the session's weather object, which the server made from the
// joining player's FullWeather (msgs 53/54) - fh2srv doesn't make it yet. The patch turns the wait into
// "done" (the jump at 1409641EA to the transition at 140964234); ApplyFullWeatherFromServer, next, skips
// itself when there is no weather object (140865A31).

static int g_skipWeatherWait;

static int patch_bytes(BYTE *at, const BYTE *orig, const BYTE *repl, SIZE_T n, const char *what) {
  if (!readable(at, n) || memcmp(at, orig, n)) { logf("patch %s at %p: original bytes differ, not applied", what, at); return 0; }
  DWORD old; VirtualProtect(at, n, PAGE_EXECUTE_READWRITE, &old);
  memcpy(at, repl, n);
  VirtualProtect(at, n, old, &old);
  FlushInstructionCache(GetCurrentProcess(), at, n);
  logf("patch %s applied at %p", what, at);
  return 1;
}

// [xbl] Xuid=<decimal>: the player's Xbox user id. Azimuth 0.9.7 has it as a constant (0x9000000000000 =
// 2533274790395904); consoles playing together each need their own. Only the XboxUserId string (movabs r8
// at RVA 23855) is patched: the other use (RVA 131D25) names the save container (User_%llX), and changing
// it would start a new save.
static void xuid_patch(void) {
  wchar_t s[32]; GetPrivateProfileStringW(L"xbl", L"Xuid", L"", s, 32, g_ini);
  if (!s[0]) return;
  ULONG64 x = wcstoull(s, NULL, 10);
  BYTE *az = (BYTE *)GetModuleHandleW(NULL);
  BYTE orig[10] = { 0x49, 0xB8 }, repl[10] = { 0x49, 0xB8 };
  ULONG64 azx = 0x9000000000000ULL;
  memcpy(orig + 2, &azx, 8); memcpy(repl + 2, &x, 8);
  patch_bytes(az + 0x23855, orig, repl, 10, "Xuid");
  logf("xuid %llu", x);
}

// [net] SkipTrafficWait=1: the initial car loading (stateflow network.xml initial_car_loading) waits in
// NetworkWaitForAllPendingTraffic (update 1408E05E0) while the traffic manager's pending flag (+0xAE) is set -
// traffic Turn 10's server ran and fh2srv doesn't - and only after it are the players' cars unghosted
// (NetworkInitialCarLoadingUnghosted), so without this players drive through each other. The patch drops the
// jne at 1408E0658, so the wait is done at once (online traffic stays empty).
static int g_skipTrafficWait;

static void game_patches(void) {
  if (g_skipTrafficWait) {
    static const BYTE orig[] = { 0x75, 0x0D }, nops[] = { 0x90, 0x90 };
    patch_bytes(GAME_BASE + (0x1408E0658 - 0x140000000ULL), orig, nops, 2, "SkipTrafficWait");
  }
  if (g_skipWeatherWait) {
    static const BYTE orig[] = { 0x48, 0x8B, 0x0D }, jmp[] = { 0xEB, 0x48 };   // mov rcx, [rip+..] -> jmp 140964234
    patch_bytes(GAME_BASE + (0x1409641EA - 0x140000000ULL), orig, jmp, 2, "SkipWeatherWait");
  }
}
