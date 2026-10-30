#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <linux/openat2.h>

#include "nl_unicode_upper.h"

#if defined(__linux__)
#include <sys/mman.h>
#include <sys/types.h>
#include <pthread.h>
#endif

static const char **nl_files;
static size_t nl_file_capacity;
static int nl_test_mode;
static int nl_print_fd = STDOUT_FILENO;

#define NL_OUTPUT_BUFFER_CAPACITY (64u * 1024u)
static unsigned char nl_output_buffers[2][NL_OUTPUT_BUFFER_CAPACITY];
static size_t nl_output_lengths[2];
static int nl_output_is_terminal[2];
static int nl_output_shared_terminal = -1;
static int nl_output_last_stream = -1;

static int nl_output_flush_all(void);
static int nl_output_write(int fd, const unsigned char *bytes, uint64_t length);
static int nl_output_write_and_flush(int fd, const unsigned char *bytes,
                                     uint64_t length);


typedef struct {
    void *header_mapping;
    size_t header_bytes;
    void *mapping;
    size_t mapping_bytes;
    uint64_t reservation_bytes;
    uint64_t peak_used_bytes;
    const char *entry_name;
    unsigned char *base;
    unsigned char *top;
    unsigned char *limit;
#if defined(NLC_STACK_MODE_OFFSET)
    uint64_t top_offset;
    /* Retired with the fixed stack; kept so the context layout matches core/context.nl until that
       struct drops them too. */
    uint64_t growth_count;
    uint64_t relocation_count;
    uint64_t growth_nanoseconds;
    void *poisoned_mappings;
#endif
    uintptr_t native_stack_limit;
    uintptr_t native_stack_start;
    uint64_t recursion_budget;
} nl_data_stack_context;

/* The generated code reads the stack base straight from the context (selfhost/c_runtime.nl,
   nlc_context_current_base); keep the offset it uses in step with this struct. */
_Static_assert(offsetof(nl_data_stack_context, base) == 56, "generated code reads the context base at offset 56");

_Noreturn void nl_fail(int32_t kind, int32_t file_id, int32_t line, int32_t col);
static int nl_write_all(int fd, const unsigned char *bytes, uint64_t length);

/* Diagnostics go straight to the file descriptor with write(2); no stdio. */
static void nl_put_text(int fd, const char *text) {
    size_t length = 0;
    while (text[length]) ++length;
    (void)nl_write_all(fd, (const unsigned char *)text, length);
}

static void nl_put_unsigned(int fd, unsigned long long value) {
    char digits[24];
    int at = 24;
    do {
        digits[--at] = (char)('0' + value % 10);
        value /= 10;
    } while (value != 0);
    (void)nl_write_all(fd, (const unsigned char *)digits + at, (uint64_t)(24 - at));
}

static void nl_put_signed(int fd, long long value) {
    if (value < 0) {
        nl_put_text(fd, "-");
        nl_put_unsigned(fd, 0ULL - (unsigned long long)value);
    } else {
        nl_put_unsigned(fd, (unsigned long long)value);
    }
}

static void nl_stack_startup_failure(const char *message) {
    nl_put_text(2, "nlc: data stack startup failure: ");
    nl_put_text(2, message);
    nl_put_text(2, "\n");
    exit(1);
}

static void nl_stack_startup_failure_for(const char *entry_name, uint64_t bytes,
                                         const char *message) {
    nl_put_text(2, "nlc: data stack startup failure for entry '");
    nl_put_text(2, entry_name ? entry_name : "<unknown>");
    nl_put_text(2, "' (reservation ");
    nl_put_unsigned(2, bytes);
    nl_put_text(2, " bytes): ");
    nl_put_text(2, message);
    nl_put_text(2, "\n");
    exit(1);
}

static uint64_t nl_data_stack_reservation(uint64_t requested_bytes,
                                          const char *entry_name) {
#if defined(NLC_TEST_BUILD)
    const char *override = getenv("NLC_TEST_DATA_STACK_BYTES");
    if (override && *override) {
        errno = 0;
        char *end = NULL;
        unsigned long long value = strtoull(override, &end, 10);
        if (errno || end == override || *end || value == 0) {
            nl_stack_startup_failure_for(entry_name, requested_bytes,
                                         "NLC_TEST_DATA_STACK_BYTES must be a positive byte count");
        }
        uint64_t reservation = (uint64_t)value;
        const char *allow_small = getenv("NLC_TEST_ALLOW_STACK_EXHAUSTION");
        if (reservation < requested_bytes && (!allow_small || strcmp(allow_small, "1") != 0)) {
            nl_stack_startup_failure_for(entry_name, requested_bytes,
                                         "test reservation is below the computed worst case");
        }
        return reservation;
    }
#endif
    return requested_bytes;
}

#if defined(NLC_STACK_MODE_OFFSET)
/* Default address range reserved for an offset data stack. It is only reserved (MAP_NORESERVE),
   never committed up front; pages are touched as the stack grows. Override with
   NLC_STACK_RESERVE_BYTES, e.g. under `ulimit -v`. */
#define NL_OFFSET_STACK_DEFAULT_BYTES (UINT64_C(32) * 1024 * 1024 * 1024)

static uint64_t nl_offset_stack_reservation(uint64_t computed_bytes) {
#if defined(NLC_TEST_BUILD)
    const char *test_override = getenv("NLC_TEST_DATA_STACK_BYTES");
    if (test_override && *test_override) return computed_bytes;
#endif
    uint64_t bytes = NL_OFFSET_STACK_DEFAULT_BYTES;
    const char *override = getenv("NLC_STACK_RESERVE_BYTES");
    if (override && *override) {
        errno = 0;
        char *end = NULL;
        unsigned long long value = strtoull(override, &end, 10);
        if (errno || end == override || *end || value == 0) {
            nl_stack_startup_failure("NLC_STACK_RESERVE_BYTES must be a positive byte count");
        }
        bytes = (uint64_t)value;
    }
    return bytes > computed_bytes ? bytes : computed_bytes;
}
#endif

static uintptr_t nl_current_stack_pointer(void) {
#if defined(__x86_64__)
    uintptr_t pointer;
    __asm__ volatile("mov %%rsp, %0" : "=r"(pointer));
    return pointer;
#elif defined(__aarch64__)
    uintptr_t pointer;
    __asm__ volatile("mov %0, sp" : "=r"(pointer));
    return pointer;
#else
    volatile unsigned char marker = 0;
    return (uintptr_t)&marker;
#endif
}

static void nl_native_stack_setup(nl_data_stack_context *context,
                                  uint64_t requested_budget) {
    uintptr_t stack_low = 0;
    uint64_t stack_bytes = 0;
    pthread_attr_t attributes;
    if (pthread_getattr_np(pthread_self(), &attributes) != 0) {
        nl_stack_startup_failure("could not determine the native stack bounds");
    }
    void *stack_address = NULL;
    size_t stack_size = 0;
    size_t guard_size = 0;
    if (pthread_attr_getstack(&attributes, &stack_address, &stack_size) != 0 ||
        !stack_address || stack_size == 0) {
        pthread_attr_destroy(&attributes);
        nl_stack_startup_failure("could not determine the native stack bounds");
    }
    stack_low = (uintptr_t)stack_address;
    stack_bytes = (uint64_t)stack_size;
    if (pthread_attr_getguardsize(&attributes, &guard_size) == 0 &&
        guard_size < stack_size) {
        /* Exclude any guard area from the native bytes available to jobs. */
        stack_low += guard_size;
        stack_bytes -= guard_size;
    }
    pthread_attr_destroy(&attributes);
    uintptr_t current = nl_current_stack_pointer();
    if (current < stack_low || current - stack_low > stack_bytes) {
        nl_stack_startup_failure("current stack pointer is outside the reported native stack");
    }
    const uint64_t safety = UINT64_C(80) * 1024;
    uint64_t default_budget = stack_bytes > safety ? stack_bytes - safety : stack_bytes / 2;
    context->native_stack_limit = stack_low;
    context->native_stack_start = current;
    context->recursion_budget = requested_budget
        ? (requested_budget < default_budget ? requested_budget : default_budget)
        : default_budget;
}

void *nl_context_create(uint64_t requested_bytes, uint64_t requested_recursion_budget,
                        const char *entry_name) {
#if defined(__linux__)
    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) nl_stack_startup_failure_for(entry_name, requested_bytes,
                                                 "could not determine the system page size");
    uint64_t bytes = nl_data_stack_reservation(requested_bytes, entry_name);
#if defined(NLC_STACK_MODE_OFFSET)
    /* The offset stack never moves: reserve the address range once (untouched pages cost nothing)
       and fail cleanly when a program outgrows it. */
    bytes = nl_offset_stack_reservation(bytes);
#endif
    if (bytes == 0) {
        nl_stack_startup_failure_for(entry_name, requested_bytes,
                                     "computed data stack reservation is zero");
    }
    uint64_t page_size = (uint64_t)page;
    if (bytes > UINT64_MAX - (page_size - 1)) {
        nl_stack_startup_failure_for(entry_name, bytes, "requested reservation is too large");
    }
    bytes = ((bytes + page_size - 1) / page_size) * page_size;
    if (page_size > SIZE_MAX / 2 || bytes > SIZE_MAX - 2 * page_size) {
        nl_stack_startup_failure_for(entry_name, bytes, "requested reservation is too large");
    }
    /* Keep the context in a stable header page before the movable stack mapping. */
    size_t total = (size_t)bytes + 2 * (size_t)page_size;
    void *mapping = mmap(NULL, total, PROT_NONE,
                         MAP_PRIVATE | MAP_ANONYMOUS
#ifdef MAP_NORESERVE
                             | MAP_NORESERVE
#endif
                         , -1, 0);
