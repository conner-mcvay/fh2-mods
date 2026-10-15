// fh2net: loaded by Azimuth as data\bin\azimuth-tls.dll in front of the original one (renamed
// azimuth-tls-next.dll, Extra Options' or Azimuth's own), whose exports it forwards (fh2net.def).
// Stage 1 (probe): log-only hooks on the game's imports, to see what its online code asks for
// and what Azimuth answers. Nothing the game gets back is changed.
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <wchar.h>

#define GAME_BASE ((BYTE *)0x140000000ULL)

static CRITICAL_SECTION g_logLock;
static HANDLE g_log = INVALID_HANDLE_VALUE;
static LARGE_INTEGER g_freq, g_t0;

static void logf(const char *fmt, ...) {
  char buf[2048];
  LARGE_INTEGER t; QueryPerformanceCounter(&t);
  int n = snprintf(buf, sizeof buf, "%9.3f [%5lu] ", (double)(t.QuadPart - g_t0.QuadPart) / g_freq.QuadPart, GetCurrentThreadId());
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

static void guidstr(const GUID *g, char *out) {
  if (!g) { strcpy(out, "(null)"); return; }
  sprintf(out, "%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x", g->Data1, g->Data2, g->Data3,
          g->Data4[0], g->Data4[1], g->Data4[2], g->Data4[3], g->Data4[4], g->Data4[5], g->Data4[6], g->Data4[7]);
}

static void addrstr(const struct sockaddr *sa, char *out, size_t cap) {
  if (!sa) { snprintf(out, cap, "(null)"); return; }
  if (sa->sa_family == AF_INET) {
    const struct sockaddr_in *a = (const void *)sa; const BYTE *b = (const BYTE *)&a->sin_addr;
    snprintf(out, cap, "%u.%u.%u.%u:%u", b[0], b[1], b[2], b[3], ntohs(a->sin_port));
  } else if (sa->sa_family == AF_INET6) {
    const struct sockaddr_in6 *a = (const void *)sa; const BYTE *b = a->sin6_addr.s6_addr;
    snprintf(out, cap, "[%02x%02x:%02x%02x:..:%02x%02x:%02x%02x]:%u", b[0], b[1], b[2], b[3], b[12], b[13], b[14], b[15], ntohs(a->sin6_port));
  } else snprintf(out, cap, "family %d", sa->sa_family);
}

// ---- hooks -------------------------------------------------------------------------------------

typedef HRESULT (WINAPI *CoCreateInstance_t)(REFCLSID, void *, DWORD, REFIID, LPVOID *);
static CoCreateInstance_t o_CoCreateInstance;
#include "xhr.c"

static HRESULT WINAPI h_CoCreateInstance(REFCLSID c, void * o, DWORD ctx, REFIID i, LPVOID *pv) {
  HRESULT hr;
  if (!xhr_create(c, i, pv, &hr)) hr = o_CoCreateInstance(c, o, ctx, i, pv);
  char a[40], b[40]; guidstr(c, a); guidstr(i, b);
  logf("CoCreateInstance clsid {%s} iid {%s} -> 0x%08lx obj %p ret %p", a, b, hr, pv ? *pv : 0, __builtin_return_address(0));
  return hr;
}

// ---- settings (fh2net.ini beside the DLL) -------------------------------------------------------

static wchar_t g_ini[MAX_PATH];
static int g_netLevel;   // [net] ConnectivityLevel: 0 = Azimuth's answer; 3 = internet; 4 = Xbox Live access

// ---- Windows.Networking.Connectivity.NetworkInformation ----------------------------------------
// With ConnectivityLevel set, the statics are wrapped: GetInternetConnectionProfile answers a profile of
// that level; every other call goes to Azimuth's object.

static const GUID IID_INetworkInformationStatics = { 0x5074f851, 0x950d, 0x4165, { 0x9c, 0x15, 0x36, 0x56, 0x19, 0x48, 0x1e, 0xea } };
static const GUID IID_IConnectionProfile = { 0x71ba143c, 0x598e, 0x49d0, { 0x84, 0xeb, 0x8f, 0xeb, 0xae, 0xdc, 0xc1, 0x95 } };
static const GUID IID_IUnknown_ = { 0, 0, 0, { 0xc0, 0, 0, 0, 0, 0, 0, 0x46 } };
static const GUID IID_IInspectable_ = { 0xaf86e2e0, 0xb12d, 0x11d0, { 0x8a, 0x97, 0x00, 0xa0, 0xc9, 0x0b, 0xb5, 0xde } };

typedef struct { void **vtbl; } Obj;
#define VCALL(o, slot, T) ((T)((Obj *)(o))->vtbl[slot])

// A fake ConnectionProfile: a static object (no refcount) answering the connectivity level.
static HRESULT STDMETHODCALLTYPE prof_QI(void *t, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_IConnectionProfile) || IsEqualGUID(iid, &IID_IUnknown_) || IsEqualGUID(iid, &IID_IInspectable_)) { *out = t; return S_OK; }
  char b[40]; guidstr(iid, b); logf("fake ConnectionProfile QI {%s}: no", b);
  *out = NULL; return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE prof_AddRef(void *t) { (void)t; return 2; }
