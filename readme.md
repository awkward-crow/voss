# voss -- vector string processing


## dir. `zig`

### latest
 - word frequency hashmap: collector's `put` method counts tokens into a `StringHashMap(u32)`, with duped keys; map lifetime managed in `main`
 - stop words filtering: embed `stop_words.txt`, parse at startup into a `StringHashMap(void)`; single-letter words also excluded
 - hashmaps passed to collector as pointers (borrowed, not owned)

### previous
 - embed pride-and-prejudice.txt
 - a collector that accumulates alpha sequences across the end of the vector
 - reload vector while looking for end of alpha sequence i.e. finding q
 - labelled loop for finding p rather than explicit bool

### next
 - testing and benchmarking

### usage

Try,

```sh
cd zig/voss
zig build run
```

Or,

```sh
zig build run --release=fast
./zig-out/bin/voss 

### ownership vs borrowing

Zig has no borrow checker, but the same distinction matters and is expressed through
conventions rather than language rules.

**Ownership** — the struct initialises the resource itself and is responsible for
freeing it. The canonical example is `std.ArrayList`:

```zig
var list = std.ArrayList(u8).init(allocator);
defer list.deinit();
```

`init` stores the allocator and allocates nothing yet; subsequent operations
allocate through it; `deinit` frees everything. The caller never touches the
internal buffer directly. Passing `allocator` by value is idiomatic because
`std.mem.Allocator` is already a fat pointer (ptr + vtable), so copying it is
cheap and correct.

**Borrowing** — the struct holds a pointer to a resource that someone else owns
and will free. The pointer signals "I did not allocate this and I will not free
it." In this codebase the collector borrows the word-count map and stop-words map:

```zig
map: *std.StringHashMap(u32),
stop_words: *std.StringHashMap(void),
```

Both maps are declared, initialised, and deferred-deinit'd in `main`; the
collector receives pointers and uses them without any cleanup responsibility.
This also means `main` can inspect or iterate the map directly after the
tokenisation loop, without going through the collector.

The practical rule: if a struct calls `init` on something, it should call
`deinit` on it too (own it). If it receives something already initialised,
it should hold a pointer and leave cleanup to the caller (borrow it).


## dir. `c`

### latest
 - profile performance, suggests branchless tokenization
 - some tuning of capacity of counts hashmap
 - count words, find k most common using a binary heap and report stats on performance of roll-your-own hashmap

### next
 - branchless tokenization, see note below

### usage

Try,

```sh
cd c
make
./build/voss ../zig/voss/src/pride-and-prejudice.txt
```


## Branchless SIMD Tokenization

### The problem

The current tokenize loop in `main.c` makes a branch decision on every byte:

```c
while (i < len && buf[i] == '\0') i++;   /* skip separator bytes */
const char *start = buf + i;
while (i < len && buf[i] != '\0') i++;   /* capture token body */
```

For natural English text the CPU's branch predictor cannot anticipate when a
run of zero bytes ends or when a word ends — word lengths and gap lengths both
vary unpredictably. `perf stat` on Pride and Prejudice shows `tma_bad_speculation`
at 41%, with a branch miss rate of 6.4% across ~8M branches. These loops are
the most likely source.

### The bitmask approach (full AVX2)

The core idea: load 32 bytes at a time, reduce each chunk to a 32-bit bitmask,
and use bit manipulation to jump directly to token boundaries rather than
testing one byte at a time.

**Step 1 — produce the nonzero mask**

```c
__m256i chunk  = _mm256_loadu_si256((__m256i *)(buf + i));
__m256i zeroes = _mm256_setzero_si256();
__m256i eq     = _mm256_cmpeq_epi8(chunk, zeroes);   /* 0xFF where zero */
uint32_t mask  = ~(uint32_t)_mm256_movemask_epi8(eq); /* 1 where nonzero */
```

`mask` is now a 32-bit integer where bit `k` is set if `buf[i+k]` is a
nonzero (alphanumeric) byte.

**Step 2 — detect transitions**

Carry one bit of state between chunks: `prev_bit`, set to 1 if the last byte
of the previous chunk was nonzero (i.e. we were inside a token).

```c
uint32_t prev_extended = (uint32_t)prev_bit;
uint32_t starts = mask  & ~((mask  << 1) | prev_extended);
uint32_t ends   = ~mask & ((mask  << 1) | prev_extended);
```

- `starts`: bits that are 1 where the preceding bit was 0 — the first byte of each token.
- `ends`: bits that are 0 where the preceding bit was 1 — the first separator byte after each token (one past the end).

Update carry: `prev_bit = (mask >> 31) & 1`.

**Step 3 — extract positions with tzcnt**

Iterate the set bits of `starts` and `ends` using `_tzcnt_u32`, which returns
the position of the lowest set bit in a single instruction:

```c
while (starts) {
    int s = _tzcnt_u32(starts);
    starts &= starts - 1;          /* clear lowest set bit */
    record_start(i + s);
}
while (ends) {
    int e = _tzcnt_u32(ends);
    ends &= ends - 1;
    record_end(i + e);
}
```

On average English text (word length ~5, gap ~1–2) a 32-byte chunk holds
roughly 4–5 tokens, so this inner loop runs ~4–5 times per chunk rather than 32.

**Step 4 — pairing starts and ends**

Starts and ends within a chunk are not necessarily balanced: a chunk can begin
mid-token (carrying a start from the previous chunk) or end mid-token (the end
will arrive in the next chunk). The simplest handling is to maintain a pending
start position carried across chunks. A token is emitted only when both its
start and end are known.

After the main loop, handle the remaining `< 32` bytes with a scalar tail,
passing the final `prev_bit` state in.

### The simpler variant (SIMD skip only)

The full approach above is non-trivial to get right. A lower-effort version
applies SIMD only to the zero-skipping phase — the part that scans forward over
separator bytes looking for the next token start. This mirrors how optimized
`memchr` implementations work.

```c
while (i + 32 <= len) {
    __m256i chunk = _mm256_loadu_si256((__m256i *)(buf + i));
    __m256i eq    = _mm256_cmpeq_epi8(chunk, _mm256_setzero_si256());
    uint32_t mask = (uint32_t)_mm256_movemask_epi8(eq);
    if (mask != 0xFFFFFFFF) {
        i += _tzcnt_u32(~mask);
        break;
    }
    i += 32;
}
while (i < len && buf[i] == '\0') i++;
```

The token-body scan remains scalar (words are short; the scalar loop typically
runs only 5–8 iterations before finding a zero, so misprediction cost there is
lower). This variant eliminates the dominant source of mispredictions — long
zero-runs between words — with much less implementation complexity.

### Expected gain

At 11ms total for Pride and Prejudice, 41% bad speculation corresponds to
roughly 4–5ms of wasted cycles. Eliminating most of the per-byte branches in
the tokenize loop would not recover all of that, but a 2–3× reduction in branch
miss count is plausible, potentially shaving 2–3ms.

### Implementation notes

- Both variants belong in new `voss_tokenize_avx2` / `voss_tokenize_sse2`
  functions, following the same dispatch pattern as `voss_normalize`.
- The carry bit (`prev_bit`) must be initialised to 0 at the start of each call.
- The full bitmask variant requires that `starts` and `ends` are processed in
  the same order they arrive; an assertion that they remain paired is useful
  during development.
- Neither variant changes the output — token spans are still `(ptr, len)` pairs
  pointing into `buf`.


#### end