#if defined(NLC_STACK_MODE_OFFSET)
    /* Under an address-space limit (ulimit -v, containers) the default range may not fit: halve it
       until it does. A program that then outgrows the range fails with "data stack exhausted". */
    while (mapping == MAP_FAILED && bytes > UINT64_C(256) * 1024 * 1024 && bytes > requested_bytes) {
        bytes = (bytes / 2 / page_size) * page_size;
        total = (size_t)bytes + 2 * (size_t)page_size;
        mapping = mmap(NULL, total, PROT_NONE,
                       MAP_PRIVATE | MAP_ANONYMOUS
#ifdef MAP_NORESERVE
                           | MAP_NORESERVE
#endif
                       , -1, 0);
    }
#endif
    if (mapping == MAP_FAILED) {
        nl_stack_startup_failure_for(entry_name, bytes,
                                     "could not reserve the requested address range");
    }
    unsigned char *base = (unsigned char *)mapping + page_size;
    if (sizeof(nl_data_stack_context) > page_size ||
        mprotect(mapping, (size_t)page_size, PROT_READ | PROT_WRITE) != 0 ||
        mprotect(base, (size_t)bytes, PROT_READ | PROT_WRITE) != 0) {
        munmap(mapping, total);
        nl_stack_startup_failure_for(entry_name, bytes,
                                     "could not enable writable data stack pages");
    }
    nl_data_stack_context *context = (nl_data_stack_context *)mapping;
    memset(context, 0, sizeof(*context));
    context->header_mapping = mapping;
    context->header_bytes = (size_t)page_size;
    context->mapping = base;
    context->mapping_bytes = (size_t)bytes + (size_t)page_size;
    context->reservation_bytes = bytes;
    context->entry_name = entry_name;
    context->base = base;
    context->top = context->base;
    context->limit = context->base + bytes;
    nl_native_stack_setup(context, requested_recursion_budget);
    return context;
#else
    (void)requested_bytes;
    (void)requested_recursion_budget;
    nl_stack_startup_failure("data stack reservation requires Linux in this build");
    return NULL;
#endif
}

__attribute__((noinline)) void nl_recursion_check(void *opaque, uint64_t required,
                                                  int32_t file_id, int32_t line,
                                                  int32_t col) {
    nl_data_stack_context *context = opaque;
    if (!context) nl_stack_startup_failure("missing job context in recursion check");
    uintptr_t stack_pointer = nl_current_stack_pointer();
    const uint64_t reporting_margin = UINT64_C(16) * 1024;
    const uint64_t helper_margin = 512;
    if (required > UINT64_MAX - reporting_margin - helper_margin) {
        nl_fail(19, file_id, line, col);
    }
    uint64_t needed = required + reporting_margin + helper_margin;
    uint64_t remaining = stack_pointer > context->native_stack_limit
        ? (uint64_t)(stack_pointer - context->native_stack_limit)
        : 0;
    uint64_t used = context->native_stack_start > stack_pointer
        ? (uint64_t)(context->native_stack_start - stack_pointer)
        : 0;
    if (remaining < needed || used > context->recursion_budget ||
        needed > context->recursion_budget - used) {
        nl_fail(19, file_id, line, col);
    }
}

void *nl_context_base(void *opaque) {
    nl_data_stack_context *context = opaque;
    return context ? context->base : NULL;
}

void *nl_context_limit(void *opaque) {
    nl_data_stack_context *context = opaque;
    return context ? context->limit : NULL;
}

#if defined(NLC_STACK_MODE_OFFSET)
uint64_t nl_context_base_offset(void *opaque) {
    /* Offsets are relative to the current base, so the base is always zero. */
    (void)opaque;
    return 0;
}

uint64_t nl_context_reservation_bytes(void *opaque) {
    nl_data_stack_context *context = opaque;
    return context ? context->reservation_bytes : 0;
}

void nl_context_note_peak_offset(void *opaque, uint64_t top_offset) {
    nl_data_stack_context *context = opaque;
    if (!context || top_offset > context->reservation_bytes) return;
    if (top_offset > context->peak_used_bytes) context->peak_used_bytes = top_offset;
}
#endif

#if defined(NLC_STACK_MODE_OFFSET)
void nl_context_set_top_offset(void *opaque, uint64_t top_offset) {
    nl_data_stack_context *context = opaque;
    if (!context) return;
    if (top_offset > context->reservation_bytes) {
        nl_stack_startup_failure("invalid offset data stack top");
    }
    context->top_offset = top_offset;
}

#if defined(__linux__)
static void nl_stack_grow_offset(nl_data_stack_context *context, uint64_t needed_bytes,
                                 int32_t file_id, int32_t line, int32_t col) {
    if (needed_bytes <= context->reservation_bytes) return;
    nl_fail(18, file_id, line, col);
}
#endif

uint64_t nl_stack_alloc_offset(void *opaque, uint64_t top_offset, uint64_t bytes,
                               uint64_t alignment, int32_t file_id, int32_t line,
                               int32_t col) {
    nl_data_stack_context *context = opaque;
    if (!context || alignment == 0 || (alignment & (alignment - 1)) != 0) {
        nl_stack_startup_failure("invalid offset region allocation request");
    }
    if (top_offset > context->reservation_bytes || top_offset > UINT64_MAX - (alignment - 1)) {
        nl_fail(18, file_id, line, col);
    }
    uint64_t aligned = (top_offset + alignment - 1) & ~(alignment - 1);
    if (bytes > UINT64_MAX - aligned) nl_fail(18, file_id, line, col);
    uint64_t after = aligned + bytes;
#if defined(__linux__)
    nl_stack_grow_offset(context, after, file_id, line, col);
#else
    if (after > context->reservation_bytes) nl_fail(18, file_id, line, col);
#endif
    if (after > context->peak_used_bytes) context->peak_used_bytes = after;
    return aligned;
}
#endif

void nl_context_destroy(void *opaque) {
    nl_data_stack_context *context = opaque;
    if (!context) return;
#if defined(__linux__)
    if (nl_output_flush_all() != 0) nl_fail(20, -1, 0, 0);
#if defined(NLC_STACK_MODE_OFFSET)
#endif
    munmap(context->mapping, context->mapping_bytes);
    void *header_mapping = context->header_mapping;
    size_t header_bytes = context->header_bytes;
    munmap(header_mapping, header_bytes);
#endif
}

void nl_register_file(int32_t file_id, const char *name) {
    if (file_id < 0) return;
    size_t needed = (size_t)file_id + 1;
    if (needed > nl_file_capacity) {
        /* Startup-only source-name registry growth for runtime diagnostics. */
        size_t capacity = nl_file_capacity ? nl_file_capacity : 8;
        while (capacity < needed) capacity *= 2;
        const char **files = realloc(nl_files, capacity * sizeof(*files));
        if (!files) return;
        for (size_t i = nl_file_capacity; i < capacity; ++i) files[i] = NULL;
        nl_files = files;
        nl_file_capacity = capacity;
    }
    nl_files[file_id] = name;
}

int32_t nl_test_selected_index(void) {
    const char *value = getenv("NLC_TEST_INDEX");
    if (!value || !*value) return -1;
    char *end = NULL;
    long index = strtol(value, &end, 10);
    if (!end || *end || index < 0 || index > INT32_MAX) return -1;
    return (int32_t)index;
}

void nl_set_test_mode(void) {
    nl_test_mode = 1;
}

static const char *nl_file_name(int32_t file_id) {
    const char *file = (file_id >= 0 && (size_t)file_id < nl_file_capacity && nl_files[file_id]) ? nl_files[file_id] : "<source>";
    return file;
}

_Noreturn void nl_fail(int32_t kind, int32_t file_id, int32_t line, int32_t col) {
    (void)nl_output_flush_all();
    const char *file = nl_file_name(file_id);
    const char *message = "runtime failure";
    switch (kind) {
        case 1: message = "overflow in int addition"; break;
        case 2: message = "overflow in int subtraction"; break;
        case 3: message = "overflow in int multiplication"; break;
        case 4: message = "overflow in int negation"; break;
        case 5: message = "overflow in long addition"; break;
        case 6: message = "overflow in long subtraction"; break;
        case 7: message = "overflow in long multiplication"; break;
        case 8: message = "overflow in long negation"; break;
        case 9: message = "divide by zero"; break;
        case 10: message = "bad cast"; break;
        case 11: message = "bad shift"; break;
        case 12: message = "overflow in int division"; break;
        case 13: message = "overflow in long division"; break;
        case 14: message = "unwrap called on none"; break;
        case 15: message = "unwrap called on err"; break;
        case 16: message = "index out of range"; break;
        case 17: message = "binary_search requires sorted input"; break;
        case 21: message = "clamp lower bound is greater than its upper bound"; break;
        case 22: message = "floating-point operation produced NaN"; break;
        case 23: message = "loop step budget exhausted"; break;
        case 24: message = "formatted number does not fit its text"; break;
        case 18: message = "data stack exhausted"; break;
        case 19: message = "recursion budget exhausted"; break;
        case 20: message = "standard output write failed"; break;
    }
    nl_put_text(2, file);
    nl_put_text(2, ":");
    nl_put_signed(2, line);
    nl_put_text(2, ":");
    nl_put_signed(2, col);
    nl_put_text(2, ": ");
    nl_put_text(2, message);
    nl_put_text(2, "\n");
    exit(nl_test_mode ? 70 : 1);
}

