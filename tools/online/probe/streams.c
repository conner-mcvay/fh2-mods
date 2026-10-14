// Included by fh2net.c after proxy.c. Windows.Storage.Streams for the Xbox Live library, whose reply bodies
// Azimuth's DataWriter loses (WriteBytes succeeds, DetachBuffer answers a buffer of length 0, so every reply
// reads as empty). With [net] FixStreams=1:
// - DataWriter (IActivationFactory.ActivateInstance) is ours: IDataWriter {64b89265-...}; WriteBytes (12)
//   appends, UnstoredBufferLength (6) answers the size, DetachBuffer (31) hands the bytes over as our Buffer.
//   That's all the library uses; other slots log and fail.
// - Buffer: IBuffer {905a0fe0-...} (Capacity 6, Length 7/8) and IBufferByteAccess {905a0fef-...} (Buffer 3).
// - DataReader.FromBuffer (IDataReaderStatics slot 6) on one of our buffers answers our reader: IDataReader
//   UnconsumedBufferLength (6), UnicodeEncoding (7/8), ByteOrder (9/10), InputStreamOptions (11/12),
//   ReadByte (13), ReadBytes (14), ReadString (26, UTF-8 or UTF-16LE). Other buffers go to Azimuth's.

static int g_fixStreams;
static const GUID IID_IDataWriter = { 0x64b89265, 0xd341, 0x4922, { 0xb3, 0x8a, 0xdd, 0x4a, 0xf8, 0x80, 0x8c, 0x4e } };
static const GUID IID_IBuffer = { 0x905a0fe0, 0xbc53, 0x11df, { 0x8c, 0x49, 0x00, 0x1e, 0x4f, 0xc6, 0x86, 0xda } };
static const GUID IID_IBufferByteAccess = { 0x905a0fef, 0xbc53, 0x11df, { 0x8c, 0x49, 0x00, 0x1e, 0x4f, 0xc6, 0x86, 0xda } };
static const GUID IID_IDataReader = { 0xe2b50029, 0xb4c1, 0x4314, { 0xa4, 0xb8, 0x68, 0xa2, 0x40, 0xd4, 0x46, 0x95 } };
static const GUID IID_IDataReaderStatics = { 0x11fcbfc8, 0xf93a, 0x471b, { 0xb1, 0x21, 0xf3, 0x79, 0xe3, 0x49, 0x31, 0x3c } };
static const GUID IID_IClosable = { 0x30d5a829, 0x7fa4, 0x4026, { 0x83, 0xbb, 0xd7, 0x5b, 0xae, 0x4e, 0xa9, 0x9e } };

static int is_unknownish(const GUID *iid) {
  return IsEqualGUID(iid, &IID_IUnknown_) || IsEqualGUID(iid, &IID_IInspectable_) || IsEqualGUID(iid, &IID_IAgileObject_);
}
static void log_noiface(const char *what, const GUID *iid) { char b[40]; guidstr(iid, b); logf("%s QI {%s}: no", what, b); }

