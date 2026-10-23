// Included by fh2wheels.c before the hooks. [debug] Profile=1 in fh2wheels.ini: how often each hook runs and how long
// it takes, logged every PROF_PERIOD seconds (calls, total ms, the slowest call in microseconds), so fh2wheels' cost
// can be told apart from the game's. Off, a hook pays one test of g_prof.

enum { P_SQL, P_TEXT, P_BUILD, P_TIRE, P_RIM_LOAD, P_LOOKS, P_STEER_LOAD, P_COUNT };
static const char *const g_profName[P_COUNT] = { "sql prepare", "text lookup", "car build (track)", "tire fitter", "rim load", "car looks", "steering data" };
#define PROF_PERIOD 30

static int g_prof;
static volatile LONG64 g_profCalls[P_COUNT], g_profTicks[P_COUNT], g_profMax[P_COUNT];

static LONG64 prof_now(void) { LARGE_INTEGER t; QueryPerformanceCounter(&t); return t.QuadPart; }
static void prof_add(int k, LONG64 start) {
  LONG64 d = prof_now() - start, m;
  InterlockedIncrement64(&g_profCalls[k]);
  InterlockedAdd64(&g_profTicks[k], d);
  while (d > (m = g_profMax[k]) && InterlockedCompareExchange64(&g_profMax[k], d, m) != m) ;
}
#define PROF_BEGIN LONG64 prof_t0 = g_prof ? prof_now() : 0
#define PROF_END(k) do { if (g_prof) prof_add(k, prof_t0); } while (0)

static DWORD WINAPI prof_thread(LPVOID p) {
  (void)p;
  for (;;) {
    Sleep(PROF_PERIOD * 1000);
    double total = 0;
    for (int k = 0; k < P_COUNT; k++) {
      LONG64 calls = InterlockedExchange64(&g_profCalls[k], 0), ticks = InterlockedExchange64(&g_profTicks[k], 0);
      LONG64 mx = InterlockedExchange64(&g_profMax[k], 0);
      if (!calls) continue;
      double ms = ticks * 1000.0 / g_freq.QuadPart;
      total += ms;
      logf("profile: %-18s %8lld calls %9.2f ms  slowest %8.1f us", g_profName[k], calls, ms, mx * 1e6 / g_freq.QuadPart);
    }
    logf("profile: %.2f ms in fh2wheels' hooks in the last %d s (%.3f%% of the time)", total, PROF_PERIOD, total / (PROF_PERIOD * 10.0));
  }
  return 0;
}