void nl_expect_fail_compare(int32_t file_id, int32_t line, int32_t col,
                            const char *source, int64_t left, int64_t right,
                            int32_t is_bool) {
    (void)nl_output_flush_all();
    nl_put_text(1, "  ");
    nl_put_text(1, nl_file_name(file_id));
    nl_put_text(1, ":");
    nl_put_signed(1, line);
    nl_put_text(1, ":");
    nl_put_signed(1, col);
    nl_put_text(1, ": ");
    nl_put_text(1, source);
    nl_put_text(1, "\n    left:  ");
    if (is_bool) nl_put_text(1, left ? "true" : "false"); else nl_put_signed(1, left);
    nl_put_text(1, "\n    right: ");
    if (is_bool) nl_put_text(1, right ? "true" : "false"); else nl_put_signed(1, right);
    nl_put_text(1, "\n");
}

void nl_expect_fail_bool(int32_t file_id, int32_t line, int32_t col,
                         const char *source) {
    (void)nl_output_flush_all();
    nl_put_text(1, "  ");
    nl_put_text(1, nl_file_name(file_id));
    nl_put_text(1, ":");
    nl_put_signed(1, line);
    nl_put_text(1, ":");
    nl_put_signed(1, col);
    nl_put_text(1, ": ");
    nl_put_text(1, source);
    nl_put_text(1, "\n    value: false\n");
}

static void nl_print_bytes(const unsigned char *bytes, uint64_t length) {
    if (nl_output_write(nl_print_fd, bytes, length) != 0) nl_fail(20, -1, 0, 0);
}

void nl_print_ascii(const unsigned char *bytes, uint64_t length) {
    nl_print_bytes(bytes, length);
}

int32_t nl_ascii_compare(const unsigned char *left, uint64_t left_length,
                         const unsigned char *right, uint64_t right_length) {
    uint64_t shared = left_length < right_length ? left_length : right_length;
    int comparison = shared ? memcmp(left, right, (size_t)shared) : 0;
    if (comparison != 0) return comparison < 0 ? -1 : 1;
    if (left_length < right_length) return -1;
    if (left_length > right_length) return 1;
    return 0;
}

uint64_t nl_hash_ascii(const unsigned char *bytes, uint64_t length,
                       uint64_t hash) {
    hash = (hash ^ length) * UINT64_C(1099511628211);
    for (uint64_t index = 0; index < length; ++index) {
        hash = (hash ^ bytes[index]) * UINT64_C(1099511628211);
    }
    return hash;
}

static const unsigned char nl_ascii_decimal_pairs[] =
    "0001020304050607080910111213141516171819202122232425262728293031323334"
    "3536373839404142434445464748495051525354555657585960616263646566676869"
    "707172737475767778798081828384858687888990919293949596979899";

static uint64_t nl_ascii_decimal_digits(uint64_t magnitude) {
    if (magnitude >= UINT64_C(10000000000000000000)) return 20;
    if (magnitude >= UINT64_C(1000000000000000000)) return 19;
    if (magnitude >= UINT64_C(100000000000000000)) return 18;
    if (magnitude >= UINT64_C(10000000000000000)) return 17;
    if (magnitude >= UINT64_C(1000000000000000)) return 16;
    if (magnitude >= UINT64_C(100000000000000)) return 15;
    if (magnitude >= UINT64_C(10000000000000)) return 14;
    if (magnitude >= UINT64_C(1000000000000)) return 13;
    if (magnitude >= UINT64_C(100000000000)) return 12;
    if (magnitude >= UINT64_C(10000000000)) return 11;
    if (magnitude >= UINT64_C(1000000000)) return 10;
    if (magnitude >= UINT64_C(100000000)) return 9;
    if (magnitude >= UINT64_C(10000000)) return 8;
    if (magnitude >= UINT64_C(1000000)) return 7;
    if (magnitude >= UINT64_C(100000)) return 6;
    if (magnitude >= UINT64_C(10000)) return 5;
    if (magnitude >= UINT64_C(1000)) return 4;
    if (magnitude >= UINT64_C(100)) return 3;
    if (magnitude >= UINT64_C(10)) return 2;
    return 1;
}

static uint64_t nl_ascii_i64_magnitude(int64_t value) {
    return value < 0 ? (uint64_t)(-(value + 1)) + 1 : (uint64_t)value;
}

uint64_t nl_ascii_decimal_length_i64(int64_t value) {
    return nl_ascii_decimal_digits(nl_ascii_i64_magnitude(value)) +
           (uint64_t)(value < 0);
}

static uint64_t nl_ascii_format_i64_decimal(int64_t value,
                                            unsigned char *destination) {
    uint64_t magnitude = nl_ascii_i64_magnitude(value);
    uint64_t digits = nl_ascii_decimal_digits(magnitude);
    uint64_t negative = (uint64_t)(value < 0);
    if (negative) destination[0] = '-';
    unsigned char *output = destination + negative;
    uint64_t offset = digits;
    while (magnitude >= 100) {
        uint64_t pair = (magnitude % 100) * 2;
        offset -= 2;
        output[offset] = nl_ascii_decimal_pairs[pair];
        output[offset + 1] = nl_ascii_decimal_pairs[pair + 1];
        magnitude /= 100;
    }
    if (magnitude < 10) {
        output[offset - 1] = (unsigned char)('0' + magnitude);
    } else {
        uint64_t pair = magnitude * 2;
        output[offset - 2] = nl_ascii_decimal_pairs[pair];
        output[offset - 1] = nl_ascii_decimal_pairs[pair + 1];
    }
    return digits + negative;
}

uint64_t nl_ascii_format_i64_radix_general(int64_t value, int32_t radix,
                                           unsigned char *destination) {
    static const unsigned char digits[] = "0123456789abcdef";
    unsigned char reversed[64];
    uint64_t length = 0;
    uint64_t magnitude;
    int negative = value < 0;
    if (radix != 2 && radix != 8 && radix != 10 && radix != 16) return 0;
    if (negative) {
        magnitude = (uint64_t)(-(value + 1)) + 1;
    } else {
        magnitude = (uint64_t)value;
    }
    do {
        reversed[length++] = digits[magnitude % (uint64_t)radix];
        magnitude /= (uint64_t)radix;
    } while (magnitude != 0);
    if (negative) destination[0] = '-';
    uint64_t offset = (uint64_t)negative;
    while (length != 0) destination[offset++] = reversed[--length];
    return offset;
}

uint64_t nl_ascii_format_i64_radix(int64_t value, int32_t radix,
                                  unsigned char *destination) {
    if (radix == 10) return nl_ascii_format_i64_decimal(value, destination);
    return nl_ascii_format_i64_radix_general(value, radix, destination);
}

uint64_t nl_ascii_format_i64(int64_t value, unsigned char *destination) {
    return nl_ascii_format_i64_decimal(value, destination);
}

uint64_t nl_ascii_format_pad_i64(int64_t value, int64_t width, int32_t radix,
                                 int32_t pad_left,
                                 unsigned char *destination) {
    unsigned char formatted[66];
    uint64_t length = nl_ascii_format_i64_radix(value, radix, formatted);
    uint64_t padding = width > 0 && (uint64_t)width > length
                           ? (uint64_t)width - length
                           : 0;
    if (pad_left && padding) memset(destination, ' ', (size_t)padding);
    if (length) {
        memmove(destination + (pad_left ? padding : 0), formatted, (size_t)length);
    }
    if (!pad_left && padding) {
        memset(destination + length, ' ', (size_t)padding);
    }
    return length + padding;
}

uint64_t nl_ascii_format_zero_padded_i64(int64_t value, int64_t width,
                                         unsigned char *destination) {
    unsigned char formatted[66];
    uint64_t length = nl_ascii_format_i64_radix(value, 10, formatted);
    uint64_t padding = width > 0 && (uint64_t)width > length
                           ? (uint64_t)width - length
                           : 0;
    uint64_t sign = length && formatted[0] == '-' ? 1 : 0;
    if (sign) destination[0] = '-';
    if (padding) memset(destination + sign, '0', (size_t)padding);
    if (length > sign) {
        memmove(destination + sign + padding, formatted + sign,
                (size_t)(length - sign));
    }
    return length + padding;
}

static int nl_ascii_digit_value(unsigned char byte) {
    if (byte >= '0' && byte <= '9') return (int)(byte - '0');
    if (byte >= 'a' && byte <= 'f') return (int)(byte - 'a') + 10;
    if (byte >= 'A' && byte <= 'F') return (int)(byte - 'A') + 10;
    return -1;
}

int32_t nl_parse_integer(const unsigned char *bytes, uint64_t length,
                         int32_t radix, int32_t literal, int32_t target_bits,
                         int64_t *value) {
    uint64_t start = 0;
    int negative = 0;
    if (!bytes || !value || (target_bits != 32 && target_bits != 64)) return 0;
    if (literal) {
        radix = 10;
        if (length >= 2 && bytes[0] == '0' &&
            (bytes[1] == 'x' || bytes[1] == 'X')) {
            radix = 16;
            start = 2;
        } else if (length >= 2 && bytes[0] == '0' &&
                   (bytes[1] == 'b' || bytes[1] == 'B')) {
            radix = 2;
            start = 2;
        }
    } else {
        if (length && (bytes[0] == '+' || bytes[0] == '-')) {
            negative = bytes[0] == '-';
            start = 1;
        }
    }
    if (radix != 2 && radix != 8 && radix != 10 && radix != 16) return 0;
    if (start >= length) return 0;

    uint64_t positive_limit = target_bits == 32 ? (uint64_t)INT32_MAX
                                                 : (uint64_t)INT64_MAX;
    uint64_t limit = negative ? positive_limit + 1 : positive_limit;
    uint64_t magnitude = 0;
    int saw_digit = 0;
    int previous_underscore = 0;
    for (uint64_t index = start; index < length; ++index) {
        unsigned char byte = bytes[index];
        if (byte == '_') {
            if (!saw_digit || previous_underscore || index + 1 >= length) return 0;
            int next_digit = nl_ascii_digit_value(bytes[index + 1]);
            if (next_digit < 0 || next_digit >= radix) return 0;
            previous_underscore = 1;
            continue;
        }
        int digit = nl_ascii_digit_value(byte);
        if (digit < 0 || digit >= radix) return 0;
        if (magnitude > (limit - (uint64_t)digit) / (uint64_t)radix) return 0;
        magnitude = magnitude * (uint64_t)radix + (uint64_t)digit;
        saw_digit = 1;
        previous_underscore = 0;
    }
    if (!saw_digit || previous_underscore) return 0;
    if (negative) {
        if (target_bits == 32 && magnitude == (uint64_t)INT32_MAX + 1) {
            *value = INT32_MIN;
        } else if (target_bits == 64 && magnitude == (uint64_t)INT64_MAX + 1) {
            *value = INT64_MIN;
        } else {
            *value = -(int64_t)magnitude;
        }
    } else {
        *value = (int64_t)magnitude;
    }
    return 1;
}

