// Included by fh2net.c after proxy.c. Windows.Xbox.Multiplayer.Party, which Azimuth answers offline: with
// [net] FakeParty=1 the IPartyStatics ({e6110c4c-...}) are wrapped, and slots 6 and 7 - which the game calls
// with (user, session reference) after writing its game and match sessions (RegisterGameSessionAsync /
// RegisterMatchSessionAsync) - answer an IAsyncAction already completed successfully. Azimuth's actions
// complete with an error, which fails the session activity (1417AE470) before the server is allocated.

static int g_fakeParty;
static const GUID IID_IPartyStatics = { 0xe6110c4c, 0x3660, 0x4230, { 0x98, 0x80, 0x20, 0x8b, 0x14, 0x9a, 0x3c, 0xa4 } };

// IAsyncAction: put_Completed 6, get_Completed 7, GetResults 8 (no result). Same object layout as TokenOp.
static HRESULT STDMETHODCALLTYPE act_GetResults(void *t) { (void)t; return S_OK; }
static void *g_actVtbl[] = { op_QI, op_AddRef, op_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  op_PutCompleted, op_GetCompleted, act_GetResults };

static void *completed_action(const char *what) {
  TokenOp *o = HeapAlloc(GetProcessHeap(), 0, sizeof *o);
  o->vtbl = g_actVtbl; o->infoVtbl = g_infVtbl; o->refs = 1; o->handler = NULL; o->result = &g_result; o->what = what;
  return o;
}

#define PS(t) ((QosStatics *)(t))
#define PS_FWD(slot) static HRESULT STDMETHODCALLTYPE ps_##slot(void *t, void *a, void *b, void *c, void *d, void *e, void *f) { \
  return VCALL(PS(t)->real, slot, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void *, void *, void *, void *, void *))(PS(t)->real, a, b, c, d, e, f); }
PS_FWD(3) PS_FWD(4) PS_FWD(5) PS_FWD(8) PS_FWD(9) PS_FWD(10) PS_FWD(11) PS_FWD(12) PS_FWD(13) PS_FWD(14) PS_FWD(15) PS_FWD(16)
PS_FWD(17) PS_FWD(18) PS_FWD(19) PS_FWD(20) PS_FWD(21) PS_FWD(22) PS_FWD(23) PS_FWD(24) PS_FWD(25) PS_FWD(26) PS_FWD(27)
static HRESULT STDMETHODCALLTYPE ps_QI(void *t, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_IPartyStatics) || IsEqualGUID(iid, &IID_IUnknown_) || IsEqualGUID(iid, &IID_IInspectable_)) {
    InterlockedIncrement(&PS(t)->refs); *out = t; return S_OK;
  }
  return VCALL(PS(t)->real, 0, HRESULT (STDMETHODCALLTYPE *)(void *, const GUID *, void **))(PS(t)->real, iid, out);
}
static HRESULT STDMETHODCALLTYPE ps_Register6(void *t, void *user, void *ref, void **out) {
  (void)t; logf("Party slot 6 (user %p, session %p): register game session -> completed", user, ref);
  *out = completed_action("Party.RegisterGameSession"); return S_OK;
}
static HRESULT STDMETHODCALLTYPE ps_Register7(void *t, void *user, void *ref, void **out) {
  (void)t; logf("Party slot 7 (user %p, session %p): register match session -> completed", user, ref);
  *out = completed_action("Party.RegisterMatchSession"); return S_OK;
}
static void *g_psVtbl[] = { ps_QI, qs_AddRef, qs_Release, ps_3, ps_4, ps_5, ps_Register6, ps_Register7, ps_8, ps_9, ps_10,
  ps_11, ps_12, ps_13, ps_14, ps_15, ps_16, ps_17, ps_18, ps_19, ps_20, ps_21, ps_22, ps_23, ps_24, ps_25, ps_26, ps_27 };

static int fix_party(const wchar_t *cls, GUID *iid, void **out) {
  if (!g_fakeParty || !*out || !IsEqualGUID(iid, &IID_IPartyStatics) || wcscmp(cls, L"Windows.Xbox.Multiplayer.Party")) return 0;
  QosStatics *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
  w->vtbl = g_psVtbl; w->real = *out; w->refs = 1;
  *out = w;
  return 1;
}
