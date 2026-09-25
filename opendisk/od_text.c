/* od_text.c — the name folding OpenDisk's search matches on.
 *
 * OpenDisk folds with lowercased() + NFC (precomposed), so "Café" typed by a
 * user matches a file whose name macOS stored decomposed (e + U+0301). This
 * covers the Latin scripts: lowercase for ASCII, Latin-1 Supplement and
 * Latin Extended-A, then compose a base letter followed by one of the common
 * combining marks into its precomposed form. Other scripts pass through
 * unchanged (still matched byte-for-byte). A full Unicode fold would come
 * from utf8proc (vendored in aether's contrib/i18n) once that exposes one.
 *
 * od_fold returns a malloc'd string the caller owns. */
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static uint32_t lower_cp(uint32_t c) {
    if (c >= 'A' && c <= 'Z') return c + 32;
    if (c >= 0xC0 && c <= 0xDE && c != 0xD7) return c + 32;
    if (c >= 0x100 && c <= 0x137) return (c % 2 == 0) ? c + 1 : c;
    if (c >= 0x139 && c <= 0x148) return (c % 2 == 1) ? c + 1 : c;
    if (c >= 0x14A && c <= 0x177) return (c % 2 == 0) ? c + 1 : c;
    if (c == 0x178) return 0xFF;
    if (c >= 0x179 && c <= 0x17E) return (c % 2 == 1) ? c + 1 : c;
    return c;
}

/* base letter (lowercase) + combining mark -> precomposed, or 0. */
static uint32_t compose(uint32_t b, uint32_t m) {
    switch (m) {
    case 0x300: /* grave */
        switch (b) { case 'a': return 0xE0; case 'e': return 0xE8; case 'i': return 0xEC;
                     case 'o': return 0xF2; case 'u': return 0xF9; }
        break;
    case 0x301: /* acute */
        switch (b) { case 'a': return 0xE1; case 'e': return 0xE9; case 'i': return 0xED;
                     case 'o': return 0xF3; case 'u': return 0xFA; case 'y': return 0xFD;
                     case 'c': return 0x107; case 'n': return 0x144; case 's': return 0x15B;
                     case 'z': return 0x17A; case 'l': return 0x13A; case 'r': return 0x155; }
        break;
    case 0x302: /* circumflex */
        switch (b) { case 'a': return 0xE2; case 'e': return 0xEA; case 'i': return 0xEE;
                     case 'o': return 0xF4; case 'u': return 0xFB; }
        break;
    case 0x303: /* tilde */
        switch (b) { case 'a': return 0xE3; case 'n': return 0xF1; case 'o': return 0xF5; }
        break;
    case 0x308: /* diaeresis */
        switch (b) { case 'a': return 0xE4; case 'e': return 0xEB; case 'i': return 0xEF;
                     case 'o': return 0xF6; case 'u': return 0xFC; case 'y': return 0xFF; }
        break;
    case 0x30A: /* ring */
        switch (b) { case 'a': return 0xE5; case 'u': return 0x16F; }
        break;
    case 0x327: /* cedilla */
        switch (b) { case 'c': return 0xE7; case 's': return 0x15F; }
        break;
    case 0x30C: /* caron */
        switch (b) { case 'c': return 0x10D; case 'e': return 0x11B; case 'n': return 0x148;
                     case 'r': return 0x159; case 's': return 0x161; case 'z': return 0x17E; }
        break;
    }
    return 0;
}

static int decode(const unsigned char* s, uint32_t* cp) {
    if (s[0] < 0x80) { *cp = s[0]; return 1; }
    if ((s[0] & 0xE0) == 0xC0 && (s[1] & 0xC0) == 0x80) {
        *cp = ((uint32_t)(s[0] & 0x1F) << 6) | (s[1] & 0x3F); return 2;
    }
    if ((s[0] & 0xF0) == 0xE0 && (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80) {
        *cp = ((uint32_t)(s[0] & 0x0F) << 12) | ((uint32_t)(s[1] & 0x3F) << 6) | (s[2] & 0x3F);
        return 3;
    }
    if ((s[0] & 0xF8) == 0xF0 && (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80
        && (s[3] & 0xC0) == 0x80) {
        *cp = ((uint32_t)(s[0] & 0x07) << 18) | ((uint32_t)(s[1] & 0x3F) << 12)
            | ((uint32_t)(s[2] & 0x3F) << 6) | (s[3] & 0x3F);
        return 4;
    }
    *cp = s[0];   /* invalid byte: pass it through as itself */
    return 1;
}

static int encode(uint32_t c, char* o) {
    if (c < 0x80) { o[0] = (char)c; return 1; }
    if (c < 0x800) { o[0] = (char)(0xC0 | (c >> 6)); o[1] = (char)(0x80 | (c & 0x3F)); return 2; }
    if (c < 0x10000) {
        o[0] = (char)(0xE0 | (c >> 12)); o[1] = (char)(0x80 | ((c >> 6) & 0x3F));
        o[2] = (char)(0x80 | (c & 0x3F)); return 3;
    }
    o[0] = (char)(0xF0 | (c >> 18)); o[1] = (char)(0x80 | ((c >> 12) & 0x3F));
    o[2] = (char)(0x80 | ((c >> 6) & 0x3F)); o[3] = (char)(0x80 | (c & 0x3F)); return 4;
}

char* od_fold(const char* in) {
    if (!in) in = "";
    size_t n = strlen(in);
    char* out = (char*)malloc(n + 1);
    if (!out) return NULL;
    const unsigned char* s = (const unsigned char*)in;
    size_t i = 0, o = 0;
    uint32_t prev = 0;       /* last emitted code point (for composition) */
    size_t prev_at = 0;      /* where it starts in out */
    int have_prev = 0;
    while (i < n) {
        uint32_t cp;
        int len = decode(s + i, &cp);
        if (i + (size_t)len > n) len = (int)(n - i);
        i += (size_t)len;
        cp = lower_cp(cp);
        if (have_prev) {
            uint32_t c = compose(prev, cp);
            if (c) {
                /* Replace the base with the precomposed letter; it is never
                 * longer than base (1 byte) + mark (2 bytes). */
                o = prev_at;
                o += (size_t)encode(c, out + o);
                prev = c;
                continue;
            }
        }
        prev_at = o;
        o += (size_t)encode(cp, out + o);
        prev = cp;
        have_prev = 1;
    }
    out[o] = '\0';
    return out;
}