uint64_t nl_pad_copy(const unsigned char *source, uint64_t byte_length,
                     uint64_t codepoints, int64_t width, int32_t pad_left,
                     unsigned char *destination) {
    uint64_t padding = width > 0 && (uint64_t)width > codepoints
                           ? (uint64_t)width - codepoints
                           : 0;
    if (pad_left && padding) memset(destination, ' ', (size_t)padding);
    if (byte_length) {
        memmove(destination + (pad_left ? padding : 0), source,
                (size_t)byte_length);
    }
    if (!pad_left && padding) {
        memset(destination + byte_length, ' ', (size_t)padding);
    }
    return byte_length + padding;
}

void nl_ascii_upper_copy(const unsigned char *source,
                         unsigned char *destination, uint64_t length) {
    for (uint64_t index = 0; index < length; ++index) {
        unsigned char byte = source[index];
        destination[index] = byte >= 'a' && byte <= 'z'
                                 ? (unsigned char)(byte - ('a' - 'A'))
                                 : byte;
    }
}

static int nl_utf8_decode(const unsigned char *bytes, uint64_t length,
                          uint64_t *offset, uint32_t *codepoint) {
    if (*offset >= length) return 0;
    uint64_t at = *offset;
    unsigned char first = bytes[at++];
    uint32_t value;
    uint64_t extra;
    if (first <= 0x7f) { value = first; extra = 0; }
    else if (first >= 0xc2 && first <= 0xdf) { value = first & 0x1f; extra = 1; }
    else if (first >= 0xe0 && first <= 0xef) { value = first & 0x0f; extra = 2; }
    else if (first >= 0xf0 && first <= 0xf4) { value = first & 0x07; extra = 3; }
    else return 0;
    if (extra > length - at) return 0;
    for (uint64_t index = 0; index < extra; ++index) {
        unsigned char next = bytes[at++];
        if ((next & 0xc0) != 0x80) return 0;
        if (index == 0 && first == 0xe0 && next < 0xa0) return 0;
        if (index == 0 && first == 0xed && next >= 0xa0) return 0;
        if (index == 0 && first == 0xf0 && next < 0x90) return 0;
        if (index == 0 && first == 0xf4 && next >= 0x90) return 0;
        value = (value << 6) | (uint32_t)(next & 0x3f);
    }
    *offset = at;
    *codepoint = value;
    return 1;
}

int32_t nl_utf8_validate(const unsigned char *bytes, uint64_t length,
                         int64_t *valid_up_to, int64_t *codepoint_count) {
    if ((length && !bytes) || length > INT64_MAX) return 0;
    uint64_t offset = 0;
    uint64_t count = 0;
    while (offset < length) {
        uint64_t sequence_start = offset;
        uint32_t codepoint;
        if (!nl_utf8_decode(bytes, length, &offset, &codepoint)) {
            if (valid_up_to) *valid_up_to = (int64_t)sequence_start;
            return 0;
        }
        (void)codepoint;
        if (count == INT64_MAX) {
            if (valid_up_to) *valid_up_to = (int64_t)sequence_start;
            return 0;
        }
        ++count;
    }
    if (valid_up_to) *valid_up_to = (int64_t)length;
    if (codepoint_count) *codepoint_count = (int64_t)count;
    return 1;
}

int32_t nl_utf8_count(const unsigned char *bytes, uint64_t length,
                      int64_t *codepoint_count) {
    if (!codepoint_count) return 0;
    return nl_utf8_validate(bytes, length, NULL, codepoint_count);
}

int64_t nl_utf8_offset(const unsigned char *bytes, uint64_t length,
                       int64_t codepoint_index) {
    if (codepoint_index < 0 || (length && !bytes)) return -1;
    uint64_t offset = 0;
    int64_t count = 0;
    while (count < codepoint_index) {
        uint32_t codepoint;
        if (!nl_utf8_decode(bytes, length, &offset, &codepoint)) return -1;
        (void)codepoint;
        ++count;
    }
    return offset <= INT64_MAX ? (int64_t)offset : -1;
}

static uint64_t nl_utf8_encode(uint32_t codepoint, unsigned char *destination) {
    if (codepoint <= 0x7f) {
        destination[0] = (unsigned char)codepoint;
        return 1;
    }
    if (codepoint <= 0x7ff) {
        destination[0] = (unsigned char)(0xc0 | (codepoint >> 6));
        destination[1] = (unsigned char)(0x80 | (codepoint & 0x3f));
        return 2;
    }
    if (codepoint <= 0xffff) {
        destination[0] = (unsigned char)(0xe0 | (codepoint >> 12));
        destination[1] = (unsigned char)(0x80 | ((codepoint >> 6) & 0x3f));
        destination[2] = (unsigned char)(0x80 | (codepoint & 0x3f));
        return 3;
    }
    destination[0] = (unsigned char)(0xf0 | (codepoint >> 18));
    destination[1] = (unsigned char)(0x80 | ((codepoint >> 12) & 0x3f));
    destination[2] = (unsigned char)(0x80 | ((codepoint >> 6) & 0x3f));
    destination[3] = (unsigned char)(0x80 | (codepoint & 0x3f));
    return 4;
}

static const typeof(nl_upper_map[0]) *nl_upper_mapping(uint32_t codepoint) {
    size_t low = 0;
    size_t high = sizeof(nl_upper_map) / sizeof(nl_upper_map[0]);
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (nl_upper_map[middle].source < codepoint) low = middle + 1;
        else high = middle;
    }
    return low < sizeof(nl_upper_map) / sizeof(nl_upper_map[0]) &&
                   nl_upper_map[low].source == codepoint
               ? &nl_upper_map[low]
               : NULL;
}

uint64_t nl_text_upper_copy(const unsigned char *source,
                            uint64_t source_length,
                            unsigned char *destination,
                            int64_t *codepoint_count) {
    uint64_t source_offset = 0;
    uint64_t output_offset = 0;
    int64_t output_count = 0;
    while (source_offset < source_length) {
        uint32_t codepoint;
        if (!nl_utf8_decode(source, source_length, &source_offset, &codepoint))
            return UINT64_MAX;
        const typeof(nl_upper_map[0]) *mapping = nl_upper_mapping(codepoint);
        if (mapping) {
            for (uint8_t index = 0; index < mapping->length; ++index) {
                output_offset += nl_utf8_encode(mapping->target[index], destination + output_offset);
                ++output_count;
            }
        } else {
            output_offset += nl_utf8_encode(codepoint, destination + output_offset);
            ++output_count;
        }
    }
    if (codepoint_count) *codepoint_count = output_count;
    return output_offset;
}

int32_t nl_bytes_are_ascii(const unsigned char *bytes, uint64_t length) {
    if (length && !bytes) return 0;
    for (uint64_t index = 0; index < length; ++index) {
        if (bytes[index] > 0x7f) return 0;
    }
    return 1;
}

void nl_print_set_fd(int32_t fd) {
    if (fd == STDOUT_FILENO || fd == STDERR_FILENO) nl_print_fd = fd;
}

void nl_print_error_prefix(void) {
    static const unsigned char prefix[] = "error: ";
    if (nl_output_write(STDERR_FILENO, prefix, sizeof(prefix) - 1) != 0) nl_fail(20, -1, 0, 0);
}

static void nl_print_decimal(int64_t value, int newline) {
    unsigned char buffer[22];
    uint64_t length = nl_ascii_format_i64(value, buffer);
    if (newline) buffer[length++] = '\n';
    nl_print_bytes(buffer, length);
}

void nl_print_int(int32_t value) {
    nl_print_decimal(value, 1);
}

void nl_print_long(int64_t value) {
    nl_print_decimal(value, 1);
}

void nl_print_bool(_Bool value) {
    static const unsigned char yes[] = "true\n";
    static const unsigned char no[] = "false\n";
    nl_print_bytes(value ? yes : no, value ? sizeof(yes) - 1 : sizeof(no) - 1);
}

void nl_print_int_raw(int32_t value) {
    nl_print_decimal(value, 0);
}

void nl_print_long_raw(int64_t value) {
    nl_print_decimal(value, 0);
}

void nl_print_bool_raw(_Bool value) {
    static const unsigned char yes[] = "true";
    static const unsigned char no[] = "false";
    nl_print_bytes(value ? yes : no, value ? sizeof(yes) - 1 : sizeof(no) - 1);
}

void nl_print_text(const char *value) {
    if (value) {
        uint64_t length = (uint64_t)strlen(value);
        nl_print_bytes((const unsigned char *)value, length);
    }
}

void nl_print_newline(void) {
    static const unsigned char newline = '\n';
    nl_print_bytes(&newline, 1);
}

