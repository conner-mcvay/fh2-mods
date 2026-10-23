// Included by fh2wheels.c. The offset menus' text (strings.h, made by make_offset_sql.py).
//
// The game shows gamedb text through its string tables: "_&<id>" becomes a LocString (table index from the id's high
// 16 bits, key = low 16; 14123D100), whose text comes from 14123D780 (manager, table index, key), a binary search of
// that table's keys returning UTF-16 text (or an empty string when the key is missing). Its entry jumps to
// text_lookup, which answers the keys in g_stringRanges (no string table has them) and hands every other key
// to the original (text_original: the replaced instructions, then back).

#include "strings.h"

void *g_textBack = (void *)0x14123D789;
typedef const wchar_t *(*text_lookup_t)(void *manager, unsigned table, unsigned key);

__attribute__((naked, used)) static const wchar_t *text_original(void *manager, unsigned table, unsigned key) {
  __asm__ volatile(
    "sub $0x38, %%rsp\n\t mov $0xffff, %%eax\n\t"   // the replaced instructions
    "jmp *g_textBack(%%rip)\n\t" ::: "memory");
}

static const wchar_t *text_lookup_impl(void *manager, unsigned table, unsigned key);
const wchar_t * __attribute__((used)) text_lookup(void *manager, unsigned table, unsigned key) { PROF_BEGIN; const wchar_t *r = text_lookup_impl(manager, table, key); PROF_END(P_TEXT); return r; }
static const wchar_t *text_lookup_impl(void *manager, unsigned table, unsigned key) {
  for (size_t r = 0; r < sizeof g_stringRanges / sizeof *g_stringRanges; r++) {
    unsigned k = (key & 0xFFFF) - g_stringRanges[r].base;
    if (k < g_stringRanges[r].count) return g_stringRanges[r].text[k];
  }
  return text_original(manager, table, key);
}

static DWORD WINAPI text_install(LPVOID p) {
  (void)p;
  static const BYTE orig[] = { 0x48, 0x83, 0xEC, 0x38, 0xB8, 0xFF, 0xFF, 0x00, 0x00 };   // sub rsp, 0x38 / mov eax, 0xffff
  hook_jmp(GAME_BASE + (0x14123D780 - 0x140000000ULL), orig, sizeof orig, (void *)text_lookup, "string table lookup");
  return 0;
}
