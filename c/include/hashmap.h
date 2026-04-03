#pragma once

#include <stddef.h>
#include <stdint.h>

typedef struct {
    const char **keys;
    size_t      *klens;
    int         *counts;
    uint8_t     *occupied;
    size_t       cap;
    size_t       used;
} hashmap_t;

/* cap need not be a power of two; hashmap_init rounds up internally. */
int  hashmap_init(hashmap_t *m, size_t cap);
void hashmap_free(hashmap_t *m);

/* Increment the count for (key, klen). Inserts with count 1 if absent. */
void hashmap_increment(hashmap_t *m, const char *key, size_t klen);

/* Returns 1 if (key, klen) is present, 0 otherwise. */
int  hashmap_contains(const hashmap_t *m, const char *key, size_t klen);

typedef struct {
    double load_factor;
    size_t max_probe;
    double mean_probe;
    size_t max_run;
    double mean_run;
    size_t hist[6]; /* probe distances 0,1,2,3,4,5+ */
} hashmap_stats_t;

void hashmap_stats(const hashmap_t *m, hashmap_stats_t *s);
