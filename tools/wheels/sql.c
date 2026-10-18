// Included by fh2wheels.c. The game's SQLite (statically linked): every statement goes through sqlite3Prepare at
// 14003CDC0 (db, zSql, nBytes, ...), whose first instruction (mov [rsp+0x20], r9d) is 5 bytes long. The patch jumps
// from there to sql_stub, which hands the SQL text and its length to sql_on_prepare (which may replace them) and
// then runs that instruction and continues. menu.c's rewrites are applied here.
//   [debug] SqlLog=<text>[|<text>...]: log every statement containing one of them (case-sensitive), e.g. SqlLog=Upgrade

void *g_sqlBack = (void *)0x14003CDC5;
static char g_sqlLog[128];

static void log_long(const char *what, const char *s, int n) {
  if (n < 0) n = (int)strlen(s);
  char head[64]; int h = snprintf(head, sizeof head, "%s (%d): ", what, n);
  EnterCriticalSection(&g_logLock);
  DWORD w; WriteFile(g_log, head, h, &w, NULL); WriteFile(g_log, s, n, &w, NULL); WriteFile(g_log, "\r\n", 2, &w, NULL);
  LeaveCriticalSection(&g_logLock);
}

static int contains(const char *s, int n, const char *needle) {
  size_t k = strlen(needle);
  if (n < 0) return strstr(s, needle) != NULL;
  for (int i = 0; i + (int)k <= n; i++) if (!memcmp(s + i, needle, k)) return 1;
  return 0;
}

#include "menu.c"

// SqlLog=a|b|c: any of them.
static int sql_logged(const char *s, int n) {
  char t[128];
  for (const char *p = g_sqlLog; *p; ) {
    const char *e = strchr(p, '|'); size_t k = e ? (size_t)(e - p) : strlen(p);
    if (k && k < sizeof t) { memcpy(t, p, k); t[k] = 0; if (contains(s, n, t)) return 1; }
    p += k + (e != NULL);
  }
  return 0;
}

// A rewritten statement is never freed: SQLite may keep pointers into it (the tail of a multi-statement string),
// and the few rewritten statements (a car load, opening a menu) are small.
void __attribute__((used)) sql_on_prepare(const char **psql, int *pn) {
  const char *s = *psql;
  if (!s) return;
  char *r = menu_rewrite(s, *pn);
  if (r) { *psql = r; *pn = -1; s = r; }
  if (g_sqlLog[0] && sql_logged(s, *pn)) log_long(r ? "sql (rewritten)" : "sql", s, *pn);
}

__attribute__((naked, used)) static void sql_stub(void) {
  __asm__ volatile(
    "push %%rax\n\t push %%rcx\n\t push %%rdx\n\t push %%r8\n\t push %%r9\n\t push %%r10\n\t push %%r11\n\t"
    "sub $0x80, %%rsp\n\t"                    // entry rsp is 8 mod 16: 7 pushes + 0x80 make it 0 mod 16
    "movups %%xmm0, 0x20(%%rsp)\n\t movups %%xmm1, 0x30(%%rsp)\n\t movups %%xmm2, 0x40(%%rsp)\n\t"
    "movups %%xmm3, 0x50(%%rsp)\n\t movups %%xmm4, 0x60(%%rsp)\n\t movups %%xmm5, 0x70(%%rsp)\n\t"
    "lea 0xa0(%%rsp), %%rcx\n\t"              // the saved rdx (zSql): 0x80 + 4 pushes above
    "lea 0x98(%%rsp), %%rdx\n\t"              // the saved r8 (nBytes)
    "call sql_on_prepare\n\t"
    "movups 0x20(%%rsp), %%xmm0\n\t movups 0x30(%%rsp), %%xmm1\n\t movups 0x40(%%rsp), %%xmm2\n\t"
    "movups 0x50(%%rsp), %%xmm3\n\t movups 0x60(%%rsp), %%xmm4\n\t movups 0x70(%%rsp), %%xmm5\n\t"
    "add $0x80, %%rsp\n\t"
    "pop %%r11\n\t pop %%r10\n\t pop %%r9\n\t pop %%r8\n\t pop %%rdx\n\t pop %%rcx\n\t pop %%rax\n\t"
    "mov %%r9d, 0x20(%%rsp)\n\t"              // the replaced instruction
    "jmp *g_sqlBack(%%rip)\n\t" ::: "memory");
}

static DWORD WINAPI sql_install(LPVOID p) {
  (void)p;
  static const BYTE orig[] = { 0x44, 0x89, 0x4C, 0x24, 0x20 };   // mov [rsp+0x20], r9d
  hook_jmp(GAME_BASE + (0x14003CDC0 - 0x140000000ULL), orig, 5, (void *)sql_stub, "sqlite3Prepare");
  return 0;
}

static void sql_start(void) {
  GetPrivateProfileStringA("debug", "SqlLog", "", g_sqlLog, sizeof g_sqlLog, g_iniA);
  if (g_sqlLog[0]) logf("logging SQL containing \"%s\"", g_sqlLog);
  CloseHandle(CreateThread(NULL, 0, sql_install, NULL, 0, NULL));
  CloseHandle(CreateThread(NULL, 0, menu_install, NULL, 0, NULL));
}
