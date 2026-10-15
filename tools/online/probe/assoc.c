// Included by fh2net.c after party.c. Windows.Xbox.Networking.SecureDeviceAssociationTemplate: joining a
// session makes the game (SecureIPResolver, 1417A0FF0) call the template's CreateAssociationAsync (slot 8:
// remote SecureDeviceAddress, behavior, out operation) for the server's address, which Azimuth answers by
// stopping the process ("offline secure association creation"). With [net] FakeAssociation=1 the statics
// ({46745a18-...}) are wrapped, GetTemplateByName (slot 6) hands out a wrapped template, and slot 8 answers a
// completed operation whose result is, for now, a logging probe - to learn what the game uses on it.

static int g_fakeAssociation;
static const GUID IID_ISecureDeviceAssociationTemplateStatics = { 0x46745a18, 0x697a, 0x47e1, { 0xbb, 0x62, 0xcc, 0x71, 0xde, 0x0f, 0xdd, 0x8c } };
static wchar_t g_serverIp6[64];   // [net] ServerAddress= (IPv6, default ::1), ServerPort= (default 5101)
static int g_serverPort;

// The association. Slot 9 (GetRemoteSocketAddressBytes: array length, bytes) answers the server's
// sockaddr_in6 - the game's own socket is IPv6, bound to [::]:5100 (the manifest's SecureConsoleSocket).
// Slot 8 (DestroyAsync) answers a completed action; every other slot is still a logging probe.
static HRESULT STDMETHODCALLTYPE sda_RemoteBytes(Probe *t, UINT32 len, BYTE *bytes) {
  (void)t;
  struct sockaddr_in6 a = { 0 };
  a.sin6_family = AF_INET6; a.sin6_port = htons((u_short)g_serverPort);
  if (InetPtonW(AF_INET6, g_serverIp6, &a.sin6_addr) != 1) logf("association: bad ServerAddress %ls", g_serverIp6);
  if (len < sizeof a) { logf("association: remote address asked into %u bytes", len); return E_INVALIDARG; }
  memset(bytes, 0, len); memcpy(bytes, &a, sizeof a);
  logf("association: remote socket address [%ls]:%d", g_serverIp6, g_serverPort);
  return S_OK;
}
// Slot 8 (DestroyAsync, out IAsyncAction): the game leaving the session (14179EA70) - a completed action.
static HRESULT STDMETHODCALLTYPE sda_Destroy(Probe *t, void **out) {
  (void)t; logf("association: DestroyAsync -> completed"); *out = completed_action("SecureDeviceAssociation.Destroy"); return S_OK;
}
static void *g_sdaVtbl[] = { pr_QI, pr_AddRef, pr_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  pr_6, pr_7, sda_Destroy, sda_RemoteBytes, pr_10, pr_11, pr_12, pr_13, pr_14, pr_15, pr_16, pr_17, pr_18, pr_19, pr_20, pr_21, pr_22, pr_23 };
static Probe g_assocProbe = { g_sdaVtbl, "SecureDeviceAssociation" };

// An IAsyncOperation<T> already completed with `result` (the token operation's object).
static void *completed_op(Obj *result, const char *what) {
  TokenOp *o = HeapAlloc(GetProcessHeap(), 0, sizeof *o);
  o->vtbl = g_opVtbl; o->infoVtbl = g_infVtbl; o->refs = 1; o->handler = NULL; o->result = result; o->what = what;
  return o;
}

// The template: every slot but 8 is forwarded to Azimuth's (and logged).
typedef struct { void **vtbl; Obj *real; LONG refs; } TplWrap;
#define TW(t) ((TplWrap *)(t))
static HRESULT STDMETHODCALLTYPE tw_QI(void *t, const GUID *iid, void **out) {
  HRESULT hr = VCALL(TW(t)->real, 0, QIfn)(TW(t)->real, iid, out);
  char b[40]; guidstr(iid, b); logf("association template QI {%s} -> 0x%08lx", b, hr);
  if (SUCCEEDED(hr) && *out == TW(t)->real) *out = t;
  return hr;
}
static ULONG STDMETHODCALLTYPE tw_AddRef(void *t) { return InterlockedIncrement(&TW(t)->refs); }
static ULONG STDMETHODCALLTYPE tw_Release(void *t) { return InterlockedDecrement(&TW(t)->refs); }  // never freed: the game keeps it
#define TW_FWD(n) static HRESULT STDMETHODCALLTYPE tw_##n(void *t, void *a, void *b, void *c, void *d, void *e, void *f) { \
  HRESULT hr = VCALL(TW(t)->real, n, Fwd6)(TW(t)->real, a, b, c, d, e, f); \
  logf("association template slot %d (%p %p %p) -> 0x%08lx, called from %p", n, a, b, c, hr, __builtin_return_address(0)); return hr; }
