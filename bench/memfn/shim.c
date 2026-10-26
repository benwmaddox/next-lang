#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

#define MAX_SIZE (16u * 1024u * 1024u)
#define TARGET_NS 100000000ull

typedef void *(*copy_function)(void *, const void *, size_t);
typedef void *(*fill_function)(void *, int, size_t);

extern void *bench_core_memcpy(void *, const void *, size_t);
extern void *bench_core_memset(void *, int, size_t);

static unsigned char source[MAX_SIZE + 16];
static unsigned char destination[MAX_SIZE + 16];
static volatile uint64_t sink;
static copy_function volatile core_copy = bench_core_memcpy;
static copy_function volatile libc_copy = NULL;
static fill_function volatile core_fill = bench_core_memset;
static fill_function volatile libc_fill = NULL;

__attribute__((noinline)) void *bench_libc_memcpy(void *dst, const void *src,
                                                  size_t count) {
    return memcpy(dst, src, count);
}

__attribute__((noinline)) void *bench_libc_memset(void *dst, int value,
                                                  size_t count) {
    return memset(dst, value, count);
}

static inline long raw_clock_gettime(struct timespec *value) {
    long result;
    __asm__ volatile("syscall"
                     : "=a"(result)
                     : "0"(228L), "D"(1L), "S"(value)
                     : "rcx", "r11", "memory");
    return result;
}

static inline long raw_write(int fd, const void *bytes, size_t count) {
    long result;
    __asm__ volatile("syscall"
                     : "=a"(result)
                     : "0"(1L), "D"((long)fd), "S"(bytes), "d"((long)count)
                     : "rcx", "r11", "memory");
    return result;
}

static uint64_t now_ns(void) {
    struct timespec value;
    if (raw_clock_gettime(&value) != 0) return 0;
    return (uint64_t)value.tv_sec * 1000000000ull + (uint64_t)value.tv_nsec;
}

static size_t append_unsigned(char *out, size_t at, uint64_t value) {
    char digits[24];
    size_t count = 0;
    do {
        digits[count++] = (char)('0' + value % 10);
        value /= 10;
    } while (value != 0);
    while (count != 0) out[at++] = digits[--count];
    return at;
}

static void write_result(const char *kind, size_t size, size_t alignment,
                         uint64_t core_ps, uint64_t libc_ps) {
    char line[128];
    size_t at = 0;
    while (*kind) line[at++] = *kind++;
    line[at++] = ',';
    at = append_unsigned(line, at, size);
    line[at++] = ',';
    at = append_unsigned(line, at, alignment);
    line[at++] = ',';
    at = append_unsigned(line, at, core_ps);
    line[at++] = ',';
    at = append_unsigned(line, at, libc_ps);
    line[at++] = '\n';
    (void)raw_write(1, line, at);
}

static uint64_t time_copy(copy_function volatile *function, unsigned char *dst,
                          const unsigned char *src, size_t size) {
    uint64_t start = now_ns();
    uint64_t end = start;
    uint64_t calls = 0;
    copy_function operation = *function;
    for (;;) {
        operation(dst, src, size);
        sink += dst[size == 0 ? 0 : size - 1];
        ++calls;
        if (size >= 4096 || (calls & 4095u) == 0) {
            end = now_ns();
            if (end - start >= TARGET_NS) break;
        }
    }
    return calls == 0 ? 0 : (end - start) * 1000 / calls;
}

static uint64_t time_fill(fill_function volatile *function, unsigned char *dst,
                          size_t size, unsigned char value) {
    uint64_t start = now_ns();
    uint64_t end = start;
    uint64_t calls = 0;
    fill_function operation = *function;
    for (;;) {
        operation(dst, value, size);
        sink += dst[size == 0 ? 0 : size - 1];
        ++calls;
        if (size >= 4096 || (calls & 4095u) == 0) {
            end = now_ns();
            if (end - start >= TARGET_NS) break;
        }
    }
    return calls == 0 ? 0 : (end - start) * 1000 / calls;
}

static uint64_t best_copy(copy_function volatile *core,
                          copy_function volatile *libc, unsigned char *dst,
                          const unsigned char *src, size_t size,
                          uint64_t *libc_best) {
    uint64_t core_best = UINT64_MAX;
    *libc_best = UINT64_MAX;
    for (unsigned repeat = 0; repeat < 7; ++repeat) {
        uint64_t core_sample;
        uint64_t libc_sample;
        if ((repeat & 1u) == 0) {
            core_sample = time_copy(core, dst, src, size);
            libc_sample = time_copy(libc, dst, src, size);
        } else {
            libc_sample = time_copy(libc, dst, src, size);
            core_sample = time_copy(core, dst, src, size);
        }
        if (core_sample < core_best) core_best = core_sample;
        if (libc_sample < *libc_best) *libc_best = libc_sample;
    }
    return core_best;
}

static uint64_t best_fill(fill_function volatile *core,
                          fill_function volatile *libc, unsigned char *dst,
                          size_t size, uint64_t *libc_best) {
    uint64_t core_best = UINT64_MAX;
    *libc_best = UINT64_MAX;
    for (unsigned repeat = 0; repeat < 7; ++repeat) {
        uint64_t core_sample;
        uint64_t libc_sample;
        if ((repeat & 1u) == 0) {
            core_sample = time_fill(core, dst, size, 173);
            libc_sample = time_fill(libc, dst, size, 173);
        } else {
            libc_sample = time_fill(libc, dst, size, 173);
            core_sample = time_fill(core, dst, size, 173);
        }
        if (core_sample < core_best) core_best = core_sample;
        if (libc_sample < *libc_best) *libc_best = libc_sample;
    }
    return core_best;
}

void bench_run(void) {
#ifdef BENCH_QUICK
    size_t sizes[] = {0, 8, 16, 64, 256, 4096, 65536, 1024 * 1024, 16 * 1024 * 1024};
    size_t size_count = sizeof(sizes) / sizeof(sizes[0]);
#else
    size_t sizes[73];
    size_t size_count = 0;
    for (size_t size = 0; size <= 64; ++size) sizes[size_count++] = size;
    sizes[size_count++] = 128;
    sizes[size_count++] = 256;
    sizes[size_count++] = 512;
    sizes[size_count++] = 1024;
    sizes[size_count++] = 4096;
    sizes[size_count++] = 65536;
    sizes[size_count++] = 1024 * 1024;
    sizes[size_count++] = 16 * 1024 * 1024;
#endif
    libc_copy = bench_libc_memcpy;
    libc_fill = bench_libc_memset;
    for (size_t index = 0; index < MAX_SIZE; ++index) {
        source[index] = (unsigned char)(index * 31u + 17u);
    }
    static const char header[] = "kind,size,alignment,core_ps_per_call,glibc_ps_per_call\n";
    (void)raw_write(1, header, sizeof(header) - 1);
    const size_t alignments[] = {0, 1, 7};
    for (size_t size_index = 0; size_index < size_count; ++size_index) {
        size_t size = sizes[size_index];
        for (size_t alignment_index = 0; alignment_index < 3; ++alignment_index) {
            size_t alignment = alignments[alignment_index];
            unsigned char *dst = destination + alignment;
            const unsigned char *src = source + alignment;
            uint64_t libc_ps;
            uint64_t core_ps = best_copy(&core_copy, &libc_copy, dst, src, size, &libc_ps);
            write_result("memcpy", size, alignment, core_ps, libc_ps);
            core_ps = best_fill(&core_fill, &libc_fill, dst, size, &libc_ps);
            write_result("memset", size, alignment, core_ps, libc_ps);
        }
    }
    (void)sink;
}