void nl_expect_fail_header(int32_t file_id, int32_t line, int32_t col,
                           const char *source) {
    (void)nl_output_flush_all();
    nl_put_text(1, "  ");
    nl_put_text(1, nl_file_name(file_id));
    nl_put_text(1, ":");
    nl_put_signed(1, line);
    nl_put_text(1, ":");
    nl_put_signed(1, col);
    nl_put_text(1, ": ");
    nl_put_text(1, source);
    nl_put_text(1, "\n");
}
void nl_expect_fail_left(void) {
    (void)nl_output_flush_all();
    nl_put_text(1, "    left:  ");
}
void nl_expect_fail_right(void) {
    (void)nl_output_flush_all();
    nl_put_text(1, "    right: ");
}

typedef struct { int root_fd; } nl_fs_handle;
typedef struct { int fd; } nl_out_handle;
typedef struct { int argc; char **argv; } nl_args_view;
typedef struct {
    int capabilities;
    int root_fd;
    char *test_directory;
    nl_fs_handle fs;
    nl_out_handle out[2];
    nl_args_view args;
} nl_environment;

static void nl_io_error(void *result, int error_tag, int error_code) {
    unsigned char *bytes = (unsigned char *)result;
    memset(bytes, 0, 12);
    int32_t *words = (int32_t *)bytes;
    words[0] = error_tag < 0 ? 0 : 1;
    if (error_tag >= 0) {
        words[1] = error_tag;
        if (error_tag == 7) words[2] = error_code;
    }
}

#define NL_IO_ERROR_INVALID_UTF8 8

static int nl_errno_error(int error) {
    if (error == ENOENT) return 0;
    if (error == EACCES || error == EPERM || error == EROFS) return 1;
    if (error == EXDEV || error == ELOOP) return 6;
    return 7;
}

static void nl_args_startup_failure(const char *message) {
    nl_put_text(2, "nlc: startup argument failure: ");
    nl_put_text(2, message);
    nl_put_text(2, "\n");
    exit(1);
}

#if defined(NLC_TEST_BUILD)
/* Test-only temporary-root cleanup may use short-lived path strings. */
static void nl_remove_tree(const char *path) {
    DIR *directory = opendir(path);
    if (!directory) {
        unlink(path);
        return;
    }
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t path_length = strlen(path);
        size_t name_length = strlen(entry->d_name);
        char *child = (char *)malloc(path_length + name_length + 2);
        if (!child) continue;
        memcpy(child, path, path_length);
        child[path_length] = '/';
        memcpy(child + path_length + 1, entry->d_name, name_length + 1);
        struct stat status;
        if (lstat(child, &status) == 0 && S_ISDIR(status.st_mode)) nl_remove_tree(child);
        else unlink(child);
        free(child);
    }
    closedir(directory);
    rmdir(path);
}
#endif

void *nl_env_create(int argc, char **argv, int capabilities) {
    /* Startup-only capability view, released after the program entry point. */
    nl_environment *environment = (nl_environment *)calloc(1, sizeof(nl_environment));
    if (!environment) nl_stack_startup_failure("cannot allocate capability environment");
    environment->capabilities = capabilities;
    (void)signal(SIGPIPE, SIG_IGN);
    environment->root_fd = -1;
    environment->fs.root_fd = -1;
    environment->args.argv = argv;
    for (int i = 1; i < argc; ++i) {
        if (environment->args.argc == 64) nl_args_startup_failure("more than 64 program arguments were supplied");
        size_t length = strlen(argv[i]);
        if (length > 4096) nl_args_startup_failure("a program argument is longer than 4096 bytes");
        environment->args.argc++;
    }
#if defined(NLC_TEST_BUILD)
    char temporary[] = "/tmp/next-lang-test-XXXXXX";
    char *directory = mkdtemp(temporary);
    if (!directory) nl_stack_startup_failure("cannot create the test file-system root");
    /* Test-only startup root copy, released by nl_env_destroy. */
    environment->test_directory = strdup(directory);
    if (!environment->test_directory) nl_stack_startup_failure("cannot save the test file-system root");
    environment->root_fd = open(directory, O_PATH | O_DIRECTORY | O_CLOEXEC);
#else
    environment->root_fd = open(".", O_PATH | O_DIRECTORY | O_CLOEXEC);
#endif
    if (environment->root_fd < 0) nl_stack_startup_failure("cannot open the file-system root");
    environment->fs.root_fd = environment->root_fd;
    environment->out[0].fd = STDOUT_FILENO;
    environment->out[1].fd = STDERR_FILENO;
    return environment;
}

void nl_env_destroy(void *value) {
    nl_environment *environment = (nl_environment *)value;
    if (!environment) return;
    if (environment->root_fd >= 0) close(environment->root_fd);
#if defined(NLC_TEST_BUILD)
    if (environment->test_directory) {
        nl_remove_tree(environment->test_directory);
        free(environment->test_directory);
    }
#endif
    /* Startup-only capability environment cleanup. */
    free(environment);
}

void *nl_env_args(void *value) { return &((nl_environment *)value)->args; }
void *nl_env_fs(void *value) { return &((nl_environment *)value)->fs; }
void *nl_env_out(void *value, int fd) {
    nl_environment *environment = (nl_environment *)value;
    return &environment->out[fd == STDERR_FILENO ? 1 : 0];
}

_Noreturn void nl_env_exit(int32_t code) {
    if (nl_output_flush_all() != 0) nl_fail(20, -1, 0, 0);
    if (nl_test_mode) {
        nl_put_text(2, "Env.exit(");
        nl_put_signed(2, code);
        nl_put_text(2, ") cannot be used in a test; this test process failed\n");
        exit(70);
    }
    exit(code);
}
int64_t nl_args_count(void *value) { return ((nl_args_view *)value)->argc; }
void *nl_args_get(void *value, int64_t index) {
    nl_args_view *args = (nl_args_view *)value;
    if (index < 0 || index >= args->argc) return NULL;
    return args->argv[index + 1];
}
int64_t nl_arg_length(void *value) { return value ? (int64_t)strlen((const char *)value) : 0; }
int32_t nl_arg_byte(void *value, int64_t index) {
    if (!value || index < 0) return -1;
    const unsigned char *argument = (const unsigned char *)value;
    size_t length = strlen((const char *)value);
    return (uint64_t)index < length ? (int32_t)argument[index] : -1;
}

static int nl_extract_path(const void *value, int is_argument, uint64_t capacity,
                           char output[4097], int *error_tag, int *error_code) {
    uint64_t length;
    if (is_argument == 1) {
        if (!value) { *error_tag = 0; return 0; }
        length = strlen((const char *)value);
        if (length > 4096) { *error_tag = 2; return 0; }
        memcpy(output, value, (size_t)length);
    } else if (is_argument == 2) {
        if (!value) { *error_tag = 5; return 0; }
        const unsigned char *bytes = *(const unsigned char *const *)value;
        int64_t count = *(const int64_t *)((const unsigned char *)value + 8);
        if (count < 0 || (uint64_t)count > capacity) { *error_tag = 5; return 0; }
        length = (uint64_t)count;
        if (length > 4096) { *error_tag = 2; return 0; }
        if (length && !bytes) { *error_tag = 5; return 0; }
        for (uint64_t i = 0; i < length; ++i) {
            if (bytes[i] == 0) { *error_tag = 5; return 0; }
            output[i] = (char)bytes[i];
        }
    } else {
        if (!value) { *error_tag = 5; return 0; }
        int64_t count = *(const int64_t *)value;
        if (count < 0 || (uint64_t)count > capacity) { *error_tag = 5; return 0; }
        length = (uint64_t)count;
        if (length > 4096) { *error_tag = 2; return 0; }
        const int32_t *items = (const int32_t *)((const unsigned char *)value + 8);
        for (uint64_t i = 0; i < length; ++i) {
            if (items[i] == 0) { *error_tag = 5; return 0; }
            if (items[i] < 0 || items[i] > 255) { *error_tag = 7; *error_code = EINVAL; return 0; }
            output[i] = (char)items[i];
        }
    }
    output[length] = 0;
    if (length && output[0] == '/') { *error_tag = 6; return 0; }
    if (!length) memcpy(output, ".", 2);
    return 1;
}

static int nl_extract_raw(const void *value, int is_argument, uint64_t capacity,
                          unsigned char scratch[4096],
                          const unsigned char **bytes, uint64_t *length,
                          int *error_tag, int *error_code) {
    if (is_argument == 1) {
        if (!value) { *error_tag = 0; return 0; }
        *bytes = (const unsigned char *)value;
        *length = strlen((const char *)value);
        return 1;
    }
    if (is_argument == 2) {
        if (!value) { *error_tag = 5; return 0; }
        const unsigned char *data = *(const unsigned char *const *)value;
        int64_t count = *(const int64_t *)((const unsigned char *)value + 8);
        if (count < 0 || (uint64_t)count > capacity || (count && !data)) {
            *error_tag = 5;
            return 0;
        }
        *bytes = data;
        *length = (uint64_t)count;
        return 1;
    }
    if (!value) { *error_tag = 5; return 0; }
    int64_t count = *(const int64_t *)value;
    if (count < 0 || (uint64_t)count > capacity) { *error_tag = 5; return 0; }
    if ((uint64_t)count > 4096) { *error_tag = 2; return 0; }
    const int32_t *items = (const int32_t *)((const unsigned char *)value + 8);
    for (int64_t i = 0; i < count; ++i) {
        if (items[i] < 0 || items[i] > 255) { *error_tag = 7; *error_code = EINVAL; return 0; }
        scratch[i] = (unsigned char)items[i];
    }
    *bytes = scratch;
    *length = (uint64_t)count;
    return 1;
}