// ---- Buffer -----------------------------------------------------------------------------------------
typedef struct { void **vtbl; void **byteVtbl; LONG refs; BYTE *data; UINT32 len, cap; } SBuffer;
static void **g_sbVtblPtr;   // identifies our buffers
static SBuffer *sb_of_bytes(void *t) { return (SBuffer *)((BYTE *)t - 8); }
static HRESULT STDMETHODCALLTYPE sb_QI(void *t, const GUID *iid, void **out) {
  SBuffer *b = t;
  if (IsEqualGUID(iid, &IID_IBuffer) || is_unknownish(iid)) { *out = b; InterlockedIncrement(&b->refs); return S_OK; }
  if (IsEqualGUID(iid, &IID_IBufferByteAccess)) { *out = &b->byteVtbl; InterlockedIncrement(&b->refs); return S_OK; }
  log_noiface("Buffer", iid); *out = NULL; return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE sb_AddRef(void *t) { return InterlockedIncrement(&((SBuffer *)t)->refs); }
static ULONG STDMETHODCALLTYPE sb_Release(void *t) {
  SBuffer *b = t; LONG r = InterlockedDecrement(&b->refs);
  if (!r) { xfree(b->data); xfree(b); }
  return r;
}
static HRESULT STDMETHODCALLTYPE sb_Capacity(void *t, UINT32 *v) { *v = ((SBuffer *)t)->cap; return S_OK; }
static HRESULT STDMETHODCALLTYPE sb_Length(void *t, UINT32 *v) { *v = ((SBuffer *)t)->len; return S_OK; }
static HRESULT STDMETHODCALLTYPE sb_PutLength(void *t, UINT32 v) { SBuffer *b = t; if (v > b->cap) return E_INVALIDARG; b->len = v; return S_OK; }
static void *g_sbVtbl[] = { sb_QI, sb_AddRef, sb_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  sb_Capacity, sb_Length, sb_PutLength };
static HRESULT STDMETHODCALLTYPE sba_QI(void *t, const GUID *iid, void **out) { return sb_QI(sb_of_bytes(t), iid, out); }
static ULONG STDMETHODCALLTYPE sba_AddRef(void *t) { return sb_AddRef(sb_of_bytes(t)); }
static ULONG STDMETHODCALLTYPE sba_Release(void *t) { return sb_Release(sb_of_bytes(t)); }
static HRESULT STDMETHODCALLTYPE sba_Buffer(void *t, BYTE **p) { *p = sb_of_bytes(t)->data; return S_OK; }
static void *g_sbaVtbl[] = { sba_QI, sba_AddRef, sba_Release, sba_Buffer };

static SBuffer *sbuffer_new(BYTE *data, UINT32 len) {   // takes ownership of data (HeapAlloc'd)
  SBuffer *b = heap(sizeof *b);
  b->vtbl = g_sbVtbl; b->byteVtbl = g_sbaVtbl; b->refs = 1; b->data = data ? data : heap(1); b->len = b->cap = len;
  g_sbVtblPtr = g_sbVtbl;
  return b;
}

// ---- DataWriter ---------------------------------------------------------------------------------------
typedef struct { void **vtbl; LONG refs; BYTE *data; UINT32 len, cap; } SWriter;
static HRESULT STDMETHODCALLTYPE sw_QI(void *t, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_IDataWriter) || IsEqualGUID(iid, &IID_IClosable) || is_unknownish(iid)) {
    *out = t; InterlockedIncrement(&((SWriter *)t)->refs); return S_OK;   // IClosable.Close is slot 6 too: harmless here
  }
  log_noiface("DataWriter", iid); *out = NULL; return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE sw_AddRef(void *t) { return InterlockedIncrement(&((SWriter *)t)->refs); }
