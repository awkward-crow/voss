#include "hashmap.h"
#include <stdlib.h>
#include <string.h>

static uint64_t fnv1a(const char *key, size_t len)
{
    uint64_t h = 0xcbf29ce484222325ULL;
    for (size_t i = 0; i < len; i++)
        h = (h ^ (uint8_t)key[i]) * 0x100000001b3ULL;
    return h;
}

static size_t next_pow2(size_t n)
{
    size_t p = 1;
    while (p < n) p <<= 1;
    return p;
}

int hashmap_init(hashmap_t *m, size_t cap)
{
    cap         = next_pow2(cap);
    m->keys     = malloc(cap * sizeof *m->keys);
    m->klens    = malloc(cap * sizeof *m->klens);
    m->counts   = malloc(cap * sizeof *m->counts);
    m->occupied = calloc(cap, sizeof *m->occupied);
    m->cap      = cap;
    m->used     = 0;
    if (!m->keys || !m->klens || !m->counts || !m->occupied) {
        hashmap_free(m);
        return -1;
    }
    return 0;
}

void hashmap_free(hashmap_t *m)
{
    free(m->keys);
    free(m->klens);
    free(m->counts);
    free(m->occupied);
}

/* returns the index of the slot for (key, klen) -- either the existing
   entry or the first empty slot where it should be inserted. */
static size_t probe(const hashmap_t *m, const char *key, size_t klen)
{
    size_t i = fnv1a(key, klen) & (m->cap - 1);
    while (m->occupied[i]) {
        if (m->klens[i] == klen && memcmp(m->keys[i], key, klen) == 0)
            return i;
        i = (i + 1) & (m->cap - 1);
    }
    return i;
}

void hashmap_increment(hashmap_t *m, const char *key, size_t klen)
{
    size_t i = probe(m, key, klen);
    if (!m->occupied[i]) {
        m->keys[i]     = key;
        m->klens[i]    = klen;
        m->counts[i]   = 0;
        m->occupied[i] = 1;
        m->used++;
    }
    m->counts[i]++;
}

int hashmap_contains(const hashmap_t *m, const char *key, size_t klen)
{
    size_t i = probe(m, key, klen);
    return m->occupied[i];
}

void hashmap_stats(const hashmap_t *m, hashmap_stats_t *s)
{
    memset(s, 0, sizeof *s);
    if (m->used == 0) return;

    s->load_factor = (double)m->used / (double)m->cap;

    /* probe distances. */
    size_t total_probe = 0;
    for (size_t i = 0; i < m->cap; i++) {
        if (!m->occupied[i]) continue;
        size_t home = fnv1a(m->keys[i], m->klens[i]) & (m->cap - 1);
        size_t dist = (i + m->cap - home) & (m->cap - 1);
        if (dist > s->max_probe) s->max_probe = dist;
        total_probe += dist;
        s->hist[dist < 5 ? dist : 5]++;
    }
    s->mean_probe = (double)total_probe / (double)m->used;

    /* run lengths -- consecutive occupied slots. */
    size_t runs = 0, total_run = 0, cur = 0;
    for (size_t i = 0; i < m->cap; i++) {
        if (m->occupied[i]) {
            cur++;
        } else if (cur > 0) {
            if (cur > s->max_run) s->max_run = cur;
            total_run += cur;
            runs++;
            cur = 0;
        }
    }
    if (cur > 0) {
        if (cur > s->max_run) s->max_run = cur;
        total_run += cur;
        runs++;
    }
    s->mean_run = runs ? (double)total_run / (double)runs : 0.0;
}
