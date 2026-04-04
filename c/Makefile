CC      = gcc
CFLAGS  = -std=c11 -O3 -march=native -Wall -Wextra -Iinclude
BUILD   = build
TARGET  = $(BUILD)/voss

SRCS = src/voss_sse2.c \
       src/voss_avx2.c \
       src/voss_dispatch.c \
       src/hashmap.c \
       src/main.c

OBJS = $(SRCS:src/%.c=$(BUILD)/%.o)

.PHONY: all clean tidy

all: $(TARGET)

$(BUILD):
	mkdir -p $(BUILD)

# SSE2 translation unit needs -msse2
$(BUILD)/voss_sse2.o: src/voss_sse2.c | $(BUILD)
	$(CC) $(CFLAGS) -msse2 -c $< -o $@

# AVX2 translation unit needs -mavx2 (also implies SSE2/4.2)
$(BUILD)/voss_avx2.o: src/voss_avx2.c | $(BUILD)
	$(CC) $(CFLAGS) -mavx2 -c $< -o $@

# Dispatch and main compile without ISA flags so the binary stays portable
$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET): $(OBJS)
	$(CC) $^ -o $@ -lm

tidy:
	rm -f $(BUILD)/*.o

clean:
	rm -rf $(BUILD)