static ULONG STDMETHODCALLTYPE sw_Release(void *t) {
  SWriter *w = t; LONG r = InterlockedDecrement(&w->refs);
  if (!r) { xfree(w->data); xfree(w); }
  return r;
}
static HRESULT STDMETHODCALLTYPE sw_Unstored(void *t, UINT32 *v) { *v = ((SWriter *)t)->len; return S_OK; }
static HRESULT STDMETHODCALLTYPE sw_WriteBytes(void *t, UINT32 n, const BYTE *p) {
  SWriter *w = t;
  if (w->len + n > w->cap) {
    UINT32 cap = (w->len + n) * 2 + 256;
    BYTE *d = heap(cap); if (w->data) { memcpy(d, w->data, w->len); xfree(w->data); }
    w->data = d; w->cap = cap;
  }
  memcpy(w->data + w->len, p, n); w->len += n;
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE sw_Detach(void *t, void **out) {
  SWriter *w = t;
  *out = sbuffer_new(w->data, w->len);
  w->data = NULL; w->len = w->cap = 0;
  return S_OK;
}
#define SW_NOT(n) static HRESULT STDMETHODCALLTYPE sw_##n(void *t) { (void)t; logf("our DataWriter: slot %d not implemented", n); return E_NOTIMPL; }
SW_NOT(7) SW_NOT(8) SW_NOT(9) SW_NOT(10) SW_NOT(11) SW_NOT(13) SW_NOT(14) SW_NOT(15) SW_NOT(16) SW_NOT(17) SW_NOT(18)
SW_NOT(19) SW_NOT(20) SW_NOT(21) SW_NOT(22) SW_NOT(23) SW_NOT(24) SW_NOT(25) SW_NOT(26) SW_NOT(27) SW_NOT(28)
SW_NOT(29) SW_NOT(30) SW_NOT(32)
static void *g_swVtbl[] = { sw_QI, sw_AddRef, sw_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  sw_Unstored, sw_7, sw_8, sw_9, sw_10, sw_11, sw_WriteBytes, sw_13, sw_14, sw_15, sw_16, sw_17, sw_18, sw_19, sw_20,
  sw_21, sw_22, sw_23, sw_24, sw_25, sw_26, sw_27, sw_28, sw_29, sw_30, sw_Detach, sw_32 };

// The DataWriter factory: ActivateInstance (6) makes ours; the rest goes to Azimuth's factory.
static HRESULT STDMETHODCALLTYPE swf_Activate(void *t, void **out) {
  (void)t;
  SWriter *w = heap(sizeof *w); w->vtbl = g_swVtbl; w->refs = 1;
  *out = w; return S_OK;
}
static void *g_swfVtbl[] = { fw_QI, fw_AddRef, fw_Release, fw_3, fw_4, fw_5, swf_Activate };

// ---- DataReader -----------------------------------------------------------------------------------------
typedef struct { void **vtbl; LONG refs; SBuffer *buf; UINT32 pos; int encoding, order, options; } SReader;
static HRESULT STDMETHODCALLTYPE sr_QI(void *t, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_IDataReader) || IsEqualGUID(iid, &IID_IClosable) || is_unknownish(iid)) {
    *out = t; InterlockedIncrement(&((SReader *)t)->refs); return S_OK;
  }
  log_noiface("DataReader", iid); *out = NULL; return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE sr_AddRef(void *t) { return InterlockedIncrement(&((SReader *)t)->refs); }
