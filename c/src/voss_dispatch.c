#include "voss.h"

/*
 * voss_normalize -- runtime dispatch to AVX2 or SSE2.
 *
 * __builtin_cpu_supports is evaluated once at runtime; GCC/Clang cache
 * the CPUID result so there is no measurable overhead per call.
 */
void voss_normalize(const char *src, char *dst, size_t len)
{
    if (__builtin_cpu_supports("avx2"))
        voss_normalize_avx2(src, dst, len);
    else
        voss_normalize_sse2(src, dst, len);
}

/*
 * voss_tokenize -- scalar walk over a normalized buffer.
 *
 * alphanumeric bytes are non-zero; separators are 0.
 * produces token spans as (pointer, length) pairs.
 */
size_t voss_tokenize(const char *buf, size_t len,
                     voss_token_t *tokens, size_t cap)
{
    size_t n = 0;
    size_t i = 0;

    while (i < len && n < cap) {
        /* skip separator (zero) bytes. */
        while (i < len && buf[i] == '\0') i++;
        if (i >= len) break;

        /* capture the run of alnum bytes. */
        const char *start = buf + i;
        while (i < len && buf[i] != '\0') i++;

        tokens[n].ptr = start;
        tokens[n].len = (size_t)(buf + i - start);
        n++;
    }

    return n;
}
