// Included by fh2net.c. Trace points: [trace] Game=<va>,<va>... (game addresses) and Xsapi=<va>,... (addresses
// at Microsoft.Xbox.Services.dll's preferred base 0x180000000, rebased to where Azimuth mapped it). Each
// address gets an int3; a vectored handler logs the hit (rcx rdx r8 r9 rax, and the return address at [rsp]),
// puts the original byte back, single-steps it, and re-arms. For diagnosis only: it slows those paths.

#define MAX_TRACE 64
typedef struct { BYTE *addr; BYTE orig; const char *tag; LONG hits; } TracePoint;
static TracePoint g_trace[MAX_TRACE];
static int g_traceCount;
static DWORD g_traceTls = TLS_OUT_OF_INDEXES;   // the point being stepped over on this thread (index + 1)

static void trace_write(BYTE *a, BYTE v) {
  DWORD old; VirtualProtect(a, 1, PAGE_EXECUTE_READWRITE, &old);
  *a = v;
  VirtualProtect(a, 1, old, &old);
  FlushInstructionCache(GetCurrentProcess(), a, 1);
}

static LONG CALLBACK trace_handler(EXCEPTION_POINTERS *e) {
  CONTEXT *c = e->ContextRecord;
  DWORD code = e->ExceptionRecord->ExceptionCode;
  if (code == EXCEPTION_BREAKPOINT) {
    BYTE *at = (BYTE *)e->ExceptionRecord->ExceptionAddress;
    for (int i = 0; i < g_traceCount; i++) {
      if (g_trace[i].addr != at) continue;
      LONG n = InterlockedIncrement(&g_trace[i].hits);
      if (n <= 40) {
        logf("trace %s %p hit %ld: rcx %llx rdx %llx r8 %llx r9 %llx rax %llx rbx %llx rsi %llx rdi %llx [rsp] %llx", g_trace[i].tag, at, n,
             c->Rcx, c->Rdx, c->R8, c->R9, c->Rax, c->Rbx, c->Rsi, c->Rdi, *(ULONG64 *)c->Rsp);
        // the first 32 bytes rcx, rdx, rbx, r8 and *r8 point at, when readable
        DWORD64 regs[5] = { c->Rcx, c->Rdx, c->Rbx, c->R8, 0 }; const char *rn[5] = { "rcx", "rdx", "rbx", "r8", "*r8" };
        if (c->R8 >= 0x10000 && readable((void *)c->R8, 8)) regs[4] = *(DWORD64 *)c->R8;   // one level through r8
        for (int r = 0; r < 5; r++) {
          if (regs[r] < 0x10000 || !readable((void *)regs[r], 32)) continue;
          const DWORD *w = (const DWORD *)regs[r];
          logf("    [%s] %08lx %08lx %08lx %08lx %08lx %08lx %08lx %08lx", rn[r], w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7]);
        }
      }
      trace_write(at, g_trace[i].orig);
      c->Rip = (DWORD64)at;
      c->EFlags |= 0x100;                       // single-step the original instruction
      TlsSetValue(g_traceTls, (void *)(INT_PTR)(i + 1));
      return EXCEPTION_CONTINUE_EXECUTION;
    }
  } else if (code == EXCEPTION_SINGLE_STEP) {
    INT_PTR i = (INT_PTR)TlsGetValue(g_traceTls);
    if (i) {
      TlsSetValue(g_traceTls, 0);
      trace_write(g_trace[i - 1].addr, 0xCC);   // re-arm
      return EXCEPTION_CONTINUE_EXECUTION;
    }
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

// "a,b,c" of hex VAs; rebased by (base - preferred)
static void trace_add_list(const wchar_t *key, BYTE *base, ULONG64 preferred, const char *tag) {
  wchar_t buf[2048]; GetPrivateProfileStringW(L"trace", key, L"", buf, 2048, g_ini);
  for (wchar_t *p = buf; *p && g_traceCount < MAX_TRACE; ) {
    while (*p == L',' || *p == L' ') p++;
    if (!*p) break;
    wchar_t *end; ULONG64 va = wcstoull(p, &end, 16);
    if (end == p) break;
    p = end;
    BYTE *a = base + (va - preferred);
    if (!readable(a, 1)) { logf("trace %s %llx: not mapped", tag, va); continue; }
    TracePoint *t = &g_trace[g_traceCount++];
    t->addr = a; t->orig = *a; t->tag = tag; t->hits = 0;
    trace_write(a, 0xCC);
    logf("trace %s armed at %p (%llx)", tag, a, va);
  }
}

static void trace_install(const wchar_t *key, BYTE *base, ULONG64 preferred, const char *tag) {
  if (g_traceTls == TLS_OUT_OF_INDEXES) {
    g_traceTls = TlsAlloc();
    AddVectoredExceptionHandler(1, trace_handler);
  }
  trace_add_list(key, base, preferred, tag);
}