static ULONG STDMETHODCALLTYPE sr_Release(void *t) {
  SReader *r = t; LONG n = InterlockedDecrement(&r->refs);
  if (!n) { sb_Release(r->buf); xfree(r); }
  return n;
}
static HRESULT STDMETHODCALLTYPE sr_Unconsumed(SReader *t, UINT32 *v) { *v = t->buf->len - t->pos; return S_OK; }
static HRESULT STDMETHODCALLTYPE sr_GetEnc(SReader *t, int *v) { *v = t->encoding; return S_OK; }
static HRESULT STDMETHODCALLTYPE sr_PutEnc(SReader *t, int v) { t->encoding = v; return S_OK; }
static HRESULT STDMETHODCALLTYPE sr_GetOrder(SReader *t, int *v) { *v = t->order; return S_OK; }
static HRESULT STDMETHODCALLTYPE sr_PutOrder(SReader *t, int v) { t->order = v; return S_OK; }
static HRESULT STDMETHODCALLTYPE sr_GetOpt(SReader *t, int *v) { *v = t->options; return S_OK; }
static HRESULT STDMETHODCALLTYPE sr_PutOpt(SReader *t, int v) { t->options = v; return S_OK; }
static HRESULT STDMETHODCALLTYPE sr_ReadByte(SReader *t, BYTE *v) {
  if (t->pos >= t->buf->len) return E_BOUNDS;
  *v = t->buf->data[t->pos++]; return S_OK;
}
static HRESULT STDMETHODCALLTYPE sr_ReadBytes(SReader *t, UINT32 n, BYTE *v) {
  if (t->pos + n > t->buf->len) return E_BOUNDS;
  memcpy(v, t->buf->data + t->pos, n); t->pos += n; return S_OK;
}
// ReadString(codeUnitCount): UnicodeEncoding 0 = UTF-8 (count in bytes), 1/2 = UTF-16 LE/BE (count in code units)
static HRESULT STDMETHODCALLTYPE sr_ReadString(SReader *t, UINT32 n, void **out) {
  if (t->encoding == 0) {
    if (t->pos + n > t->buf->len) return E_BOUNDS;
    int wl = MultiByteToWideChar(CP_UTF8, 0, (const char *)t->buf->data + t->pos, (int)n, NULL, 0);
    wchar_t *w = heap(((size_t)wl + 1) * sizeof(wchar_t));
    MultiByteToWideChar(CP_UTF8, 0, (const char *)t->buf->data + t->pos, (int)n, w, wl);
    t->pos += n;
    HRESULT hr = p_WindowsCreateString(w, (UINT32)wl, out);
    xfree(w); return hr;
  }
  if (t->pos + n * 2 > t->buf->len) return E_BOUNDS;
  wchar_t *w = heap(((size_t)n + 1) * sizeof(wchar_t));
  memcpy(w, t->buf->data + t->pos, n * 2);
  if (t->encoding == 2) for (UINT32 i = 0; i < n; i++) w[i] = (wchar_t)((w[i] >> 8) | (w[i] << 8));
  t->pos += n * 2;
  HRESULT hr = p_WindowsCreateString(w, n, out);
  xfree(w); return hr;
}
#define SR_NOT(n) static HRESULT STDMETHODCALLTYPE sr_##n(void *t) { (void)t; logf("our DataReader: slot %d not implemented", n); return E_NOTIMPL; }
SR_NOT(15) SR_NOT(16) SR_NOT(17) SR_NOT(18) SR_NOT(19) SR_NOT(20) SR_NOT(21) SR_NOT(22) SR_NOT(23) SR_NOT(24) SR_NOT(25)
SR_NOT(27) SR_NOT(28) SR_NOT(29) SR_NOT(30)
static void *g_srVtbl[] = { sr_QI, sr_AddRef, sr_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  sr_Unconsumed, sr_GetEnc, sr_PutEnc, sr_GetOrder, sr_PutOrder, sr_GetOpt, sr_PutOpt, sr_ReadByte, sr_ReadBytes,
  sr_15, sr_16, sr_17, sr_18, sr_19, sr_20, sr_21, sr_22, sr_23, sr_24, sr_25, sr_ReadString, sr_27, sr_28, sr_29, sr_30 };

// DataReader statics wrapper: FromBuffer (6) on our buffer answers our reader.
static HRESULT STDMETHODCALLTYPE srs_FromBuffer(void *t, Obj *buffer, void **out) {
  if (buffer && g_sbVtblPtr && ((Obj *)buffer)->vtbl == g_sbVtblPtr) {
    SBuffer *b = (SBuffer *)buffer; sb_AddRef(b);
    SReader *r = heap(sizeof *r); r->vtbl = g_srVtbl; r->refs = 1; r->buf = b; r->encoding = 0; r->order = 0;
    *out = r; return S_OK;
  }
  return VCALL(JS(t)->real, 6, HRESULT (STDMETHODCALLTYPE *)(void *, Obj *, void **))(JS(t)->real, buffer, out);
}
static void *g_srsVtbl[] = { js_QI, js_AddRef, js_Release, js_3, js_4, js_5, srs_FromBuffer };

static int fix_streams(const wchar_t *cls, GUID *iid, void **out) {
  static const GUID IID_IActivationFactory_ = { 0x00000035, 0, 0, { 0xc0, 0, 0, 0, 0, 0, 0, 0x46 } };
  if (!g_fixStreams || !*out) return 0;
  if (!wcscmp(cls, L"Windows.Storage.Streams.DataWriter") && IsEqualGUID(iid, &IID_IActivationFactory_)) {
    FactoryWrap *w = heap(sizeof *w); w->vtbl = g_swfVtbl; w->real = *out; w->refs = 1;
    *out = w; return 1;
  }
  if (!wcscmp(cls, L"Windows.Storage.Streams.DataReader") && IsEqualGUID(iid, &IID_IDataReaderStatics)) {
    JsonStatics *w = heap(sizeof *w); w->vtbl = g_srsVtbl; w->real = *out; w->refs = 1;
    *out = w; return 1;
  }
  return 0;
}