static ULONG STDMETHODCALLTYPE prof_Release(void *t) { (void)t; return 1; }
static HRESULT STDMETHODCALLTYPE prof_GetIids(void *t, ULONG *n, GUID **iids) { (void)t; *n = 0; *iids = NULL; return S_OK; }
static HRESULT STDMETHODCALLTYPE prof_GetRuntimeClassName(void *t, void **s) { (void)t; *s = NULL; return S_OK; }
static HRESULT STDMETHODCALLTYPE prof_GetTrustLevel(void *t, int *l) { (void)t; *l = 0; return S_OK; }
static HRESULT STDMETHODCALLTYPE prof_ProfileName(void *t, void **s) { (void)t; *s = NULL; return S_OK; }  // empty HSTRING
static HRESULT STDMETHODCALLTYPE prof_Level(void *t, int *l) { (void)t; *l = g_netLevel; logf("fake ConnectionProfile level -> %d", g_netLevel); return S_OK; }
static HRESULT STDMETHODCALLTYPE prof_NotImpl(void *t) { (void)t; logf("fake ConnectionProfile: unimplemented call"); return E_NOTIMPL; }
static void *g_profVtbl[] = { prof_QI, prof_AddRef, prof_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  prof_ProfileName, prof_Level, prof_NotImpl, prof_NotImpl, prof_NotImpl, prof_NotImpl, prof_NotImpl, prof_NotImpl, prof_NotImpl };
static Obj g_profile = { g_profVtbl };

// The statics wrapper: slots 0-13 of INetworkInformationStatics, forwarded except 7 (GetInternetConnectionProfile).
typedef struct { void **vtbl; Obj *real; LONG refs; } NetStatics;
#define NS(t) ((NetStatics *)(t))
static HRESULT STDMETHODCALLTYPE ns_QI(void *t, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_INetworkInformationStatics) || IsEqualGUID(iid, &IID_IUnknown_) || IsEqualGUID(iid, &IID_IInspectable_)) {
    InterlockedIncrement(&NS(t)->refs); *out = t; return S_OK;
  }
  return VCALL(NS(t)->real, 0, HRESULT (STDMETHODCALLTYPE *)(void *, const GUID *, void **))(NS(t)->real, iid, out);
}
static ULONG STDMETHODCALLTYPE ns_AddRef(void *t) { return InterlockedIncrement(&NS(t)->refs); }
static ULONG STDMETHODCALLTYPE ns_Release(void *t) { return InterlockedDecrement(&NS(t)->refs); }  // never freed: the game may cache it
#define NS_FWD(slot) static HRESULT STDMETHODCALLTYPE ns_##slot(void *t, void *a, void *b, void *c) { \
  return VCALL(NS(t)->real, slot, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void *, void *))(NS(t)->real, a, b, c); }
NS_FWD(3) NS_FWD(4) NS_FWD(5) NS_FWD(6) NS_FWD(8) NS_FWD(9) NS_FWD(10) NS_FWD(11) NS_FWD(12) NS_FWD(13)
static HRESULT STDMETHODCALLTYPE ns_GetInternetConnectionProfile(void *t, void **out) {
  void *realProf = NULL;
  HRESULT hr = VCALL(NS(t)->real, 7, HRESULT (STDMETHODCALLTYPE *)(void *, void **))(NS(t)->real, &realProf);
  int lvl = -1;
  if (SUCCEEDED(hr) && realProf) {
    VCALL(realProf, 7, HRESULT (STDMETHODCALLTYPE *)(void *, int *))(realProf, &lvl);
    VCALL(realProf, 2, ULONG (STDMETHODCALLTYPE *)(void *))(realProf);
  }
  logf("GetInternetConnectionProfile: Azimuth says hr 0x%08lx profile %p level %d; answering a profile of level %d", hr, realProf, lvl, g_netLevel);
  *out = &g_profile;
  return S_OK;
}
static void *g_nsVtbl[] = { ns_QI, ns_AddRef, ns_Release, ns_3, ns_4, ns_5, ns_6, ns_GetInternetConnectionProfile, ns_8, ns_9, ns_10, ns_11, ns_12, ns_13 };

static int wrap_qos(const wchar_t *cls, GUID *iid, void **out);   // qos.c
static int wrap_json(const wchar_t *cls, GUID *iid, void **out);  // json.c
static int wrap_streams(const wchar_t *cls, GUID *iid, void **out);  // proxy.c
static int fix_streams(const wchar_t *cls, GUID *iid, void **out);   // streams.c
static int fix_party(const wchar_t *cls, GUID *iid, void **out);     // party.c
static int fix_association(const wchar_t *cls, GUID *iid, void **out);  // assoc.c
static void game_patches(void);                                         // patches.c
static void xuid_patch(void);                                           // patches.c

