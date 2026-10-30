#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <errno.h>
#include <limits.h>
#include <time.h>

#if defined(_WIN32)
#define NL_WINDOWS 1
#else
#define NL_WINDOWS 0
#endif

#if NL_WINDOWS
/* Windows (64-bit, clang targeting the MSVC runtime). The data stack reserves its address range with
   VirtualAlloc and commits it as the stack grows; files go through CRT descriptors opened with
   CreateFileW beneath the working directory. Tests (NLC_TEST_BUILD) are not supported here yet. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <io.h>
#include <fcntl.h>
#include <sys/stat.h>
#if !defined(__MINGW32__)
typedef long long ssize_t;
#endif
typedef int mode_t;
#undef SSIZE_MAX
#define SSIZE_MAX INT_MAX
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#define O_CLOEXEC 0
#define O_PATH 0
#define O_DIRECTORY 0
#ifndef S_ISREG
#define S_ISREG(mode) (((mode) & _S_IFMT) == _S_IFREG)
#define S_ISDIR(mode) (((mode) & _S_IFMT) == _S_IFDIR)
#endif
#define read _read
#define write _write
#define close _close
#define isatty _isatty
/* The native stack is only 1 MiB by default; the compiler recurses deeply. */
#pragma comment(linker, "/STACK:268435456")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "synchronization.lib")
/* The file-system root is the working directory at startup, held as a wide path. */
static wchar_t nl_win_root[32768];
static size_t nl_win_root_length;
#else
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <linux/openat2.h>
#endif

#include "nl_unicode_upper.h"

#if defined(__linux__)
#include <sys/mman.h>
#include <sys/types.h>
#include <pthread.h>
#endif

/* Threads. nl_multithreaded becomes 1 when the first extra thread starts and stays 1. */
static volatile int nl_multithreaded;
#if NL_WINDOWS
static CRITICAL_SECTION nl_output_mutex;
static void nl_output_lock(void) { if (nl_multithreaded) EnterCriticalSection(&nl_output_mutex); }
static void nl_output_unlock(void) { if (nl_multithreaded) LeaveCriticalSection(&nl_output_mutex); }
#else
static pthread_mutex_t nl_output_mutex = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;
static void nl_output_lock(void) { if (nl_multithreaded) pthread_mutex_lock(&nl_output_mutex); }
static void nl_output_unlock(void) { if (nl_multithreaded) pthread_mutex_unlock(&nl_output_mutex); }
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
    /* Bytes of the stack range (from base) that are backed by memory. Linux backs all of it lazily;
       Windows commits as the stack grows. */
    uint64_t committed_bytes;
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

/* Address-range helpers for the data stack. Reserve a range without backing it, make a part of it
   usable, and give it back. */
static long nl_page_size(void) {
#if NL_WINDOWS
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return (long)info.dwPageSize;
#else
    return sysconf(_SC_PAGESIZE);
#endif
}

static void *nl_map_reserve(size_t total) {
#if NL_WINDOWS
    return VirtualAlloc(NULL, total, MEM_RESERVE, PAGE_NOACCESS);
#else
    void *mapping = mmap(NULL, total, PROT_NONE,
                         MAP_PRIVATE | MAP_ANONYMOUS
#ifdef MAP_NORESERVE
                             | MAP_NORESERVE
#endif
                         , -1, 0);
    return mapping == MAP_FAILED ? NULL : mapping;
#endif
}

static int nl_map_enable(void *address, size_t bytes) {
#if NL_WINDOWS
    return VirtualAlloc(address, bytes, MEM_COMMIT, PAGE_READWRITE) ? 0 : -1;
#else
    return mprotect(address, bytes, PROT_READ | PROT_WRITE);
#endif
}

/* Make the first part of the stack range usable; Linux enables all of it (pages are only backed when
   touched), Windows commits an initial chunk and the rest as the stack grows. */
static int nl_map_enable_stack(void *base, uint64_t bytes, uint64_t *committed) {
#if NL_WINDOWS
    uint64_t initial = bytes < UINT64_C(1048576) ? bytes : UINT64_C(1048576);
    if (nl_map_enable(base, (size_t)initial) != 0) return -1;
    *committed = initial;
    return 0;
#else
    if (nl_map_enable(base, (size_t)bytes) != 0) return -1;
    *committed = bytes;
    return 0;
#endif
}