static int nl_open_beneath(int root_fd, const char *path, int flags, mode_t mode) {
#if defined(__linux__) && defined(SYS_openat2)
    struct open_how how;
    memset(&how, 0, sizeof(how));
    how.flags = (uint64_t)flags;
    how.mode = (uint64_t)mode;
    how.resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS;
    return (int)syscall(SYS_openat2, root_fd, path, &how, sizeof(how));
#else
    errno = ENOSYS;
    return -1;
#endif
}

static int nl_entry_kind_beneath(int root_fd, const char *directory_path,
                                 const char *name, size_t name_length) {
    size_t directory_length = strlen(directory_path);
    size_t separator = directory_length && directory_path[directory_length - 1] != '/';
    if (directory_length + separator + name_length > 4096) return 2;
    char path[4097];
    memcpy(path, directory_path, directory_length);
    size_t offset = directory_length;
    if (separator) path[offset++] = '/';
    memcpy(path + offset, name, name_length);
    path[offset + name_length] = 0;
    int target = nl_open_beneath(root_fd, path, O_PATH | O_CLOEXEC, 0);
    if (target < 0) return 2;
    struct stat status;
    int kind = 2;
    if (fstat(target, &status) == 0) {
        kind = S_ISREG(status.st_mode) ? 0 : S_ISDIR(status.st_mode) ? 1 : 2;
    }
    close(target);
    return kind;
}

static int nl_write_all(int fd, const unsigned char *bytes, uint64_t length) {
    uint64_t written = 0;
    while (written < length) {
        size_t chunk = length - written > (uint64_t)SSIZE_MAX ? (size_t)SSIZE_MAX : (size_t)(length - written);
        ssize_t result = write(fd, bytes + written, chunk);
        if (result < 0 && errno == EINTR) continue;
        if (result <= 0) return errno ? errno : EIO;
        written += (uint64_t)result;
    }
    return 0;
}

static int nl_output_index(int fd) {
    if (fd == STDOUT_FILENO) return 0;
    if (fd == STDERR_FILENO) return 1;
    return -1;
}

static int nl_output_uses_same_terminal(void) {
    if (nl_output_shared_terminal >= 0) return nl_output_shared_terminal;
    struct stat output_status;
    struct stat error_status;
    nl_output_is_terminal[0] = isatty(STDOUT_FILENO) != 0;
    nl_output_is_terminal[1] = isatty(STDERR_FILENO) != 0;
    nl_output_shared_terminal =
        nl_output_is_terminal[0] && nl_output_is_terminal[1] &&
                fstat(STDOUT_FILENO, &output_status) == 0 &&
                fstat(STDERR_FILENO, &error_status) == 0 &&
                output_status.st_dev == error_status.st_dev &&
                output_status.st_ino == error_status.st_ino
            ? 1
            : 0;
    return nl_output_shared_terminal;
}

static int nl_output_flush_index(int index) {
    int fd = index == 0 ? STDOUT_FILENO : STDERR_FILENO;
    size_t length = nl_output_lengths[index];
    size_t written = 0;
    while (written < length) {
        ssize_t result = write(fd, nl_output_buffers[index] + written,
                               length - written);
        if (result < 0 && errno == EINTR) continue;
        if (result <= 0) {
            int error = errno ? errno : EIO;
            if (written) {
                memmove(nl_output_buffers[index],
                        nl_output_buffers[index] + written, length - written);
                nl_output_lengths[index] = length - written;
            }
            return error;
        }
        written += (size_t)result;
    }
    nl_output_lengths[index] = 0;
    return 0;
}

static int nl_output_flush_all(void) {
    int shared_terminal = nl_output_uses_same_terminal();
    int first = 0;
    int second = 1;
    if (shared_terminal && nl_output_lengths[0] && nl_output_lengths[1]) {
        /* The last queued stream is newer, so flush the other stream first. */
        if (nl_output_last_stream == 0) {
            first = 1;
            second = 0;
        }
    }
    int error = nl_output_flush_index(first);
    int other_error = nl_output_flush_index(second);
    return error ? error : other_error;
}

static int nl_output_write(int fd, const unsigned char *bytes, uint64_t length) {
    int index = nl_output_index(fd);
    if (index < 0) return nl_write_all(fd, bytes, length);
    int other = index == 0 ? 1 : 0;
    int shared_terminal = nl_output_uses_same_terminal();
    if (shared_terminal && nl_output_lengths[other]) {
        int error = nl_output_flush_index(other);
        if (error) return error;
    }
    int line_buffered = nl_output_is_terminal[index];
    while (length) {
        size_t available = NL_OUTPUT_BUFFER_CAPACITY - nl_output_lengths[index];
        if (!available) {
            int error = nl_output_flush_index(index);
            if (error) return error;
            available = NL_OUTPUT_BUFFER_CAPACITY;
        }
        size_t amount = length < available ? (size_t)length : available;
        int flush_line = 0;
        if (line_buffered) {
            const unsigned char *newline = memchr(bytes, '\n', amount);
            if (newline) {
                amount = (size_t)(newline - bytes) + 1;
                flush_line = 1;
            }
        }
        memcpy(nl_output_buffers[index] + nl_output_lengths[index], bytes, amount);
        nl_output_lengths[index] += amount;
        bytes += amount;
        length -= amount;
        nl_output_last_stream = index;
        if (flush_line) {
            int error = nl_output_flush_index(index);
            if (error) return error;
        }
    }
    return 0;
}

static int nl_output_write_and_flush(int fd, const unsigned char *bytes,
                                     uint64_t length) {
    int index = nl_output_index(fd);
    int error = nl_output_write(fd, bytes, length);
    if (!error && index >= 0) error = nl_output_flush_index(index);
    if (error && index >= 0) {
        /* Out.write reports this failure to its caller; do not retry at exit. */
        nl_output_lengths[index] = 0;
    }
    return error;
}

static int nl_write_byte_list(int fd, const void *value, uint64_t capacity) {
    if (!value) return EINVAL;
    int64_t count = *(const int64_t *)value;
    if (count < 0 || (uint64_t)count > capacity) return EINVAL;
    const int32_t *items = (const int32_t *)((const unsigned char *)value + 8);
    unsigned char scratch[8192];
    uint64_t offset = 0;
    while (offset < (uint64_t)count) {
        size_t amount = (size_t)(((uint64_t)count - offset) < sizeof(scratch) ? ((uint64_t)count - offset) : sizeof(scratch));
        for (size_t i = 0; i < amount; ++i) {
            int32_t byte = items[offset + i];
            if (byte < 0 || byte > 255) return EINVAL;
            scratch[i] = (unsigned char)byte;
        }
        int error = nl_output_write(fd, scratch, amount);
        if (error) return error;
        offset += amount;
    }
    return 0;
}

void nl_fs_read(void *handle, void *path_value, int path_is_argument, uint64_t path_capacity,
                void *buffer, uint64_t capacity, void *result) {
    int error_tag = -1, error_code = 0;
    char path[4097];
    if (buffer) *(int64_t *)buffer = 0;
    if (capacity > (SIZE_MAX - 8) / 4 || !buffer) {
        nl_io_error(result, 2, 0); return;
    }
    if (!nl_extract_path(path_value, path_is_argument, path_capacity, path, &error_tag, &error_code)) {
        nl_io_error(result, error_tag, error_code); return;
    }
    int flush_error = nl_output_flush_all();
    if (flush_error) {
        nl_io_error(result, nl_errno_error(flush_error), flush_error);
        return;
    }
    int fd = nl_open_beneath(((nl_fs_handle *)handle)->root_fd, path, O_RDONLY | O_CLOEXEC, 0);
    if (fd < 0) { int error = errno; nl_io_error(result, nl_errno_error(error), error); return; }
    int32_t *items = (int32_t *)((unsigned char *)buffer + 8);
    unsigned char scratch[8192];
    uint64_t total = 0;
    int failure = 0;
    while (total < capacity) {
        size_t amount = (size_t)((capacity - total) < sizeof(scratch) ? capacity - total : sizeof(scratch));
        ssize_t got = read(fd, scratch, amount);
        if (got < 0 && errno == EINTR) continue;
        if (got < 0) { failure = errno; break; }
        if (got == 0) break;
        for (ssize_t i = 0; i < got; ++i) items[total + (uint64_t)i] = scratch[i];
        total += (uint64_t)got;
    }
    if (!failure && total == capacity) {
        unsigned char extra;
        for (;;) {
            ssize_t got = read(fd, &extra, 1);
            if (got < 0 && errno == EINTR) continue;
            if (got < 0) failure = errno;
            else if (got > 0) error_tag = 2;
            break;
        }
    }
    close(fd);
    if (failure || error_tag == 2) {
        *(int64_t *)buffer = 0;
        nl_io_error(result, error_tag == 2 ? 2 : nl_errno_error(failure), failure);
        return;
    }
    *(int64_t *)buffer = (int64_t)total;
    nl_io_error(result, -1, 0);
}