// vccorlib110: ?GetActivationFactoryByPCWSTR@@YAJPEAXAEAVGuid@Platform@@PEAPEAX@Z (name, iid, out)
typedef HRESULT (*GetAF_t)(void *, GUID *, void **);
static GetAF_t o_GetAF;
static HRESULT h_GetAF(void *name, GUID *iid, void **out) {
  HRESULT hr = o_GetAF(name, iid, out);
  char b[40]; guidstr(iid, b);
  const wchar_t *cls = name;
  if (wcscmp(cls, L"Windows.Xbox.Management.Deployment.PackageTransferManager"))
    logf("ActivationFactory %ls iid {%s} -> 0x%08lx ret %p", cls, b, hr, __builtin_return_address(0));
  if (g_netLevel && SUCCEEDED(hr) && *out && IsEqualGUID(iid, &IID_INetworkInformationStatics)
      && !wcscmp(cls, L"Windows.Networking.Connectivity.NetworkInformation")) {
    NetStatics *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
    w->vtbl = g_nsVtbl; w->real = *out; w->refs = 1;
    *out = w;
    logf("  wrapped NetworkInformation statics (level %d)", g_netLevel);
  }
  if (SUCCEEDED(hr)) { wrap_qos(cls, iid, out); wrap_json(cls, iid, out); if (!fix_party(cls, iid, out) && !fix_association(cls, iid, out) && !fix_streams(cls, iid, out)) wrap_streams(cls, iid, out); }
  return hr;
}

typedef void (WINAPI *ODSA_t)(LPCSTR);
typedef void (WINAPI *ODSW_t)(LPCWSTR);
static ODSA_t o_ODSA; static ODSW_t o_ODSW;
static void WINAPI h_ODSA(LPCSTR s) { if (s) logf("dbg %.*s", (int)strcspn(s, "\r\n"), s); o_ODSA(s); }
static void WINAPI h_ODSW(LPCWSTR s) { if (s) logf("dbgW %.*ls", (int)wcscspn(s, L"\r\n"), s); o_ODSW(s); }

typedef int (WSAAPI *getaddrinfo_t)(PCSTR, PCSTR, const ADDRINFOA *, PADDRINFOA *);
static getaddrinfo_t o_getaddrinfo;
static int WSAAPI h_getaddrinfo(PCSTR n, PCSTR s, const ADDRINFOA *h, PADDRINFOA *r) {
  int rc = o_getaddrinfo(n, s, h, r);
  char a[64] = "-"; if (rc == 0 && r && *r) addrstr((*r)->ai_addr, a, sizeof a);
  logf("getaddrinfo %s %s -> %d (%s) ret %p", n ? n : "(null)", s ? s : "", rc, a, __builtin_return_address(0));
  return rc;
}

typedef struct hostent *(WSAAPI *gethostbyname_t)(const char *);
static gethostbyname_t o_gethostbyname;
static struct hostent *WSAAPI h_gethostbyname(const char *n) {
  struct hostent *r = o_gethostbyname(n);
  logf("gethostbyname %s -> %p", n ? n : "(null)", r);
  return r;
}

typedef SOCKET (WSAAPI *socket_t)(int, int, int);
static socket_t o_socket;
static SOCKET WSAAPI h_socket(int af, int type, int proto) {
  SOCKET s = o_socket(af, type, proto);
  logf("socket af %d type %d proto %d -> %lld", af, type, proto, (long long)s);
  return s;
}

typedef SOCKET (WSAAPI *WSASocketW_t)(int, int, int, LPWSAPROTOCOL_INFOW, GROUP, DWORD);
static WSASocketW_t o_WSASocketW;
static SOCKET WSAAPI h_WSASocketW(int af, int type, int proto, LPWSAPROTOCOL_INFOW pi, GROUP g, DWORD f) {
  SOCKET s = o_WSASocketW(af, type, proto, pi, g, f);
  logf("WSASocketW af %d type %d proto %d flags 0x%lx -> %lld (err %d)", af, type, proto, f, (long long)s, s == INVALID_SOCKET ? WSAGetLastError() : 0);
  return s;
}

typedef int (WSAAPI *connect_t)(SOCKET, const struct sockaddr *, int);
static connect_t o_connect;
static int WSAAPI h_connect(SOCKET s, const struct sockaddr *sa, int len) {
  int rc = o_connect(s, sa, len);
  char a[64]; addrstr(sa, a, sizeof a);
  logf("connect %lld %s -> %d", (long long)s, a, rc);
  return rc;
}

typedef int (WSAAPI *bind_t)(SOCKET, const struct sockaddr *, int);
static bind_t o_bind;
static int WSAAPI h_bind(SOCKET s, const struct sockaddr *sa, int len) {
  // The game's UDP socket is IPv6 ([::]:5100) and Windows makes those IPv6-only: let it reach IPv4 hosts too
  // (as ::ffff:a.b.c.d), so [net] ServerAddress can be a LAN server's IPv4 address.
  if (sa && sa->sa_family == AF_INET6) {
    DWORD off = 0;
    setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, (const char *)&off, sizeof off);
  }
  int rc = o_bind(s, sa, len);
  char a[64]; addrstr(sa, a, sizeof a);
  logf("bind %lld %s -> %d", (long long)s, a, rc);
  return rc;
}

