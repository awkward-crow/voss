#pragma once

#include <stddef.h>

/* A non-owning slice into a normalized buffer. */
typedef struct {
    const char *ptr;
    size_t      len;
} voss_token_t;

/*
 * voss_normalize -- lowercase [A-Z] and zero out non-alphanumeric bytes.
 *
 * src and dst may alias (in-place is fine).
 * Dispatches to AVX2 or SSE2 based on CPU features.
 */
void voss_normalize(const char *src, char *dst, size_t len);

/*
 * voss_tokenize -- walk a normalized buffer and fill token spans.
 *
 * Expects a buffer produced by voss_normalize (alnum bytes preserved,
 * separators set to 0).  Fills tokens[] with up to cap entries.
 * Returns the number of tokens found.
 */
size_t voss_tokenize(const char *buf, size_t len,
                     voss_token_t *tokens, size_t cap);

/* Internal: per-ISA normalize implementations. */
void voss_normalize_sse2(const char *src, char *dst, size_t len);
void voss_normalize_avx2(const char *src, char *dst, size_t len);
