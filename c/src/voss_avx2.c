#include "voss.h"
#include <immintrin.h>

/*
 * voss_normalize_avx2 -- process 32 bytes per iteration with AVX2.
 *
 * Same logic as the SSE2 version but operating on 256-bit registers.
 */
void voss_normalize_avx2(const char *src, char *dst, size_t len)
{
    const __m256i upper_floor = _mm256_set1_epi8('A' - 1);
    const __m256i upper_ceil  = _mm256_set1_epi8('Z' + 1);
    const __m256i lower_floor = _mm256_set1_epi8('a' - 1);
    const __m256i lower_ceil  = _mm256_set1_epi8('z' + 1);
    const __m256i digit_floor = _mm256_set1_epi8('0' - 1);
    const __m256i digit_ceil  = _mm256_set1_epi8('9' + 1);
    const __m256i case_bit    = _mm256_set1_epi8(0x20);

    size_t i = 0;
    for (; i + 32 <= len; i += 32) {
        __m256i chunk = _mm256_loadu_si256((const __m256i *)(src + i));

        __m256i is_upper = _mm256_and_si256(
            _mm256_cmpgt_epi8(chunk, upper_floor),
            _mm256_cmpgt_epi8(upper_ceil, chunk));
        chunk = _mm256_or_si256(chunk, _mm256_and_si256(is_upper, case_bit));

        __m256i is_lower = _mm256_and_si256(
            _mm256_cmpgt_epi8(chunk, lower_floor),
            _mm256_cmpgt_epi8(lower_ceil, chunk));
        __m256i is_digit = _mm256_and_si256(
            _mm256_cmpgt_epi8(chunk, digit_floor),
            _mm256_cmpgt_epi8(digit_ceil, chunk));
        __m256i is_alnum = _mm256_or_si256(is_lower, is_digit);

        _mm256_storeu_si256((__m256i *)(dst + i),
                            _mm256_and_si256(chunk, is_alnum));
    }

    /* fall through remaining bytes with the SSE2 kernel. */
    voss_normalize_sse2(src + i, dst + i, len - i);
}