typedef int (WSAAPI *sendto_t)(SOCKET, const char *, int, int, const struct sockaddr *, int);
static sendto_t o_sendto;
static volatile LONG g_sendtoCount;
static int WSAAPI h_sendto(SOCKET s, const char *b, int n, int f, const struct sockaddr *sa, int len) {
  int rc = o_sendto(s, b, n, f, sa, len);
  if (InterlockedIncrement(&g_sendtoCount) <= 50) { char a[64]; addrstr(sa, a, sizeof a); logf("sendto %lld %d bytes %s -> %d", (long long)s, n, a, rc); }
  return rc;
}

typedef int (WSAAPI *WSAStartup_t)(WORD, LPWSADATA);
static WSAStartup_t o_WSAStartup;
static int WSAAPI h_WSAStartup(WORD v, LPWSADATA d) {
  int rc = o_WSAStartup(v, d);
  logf("WSAStartup 0x%04x -> %d", v, rc);
  return rc;
}

// ---- IAT patching ------------------------------------------------------------------------------

typedef struct { const char *dll, *name; void *hook; void **orig; WORD ord; } Hook;  // ord: also match this ordinal import
static Hook g_hooks[] = {
  { "combase.dll", "CoCreateInstance", h_CoCreateInstance, (void **)&o_CoCreateInstance },
  { "vccorlib110.dll", "?GetActivationFactoryByPCWSTR@@YAJPEAXAEAVGuid@Platform@@PEAPEAX@Z", h_GetAF, (void **)&o_GetAF },
  { "kernelx.dll", "OutputDebugStringA", h_ODSA, (void **)&o_ODSA },
  { "kernelx.dll", "OutputDebugStringW", h_ODSW, (void **)&o_ODSW },
  { "ws2_32.dll", "getaddrinfo", h_getaddrinfo, (void **)&o_getaddrinfo },
  { "ws2_32.dll", "gethostbyname", h_gethostbyname, (void **)&o_gethostbyname, 52 },
  { "ws2_32.dll", "socket", h_socket, (void **)&o_socket, 23 },
  { "ws2_32.dll", "WSASocketW", h_WSASocketW, (void **)&o_WSASocketW },
  { "ws2_32.dll", "connect", h_connect, (void **)&o_connect, 4 },
  { "ws2_32.dll", "bind", h_bind, (void **)&o_bind, 2 },
  { "ws2_32.dll", "sendto", h_sendto, (void **)&o_sendto, 20 },
  { "ws2_32.dll", "WSAStartup", h_WSAStartup, (void **)&o_WSAStartup, 115 },
};

static int readable(const void *p, SIZE_T n) {
  MEMORY_BASIC_INFORMATION mi;
  if (!VirtualQuery(p, &mi, sizeof mi) || mi.State != MEM_COMMIT) return 0;
  if (mi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return 0;
  return (const BYTE *)p + n <= (const BYTE *)mi.BaseAddress + mi.RegionSize;
}

// Patches one module's IAT; returns the number of entries hooked, or -1 while its imports aren't bound yet.
static int patch_iat(BYTE *base, const char *tag) {
  if (!readable(base, 0x1000)) return -1;
  IMAGE_DOS_HEADER *dos = (void *)base;
  if (dos->e_magic != IMAGE_DOS_SIGNATURE) return -1;
  IMAGE_NT_HEADERS64 *nt = (void *)(base + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE) return -1;
  IMAGE_DATA_DIRECTORY dd = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (!dd.VirtualAddress || !readable(base + dd.VirtualAddress, dd.Size)) return -1;
  int hooked = 0;
  for (IMAGE_IMPORT_DESCRIPTOR *d = (void *)(base + dd.VirtualAddress); d->Name; d++) {
    const char *dll = (const char *)(base + d->Name);
    ULONGLONG *names = (void *)(base + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk));
    void **iat = (void **)(base + d->FirstThunk);
    for (int k = 0; names[k]; k++) {
      int byOrd = IMAGE_SNAP_BY_ORDINAL64(names[k]);
      WORD ord = byOrd ? (WORD)IMAGE_ORDINAL64(names[k]) : 0;
      const char *fn = byOrd ? NULL : (const char *)((IMAGE_IMPORT_BY_NAME *)(base + names[k]))->Name;
      for (size_t h = 0; h < sizeof g_hooks / sizeof *g_hooks; h++) {
        if (_stricmp(dll, g_hooks[h].dll)) continue;
        if (byOrd ? (!g_hooks[h].ord || ord != g_hooks[h].ord) : strcmp(fn, g_hooks[h].name)) continue;
        fn = g_hooks[h].name;
        void *cur = iat[k];
        if (!cur || cur == (void *)names[k]) return -1;  // not bound yet
        if (cur == g_hooks[h].hook) continue;
        if (!*g_hooks[h].orig) *g_hooks[h].orig = cur;
        else if (*g_hooks[h].orig != cur) { logf("skipped %s %s!%s: bound to %p, not %p", tag, dll, fn, cur, *g_hooks[h].orig); continue; }
        DWORD old; VirtualProtect(&iat[k], 8, PAGE_READWRITE, &old);
        iat[k] = g_hooks[h].hook;
        VirtualProtect(&iat[k], 8, old, &old);
        logf("hooked %s %s!%s (was %p)", tag, dll, fn, cur);
        hooked++;
      }
    }
  }
  return hooked;
}