TW_FWD(3) TW_FWD(4) TW_FWD(5) TW_FWD(6) TW_FWD(7) TW_FWD(9) TW_FWD(10) TW_FWD(11) TW_FWD(12) TW_FWD(13) TW_FWD(14) TW_FWD(15)
static HRESULT STDMETHODCALLTYPE tw_Create(void *t, Obj *remote, int behavior, void **out) {
  (void)t;
  void *s = NULL; if (remote) VCALL(remote, 10, HRESULT (STDMETHODCALLTYPE *)(void *, void **))(remote, &s);
  logf("SecureDeviceAssociationTemplate.CreateAssociationAsync(%ls, behavior %d) -> completed, called from %p", s ? hs(s) : L"?", behavior, __builtin_return_address(0));
  *out = completed_op((Obj *)&g_assocProbe, "CreateAssociation");
  return S_OK;
}
static void *g_twVtbl[] = { tw_QI, tw_AddRef, tw_Release, tw_3, tw_4, tw_5, tw_6, tw_7, tw_Create, tw_9, tw_10, tw_11, tw_12,
  tw_13, tw_14, tw_15 };

// The statics: GetTemplateByName (slot 6) wraps the template Azimuth answers.
#define AS(t) ((QosStatics *)(t))
#define AS_FWD(n) static HRESULT STDMETHODCALLTYPE as_##n(void *t, void *a, void *b, void *c, void *d, void *e, void *f) { \
  HRESULT hr = VCALL(AS(t)->real, n, Fwd6)(AS(t)->real, a, b, c, d, e, f); \
  logf("association statics slot %d -> 0x%08lx", n, hr); return hr; }
AS_FWD(3) AS_FWD(4) AS_FWD(5) AS_FWD(7) AS_FWD(8) AS_FWD(9)
static HRESULT STDMETHODCALLTYPE as_QI(void *t, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_ISecureDeviceAssociationTemplateStatics) || IsEqualGUID(iid, &IID_IUnknown_) || IsEqualGUID(iid, &IID_IInspectable_)) {
    InterlockedIncrement(&AS(t)->refs); *out = t; return S_OK;
  }
  return VCALL(AS(t)->real, 0, QIfn)(AS(t)->real, iid, out);
}
static HRESULT STDMETHODCALLTYPE as_GetTemplateByName(void *t, void *name, void **out) {
  HRESULT hr = VCALL(AS(t)->real, 6, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void **))(AS(t)->real, name, out);
  logf("SecureDeviceAssociationTemplate.GetTemplateByName(%ls) -> 0x%08lx %p (wrapped)", hs(name), hr, SUCCEEDED(hr) ? *out : NULL);
  if (SUCCEEDED(hr) && *out) {
    TplWrap *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
    w->vtbl = g_twVtbl; w->real = *out; w->refs = 1;
    *out = w;
  }
  return hr;
}
static void *g_asVtbl[] = { as_QI, qs_AddRef, qs_Release, as_3, as_4, as_5, as_GetTemplateByName, as_7, as_8, as_9 };

static int fix_association(const wchar_t *cls, GUID *iid, void **out) {
  if (!g_fakeAssociation || !*out || !IsEqualGUID(iid, &IID_ISecureDeviceAssociationTemplateStatics)
      || wcscmp(cls, L"Windows.Xbox.Networking.SecureDeviceAssociationTemplate")) return 0;
  QosStatics *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
  w->vtbl = g_asVtbl; w->real = *out; w->refs = 1;
  *out = w;
  logf("  wrapped SecureDeviceAssociationTemplate statics");
  return 1;
}
