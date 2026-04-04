#include "voss.h"
#include "hashmap.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

typedef struct {
    const char *key;
    size_t      klen;
    int         count;
} entry_t;

static int cmp_asc(const void *a, const void *b)
{
    int ca = ((const entry_t *)a)->count;
    int cb = ((const entry_t *)b)->count;
    return (ca > cb) - (ca < cb);
}

static int cmp_desc(const void *a, const void *b)
{
    return cmp_asc(b, a);
}

static void sift_down(entry_t *h, size_t n, size_t i)
{
    while (1) {
        size_t m = i, l = 2*i + 1, r = 2*i + 2;
        if (l < n && h[l].count < h[m].count) m = l;
        if (r < n && h[r].count < h[m].count) m = r;
        if (m == i) break;
        entry_t tmp = h[i]; h[i] = h[m]; h[m] = tmp;
        i = m;
    }
}

static void usage(const char *argv0)
{
    fprintf(stderr, "usage: %s <file>\n", argv0);
}

int main(int argc, char **argv)
{
    if (argc != 2) { usage(argv[0]); return 1; }

    const char *isa = __builtin_cpu_supports("avx2") ? "avx2" : "sse2";
    fprintf(stderr, "isa    : %s\n", isa);

    struct stat st;
    if (stat(argv[1], &st) != 0) { perror(argv[1]); return 1; }
    size_t len = (size_t)st.st_size;
    fprintf(stderr, "file   : %s (%zu bytes)\n", argv[1], len);

    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }

    char *input = malloc(len);
    if (!input) { perror("malloc"); fclose(f); return 1; }
    if (fread(input, 1, len, f) != len) {
        fprintf(stderr, "read error\n"); fclose(f); free(input); return 1;
    }
    fclose(f);

    char *buf = malloc(len);
    if (!buf) { perror("malloc"); free(input); return 1; }

    voss_normalize(input, buf, len);

    size_t n = 0;
    {
        int in_token = 0;
        for (size_t i = 0; i < len; i++) {
            if (buf[i] != '\0') { if (!in_token) { n++; in_token = 1; } }
            else in_token = 0;
        }
    }
    fprintf(stderr, "tokens : %zu\n", n);

    /* load stop words from a comma-separated file. */
    hashmap_t stop = {0};
    char *stop_buf = NULL;
    struct stat sst;
    if (stat("../stop_words.txt", &sst) == 0) {
        FILE *sf = fopen("../stop_words.txt", "rb");
        if (!sf) {
            perror("../stop_words.txt"); free(buf); free(input); return 1;
        } else {
            stop_buf = malloc(sst.st_size);
            if (stop_buf && fread(stop_buf, 1, sst.st_size, sf) == (size_t)sst.st_size) {
                /* count commas to estimate word count for hashmap sizing. */
                size_t ncommas = 0;
                for (size_t i = 0; i < (size_t)sst.st_size; i++)
                    if (stop_buf[i] == ',') ncommas++;
                hashmap_init(&stop, (ncommas + 1 + 26) * 2); /* +26 for single letters a-z */
                const char *p = stop_buf, *end = stop_buf + sst.st_size;
                while (p < end) {
                    const char *q = p;
                    while (q < end && *q != ',') q++;
                    if (q > p) hashmap_increment(&stop, p, (size_t)(q - p));
                    p = q + 1;
                }
                static const char alpha[] = "abcdefghijklmnopqrstuvwxyz";
                for (size_t j = 0; j < 26; j++)
                    hashmap_increment(&stop, alpha + j, 1);
                fprintf(stderr, "stop   : %zu words\n", stop.used);
            }
            fclose(sf);
        }
    } else {
        fprintf(stderr, "stop   : ../stop_words.txt not found\n");
        free(buf); free(input); return 1;
    }

    /* Heaps' law: unique word count ≈ K * n^beta, K≈10, beta≈0.7 for
     * English.  Floor at 1024 for small inputs. */
    size_t cap_hint = (size_t)(10.0 * pow((double)n, 0.7));
    if (cap_hint < 1024) cap_hint = 1024;
    hashmap_t m;
    if (hashmap_init(&m, cap_hint) != 0) {
        fprintf(stderr, "hashmap_init failed\n");
        free(buf); free(input); return 1;
    }
    fprintf(stderr, "map cap: %zu  (n*2=%zu, rounded up to next pow2)\n", m.cap, n * 2);
    {
        size_t i = 0;
        while (i < len) {
            while (i < len && buf[i] == '\0') i++;
            if (i >= len) break;
            const char *start = buf + i;
            while (i < len && buf[i] != '\0') i++;
            size_t tlen = (size_t)(buf + i - start);
            if (hashmap_contains(&stop, start, tlen)) continue;
            hashmap_increment(&m, start, tlen);
        }
    }
    fprintf(stderr, "unique : %zu\n", m.used);

    hashmap_stats_t hst;
    hashmap_stats(&m, &hst);
    fprintf(stderr, "load   : %.2f\n",    hst.load_factor);
    fprintf(stderr, "probe  : max=%zu mean=%.2f\n", hst.max_probe, hst.mean_probe);
    fprintf(stderr, "runs   : max=%zu mean=%.2f\n", hst.max_run,   hst.mean_run);
    fprintf(stderr, "hist   : ");
    for (size_t i = 0; i < 5; i++)
        fprintf(stderr, "[%zu]=%zu ", i, hst.hist[i]);
    fprintf(stderr, "[5+]=%zu\n", hst.hist[5]);

    size_t k = 25;
    size_t hlen = 0;
    entry_t *heap = malloc(k * sizeof *heap);
    if (!heap) {
        perror("malloc"); hashmap_free(&m); free(buf); free(input); return 1;
    }

    for (size_t i = 0; i < m.cap; i++) {
        if (!m.occupied[i]) continue;
        entry_t e = { m.keys[i], m.klens[i], m.counts[i] };
        if (hlen < k) {
            heap[hlen++] = e;
            /* once the heap is full, arrange it as a min-heap. */
            if (hlen == k)
                for (size_t j = k / 2; j-- > 0; ) sift_down(heap, k, j);
        } else if (e.count > heap[0].count) {
            heap[0] = e;
            sift_down(heap, k, 0);
        }
    }

    qsort(heap, hlen, sizeof *heap, cmp_desc);

    for (size_t i = 0; i < hlen; i++)
        printf("%6d  %.*s\n", heap[i].count, (int)heap[i].klen, heap[i].key);

    free(heap);
    hashmap_free(&m);
    hashmap_free(&stop);
    free(stop_buf);
    free(buf);
    free(input);
    return 0;
}