// The package's Xbox Live library, wherever Azimuth mapped it: an image whose export directory names it.
static BYTE *find_module(const char *exportName) {
  MEMORY_BASIC_INFORMATION mi;
  for (BYTE *p = (BYTE *)0x10000; VirtualQuery(p, &mi, sizeof mi); p = (BYTE *)mi.BaseAddress + mi.RegionSize) {
    if (mi.State != MEM_COMMIT || (mi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) || mi.BaseAddress != mi.AllocationBase) continue;
    BYTE *b = mi.BaseAddress;
    if (mi.RegionSize < 0x1000 || ((IMAGE_DOS_HEADER *)b)->e_magic != IMAGE_DOS_SIGNATURE) continue;
    LONG lfa = ((IMAGE_DOS_HEADER *)b)->e_lfanew;
    if (lfa <= 0 || lfa > 0xE00) continue;
    IMAGE_NT_HEADERS64 *nt = (void *)(b + lfa);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) continue;
    IMAGE_DATA_DIRECTORY dd = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];
    if (!dd.VirtualAddress || !readable(b + dd.VirtualAddress, sizeof(IMAGE_EXPORT_DIRECTORY))) continue;
    IMAGE_EXPORT_DIRECTORY *ed = (void *)(b + dd.VirtualAddress);
    if (ed->Name && readable(b + ed->Name, 32) && !_stricmp((const char *)(b + ed->Name), exportName)) return b;
  }
  return NULL;
}

#include "trace.c"
#include "input.c"

// A module's bound import, by name (to call Azimuth's own combase, whose HSTRINGs the game understands).
static void *iat_lookup(BYTE *base, const char *dllName, const char *fnName) {
  IMAGE_NT_HEADERS64 *nt = (void *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
  IMAGE_DATA_DIRECTORY dd = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  for (IMAGE_IMPORT_DESCRIPTOR *d = (void *)(base + dd.VirtualAddress); d->Name; d++) {
    if (_stricmp((const char *)(base + d->Name), dllName)) continue;
    ULONGLONG *names = (void *)(base + d->OriginalFirstThunk);
    for (int k = 0; names[k]; k++)
      if (!IMAGE_SNAP_BY_ORDINAL64(names[k]) && !strcmp((const char *)((IMAGE_IMPORT_BY_NAME *)(base + names[k]))->Name, fnName))
        return ((void **)(base + d->FirstThunk))[k];
  }
  return NULL;
}

// ---- real sockets -----------------------------------------------------------------------------------
// Azimuth answers the game's Winsock imports with offline stubs (WSASocketW fails with WSAENETDOWN, and
// bind / connect / sendto share one stub), so the game's network transport never starts. With
// [net] RealSockets=1 every ws2_32 import of the module goes to Windows' own ws2_32; where fh2net logs a
// call, its hook stays in the IAT and forwards to the real function.
static int g_realSockets;
static void real_sockets(BYTE *base, const char *tag) {
  HMODULE ws = LoadLibraryW(L"ws2_32.dll");
  IMAGE_NT_HEADERS64 *nt = (void *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
  IMAGE_DATA_DIRECTORY dd = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  int n = 0;
  for (IMAGE_IMPORT_DESCRIPTOR *d = (void *)(base + dd.VirtualAddress); d->Name; d++) {
    if (_stricmp((const char *)(base + d->Name), "ws2_32.dll")) continue;
    ULONGLONG *names = (void *)(base + d->OriginalFirstThunk);
    void **iat = (void **)(base + d->FirstThunk);
    for (int k = 0; names[k]; k++) {
      void *real = IMAGE_SNAP_BY_ORDINAL64(names[k])
        ? (void *)GetProcAddress(ws, MAKEINTRESOURCEA(IMAGE_ORDINAL64(names[k])))
        : (void *)GetProcAddress(ws, (const char *)((IMAGE_IMPORT_BY_NAME *)(base + names[k]))->Name);
      if (!real) continue;
      int hooked = 0;
      for (size_t h = 0; h < sizeof g_hooks / sizeof *g_hooks; h++)
        if (iat[k] == g_hooks[h].hook) { *g_hooks[h].orig = real; hooked = 1; }
      if (!hooked) {
        DWORD old; VirtualProtect(&iat[k], 8, PAGE_READWRITE, &old);
        iat[k] = real;
        VirtualProtect(&iat[k], 8, old, &old);
      }
      n++;
    }
  }
  logf("real sockets: %d ws2_32 imports of %s go to Windows' ws2_32", n, tag);
}

// ---- Xbox Live tokens --------------------------------------------------------------------------
// Azimuth's LocalUser answers GetTokenAndSignatureAsync (vtable slots 16-18) and LocalUserStatics
// GetTokenAndSignatureForAllUsersAsync (15-17) with an operation already failed with
// ERROR_NETWORK_UNREACHABLE. With [xbl] FakeToken=1 those slots answer an operation already completed
// with a made-up token, which only our own server will ever see.

typedef HRESULT (WINAPI *WindowsCreateString_t)(const wchar_t *, UINT32, void **);
typedef const wchar_t *(WINAPI *WindowsGetStringRawBuffer_t)(void *, UINT32 *);
static WindowsCreateString_t p_WindowsCreateString;
static WindowsGetStringRawBuffer_t p_WindowsGetStringRawBuffer;
static int g_fakeToken;
static wchar_t g_token[512];

static const wchar_t *hs(void *h) { return h && p_WindowsGetStringRawBuffer ? p_WindowsGetStringRawBuffer(h, NULL) : L""; }

static const GUID IID_IAsyncInfo = { 0x00000036, 0, 0, { 0xc0, 0, 0, 0, 0, 0, 0, 0x46 } };
static const GUID IID_IAgileObject_ = { 0x94ea2b94, 0xe9cc, 0x49e0, { 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 } };

// The result: Token and Signature (and any further string getter) all answer the token.
static HRESULT STDMETHODCALLTYPE res_QI(void *t, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_IUnknown_) || IsEqualGUID(iid, &IID_IInspectable_) || IsEqualGUID(iid, &IID_IAgileObject_)) { *out = t; return S_OK; }
  char b[40]; guidstr(iid, b); logf("token result QI {%s}: answered as the result interface", b);
  *out = t; return S_OK;
}
static HRESULT STDMETHODCALLTYPE res_String(void *t, void **out) { (void)t; return p_WindowsCreateString(g_token, (UINT32)wcslen(g_token), out); }
static void *g_resVtbl[] = { res_QI, prof_AddRef, prof_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  res_String, res_String, res_String, res_String, res_String, res_String };
static Obj g_result = { g_resVtbl };