void nl_fs_read_string(void *handle, void *path_value, int path_is_argument,
                       uint64_t path_capacity, unsigned char *output,
                       uint64_t capacity, int is_text,
                       uint64_t codepoint_capacity, int64_t *output_length,
                       int64_t *output_codepoints, void *result) {
    int error_tag = -1, error_code = 0;
    char path[4097];
    if (output_length) *output_length = 0;
    if (output_codepoints) *output_codepoints = 0;
    if (!output_length || (capacity && !output) || capacity > SIZE_MAX - 1) {
        nl_io_error(result, 2, 0);
        return;
    }
    if (!nl_extract_path(path_value, path_is_argument, path_capacity,
                         path, &error_tag, &error_code)) {
        nl_io_error(result, error_tag, error_code);
        return;
    }
    int flush_error = nl_output_flush_all();
    if (flush_error) {
        nl_io_error(result, nl_errno_error(flush_error), flush_error);
        return;
    }
    int fd = nl_open_beneath(((nl_fs_handle *)handle)->root_fd,
                             path, O_RDONLY | O_CLOEXEC, 0);
    if (fd < 0) {
        int error = errno;
        nl_io_error(result, nl_errno_error(error), error);
        return;
    }
    uint64_t total = 0;
    int failure = 0;
    while (total < capacity) {
        size_t amount = (size_t)((capacity - total) < 8192 ? capacity - total : 8192);
        ssize_t got = read(fd, output + total, amount);
        if (got < 0 && errno == EINTR) continue;
        if (got < 0) { failure = errno; break; }
        if (got == 0) break;
        total += (uint64_t)got;
    }
    if (!failure && total == capacity) {
        unsigned char extra;
        for (;;) {
            ssize_t got = read(fd, &extra, 1);
            if (got < 0 && errno == EINTR) continue;
            if (got < 0) failure = errno;
            else if (got > 0) error_tag = 2;
            break;
        }
    }
    close(fd);
    int64_t codepoints = 0;
    if (!failure && error_tag != 2 && is_text) {
        if (!nl_utf8_count(output, total, &codepoints)) {
            error_tag = NL_IO_ERROR_INVALID_UTF8;
        } else if ((uint64_t)codepoints > codepoint_capacity) {
            error_tag = 2;
        }
    }
    if (failure || error_tag == 2 || error_tag == NL_IO_ERROR_INVALID_UTF8) {
        nl_io_error(result, failure ? nl_errno_error(failure) : error_tag,
                    failure ? failure : error_code);
        return;
    }
    *output_length = (int64_t)total;
    if (output_codepoints) *output_codepoints = codepoints;
    nl_io_error(result, -1, 0);
}

#define NL_DIR_NAME_SLOT_BYTES UINT64_C(16392)

struct nl_linux_dirent64 {
    uint64_t inode;
    int64_t offset;
    unsigned short record_length;
    unsigned char type;
    char name[];
};

typedef struct {
    int fd;
    size_t position;
    size_t length;
    unsigned char bytes[8192];
} nl_directory_iterator;

static int nl_directory_next(nl_directory_iterator *iterator,
                             struct nl_linux_dirent64 **entry) {
    for (;;) {
        if (iterator->position == iterator->length) {
#if defined(SYS_getdents64)
            long amount = syscall(SYS_getdents64, iterator->fd,
                                  iterator->bytes, sizeof(iterator->bytes));
#else
            long amount = -1;
            errno = ENOSYS;
#endif
            if (amount < 0 && errno == EINTR) continue;
            if (amount < 0) return -1;
            if (amount == 0) return 0;
            iterator->position = 0;
            iterator->length = (size_t)amount;
        }
        size_t remaining = iterator->length - iterator->position;
        if (remaining < offsetof(struct nl_linux_dirent64, name) + 1) {
            errno = EIO;
            return -1;
        }
        struct nl_linux_dirent64 *current =
            (struct nl_linux_dirent64 *)(iterator->bytes + iterator->position);
        size_t minimum = offsetof(struct nl_linux_dirent64, name) + 1;
        if (current->record_length < minimum || current->record_length > remaining) {
            errno = EIO;
            return -1;
        }
        size_t name_capacity = current->record_length -
                               offsetof(struct nl_linux_dirent64, name);
        if (!memchr(current->name, 0, name_capacity)) {
            errno = EIO;
            return -1;
        }
        iterator->position += current->record_length;
        *entry = current;
        return 1;
    }
}

static unsigned char *nl_dir_name_slot(unsigned char *base, size_t index) {
    return base + 8 + (uint64_t)index * NL_DIR_NAME_SLOT_BYTES;
}

static int nl_dir_entry_compare(const unsigned char *base, size_t left_index,
                                size_t right_index) {
    const unsigned char *left = nl_dir_name_slot((unsigned char *)base, left_index);
    const unsigned char *right = nl_dir_name_slot((unsigned char *)base, right_index);
    uint64_t left_length = (uint64_t)*(const int64_t *)left;
    uint64_t right_length = (uint64_t)*(const int64_t *)right;
    const int32_t *left_bytes = (const int32_t *)(left + 8);
    const int32_t *right_bytes = (const int32_t *)(right + 8);
    uint64_t common = left_length < right_length ? left_length : right_length;
    for (uint64_t index = 0; index < common; ++index) {
        uint32_t left_byte = (uint32_t)left_bytes[index];
        uint32_t right_byte = (uint32_t)right_bytes[index];
        if (left_byte < right_byte) return -1;
        if (left_byte > right_byte) return 1;
    }
    return left_length < right_length ? -1 : left_length > right_length;
}

static void nl_dir_entry_swap(unsigned char *base, uint64_t capacity,
                              size_t left_index, size_t right_index) {
    if (left_index == right_index) return;
    unsigned char *left = nl_dir_name_slot(base, left_index);
    unsigned char *right = nl_dir_name_slot(base, right_index);
    uint64_t left_length = (uint64_t)*(int64_t *)left;
    uint64_t right_length = (uint64_t)*(int64_t *)right;
    int32_t *left_bytes = (int32_t *)(left + 8);
    int32_t *right_bytes = (int32_t *)(right + 8);
    uint64_t longest = left_length > right_length ? left_length : right_length;
    for (uint64_t index = 0; index < longest; ++index) {
        int32_t left_byte = index < left_length ? left_bytes[index] : 0;
        int32_t right_byte = index < right_length ? right_bytes[index] : 0;
        if (index < right_length) left_bytes[index] = right_byte;
        if (index < left_length) right_bytes[index] = left_byte;
    }
    *(int64_t *)left = (int64_t)right_length;
    *(int64_t *)right = (int64_t)left_length;

    int32_t *kinds = (int32_t *)(base + 8 + capacity * NL_DIR_NAME_SLOT_BYTES);
    int32_t kind = kinds[left_index];
    kinds[left_index] = kinds[right_index];
    kinds[right_index] = kind;
}

static void nl_dir_sift_down(unsigned char *base, uint64_t capacity,
                             size_t root, size_t count) {
    for (;;) {
        size_t child = root * 2 + 1;
        if (child >= count) return;
        if (child + 1 < count &&
            nl_dir_entry_compare(base, child, child + 1) < 0) {
            ++child;
        }
        if (nl_dir_entry_compare(base, root, child) >= 0) return;
        nl_dir_entry_swap(base, capacity, root, child);
        root = child;
    }
}

/* Sort the caller's live entries in place without a capacity-sized scratch array. */
static void nl_dir_sort(unsigned char *base, uint64_t capacity, size_t count) {
    for (size_t start = count / 2; start > 0;) {
        --start;
        nl_dir_sift_down(base, capacity, start, count);
    }
    for (size_t end = count; end > 1;) {
        --end;
        nl_dir_entry_swap(base, capacity, 0, end);
        nl_dir_sift_down(base, capacity, 0, end);
    }
}

static void nl_dir_entry_store(unsigned char *base, uint64_t capacity,
                               size_t index, const char *name, size_t length,
                               int kind) {
    unsigned char *slot = nl_dir_name_slot(base, index);
    *(int64_t *)slot = (int64_t)length;
    int32_t *bytes = (int32_t *)(slot + 8);
    for (size_t byte = 0; byte < length; ++byte) {
        bytes[byte] = (unsigned char)name[byte];
    }
    int32_t *kinds = (int32_t *)(base + 8 + capacity * NL_DIR_NAME_SLOT_BYTES);
    kinds[index] = kind;
}

void nl_fs_list(void *handle, void *path_value, int path_is_argument, uint64_t path_capacity,
                void *output, uint64_t capacity, void *result) {
    int error_tag = -1, error_code = 0;
    char path[4097];
    if (output) *(int64_t *)output = 0;
    if (capacity > (SIZE_MAX - 8) / 16396 || !output) { nl_io_error(result, 3, 0); return; }
    if (!nl_extract_path(path_value, path_is_argument, path_capacity, path, &error_tag, &error_code)) {
        nl_io_error(result, error_tag, error_code); return;
    }
    int flush_error = nl_output_flush_all();
    if (flush_error) { nl_io_error(result, nl_errno_error(flush_error), flush_error); return; }
    int fd = nl_open_beneath(((nl_fs_handle *)handle)->root_fd, path, O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0);
    if (fd < 0) { int error = errno; nl_io_error(result, nl_errno_error(error), error); return; }
    nl_directory_iterator iterator = { .fd = fd };
    unsigned char *base = (unsigned char *)output;
    size_t count = 0;
    int failure_tag = -1, failure_code = 0;
    for (;;) {
        struct nl_linux_dirent64 *entry;
        int next = nl_directory_next(&iterator, &entry);
        if (next <= 0) {
            if (next < 0) { failure_tag = nl_errno_error(errno); failure_code = errno; }
            break;
        }
        if (!strcmp(entry->name, ".") || !strcmp(entry->name, "..")) continue;
        size_t length = strlen(entry->name);
        if (length > 4096) { failure_tag = 4; break; }
        if ((uint64_t)count >= capacity) { failure_tag = 3; break; }
        struct stat status;
        if (fstatat(fd, entry->name, &status, AT_SYMLINK_NOFOLLOW) != 0) {
            failure_tag = nl_errno_error(errno); failure_code = errno; break;
        }
        int kind = S_ISREG(status.st_mode) ? 0 : S_ISDIR(status.st_mode) ? 1 : 2;
        nl_dir_entry_store(base, capacity, count, entry->name, length, kind);
        count++;
    }
    close(fd);
    if (failure_tag >= 0) {
        nl_io_error(result, failure_tag, failure_code); return;
    }
    nl_dir_sort(base, capacity, count);
    *(int64_t *)output = (int64_t)count;
    nl_io_error(result, -1, 0);
}

