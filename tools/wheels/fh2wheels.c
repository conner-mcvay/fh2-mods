// fh2wheels: per-axle wheel offsets for Forza Horizon 2 on Azimuth. Loaded by Azimuth as data\bin\azimuth-tls.dll
// in front of the DLL that had that name (renamed fh2wheels-next.dll: Extra Options', fh2net or Azimuth's own),
// whose exports it forwards (fh2wheels.def). fh2net forwards to azimuth-tls-next.dll instead, so the two chain in
// either order. Settings: data\bin\fh2wheels.ini; log: data\bin\fh2wheels.log.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <wchar.h>
#include <stdlib.h>
#include <string.h>

#define GAME_BASE ((BYTE *)0x140000000ULL)

static CRITICAL_SECTION g_logLock;
static HANDLE g_log = INVALID_HANDLE_VALUE;
static LARGE_INTEGER g_freq, g_t0;
static wchar_t g_ini[MAX_PATH];
static char g_iniA[MAX_PATH];

static void logf(const char *fmt, ...) {
  char buf[1024];
  LARGE_INTEGER t; QueryPerformanceCounter(&t);
  int n = snprintf(buf, sizeof buf, "%9.3f ", (double)(t.QuadPart - g_t0.QuadPart) / g_freq.QuadPart);
  va_list ap; va_start(ap, fmt);
  int m = vsnprintf(buf + n, sizeof buf - n - 2, fmt, ap);
  va_end(ap);
  if (m < 0) m = 0;
  n += m; if (n > (int)sizeof buf - 2) n = sizeof buf - 2;
  buf[n++] = '\r'; buf[n++] = '\n';
  EnterCriticalSection(&g_logLock);
  DWORD w; WriteFile(g_log, buf, n, &w, NULL);
  LeaveCriticalSection(&g_logLock);
}

#define EXEC_PROTECT (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)

static DWORD page_protect(const void *at) {
  MEMORY_BASIC_INFORMATION mbi;
  return VirtualQuery(at, &mbi, sizeof mbi) ? mbi.Protect : 0;
}

// Azimuth maps the game image writable first and makes its code executable a moment later; restoring the protection
// found before that would take the execute right away (a DEP crash), so the patch waits for an executable page and
// leaves it execute-read. The original bytes are checked first, so a changed game (or a second hook) is left alone.
static int patch_code(BYTE *at, const BYTE *orig, const BYTE *repl, SIZE_T n, const char *what) {
  int i;
  for (i = 0; i < 60000 && !(page_protect(at) & EXEC_PROTECT); i++) Sleep(1);
  if (!(page_protect(at) & EXEC_PROTECT)) { logf("patch %s at %p: page never became executable (0x%lx), not applied", what, at, page_protect(at)); return 0; }
  if (memcmp(at, orig, n)) { logf("patch %s at %p: original bytes differ, not applied", what, at); return 0; }
  DWORD old; VirtualProtect(at, n, PAGE_EXECUTE_READWRITE, &old);
  memcpy(at, repl, n);
  VirtualProtect(at, n, PAGE_EXECUTE_READ, &old);
  FlushInstructionCache(GetCurrentProcess(), at, n);
  logf("patch %s applied at %p", what, at);
  return 1;
}

// A page within rel32 reach of the game code, for the jump to this DLL (which loads too far away for one).
static BYTE *alloc_near(BYTE *at) {
  SYSTEM_INFO si; GetSystemInfo(&si);
  ULONG_PTR g = si.dwAllocationGranularity;
  for (ULONG_PTR d = g; d < 0x70000000; d += g) {
    BYTE *p = VirtualAlloc((BYTE *)(((ULONG_PTR)at - d) & ~(g - 1)), 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (p) return p;
    p = VirtualAlloc((BYTE *)(((ULONG_PTR)at + 0x4000000 + d) & ~(g - 1)), 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (p) return p;
  }
  return NULL;
}

// Jumps from game code at `at` (n >= 5 bytes, whole instructions, checked against orig) to a stub in this DLL, through
// a trampoline page near the game. The stub runs the replaced instructions itself and jumps back.
static int hook_jmp(BYTE *at, const BYTE *orig, SIZE_T n, void *stub, const char *what) {
  BYTE *tramp = alloc_near(at);
  if (!tramp) { logf("hook %s: no memory near the game code, not applied", what); return 0; }
  tramp[0] = 0xFF; tramp[1] = 0x25; memset(tramp + 2, 0, 4); memcpy(tramp + 6, &stub, 8);   // jmp [rip+0] / dq stub
  DWORD old; VirtualProtect(tramp, 4096, PAGE_EXECUTE_READ, &old);
  BYTE jmp[16]; memset(jmp, 0x90, sizeof jmp); jmp[0] = 0xE9;
  LONG rel = (LONG)(tramp - (at + 5)); memcpy(jmp + 1, &rel, 4);
  return patch_code(at, orig, jmp, n, what);
}

#include "sql.c"
#include "wheels.c"
#include "text.c"

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID r) {
  (void)r;
  if (reason != DLL_PROCESS_ATTACH) return TRUE;
  DisableThreadLibraryCalls(inst);
  InitializeCriticalSection(&g_logLock);
  QueryPerformanceFrequency(&g_freq); QueryPerformanceCounter(&g_t0);
  wchar_t path[MAX_PATH]; GetModuleFileNameW(inst, path, MAX_PATH);
  wchar_t *slash = wcsrchr(path, L'\\'); if (slash) slash[1] = 0;
  wchar_t logp[MAX_PATH], next[MAX_PATH];
  _snwprintf(logp, MAX_PATH, L"%lsfh2wheels.log", path);
  _snwprintf(next, MAX_PATH, L"%lsfh2wheels-next.dll", path);
  _snwprintf(g_ini, MAX_PATH, L"%lsfh2wheels.ini", path);
  WideCharToMultiByte(CP_ACP, 0, g_ini, -1, g_iniA, MAX_PATH, NULL, NULL);
  g_log = CreateFileW(logp, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  SYSTEMTIME st; GetLocalTime(&st);
  logf("fh2wheels loaded %04d-%02d-%02d %02d:%02d:%02d", st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
  // The forwarded exports resolve against this module once it is loaded under its own name.
  HMODULE nx = LoadLibraryW(next);
  logf("fh2wheels-next.dll -> %p (err %lu)", nx, nx ? 0 : GetLastError());
  CloseHandle(CreateThread(NULL, 0, wheels_install, NULL, 0, NULL));
  sql_start();
  CloseHandle(CreateThread(NULL, 0, text_install, NULL, 0, NULL));
  return TRUE;
}
