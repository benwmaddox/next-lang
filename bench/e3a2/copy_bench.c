#include <stddef.h>
#include <stdint.h>
#include <time.h>

#ifndef BENCH_SIZE
#error BENCH_SIZE must be supplied by the runner
#endif
#ifndef BENCH_LABEL
#error BENCH_LABEL must be supplied by the runner
#endif

typedef void (*copy_function)(void *, const void *);

extern void bench_special(void *, const void *);
extern void bench_generic(void *, const void *);

static unsigned char source[BENCH_SIZE + 64] __attribute__((aligned(64)));
static unsigned char destination[BENCH_SIZE + 64] __attribute__((aligned(64)));
static volatile uint64_t sink;
static copy_function volatile special_copy = bench_special;
static copy_function volatile generic_copy = bench_generic;

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

static uint64_t time_copy(copy_function volatile *function) {
    const uint64_t target_ns = 100000000ull;
    uint64_t start = now_ns();
    uint64_t end = start;
    uint64_t calls = 0;
    copy_function operation = *function;
    do {
        operation(destination, source);
        sink += destination[BENCH_SIZE - 1];
        ++calls;
        if ((calls & 4095u) == 0) end = now_ns();
    } while (end - start < target_ns);
    return calls == 0 ? 0 : (end - start) * 1000 / calls;
}

static void append_unsigned(char *out, size_t *at, uint64_t value) {
    char digits[24];
    size_t count = 0;
    do {
        digits[count++] = (char)('0' + value % 10);
        value /= 10;
    } while (value != 0);
    while (count != 0) out[(*at)++] = digits[--count];
}

static void append_text(char *out, size_t *at, const char *text) {
    while (*text) out[(*at)++] = *text++;
}

static void sort(uint64_t values[5]) {
    for (size_t index = 0; index < 5; ++index) {
        for (size_t other = index + 1; other < 5; ++other) {
            if (values[other] < values[index]) {
                uint64_t swap = values[index];
                values[index] = values[other];
                values[other] = swap;
            }
        }
    }
}

static void write_result(const char *kind, uint64_t specialized[5],
                         uint64_t generic[5]) {
    char line[256];
    size_t at = 0;
    append_text(line, &at, kind);
    line[at++] = ',';
    append_unsigned(line, &at, BENCH_SIZE);
    line[at++] = ',';
    append_unsigned(line, &at, specialized[0]);
    line[at++] = ',';
    append_unsigned(line, &at, specialized[2]);
    line[at++] = ',';
    append_unsigned(line, &at, specialized[4]);
    line[at++] = ',';
    append_unsigned(line, &at, generic[0]);
    line[at++] = ',';
    append_unsigned(line, &at, generic[2]);
    line[at++] = ',';
    append_unsigned(line, &at, generic[4]);
    line[at++] = ',';
    append_unsigned(line, &at, generic[2] * 1000 / (specialized[2] ? specialized[2] : 1));
    line[at++] = '\n';
    (void)raw_write(1, line, at);
}

void bench_run(void *context) {
    for (size_t index = 0; index < BENCH_SIZE; ++index) {
        source[index] = (unsigned char)(index * 31u + 17u);
    }
#ifdef BENCH_LIST_COUNT
    uint64_t count = BENCH_LIST_COUNT;
    for (size_t index = 0; index < sizeof(count); ++index) {
        source[index] = (unsigned char)(count >> (index * 8));
    }
#endif

    uint64_t specialized[5];
    uint64_t generic[5];
    for (size_t repeat = 0; repeat < 5; ++repeat) {
        if ((repeat & 1u) == 0) {
            specialized[repeat] = time_copy(&special_copy);
            generic[repeat] = time_copy(&generic_copy);
        } else {
            generic[repeat] = time_copy(&generic_copy);
            specialized[repeat] = time_copy(&special_copy);
        }
    }
    sort(specialized);
    sort(generic);
    write_result(BENCH_LABEL, specialized, generic);
    (void)context;
    (void)sink;
}
