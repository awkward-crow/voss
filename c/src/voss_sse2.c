#include "voss.h"
#include <immintrin.h>

/*
 * voss_normalize_sse2 -- process 16 bytes per iteration with SSE2.
 *
 * For each chunk:
 *   1. Detect uppercase bytes (A-Z) and OR with 0x20 to lowercase them.
 *   2. Detect alphanumeric bytes (a-z, 0-9) after lowercasing.
 *   3. Zero out non-alphanumeric bytes (word separators).
 *
 * _mm_cmpgt_epi8 is a signed comparison, but all ASCII values are
 * non-negative so it behaves correctly for the ranges we check.
 */
void voss_normalize_sse2(const char *src, char *dst, size_t len)
{
    const __m128i upper_floor = _mm_set1_epi8('A' - 1); /* 0x40 */
    const __m128i upper_ceil  = _mm_set1_epi8('Z' + 1); /* 0x5B */
    const __m128i lower_floor = _mm_set1_epi8('a' - 1); /* 0x60 */
    const __m128i lower_ceil  = _mm_set1_epi8('z' + 1); /* 0x7B */
    const __m128i digit_floor = _mm_set1_epi8('0' - 1); /* 0x2F */
    const __m128i digit_ceil  = _mm_set1_epi8('9' + 1); /* 0x3A */
    const __m128i case_bit    = _mm_set1_epi8(0x20);

    size_t i = 0;
    for (; i + 16 <= len; i += 16) {
        __m128i chunk = _mm_loadu_si128((const __m128i *)(src + i));

        /* 1. Lowercase: bytes in [A,Z] get 0x20 OR'd in. */
        __m128i is_upper = _mm_and_si128(
            _mm_cmpgt_epi8(chunk, upper_floor),
            _mm_cmpgt_epi8(upper_ceil, chunk));
        chunk = _mm_or_si128(chunk, _mm_and_si128(is_upper, case_bit));

        /* 2. Alphanumeric detection (after lowercasing). */
        __m128i is_lower = _mm_and_si128(
            _mm_cmpgt_epi8(chunk, lower_floor),
            _mm_cmpgt_epi8(lower_ceil, chunk));
        __m128i is_digit = _mm_and_si128(
            _mm_cmpgt_epi8(chunk, digit_floor),
            _mm_cmpgt_epi8(digit_ceil, chunk));
        __m128i is_alnum = _mm_or_si128(is_lower, is_digit);

        /* 3. Zero separators: non-alnum bytes become 0. */
        _mm_storeu_si128((__m128i *)(dst + i),
                         _mm_and_si128(chunk, is_alnum));
    }

    /* scalar tail for remaining < 16 bytes. */
    for (; i < len; i++) {
        unsigned char c = (unsigned char)src[i];
        if (c >= 'A' && c <= 'Z') c |= 0x20;
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
            dst[i] = (char)c;
        else
            dst[i] = '\0';
    }
}