// The completed operation: IAsyncOperation<GetTokenAndSignatureResult^> at +0, IAsyncInfo at +8.
typedef struct { void **vtbl; void **infoVtbl; LONG refs; Obj *handler; Obj *result; const char *what; } TokenOp;  // any completed operation
static TokenOp *op_of_info(void *i) { return (TokenOp *)((BYTE *)i - 8); }
static HRESULT STDMETHODCALLTYPE op_QI(void *t, const GUID *iid, void **out) {
  TokenOp *o = t;
  if (IsEqualGUID(iid, &IID_IAsyncInfo)) { *out = &o->infoVtbl; InterlockedIncrement(&o->refs); return S_OK; }
  if (iid->Data1 == 0x00000003 || iid->Data1 == 0x00000038 || iid->Data1 == 0x00000037) { *out = NULL; return E_NOINTERFACE; }  // IMarshal, IWeakReferenceSource, IWeakReference
  if (!IsEqualGUID(iid, &IID_IUnknown_) && !IsEqualGUID(iid, &IID_IInspectable_) && !IsEqualGUID(iid, &IID_IAgileObject_)) {
    char b[40]; guidstr(iid, b); logf("token operation QI {%s}: answered as the operation", b);
  }
  *out = t; InterlockedIncrement(&o->refs); return S_OK;
}
static ULONG STDMETHODCALLTYPE op_AddRef(void *t) { return InterlockedIncrement(&((TokenOp *)t)->refs); }
static ULONG STDMETHODCALLTYPE op_Release(void *t) {
  TokenOp *o = t; LONG r = InterlockedDecrement(&o->refs);
  if (!r) { if (o->handler) VCALL(o->handler, 2, ULONG (STDMETHODCALLTYPE *)(void *))(o->handler); HeapFree(GetProcessHeap(), 0, o); }
  return r;
}
static HRESULT STDMETHODCALLTYPE op_PutCompleted(void *t, Obj *h) {
  TokenOp *o = t;
  if (!h) return S_OK;
  VCALL(h, 1, ULONG (STDMETHODCALLTYPE *)(void *))(h);
  o->handler = h;
  logf("%s operation: completing", o->what);
  return VCALL(h, 3, HRESULT (STDMETHODCALLTYPE *)(void *, void *, int))(h, o, 1 /* Completed */);
}
static HRESULT STDMETHODCALLTYPE op_GetCompleted(void *t, Obj **h) {
  TokenOp *o = t; *h = o->handler;
  if (o->handler) VCALL(o->handler, 1, ULONG (STDMETHODCALLTYPE *)(void *))(o->handler);
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE op_GetResults(void *t, Obj **r) {
  TokenOp *o = t; *r = o->result;
  VCALL(o->result, 1, ULONG (STDMETHODCALLTYPE *)(void *))(o->result);
  logf("%s operation: results taken", o->what); return S_OK;
}
static void *g_opVtbl[] = { op_QI, op_AddRef, op_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  op_PutCompleted, op_GetCompleted, op_GetResults };

static HRESULT STDMETHODCALLTYPE inf_QI(void *t, const GUID *iid, void **out) { return op_QI(op_of_info(t), iid, out); }
static ULONG STDMETHODCALLTYPE inf_AddRef(void *t) { return op_AddRef(op_of_info(t)); }
static ULONG STDMETHODCALLTYPE inf_Release(void *t) { return op_Release(op_of_info(t)); }
static HRESULT STDMETHODCALLTYPE inf_Id(void *t, UINT32 *id) { (void)t; *id = 1; return S_OK; }
static HRESULT STDMETHODCALLTYPE inf_Status(void *t, int *s) { (void)t; *s = 1; return S_OK; }
static HRESULT STDMETHODCALLTYPE inf_Error(void *t, HRESULT *e) { (void)t; *e = S_OK; return S_OK; }
static HRESULT STDMETHODCALLTYPE inf_Nop(void *t) { (void)t; return S_OK; }
static void *g_infVtbl[] = { inf_QI, inf_AddRef, inf_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  inf_Id, inf_Status, inf_Error, inf_Nop, inf_Nop };

static HRESULT token_op(const char *who, void *method, void *url, void **out) {
  logf("%s %ls %ls -> fake token", who, hs(method), hs(url));
  TokenOp *o = HeapAlloc(GetProcessHeap(), 0, sizeof *o);
  o->vtbl = g_opVtbl; o->infoVtbl = g_infVtbl; o->refs = 1; o->handler = NULL; o->result = &g_result; o->what = "token";
  *out = o;
  return S_OK;
}
// (method, url, headers, out); (method, url, headers, bodySize, body, out); (method, url, headers, IBuffer body, out)
static HRESULT STDMETHODCALLTYPE u_tok(void *t, void *m, void *u, void *h, void **out) { (void)t; (void)h; return token_op("User.GetTokenAndSignatureAsync", m, u, out); }
static HRESULT STDMETHODCALLTYPE u_tokArr(void *t, void *m, void *u, void *h, UINT32 n, void *b, void **out) { (void)t; (void)h; (void)n; (void)b; return token_op("User.GetTokenAndSignatureAsync(body)", m, u, out); }
static HRESULT STDMETHODCALLTYPE u_tokBuf(void *t, void *m, void *u, void *h, void *b, void **out) { (void)t; (void)h; (void)b; return token_op("User.GetTokenAndSignatureAsync(buffer)", m, u, out); }
static HRESULT STDMETHODCALLTYPE s_tok(void *t, void *m, void *u, void *h, void **out) { (void)t; (void)h; return token_op("User.GetTokenAndSignatureForAllUsersAsync", m, u, out); }
static HRESULT STDMETHODCALLTYPE s_tokArr(void *t, void *m, void *u, void *h, UINT32 n, void *b, void **out) { (void)t; (void)h; (void)n; (void)b; return token_op("User.GetTokenAndSignatureForAllUsersAsync(body)", m, u, out); }
static HRESULT STDMETHODCALLTYPE s_tokBuf(void *t, void *m, void *u, void *h, void *b, void **out) { (void)t; (void)h; (void)b; return token_op("User.GetTokenAndSignatureForAllUsersAsync(buffer)", m, u, out); }

#include "qos.c"
#include "json.c"
#include "proxy.c"
#include "streams.c"
#include "party.c"
#include "assoc.c"
#include "patches.c"

// Azimuth 0.9.7's vtables (RVAs in azimuth.exe), checked slot by slot before patching.
typedef struct { DWORD table; int slot; DWORD expect; void *fn; } VtPatch;
static const VtPatch g_tokenPatches[] = {
  { 0x24FF10, 16, 0x239B0, u_tok }, { 0x24FF10, 17, 0x239D0, u_tokArr }, { 0x24FF10, 18, 0x23A20, u_tokBuf },
  { 0x250218, 15, 0x23EE0, s_tok }, { 0x250218, 16, 0x23F00, s_tokArr }, { 0x250218, 17, 0x23F50, s_tokBuf },
};

static void install_token_hooks(void) {
  p_WindowsCreateString = iat_lookup(GAME_BASE, "combase.dll", "WindowsCreateString");
  p_WindowsGetStringRawBuffer = iat_lookup(GAME_BASE, "combase.dll", "WindowsGetStringRawBuffer");
  if (!p_WindowsCreateString || !p_WindowsGetStringRawBuffer) { logf("token hooks: the game's HSTRING functions weren't found"); return; }
  BYTE *az = (BYTE *)GetModuleHandleW(NULL);
  size_t n = sizeof g_tokenPatches / sizeof *g_tokenPatches;
  for (size_t i = 0; i < n; i++) {
    void **slot = (void **)(az + g_tokenPatches[i].table) + g_tokenPatches[i].slot;
    if (*slot != az + g_tokenPatches[i].expect) { logf("token hooks: not Azimuth 0.9.7's layout (table %X slot %d is %p); none installed", g_tokenPatches[i].table, g_tokenPatches[i].slot, *slot); return; }
  }
  for (size_t i = 0; i < n; i++) {
    void **slot = (void **)(az + g_tokenPatches[i].table) + g_tokenPatches[i].slot;
    DWORD old; VirtualProtect(slot, 8, PAGE_READWRITE, &old);
    *slot = g_tokenPatches[i].fn;
    VirtualProtect(slot, 8, old, &old);
  }
  logf("token hooks installed (token \"%ls\")", g_token);
}

static DWORD WINAPI worker(LPVOID p) {
  (void)p;
  logf("waiting for the game image at %p", GAME_BASE);
  int i;
  for (i = 0; i < 600000; i++) {   // up to ~10 minutes at 1 ms
    int n = patch_iat(GAME_BASE, "game");
    if (n >= 0) { logf("game imports bound; %d hooks installed after %d polls", n, i); break; }
    Sleep(1);
  }
  if (g_realSockets) real_sockets(GAME_BASE, "the game");
  if (g_fakeToken) install_token_hooks();
  game_patches();
  trace_install(L"Game", GAME_BASE, 0x140000000ULL, "game");
  xhr_init();
  for (i = 0; i < 6000; i++) {     // up to ~10 minutes at 100 ms
    BYTE *x = find_module("Microsoft.Xbox.Services.dll");
    if (x) {
      int n = patch_iat(x, "xsapi");
      if (n >= 0) { logf("Microsoft.Xbox.Services.dll at %p; %d hooks installed", x, n); trace_install(L"Xsapi", x, 0x180000000ULL, "xsapi"); break; }
    }
    Sleep(100);
  }
  return 0;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID r) {
  (void)r;
  if (reason != DLL_PROCESS_ATTACH) return TRUE;
  DisableThreadLibraryCalls(inst);
  InitializeCriticalSection(&g_logLock);
  QueryPerformanceFrequency(&g_freq); QueryPerformanceCounter(&g_t0);
  wchar_t path[MAX_PATH]; GetModuleFileNameW(inst, path, MAX_PATH);
  wchar_t *slash = wcsrchr(path, L'\\'); if (slash) slash[1] = 0;
  wchar_t logp[MAX_PATH], next[MAX_PATH];
  _snwprintf(logp, MAX_PATH, L"%lsfh2net.log", path);
  _snwprintf(next, MAX_PATH, L"%lsazimuth-tls-next.dll", path);
  g_log = CreateFileW(logp, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  SYSTEMTIME st; GetLocalTime(&st);
  logf("fh2net probe loaded %04d-%02d-%02d %02d:%02d:%02d", st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
  _snwprintf(g_ini, MAX_PATH, L"%lsfh2net.ini", path);
  g_netLevel = GetPrivateProfileIntW(L"net", L"ConnectivityLevel", 0, g_ini);
  g_fakeToken = GetPrivateProfileIntW(L"xbl", L"FakeToken", 0, g_ini);
  GetPrivateProfileStringW(L"xbl", L"Token", L"XBL3.0 x=1234567890;fh2net", g_token, 512, g_ini);
  GetPrivateProfileStringW(L"http", L"Server", L"", g_httpServer, 256, g_ini);
  GetPrivateProfileStringW(L"xbl", L"Xuid", L"2533274790395904", g_xuid, 32, g_ini);
  GetPrivateProfileStringW(L"xbl", L"Gamertag", L"", g_gamertag, 64, g_ini);
  if (!g_gamertag[0]) {   // Azimuth's player name, from data\azimuth.ini next to data\bin
    wchar_t az[MAX_PATH]; _snwprintf(az, MAX_PATH, L"%ls..\\azimuth.ini", path);
    GetPrivateProfileStringW(L"launcher", L"player_name", L"Player 1", g_gamertag, 64, az);
  }
  logf("player: xuid %ls, gamertag %ls", g_xuid, g_gamertag);
  g_fakeQos = GetPrivateProfileIntW(L"net", L"FakeQos", 0, g_ini);
  g_debugJson = GetPrivateProfileIntW(L"debug", L"Json", 0, g_ini);
  g_debugStreams = GetPrivateProfileIntW(L"debug", L"Streams", 0, g_ini);
  g_debugParty = GetPrivateProfileIntW(L"debug", L"Party", 0, g_ini);
  g_fixStreams = GetPrivateProfileIntW(L"net", L"FixStreams", 0, g_ini);
  g_realSockets = GetPrivateProfileIntW(L"net", L"RealSockets", 0, g_ini);
  g_fakeParty = GetPrivateProfileIntW(L"net", L"FakeParty", 0, g_ini);
  g_fakeAssociation = GetPrivateProfileIntW(L"net", L"FakeAssociation", 0, g_ini);
  g_skipWeatherWait = GetPrivateProfileIntW(L"net", L"SkipWeatherWait", 0, g_ini);
  GetPrivateProfileStringW(L"net", L"ServerAddress", L"::1", g_serverIp6, 64, g_ini);
  g_serverPort = GetPrivateProfileIntW(L"net", L"ServerPort", 5101, g_ini);
  GetPrivateProfileStringW(L"net", L"LocalAddress", L"", g_localAddress, 256, g_ini);
  logf("settings: ConnectivityLevel=%d FakeToken=%d FakeQos=%d FixStreams=%d Server=%ls", g_netLevel, g_fakeToken, g_fakeQos, g_fixStreams, g_httpServer);
  // The forwarded exports resolve against this module once it is loaded under its own name.
  HMODULE nx = LoadLibraryW(next);
  logf("azimuth-tls-next.dll -> %p (err %lu)", nx, nx ? 0 : GetLastError());
  xuid_patch();
  input_install(path);
  CloseHandle(CreateThread(NULL, 0, worker, NULL, 0, NULL));
  return TRUE;
}
