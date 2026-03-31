#include "voss.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TOKENS 4096

static void usage(const char *argv0)
{
    fprintf(stderr, "usage: %s [--sse2 | --avx2]\n", argv0);
}

int main(int argc, char **argv)
{
    void (*normalize)(const char *, char *, size_t) = voss_normalize;
    const char *isa = "auto";

    if (argc == 2) {
        if (strcmp(argv[1], "--sse2") == 0) {
            normalize = voss_normalize_sse2;
            isa = "sse2";
        } else if (strcmp(argv[1], "--avx2") == 0) {
            normalize = voss_normalize_avx2;
            isa = "avx2";
        } else {
            usage(argv[0]);
            return 1;
        }
    } else if (argc != 1) {
        usage(argv[0]);
        return 1;
    }

    const char *input =
        "Hello, World! This is a TEST of SIMD string-processing: "
        "foo123 BAR_baz   UPPER lower 42things end.";

    size_t len = strlen(input);
    char  *buf = malloc(len);
    if (!buf) { perror("malloc"); return 1; }

    normalize(input, buf, len);

    voss_token_t tokens[MAX_TOKENS];
    size_t n = voss_tokenize(buf, len, tokens, MAX_TOKENS);

    printf("isa    : %s\n", isa);
    printf("input  : %s\n", input);
    printf("tokens : %zu\n\n", n);
    for (size_t i = 0; i < n; i++)
        printf("  [%2zu] %.*s\n", i, (int)tokens[i].len, tokens[i].ptr);

    free(buf);
    return 0;
}
