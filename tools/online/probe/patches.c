// Included by fh2net.c after assoc.c. Code patches in the game, each checked against the original bytes.
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

static void game_patches(void) {
  if (g_skipWeatherWait) {
    static const BYTE orig[] = { 0x48, 0x8B, 0x0D }, jmp[] = { 0xEB, 0x48 };   // mov rcx, [rip+..] -> jmp 140964234
    patch_bytes(GAME_BASE + (0x1409641EA - 0x140000000ULL), orig, jmp, 2, "SkipWeatherWait");
  }
}