static int nl_has_extension(const char *name, size_t name_length,
                            const unsigned char *extension, uint64_t extension_length) {
    size_t dot = name_length;
    while (dot > 0 && name[dot - 1] != '.') --dot;
    if (dot == 0) return 0;
    size_t separator = dot - 1;
    if (separator == 0) return 0;
    size_t actual_length = name_length - dot;
    return (uint64_t)actual_length == extension_length &&
           (!actual_length || memcmp(name + dot, extension, actual_length) == 0);
}

void nl_fs_list_with_extension(void *handle, void *path_value, int path_is_argument,
                               uint64_t path_capacity, const unsigned char *extension,
                               uint64_t extension_length, void *output,
                               uint64_t capacity, void *result) {
    int error_tag = -1, error_code = 0;
    char path[4097];
    if (output) *(int64_t *)output = 0;
    if (capacity > (SIZE_MAX - 8) / 16396 || !output ||
        (extension_length && !extension)) {
        nl_io_error(result, 3, 0);
        return;
    }
    if (!nl_extract_path(path_value, path_is_argument, path_capacity,
                         path, &error_tag, &error_code)) {
        nl_io_error(result, error_tag, error_code);
        return;
    }
    int flush_error = nl_output_flush_all();
    if (flush_error) {
        nl_io_error(result, nl_errno_error(flush_error), flush_error);
        return;
    }
    int fd = nl_open_beneath(((nl_fs_handle *)handle)->root_fd,
                             path, O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0);
    if (fd < 0) {
        int error = errno;
        nl_io_error(result, nl_errno_error(error), error);
        return;
    }
    nl_directory_iterator iterator = { .fd = fd };
    unsigned char *base = (unsigned char *)output;
    size_t count = 0;
    int failure_tag = -1, failure_code = 0;
    for (;;) {
        struct nl_linux_dirent64 *entry;
        int next = nl_directory_next(&iterator, &entry);
        if (next <= 0) {
            if (next < 0) { failure_tag = nl_errno_error(errno); failure_code = errno; }
            break;
        }
        if (!strcmp(entry->name, ".") || !strcmp(entry->name, "..")) continue;
        size_t length = strlen(entry->name);
        if (!nl_has_extension(entry->name, length, extension, extension_length)) continue;
        if (length > 4096) {
            failure_tag = 4;
            break;
        }
        int kind = nl_entry_kind_beneath(((nl_fs_handle *)handle)->root_fd,
                                         path, entry->name, length);
        if ((uint64_t)count >= capacity) {
            failure_tag = 3;
            break;
        }
        nl_dir_entry_store(base, capacity, count, entry->name, length, kind);
        ++count;
    }
    close(fd);
    if (failure_tag >= 0) {
        nl_io_error(result, failure_tag, failure_code);
        return;
    }
    nl_dir_sort(base, capacity, count);
    *(int64_t *)output = (int64_t)count;
    nl_io_error(result, -1, 0);
}

void nl_fs_write(void *handle, void *path_value, int path_is_argument, uint64_t path_capacity,
                 void *data_value, int data_is_argument, uint64_t data_capacity, void *result) {
    int error_tag = -1, error_code = 0;
    char path[4097];
    if (!nl_extract_path(path_value, path_is_argument, path_capacity, path, &error_tag, &error_code)) {
        nl_io_error(result, error_tag, error_code); return;
    }
    int fd = nl_open_beneath(((nl_fs_handle *)handle)->root_fd, path,
                             O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
    if (fd < 0) { int error = errno; nl_io_error(result, nl_errno_error(error), error); return; }
    int failure = 0;
    if (data_is_argument) {
        const unsigned char *bytes; uint64_t length;
        unsigned char scratch[4096];
        if (nl_extract_raw(data_value, data_is_argument, data_capacity, scratch, &bytes, &length, &error_tag, &error_code)) failure = nl_write_all(fd, bytes, length);
        else failure = error_code ? error_code : EINVAL;
    } else {
        failure = nl_write_byte_list(fd, data_value, data_capacity);
    }
    if (close(fd) != 0 && !failure) failure = errno;
    nl_io_error(result, failure ? nl_errno_error(failure) : -1, failure);
}

static int nl_join_path(void *dir_value, int dir_is_argument, uint64_t dir_capacity,
                        void *name_value, int name_is_argument, uint64_t name_capacity,
                        unsigned char output[4096], uint64_t *output_length,
                        int *error_tag, int *error_code) {
    const unsigned char *dir_bytes, *name_bytes; uint64_t dir_length, name_length;
    unsigned char dir_scratch[4096], name_scratch[4096];
    if (!nl_extract_raw(dir_value, dir_is_argument, dir_capacity, dir_scratch, &dir_bytes, &dir_length, error_tag, error_code)) return 0;
    if (!nl_extract_raw(name_value, name_is_argument, name_capacity, name_scratch, &name_bytes, &name_length, error_tag, error_code)) return 0;
    if ((dir_length && dir_bytes[0] == '/') || (name_length && name_bytes[0] == '/')) { *error_tag = 6; return 0; }
    uint64_t length = dir_length + name_length + (dir_length && name_length && dir_bytes[dir_length - 1] != '/' ? 1 : 0);
    if (length > 4096) { *error_tag = 2; return 0; }
    uint64_t index = 0;
    if (dir_length) { memcpy(output, dir_bytes, (size_t)dir_length); index = dir_length; }
    if (index && name_length && output[index - 1] != '/') output[index++] = '/';
    if (name_length) { memcpy(output + index, name_bytes, (size_t)name_length); index += name_length; }
    int depth = 0;
    for (uint64_t i = 0; i < index;) {
        while (i < index && output[i] == '/') ++i;
        uint64_t start = i;
        while (i < index && output[i] != '/') ++i;
        uint64_t part = i - start;
        if (!part || (part == 1 && output[start] == '.')) continue;
        if (part == 2 && output[start] == '.' && output[start + 1] == '.') {
            if (depth == 0) { *error_tag = 6; return 0; }
            --depth;
        } else ++depth;
    }
    for (uint64_t i = 0; i < index; ++i) if (output[i] == 0) { *error_tag = 5; return 0; }
    *output_length = index;
    return 1;
}

void nl_fs_join(void *handle, void *dir_value, int dir_is_argument, uint64_t dir_capacity,
                void *name_value, int name_is_argument, uint64_t name_capacity, void *result) {
    (void)handle;
    unsigned char joined[4096]; uint64_t length = 0; int error_tag = -1, error_code = 0;
    memset(result, 0, 4 + 16392);
    if (!nl_join_path(dir_value, dir_is_argument, dir_capacity, name_value, name_is_argument, name_capacity, joined, &length, &error_tag, &error_code)) {
        int32_t *words = (int32_t *)result; words[0] = 1; words[1] = error_tag; if (error_tag == 7) words[2] = error_code; return;
    }
    int32_t *tag = (int32_t *)result; *tag = 0;
    unsigned char *path = (unsigned char *)result + 4;
    *(int64_t *)path = (int64_t)length;
    int32_t *items = (int32_t *)(path + 8);
    for (uint64_t i = 0; i < length; ++i) items[i] = joined[i];
}

void nl_out_write(void *handle, void *data_value, int data_is_argument, uint64_t data_capacity,
                  int line, void *result) {
    nl_out_handle *out = (nl_out_handle *)handle;
    int error = 0;
    if (data_is_argument) {
        const unsigned char *bytes; uint64_t length; int tag = -1, code = 0;
        unsigned char scratch[4096];
        if (!nl_extract_raw(data_value, data_is_argument, data_capacity, scratch, &bytes, &length, &tag, &code)) error = code ? code : EINVAL;
        else error = nl_output_write(out->fd, bytes, length);
    } else error = nl_write_byte_list(out->fd, data_value, data_capacity);
    if (!error && line) error = nl_output_write(out->fd, (const unsigned char *)"\n", 1);
    if (!error) error = nl_output_write_and_flush(out->fd, NULL, 0);
    if (error) {
        int index = nl_output_index(out->fd);
        if (index >= 0) nl_output_lengths[index] = 0;
    }
    nl_io_error(result, error ? nl_errno_error(error) : -1, error);
}

void nl_out_arg(void *handle, void *argument, int line, void *result) {
    nl_out_handle *out = (nl_out_handle *)handle;
    const unsigned char *bytes = argument ? (const unsigned char *)argument : (const unsigned char *)"";
    int error = nl_output_write_and_flush(out->fd, bytes, strlen((const char *)bytes));
    if (!error && line) error = nl_output_write_and_flush(out->fd, (const unsigned char *)"\n", 1);
    nl_io_error(result, error ? nl_errno_error(error) : -1, error);
}

void nl_out_int(void *handle, int32_t value, void *result) {
    unsigned char buffer[21];
    uint64_t length = nl_ascii_format_i64(value, buffer);
    int error = nl_output_write_and_flush(((nl_out_handle *)handle)->fd, buffer, length);
    nl_io_error(result, error ? nl_errno_error(error) : -1, error);
}
void nl_out_long(void *handle, int64_t value, void *result) {
    unsigned char buffer[21];
    uint64_t length = nl_ascii_format_i64(value, buffer);
    int error = nl_output_write_and_flush(((nl_out_handle *)handle)->fd, buffer, length);
    nl_io_error(result, error ? nl_errno_error(error) : -1, error);
}
void nl_print_arg(void *argument) {
    if (!argument) return;
    nl_print_bytes((const unsigned char *)argument, (uint64_t)strlen((const char *)argument));
    nl_print_newline();
}