static void nl_map_release(void *mapping, size_t total) {
#if NL_WINDOWS
    (void)total;
    VirtualFree(mapping, 0, MEM_RELEASE);
#else
    munmap(mapping, total);
#endif
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

/* A job's data stack reserves less address space than the main program's: 1 GiB unless NLC_JOB_STACK_RESERVE_BYTES
   says otherwise. The flag is set (per thread) while a job's context is created. */
#define NL_JOB_STACK_DEFAULT_BYTES (UINT64_C(1) * 1024 * 1024 * 1024)
static _Thread_local int nl_creating_job_context;

static uint64_t nl_offset_stack_reservation(uint64_t computed_bytes) {
#if defined(NLC_TEST_BUILD)
    const char *test_override = getenv("NLC_TEST_DATA_STACK_BYTES");
    if (test_override && *test_override) return computed_bytes;
#endif
    uint64_t bytes = nl_creating_job_context ? NL_JOB_STACK_DEFAULT_BYTES : NL_OFFSET_STACK_DEFAULT_BYTES;
    const char *override = getenv(nl_creating_job_context ? "NLC_JOB_STACK_RESERVE_BYTES" : "NLC_STACK_RESERVE_BYTES");
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
#if NL_WINDOWS
    ULONG_PTR stack_floor = 0, stack_ceiling = 0;
    GetCurrentThreadStackLimits(&stack_floor, &stack_ceiling);
    if (stack_ceiling <= stack_floor) nl_stack_startup_failure("could not determine the native stack bounds");
    stack_low = (uintptr_t)stack_floor;
    stack_bytes = (uint64_t)(stack_ceiling - stack_floor);
#else
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
#endif
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
#if defined(__linux__) || NL_WINDOWS
    long page = nl_page_size();
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
    void *mapping = nl_map_reserve(total);
#if defined(NLC_STACK_MODE_OFFSET)
    /* Under an address-space limit (ulimit -v, containers) the default range may not fit: halve it
       until it does. A program that then outgrows the range fails with "data stack exhausted". */
    while (mapping == NULL && bytes > UINT64_C(256) * 1024 * 1024 && bytes > requested_bytes) {
        bytes = (bytes / 2 / page_size) * page_size;
        total = (size_t)bytes + 2 * (size_t)page_size;
        mapping = nl_map_reserve(total);
    }
#endif
    if (mapping == NULL) {
        nl_stack_startup_failure_for(entry_name, bytes,
                                     "could not reserve the requested address range");
    }
    unsigned char *base = (unsigned char *)mapping + page_size;
    uint64_t committed = 0;
    if (sizeof(nl_data_stack_context) > page_size ||
        nl_map_enable(mapping, (size_t)page_size) != 0 ||
        nl_map_enable_stack(base, bytes, &committed) != 0) {
        nl_map_release(mapping, total);
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
    context->committed_bytes = committed;
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

void *nl_context_create_job(uint64_t requested_bytes, uint64_t requested_recursion_budget, const char *entry_name) {
    nl_creating_job_context = 1;
    void *context = nl_context_create(requested_bytes, requested_recursion_budget, entry_name);
    nl_creating_job_context = 0;
    return context;
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

/* The generated code compares a scope's end with this and calls the grow routine when it is past it,
   so it reports the bytes that are backed (all of the range on Linux, the committed part on Windows). */
uint64_t nl_context_reservation_bytes(void *opaque) {
    nl_data_stack_context *context = opaque;
    return context ? context->committed_bytes : 0;
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

#if defined(__linux__) || NL_WINDOWS
static void nl_stack_grow_offset(nl_data_stack_context *context, uint64_t needed_bytes,
                                 int32_t file_id, int32_t line, int32_t col) {
    if (needed_bytes > context->reservation_bytes) nl_fail(18, file_id, line, col);
    if (needed_bytes <= context->committed_bytes) return;
    /* Back more of the range: at least double what is committed, in whole megabytes. */
    uint64_t target = context->committed_bytes * 2;
    if (target < needed_bytes) target = needed_bytes;
    target = (target + UINT64_C(1048575)) & ~UINT64_C(1048575);
    if (target > context->reservation_bytes) target = context->reservation_bytes;
    if (nl_map_enable(context->base + context->committed_bytes,
                      (size_t)(target - context->committed_bytes)) != 0) {
        nl_fail(18, file_id, line, col);
    }
    context->committed_bytes = target;
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
#if defined(__linux__) || NL_WINDOWS
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
#if defined(__linux__) || NL_WINDOWS
    if (nl_output_flush_all() != 0) nl_fail(20, -1, 0, 0);
#if NL_WINDOWS
    nl_map_release(context->header_mapping, 0);
#else
    munmap(context->mapping, context->mapping_bytes);
    void *header_mapping = context->header_mapping;
    size_t header_bytes = context->header_bytes;
    munmap(header_mapping, header_bytes);
#endif
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

/* Once a second thread exists, print output is gathered per thread and written a line at a time, so the pieces
   of one print statement (digits, then the newline) are never split by another thread's output. */
static _Thread_local unsigned char nl_line[512];
static _Thread_local size_t nl_line_length;

static void nl_line_flush(void) {
    if (!nl_line_length) return;
    size_t length = nl_line_length;
    nl_line_length = 0;
    if (nl_output_write(nl_print_fd, nl_line, length) != 0) nl_fail(20, -1, 0, 0);
}

static void nl_print_bytes(const unsigned char *bytes, uint64_t length) {
    if (!nl_multithreaded) {
        if (nl_output_write(nl_print_fd, bytes, length) != 0) nl_fail(20, -1, 0, 0);
        return;
    }
    if (length > sizeof(nl_line) - nl_line_length) {
        nl_line_flush();
        if (length >= sizeof(nl_line)) {
            if (nl_output_write(nl_print_fd, bytes, length) != 0) nl_fail(20, -1, 0, 0);
            return;
        }
    }
    memcpy(nl_line + nl_line_length, bytes, (size_t)length);
    nl_line_length += (size_t)length;
    if (memchr(bytes, '\n', (size_t)length)) nl_line_flush();
}

void nl_print_ascii(const unsigned char *bytes, uint64_t length) {
    nl_print_bytes(bytes, length);
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

uint64_t nl_ascii_format_i64(int64_t value, unsigned char *destination) {
    return nl_ascii_format_i64_decimal(value, destination);
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
    if (fd == STDOUT_FILENO || fd == STDERR_FILENO) { nl_line_flush(); nl_print_fd = fd; }
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
#if NL_WINDOWS
    /* Raw bytes on stdout and stderr, UTF-8 arguments, and the working directory as the file root. */
    _setmode(1, _O_BINARY);
    _setmode(2, _O_BINARY);
    {
        int wide_count = 0;
        wchar_t **wide_arguments = CommandLineToArgvW(GetCommandLineW(), &wide_count);
        if (!wide_arguments) nl_stack_startup_failure("cannot read the command line");
        argv = (char **)calloc((size_t)wide_count + 1, sizeof(char *));
        if (!argv) nl_stack_startup_failure("cannot allocate the argument list");
        for (int i = 0; i < wide_count; ++i) {
            int bytes = WideCharToMultiByte(CP_UTF8, 0, wide_arguments[i], -1, NULL, 0, NULL, NULL);
            argv[i] = (char *)calloc((size_t)bytes + 1, 1);
            if (bytes <= 0 || !argv[i]) nl_stack_startup_failure("cannot convert an argument to UTF-8");
            WideCharToMultiByte(CP_UTF8, 0, wide_arguments[i], -1, argv[i], bytes, NULL, NULL);
        }
        argc = wide_count;
        LocalFree(wide_arguments);
        DWORD root_length = GetCurrentDirectoryW((DWORD)(sizeof(nl_win_root) / sizeof(nl_win_root[0])), nl_win_root);
        if (root_length == 0 || root_length >= sizeof(nl_win_root) / sizeof(nl_win_root[0])) {
            nl_stack_startup_failure("cannot read the working directory");
        }
        nl_win_root_length = root_length;
    }
#else
    (void)signal(SIGPIPE, SIG_IGN);
#endif
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
#if NL_WINDOWS
    environment->root_fd = 0; /* unused: paths resolve against nl_win_root */
#else
    environment->root_fd = open(".", O_PATH | O_DIRECTORY | O_CLOEXEC);
#endif
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
#if !NL_WINDOWS
    if (environment->root_fd >= 0) close(environment->root_fd);
#endif
#if defined(NLC_TEST_BUILD)
    if (environment->test_directory) {
        nl_remove_tree(environment->test_directory);
        free(environment->test_directory);
    }
#endif
    /* Startup-only capability environment cleanup. */
    free(environment);
}

/* ---- Threads ----
   A thread runs `entry(argument)` with its own native stack. The generated code builds the job context inside
   the entry it passes (nl_context_create and nl_context_destroy), so a thread's data stack is its own. `pin` is a
   position in the processors this process may use (-1: leave it to the system). Park and wake are the
   operating system's wait-on-an-address calls; everything above them (rings, counters) is generated IR. */
typedef struct {
    void *(*entry)(void *);
    void *argument;
    int64_t pin;
#if NL_WINDOWS
    HANDLE handle;
#else
    pthread_t handle;
#endif
} nl_thread_record;

static void nl_pin_current_thread(int64_t position) {
    if (position < 0) return;
#if NL_WINDOWS
    DWORD_PTR mask = 0, process_mask = 0, system_mask = 0;
    if (!GetProcessAffinityMask(GetCurrentProcess(), &process_mask, &system_mask)) return;
    int64_t seen = 0;
    for (int bit = 0; bit < 64; ++bit) {
        if (!(process_mask & ((DWORD_PTR)1 << bit))) continue;
        if (seen++ == position % (int64_t)__builtin_popcountll((unsigned long long)process_mask)) { mask = (DWORD_PTR)1 << bit; break; }
    }
    if (mask) SetThreadAffinityMask(GetCurrentThread(), mask);
#elif defined(__linux__) && defined(CPU_COUNT)
    cpu_set_t allowed;
    if (sched_getaffinity(0, sizeof(allowed), &allowed) != 0) return;
    int count = CPU_COUNT(&allowed);
    if (count <= 0) return;
    int64_t wanted = position % count, seen = 0;
    for (int cpu = 0; cpu < CPU_SETSIZE; ++cpu) {
        if (!CPU_ISSET(cpu, &allowed)) continue;
        if (seen++ == wanted) {
            cpu_set_t one;
            CPU_ZERO(&one);
            CPU_SET(cpu, &one);
            (void)sched_setaffinity(0, sizeof(one), &one);
            return;
        }
    }
#endif
}

#if NL_WINDOWS
static DWORD WINAPI nl_thread_main(LPVOID raw) {
    nl_thread_record *record = (nl_thread_record *)raw;
    nl_pin_current_thread(record->pin);
    record->entry(record->argument);
    nl_line_flush();
    return 0;
}
#else
static void *nl_thread_main(void *raw) {
    nl_thread_record *record = (nl_thread_record *)raw;
    nl_pin_current_thread(record->pin);
    void *result = record->entry(record->argument);
    nl_line_flush();
    return result;
}
#endif

void *nl_thread_start(void *(*entry)(void *), void *argument, uint64_t native_stack_bytes, int64_t pin) {
    nl_thread_record *record = (nl_thread_record *)calloc(1, sizeof(*record));
    if (!record) return NULL;
    record->entry = entry;
    record->argument = argument;
    record->pin = pin;
    if (!nl_multithreaded) {
#if NL_WINDOWS
        InitializeCriticalSection(&nl_output_mutex);
#endif
        nl_multithreaded = 1;
    }
#if NL_WINDOWS
    record->handle = CreateThread(NULL, (SIZE_T)native_stack_bytes, nl_thread_main, record,
                                  native_stack_bytes ? STACK_SIZE_PARAM_IS_A_RESERVATION : 0, NULL);
    if (!record->handle) { free(record); return NULL; }
#else
    pthread_attr_t attributes;
    pthread_attr_init(&attributes);
    if (native_stack_bytes) pthread_attr_setstacksize(&attributes, (size_t)native_stack_bytes);
    int failed = pthread_create(&record->handle, &attributes, nl_thread_main, record);
    pthread_attr_destroy(&attributes);
    if (failed) { free(record); return NULL; }
#endif
    return record;
}

/* Wait for a thread to finish and release its record. Returns 0 on success. */
int64_t nl_thread_join(void *raw) {
    nl_thread_record *record = (nl_thread_record *)raw;
    if (!record) return -1;
#if NL_WINDOWS
    WaitForSingleObject(record->handle, INFINITE);
    CloseHandle(record->handle);
#else
    pthread_join(record->handle, NULL);
#endif
    free(record);
    return 0;
}

/* Sleep while *address == expected, until woken or the timeout (nanoseconds, negative: none) passes. Returns 1 on
   timeout and 0 otherwise (woken, or the value had already changed). Spurious returns are possible. */
int32_t nl_park(volatile int32_t *address, int32_t expected, int64_t timeout_nanos) {
#if NL_WINDOWS
    DWORD milliseconds = timeout_nanos < 0 ? INFINITE : (DWORD)((timeout_nanos + 999999) / 1000000);
    if (WaitOnAddress(address, &expected, sizeof(expected), milliseconds)) return 0;
    return GetLastError() == ERROR_TIMEOUT ? 1 : 0;
#elif defined(__linux__) && defined(SYS_futex)
    struct timespec limit;
    struct timespec *limit_pointer = NULL;
    if (timeout_nanos >= 0) {
        limit.tv_sec = (time_t)(timeout_nanos / 1000000000);
        limit.tv_nsec = (long)(timeout_nanos % 1000000000);
        limit_pointer = &limit;
    }
    long result = syscall(SYS_futex, address, 128 /* FUTEX_WAIT_PRIVATE */, expected, limit_pointer, NULL, 0);
    return result < 0 && errno == ETIMEDOUT ? 1 : 0;
#else
    (void)address; (void)expected; (void)timeout_nanos;
    return 0;
#endif
}

/* Wake up to `count` threads parked on the address. */
void nl_wake(volatile int32_t *address, int32_t count) {
#if NL_WINDOWS
    if (count == 1) WakeByAddressSingle((PVOID)address); else WakeByAddressAll((PVOID)address);
#elif defined(__linux__) && defined(SYS_futex)
    (void)syscall(SYS_futex, address, 129 /* FUTEX_WAKE_PRIVATE */, count, NULL, NULL, 0);
#else
    (void)address; (void)count;
#endif
}

/* ---- Jobs ----
   A job is a thread that runs one generated function on a data stack of its own. `spawn` allocates a block for the
   job's arguments, starts a thread whose entry (generated) creates the job's context and calls the function, and
   registers the thread; the program waits for every job before it finishes. Jobs are pinned in turn to the
   processors granted to the process. */
int64_t nl_host_cores(void *host);

#define NL_JOB_LIMIT 4096
#define NL_JOB_NATIVE_STACK_BYTES (UINT64_C(64) * 1024 * 1024)
static void *nl_jobs[NL_JOB_LIMIT];
static int nl_job_count;

void *nl_job_args_alloc(uint64_t bytes) {
    void *block = calloc(1, bytes ? (size_t)bytes : 1);
    if (!block) nl_stack_startup_failure("cannot allocate a job's arguments");
    return block;
}

void nl_job_args_free(void *block) { free(block); }

void nl_job_start(void *(*entry)(void *), void *arguments) {
    if (nl_job_count >= NL_JOB_LIMIT) nl_stack_startup_failure("too many jobs");
    int64_t cores = nl_host_cores(NULL);
    void *record = nl_thread_start(entry, arguments, NL_JOB_NATIVE_STACK_BYTES, cores > 0 ? nl_job_count % cores : -1);
    if (!record) nl_stack_startup_failure("cannot start a job");
    nl_jobs[nl_job_count++] = record;
}

void nl_jobs_join_all(void) {
    for (int index = 0; index < nl_job_count; ++index) (void)nl_thread_join(nl_jobs[index]);
    nl_job_count = 0;
}

/* Host facts for main. The thread grant is the processors the program may use, capped by NLC_CORES; the RAM
   figure is the machine's physical memory and is advisory. The handle is the environment itself. */
static int64_t nl_host_total_core_count(void) {
#if NL_WINDOWS
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return (int64_t)info.dwNumberOfProcessors;
#else
    long online = sysconf(_SC_NPROCESSORS_ONLN);
#if defined(__linux__) && defined(CPU_COUNT)
    cpu_set_t set;
    if (sched_getaffinity(0, sizeof(set), &set) == 0) {
        int count = CPU_COUNT(&set);
        if (count > 0) return (int64_t)count;
    }
#endif
    return online > 0 ? (int64_t)online : 1;
#endif
}

void *nl_env_host(void *value) { return value; }
int64_t nl_host_total_cores(void *host) { (void)host; return nl_host_total_core_count(); }
int64_t nl_host_cores(void *host) {
    (void)host;
    int64_t total = nl_host_total_core_count();
    const char *limit = getenv("NLC_CORES");
    if (limit && *limit) {
        char *end = NULL;
        long long wanted = strtoll(limit, &end, 10);
        if (end != limit && !*end && wanted >= 1 && wanted < total) return (int64_t)wanted;
    }
    return total;
}
int64_t nl_host_ram_bytes(void *host) {
    (void)host;
#if NL_WINDOWS
    MEMORYSTATUSEX status;
    status.dwLength = sizeof(status);
    return GlobalMemoryStatusEx(&status) ? (int64_t)status.ullTotalPhys : 0;
#else
    long pages = sysconf(_SC_PHYS_PAGES);
    long page = sysconf(_SC_PAGESIZE);
    return pages > 0 && page > 0 ? (int64_t)pages * (int64_t)page : 0;
#endif
}
int64_t nl_host_page_size(void *host) { (void)host; return (int64_t)nl_page_size(); }

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

#if NL_WINDOWS
static int nl_win_errno(DWORD error) {
    switch (error) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
    case ERROR_INVALID_NAME: return ENOENT;
    case ERROR_ACCESS_DENIED:
    case ERROR_SHARING_VIOLATION:
    case ERROR_LOCK_VIOLATION: return EACCES;
    case ERROR_ALREADY_EXISTS:
    case ERROR_FILE_EXISTS: return EEXIST;
    case ERROR_DIRECTORY: return ENOTDIR;
    case ERROR_NOT_ENOUGH_MEMORY:
    case ERROR_OUTOFMEMORY: return ENOMEM;
    default: return EIO;
    }
}

/* Turn a relative UTF-8 path into the wide path beneath the root. Absolute paths, drive letters,
   backslashes and ".." segments are refused, as RESOLVE_BENEATH refuses them on Linux. */
static int nl_win_resolve(const char *path, wchar_t *out, size_t capacity) {
    size_t length = strlen(path);
    if (length > 0 && (path[0] == '/' || path[0] == '\\')) { errno = EPERM; return -1; }
    size_t segment = 0;
    for (size_t i = 0; i <= length; ++i) {
        char c = path[i];
        if (c == ':' || c == '\\') { errno = EPERM; return -1; }
        if (c == '/' || c == 0) {
            if (i - segment == 2 && path[segment] == '.' && path[segment + 1] == '.') { errno = EPERM; return -1; }
            segment = i + 1;
        }
    }
    if (nl_win_root_length + 2 >= capacity) { errno = ENAMETOOLONG; return -1; }
    memcpy(out, nl_win_root, nl_win_root_length * sizeof(wchar_t));
    size_t at = nl_win_root_length;
    out[at++] = L'\\';
    int wide = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, (int)length + 1, out + at, (int)(capacity - at));
    if (wide <= 0) { errno = EINVAL; return -1; }
    for (wchar_t *p = out + at; *p; ++p) if (*p == L'/') *p = L'\\';
    return 0;
}

static int nl_open_beneath(int root_fd, const char *path, int flags, mode_t mode) {
    (void)root_fd;
    (void)mode;
    wchar_t wide[32768];
    if (nl_win_resolve(path, wide, sizeof(wide) / sizeof(wide[0])) != 0) return -1;
    int writing = (flags & (O_WRONLY | O_RDWR)) != 0;
    DWORD disposition = (flags & O_CREAT) ? ((flags & O_TRUNC) ? CREATE_ALWAYS : OPEN_ALWAYS) : OPEN_EXISTING;
    HANDLE handle = CreateFileW(wide, writing ? GENERIC_WRITE : GENERIC_READ,
                                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                                disposition, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (handle == INVALID_HANDLE_VALUE) { errno = nl_win_errno(GetLastError()); return -1; }
    BY_HANDLE_FILE_INFORMATION information;
    if (GetFileInformationByHandle(handle, &information) &&
        ((information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
         (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))) {
        CloseHandle(handle);
        errno = (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? EISDIR : ELOOP;
        return -1;
    }
    int fd = _open_osfhandle((intptr_t)handle, (writing ? _O_WRONLY : _O_RDONLY) | _O_BINARY);
    if (fd < 0) { CloseHandle(handle); errno = EIO; return -1; }
    return fd;
}
#else
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
#endif

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
#if NL_WINDOWS
    (void)output_status;
    (void)error_status;
    /* Both streams are consoles; Windows reports no inode, so treat them as one terminal. */
    nl_output_shared_terminal = nl_output_is_terminal[0] && nl_output_is_terminal[1] ? 1 : 0;
#else
    nl_output_shared_terminal =
        nl_output_is_terminal[0] && nl_output_is_terminal[1] &&
                fstat(STDOUT_FILENO, &output_status) == 0 &&
                fstat(STDERR_FILENO, &error_status) == 0 &&
                output_status.st_dev == error_status.st_dev &&
                output_status.st_ino == error_status.st_ino
            ? 1
            : 0;
#endif
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

static int nl_output_flush_all_body(void) {
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

static int nl_output_write_body(int fd, const unsigned char *bytes, uint64_t length) {
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

static int nl_output_write_and_flush_body(int fd, const unsigned char *bytes,
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

/* Output is buffered in shared state, so once a second thread exists the public entry points take a recursive
   lock. A single-threaded program never takes it. */
static int nl_output_flush_all(void) {
    nl_line_flush();
    nl_output_lock();
    int result = nl_output_flush_all_body();
    nl_output_unlock();
    return result;
}

static int nl_output_write(int fd, const unsigned char *bytes, uint64_t length) {
    nl_output_lock();
    int result = nl_output_write_body(fd, bytes, length);
    nl_output_unlock();
    return result;
}

static int nl_output_write_and_flush(int fd, const unsigned char *bytes, uint64_t length) {
    nl_output_lock();
    int result = nl_output_write_and_flush_body(fd, bytes, length);
    nl_output_unlock();
    return result;
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

#if !NL_WINDOWS
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

#endif

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

#if !NL_WINDOWS
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

#endif

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

#if !NL_WINDOWS
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

#endif

#if NL_WINDOWS
/* Directory listing with FindFirstFileW: names as UTF-8, kinds from the attributes (a link is "other"). */
static void nl_win_list(const char *path, const unsigned char *extension,
                        uint64_t extension_length, int filter, void *output, uint64_t capacity,
                        void *result) {
    wchar_t pattern[32768];
    if (nl_win_resolve(path, pattern, sizeof(pattern) / sizeof(pattern[0]) - 2) != 0) {
        int error = errno;
        nl_io_error(result, nl_errno_error(error), error);
        return;
    }
    size_t at = wcslen(pattern);
    if (at > 0 && pattern[at - 1] != L'\\') pattern[at++] = L'\\';
    pattern[at++] = L'*';
    pattern[at] = 0;
    WIN32_FIND_DATAW data;
    HANDLE find = FindFirstFileW(pattern, &data);
    if (find == INVALID_HANDLE_VALUE) {
        int error = nl_win_errno(GetLastError());
        nl_io_error(result, nl_errno_error(error), error);
        return;
    }
    unsigned char *base = (unsigned char *)output;
    size_t count = 0;
    int failure_tag = -1, failure_code = 0;
    do {
        if (!wcscmp(data.cFileName, L".") || !wcscmp(data.cFileName, L"..")) continue;
        char name[4 * 260 + 1];
        int length = WideCharToMultiByte(CP_UTF8, 0, data.cFileName, -1, name, (int)sizeof(name), NULL, NULL);
        if (length <= 0) { failure_tag = 4; break; }
        length -= 1;
        if (filter && !nl_has_extension(name, (size_t)length, extension, extension_length)) continue;
        if ((uint64_t)count >= capacity) { failure_tag = 3; break; }
        int kind = (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ? 2
                 : (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? 1 : 0;
        nl_dir_entry_store(base, capacity, count, name, (size_t)length, kind);
        ++count;
    } while (FindNextFileW(find, &data));
    FindClose(find);
    if (failure_tag >= 0) { nl_io_error(result, failure_tag, failure_code); return; }
    nl_dir_sort(base, capacity, count);
    *(int64_t *)output = (int64_t)count;
    nl_io_error(result, -1, 0);
}

void nl_fs_list(void *handle, void *path_value, int path_is_argument, uint64_t path_capacity,
                void *output, uint64_t capacity, void *result) {
    (void)handle;
    int error_tag = -1, error_code = 0;
    char path[4097];
    if (output) *(int64_t *)output = 0;
    if (capacity > (SIZE_MAX - 8) / 16396 || !output) { nl_io_error(result, 3, 0); return; }
    if (!nl_extract_path(path_value, path_is_argument, path_capacity, path, &error_tag, &error_code)) {
        nl_io_error(result, error_tag, error_code); return;
    }
    int flush_error = nl_output_flush_all();
    if (flush_error) { nl_io_error(result, nl_errno_error(flush_error), flush_error); return; }
    nl_win_list(path, NULL, 0, 0, output, capacity, result);
}

void nl_fs_list_with_extension(void *handle, void *path_value, int path_is_argument,
                               uint64_t path_capacity, const unsigned char *extension,
                               uint64_t extension_length, void *output,
                               uint64_t capacity, void *result) {
    (void)handle;
    int error_tag = -1, error_code = 0;
    char path[4097];
    if (output) *(int64_t *)output = 0;
    if (capacity > (SIZE_MAX - 8) / 16396 || !output || (extension_length && !extension)) {
        nl_io_error(result, 3, 0); return;
    }
    if (!nl_extract_path(path_value, path_is_argument, path_capacity, path, &error_tag, &error_code)) {
        nl_io_error(result, error_tag, error_code); return;
    }
    int flush_error = nl_output_flush_all();
    if (flush_error) { nl_io_error(result, nl_errno_error(flush_error), flush_error); return; }
    nl_win_list(path, extension, extension_length, 1, output, capacity, result);
}
#endif

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

/* Net and HTTP for Env.net_listen / net_accept / http_read / http_write / net_close. A connection is its file
   descriptor; whoever holds it (one job at a time) reads requests and writes responses. HTTP/1.1 with keep-alive:
   http_read returns the method (1 GET, 2 POST, 3 other) and copies the request target into the caller's Bytes, or
   returns -1 when the peer closed or sent something unusable. Linux only for now. */
#if !NL_WINDOWS
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/uio.h>

#define NL_HTTP_CONNECTIONS 65536
#define NL_HTTP_BUFFER 8192

typedef struct { uint32_t length; unsigned char data[NL_HTTP_BUFFER]; } nl_http_buffer;
static nl_http_buffer *nl_http_buffers[NL_HTTP_CONNECTIONS];

int64_t nl_net_listen(void *env, int64_t port) {
    (void)env;
    int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, sizeof(on));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons((uint16_t)port);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 1024) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

int64_t nl_net_accept(void *env, int64_t listener) {
    (void)env;
    for (;;) {
        int fd = accept4((int)listener, NULL, NULL, SOCK_CLOEXEC);
        if (fd < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        int on = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on));
        return fd;
    }
}

int64_t nl_net_close(void *env, int64_t fd) {
    (void)env;
    if (fd >= 0 && fd < NL_HTTP_CONNECTIONS && nl_http_buffers[fd]) {
        free(nl_http_buffers[fd]);
        nl_http_buffers[fd] = NULL;
    }
    return close((int)fd);
}

static const unsigned char *nl_http_find(const unsigned char *data, uint32_t length, const char *needle, uint32_t needle_length) {
    if (length < needle_length) return NULL;
    for (uint32_t index = 0; index + needle_length <= length; ++index) {
        if (data[index] == (unsigned char)needle[0] && memcmp(data + index, needle, needle_length) == 0) return data + index;
    }
    return NULL;
}

static int64_t nl_http_content_length(const unsigned char *headers, uint32_t length) {
    for (uint32_t index = 0; index + 16 <= length; ++index) {
        if (headers[index] == '\n' && (headers[index + 1] | 32) == 'c' && strncasecmp((const char *)headers + index + 1, "content-length:", 15) == 0) {
            int64_t value = 0;
            for (uint32_t at = index + 16; at < length && headers[at] != '\r'; ++at) {
                if (headers[at] >= '0' && headers[at] <= '9') value = value * 10 + (headers[at] - '0');
            }
            return value;
        }
    }
    return 0;
}

int64_t nl_http_read(void *env, int64_t fd, unsigned char *target, uint64_t capacity, int64_t *target_length) {
    (void)env;
    if (fd < 0 || fd >= NL_HTTP_CONNECTIONS) return -1;
    nl_http_buffer *buffer = nl_http_buffers[fd];
    if (!buffer) {
        buffer = (nl_http_buffer *)calloc(1, sizeof(*buffer));
        if (!buffer) return -1;
        nl_http_buffers[fd] = buffer;
    }
    const unsigned char *end = NULL;
    for (;;) {
        end = nl_http_find(buffer->data, buffer->length, "\r\n\r\n", 4);
        if (end) break;
        if (buffer->length >= NL_HTTP_BUFFER) return -1;
        ssize_t got = recv((int)fd, buffer->data + buffer->length, NL_HTTP_BUFFER - buffer->length, 0);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) return -1;
        buffer->length += (uint32_t)got;
    }
    uint32_t head = (uint32_t)(end - buffer->data) + 4;
    /* request line: METHOD SP target SP version */
    int64_t method = 3;
    uint32_t at = 0;
    if (head > 4 && memcmp(buffer->data, "GET ", 4) == 0) { method = 1; at = 4; }
    else if (head > 5 && memcmp(buffer->data, "POST ", 5) == 0) { method = 2; at = 5; }
    else { while (at < head && buffer->data[at] != ' ') ++at; ++at; }
    uint32_t start = at;
    while (at < head && buffer->data[at] != ' ' && buffer->data[at] != '\r') ++at;
    uint32_t size = at - start;
    if (at >= head || size > capacity) return -1;
    memcpy(target, buffer->data + start, size);
    *target_length = (int64_t)size;
    int64_t body = nl_http_content_length(buffer->data, head);
    uint32_t consumed = head;
    /* a request body is read and dropped */
    while (body > 0) {
        uint32_t have = buffer->length - consumed;
        if (have == 0) {
            buffer->length = 0;
            consumed = 0;
            ssize_t got = recv((int)fd, buffer->data, NL_HTTP_BUFFER, 0);
            if (got < 0 && errno == EINTR) continue;
            if (got <= 0) return -1;
            buffer->length = (uint32_t)got;
            have = buffer->length;
        }
        uint32_t take = (int64_t)have < body ? have : (uint32_t)body;
        consumed += take;
        body -= take;
    }
    memmove(buffer->data, buffer->data + consumed, buffer->length - consumed);
    buffer->length -= consumed;
    return method;
}

int64_t nl_http_write(void *env, int64_t fd, int64_t status, int64_t kind, void *body_descriptor, uint64_t capacity) {
    (void)env;
    unsigned char scratch[4096];
    const unsigned char *bytes; uint64_t length; int tag = -1, code = 0;
    if (!nl_extract_raw(body_descriptor, 2, capacity, scratch, &bytes, &length, &tag, &code)) return -1;
    const char *reason = status == 200 ? "OK" : status == 404 ? "Not Found" : status == 503 ? "Service Unavailable" : status == 400 ? "Bad Request" : "Status";
    const char *type = kind == 1 ? "application/json" : kind == 2 ? "text/plain; charset=utf-8" : "text/html; charset=utf-8";
    char head[256];
    int head_length = snprintf(head, sizeof(head), "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %llu\r\n\r\n",
                               (int)status, reason, type, (unsigned long long)length);
    struct iovec parts[2] = {{head, (size_t)head_length}, {(void *)bytes, (size_t)length}};
    size_t total = (size_t)head_length + (size_t)length, sent = 0;
    int first = 0;
    while (sent < total) {
        struct msghdr message;
        memset(&message, 0, sizeof(message));
        message.msg_iov = parts + first;
        message.msg_iovlen = (size_t)(2 - first);
        ssize_t wrote = sendmsg((int)fd, &message, MSG_NOSIGNAL);
        if (wrote < 0 && errno == EINTR) continue;
        if (wrote <= 0) return -1;
        sent += (size_t)wrote;
        size_t skip = (size_t)wrote;
        while (first < 2 && skip >= parts[first].iov_len) { skip -= parts[first].iov_len; ++first; }
        if (first < 2) { parts[first].iov_base = (char *)parts[first].iov_base + skip; parts[first].iov_len -= skip; }
    }
    return 0;
}
#else
int64_t nl_net_listen(void *env, int64_t port) { (void)env; (void)port; return -1; }
int64_t nl_net_accept(void *env, int64_t listener) { (void)env; (void)listener; return -1; }
int64_t nl_net_close(void *env, int64_t fd) { (void)env; (void)fd; return -1; }
int64_t nl_http_read(void *env, int64_t fd, unsigned char *target, uint64_t capacity, int64_t *target_length) {
    (void)env; (void)fd; (void)target; (void)capacity; (void)target_length; return -1;
}
int64_t nl_http_write(void *env, int64_t fd, int64_t status, int64_t kind, void *body_descriptor, uint64_t capacity) {
    (void)env; (void)fd; (void)status; (void)kind; (void)body_descriptor; (void)capacity; return -1;
}
#endif

#ifdef NLC_WITH_DB
/* Env.db_query(sql, key): run one statement with ?1 bound to key on this thread's connection to the SQLite file
   named by NLC_DB (default app.db). The answer is the first column of the first row, or none. Each thread opens its
   own connection (WAL mode) and keeps its prepared statements. */
#include "sqlite3.h"

typedef struct { uint64_t length; char *sql; sqlite3_stmt *statement; } nl_db_statement;
static _Thread_local sqlite3 *nl_db_connection;
static _Thread_local nl_db_statement nl_db_statements[64];
static _Thread_local int nl_db_statement_count;

static sqlite3 *nl_db_open(void) {
    if (nl_db_connection) return nl_db_connection;
    const char *path = getenv("NLC_DB");
    sqlite3 *connection = NULL;
    if (sqlite3_open_v2(path && *path ? path : "app.db", &connection,
                        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        sqlite3_close(connection);
        return NULL;
    }
    sqlite3_busy_timeout(connection, 5000);
    sqlite3_exec(connection, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", NULL, NULL, NULL);
    nl_db_connection = connection;
    return connection;
}

static sqlite3_stmt *nl_db_statement_for(sqlite3 *connection, const unsigned char *sql, uint64_t length) {
    for (int index = 0; index < nl_db_statement_count; ++index) {
        if (nl_db_statements[index].length == length && memcmp(nl_db_statements[index].sql, sql, length) == 0)
            return nl_db_statements[index].statement;
    }
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(connection, (const char *)sql, (int)length, &statement, NULL) != SQLITE_OK) return NULL;
    if (nl_db_statement_count < 64) {
        char *copy = (char *)malloc(length ? length : 1);
        if (copy) {
            memcpy(copy, sql, length);
            nl_db_statements[nl_db_statement_count++] = (nl_db_statement){length, copy, statement};
        }
    }
    return statement;
}

void nl_db_query(void *env, void *descriptor, uint64_t capacity, int64_t key, void *result) {
    (void)env;
    unsigned char scratch[4096];
    const unsigned char *bytes; uint64_t length; int tag = -1, code = 0;
    *(int32_t *)result = 1;
    if (!nl_extract_raw(descriptor, 2, capacity, scratch, &bytes, &length, &tag, &code)) return;
    sqlite3 *connection = nl_db_open();
    if (!connection) return;
    sqlite3_stmt *statement = nl_db_statement_for(connection, bytes, length);
    if (!statement) return;
    sqlite3_bind_int64(statement, 1, key);
    if (sqlite3_step(statement) == SQLITE_ROW) {
        *(int64_t *)((unsigned char *)result + 8) = sqlite3_column_int64(statement, 0);
        *(int32_t *)result = 0;
    }
    sqlite3_reset(statement);
    sqlite3_clear_bindings(statement);
}
#else
void nl_db_query(void *env, void *descriptor, uint64_t capacity, int64_t key, void *result) {
    (void)env; (void)descriptor; (void)capacity; (void)key;
    *(int32_t *)result = 1;
}
#endif

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
