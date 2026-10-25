#define _GNU_SOURCE
#include <stdint.h>
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
#include <linux/openat2.h>

#if defined(__linux__)
#include <sys/mman.h>
#include <sys/types.h>
#include <pthread.h>
#endif

static const char **nl_files;
static size_t nl_file_capacity;
static int nl_test_mode;
static int nl_print_fd = STDOUT_FILENO;

typedef struct {
    void *mapping;
    size_t mapping_bytes;
    unsigned char *base;
    unsigned char *top;
    unsigned char *limit;
    uintptr_t native_stack_limit;
    uintptr_t native_stack_start;
    uint64_t recursion_budget;
} nl_data_stack_context;

_Noreturn void nl_fail(int32_t kind, int32_t file_id, int32_t line, int32_t col);
static int nl_write_all(int fd, const unsigned char *bytes, uint64_t length);

static void nl_stack_startup_failure(const char *message) {
    fprintf(stderr, "nlc: data stack startup failure: %s\n", message);
    exit(1);
}

static uint64_t nl_data_stack_reservation(void) {
#if defined(NLC_TEST_BUILD)
    const char *override = getenv("NLC_TEST_DATA_STACK_BYTES");
    if (override && *override) {
        errno = 0;
        char *end = NULL;
        unsigned long long value = strtoull(override, &end, 10);
        if (errno || end == override || *end || value == 0) {
            nl_stack_startup_failure("NLC_TEST_DATA_STACK_BYTES must be a positive byte count");
        }
        return (uint64_t)value;
    }
#endif
    return UINT64_C(67108864);
}

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

void *nl_context_create(uint64_t requested_bytes, uint64_t requested_recursion_budget) {
#if defined(__linux__)
    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) nl_stack_startup_failure("could not determine the system page size");
    uint64_t bytes = requested_bytes ? requested_bytes : nl_data_stack_reservation();
    uint64_t page_size = (uint64_t)page;
    if (bytes > UINT64_MAX - (page_size - 1)) {
        nl_stack_startup_failure("requested reservation is too large");
    }
    bytes = ((bytes + page_size - 1) / page_size) * page_size;
    if (bytes > SIZE_MAX - page_size) {
        nl_stack_startup_failure("requested reservation is too large");
    }
    size_t total = (size_t)bytes + (size_t)page_size;
    void *mapping = mmap(NULL, total, PROT_NONE,
                         MAP_PRIVATE | MAP_ANONYMOUS
#ifdef MAP_NORESERVE
                             | MAP_NORESERVE
#endif
                         , -1, 0);
    if (mapping == MAP_FAILED) {
        nl_stack_startup_failure("could not reserve the requested address range");
    }
    if (mprotect(mapping, (size_t)bytes, PROT_READ | PROT_WRITE) != 0) {
        munmap(mapping, total);
        nl_stack_startup_failure("could not enable writable data stack pages");
    }
    nl_data_stack_context *context = calloc(1, sizeof(*context));
    if (!context) {
        munmap(mapping, total);
        nl_stack_startup_failure("could not allocate stack context");
    }
    context->mapping = mapping;
    context->mapping_bytes = total;
    context->base = (unsigned char *)mapping;
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

void nl_context_set_top(void *opaque, void *top) {
    nl_data_stack_context *context = opaque;
    if (!context) return;
    uintptr_t address = (uintptr_t)top;
    if (address < (uintptr_t)context->base || address > (uintptr_t)context->limit) {
        nl_stack_startup_failure("invalid data stack top");
    }
    context->top = top;
}

void nl_context_destroy(void *opaque) {
    nl_data_stack_context *context = opaque;
    if (!context) return;
#if defined(__linux__)
    munmap(context->mapping, context->mapping_bytes);
#endif
    free(context);
}

void *nl_stack_alloc(void *opaque, void *top, uint64_t bytes, uint64_t alignment,
                     int32_t file_id, int32_t line, int32_t col) {
    nl_data_stack_context *context = opaque;
    if (!context || alignment == 0 || (alignment & (alignment - 1)) != 0) {
        nl_stack_startup_failure("invalid region allocation request");
    }
    uintptr_t base = (uintptr_t)context->base;
    uintptr_t limit = (uintptr_t)context->limit;
    uintptr_t current = (uintptr_t)top;
    if (current < base || current > limit || current > UINTPTR_MAX - (alignment - 1)) {
        nl_fail(18, file_id, line, col);
    }
    uintptr_t aligned = (current + (uintptr_t)alignment - 1) & ~((uintptr_t)alignment - 1);
    if (bytes > UINTPTR_MAX - aligned || aligned + (uintptr_t)bytes > limit) {
        nl_fail(18, file_id, line, col);
    }
    context->top = (void *)(aligned + (uintptr_t)bytes);
    return (void *)aligned;
}

void nl_register_file(int32_t file_id, const char *name) {
    if (file_id < 0) return;
    size_t needed = (size_t)file_id + 1;
    if (needed > nl_file_capacity) {
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

void nl_set_test_mode(void) { nl_test_mode = 1; }

_Bool nl_has_argument(int32_t argc, const char **argv, const char *wanted) {
    for (int32_t i = 1; i < argc; ++i) {
        if (argv[i] && strcmp(argv[i], wanted) == 0) return 1;
    }
    return 0;
}

typedef struct {
    int mode;
    uint64_t memory_limit;
    uint64_t memory_used;
    uint64_t swap_limit;
    uint64_t swap_used;
    uint64_t host_available;
    uint64_t commit_limit;
    uint64_t committed;
    int has_cgroup;
    int has_host;
    int has_commit;
} nl_memory_policy;

static uint64_t nl_saturating_add(uint64_t a, uint64_t b) {
    return UINT64_MAX - a < b ? UINT64_MAX : a + b;
}

static int nl_read_u64_file(const char *path, uint64_t *value) {
    FILE *file = fopen(path, "r");
    if (!file) return 0;
    char text[128];
    int ok = fgets(text, sizeof(text), file) != NULL;
    fclose(file);
    if (!ok) return 0;
    if (strncmp(text, "max", 3) == 0) {
        *value = UINT64_MAX;
        return 1;
    }
    errno = 0;
    char *end = NULL;
    if (text[0] == '-') return 0;
    unsigned long long parsed = strtoull(text, &end, 10);
    if (errno || end == text) return 0;
    while (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n') ++end;
    if (*end != '\0') return 0;
    *value = (uint64_t)parsed;
    return 1;
}

static uint64_t nl_min_remaining(uint64_t limit, uint64_t used) {
    if (limit == UINT64_MAX) return UINT64_MAX;
    return used >= limit ? 0 : limit - used;
}

static void nl_read_host_memory(nl_memory_policy *policy) {
#if defined(__linux__)
    FILE *file = fopen("/proc/meminfo", "r");
    if (!file) return;
    char line[256];
    uint64_t available_kb = 0;
    uint64_t commit_limit_kb = 0;
    uint64_t committed_kb = 0;
    int found_available = 0;
    int found_commit_limit = 0;
    int found_committed = 0;
    while (fgets(line, sizeof(line), file)) {
        unsigned long long value = 0;
        if (sscanf(line, "MemAvailable: %llu kB", &value) == 1) {
            available_kb = value;
            found_available = 1;
        } else if (sscanf(line, "CommitLimit: %llu kB", &value) == 1) {
            commit_limit_kb = value;
            found_commit_limit = 1;
        } else if (sscanf(line, "Committed_AS: %llu kB", &value) == 1) {
            committed_kb = value;
            found_committed = 1;
        }
    }
    fclose(file);
    if (found_available) {
        policy->host_available = available_kb > UINT64_MAX / 1024 ? UINT64_MAX : available_kb * 1024;
        policy->has_host = 1;
    }
    if (found_commit_limit) {
        policy->commit_limit = commit_limit_kb > UINT64_MAX / 1024 ? UINT64_MAX : commit_limit_kb * 1024;
    }
    if (found_committed) {
        policy->committed = committed_kb > UINT64_MAX / 1024 ? UINT64_MAX : committed_kb * 1024;
    }
    policy->has_commit = found_commit_limit && found_committed;
#endif
}

static void nl_read_cgroup_memory(nl_memory_policy *policy) {
#if defined(__linux__)
    FILE *file = fopen("/proc/self/cgroup", "r");
    if (!file) return;
    char line[PATH_MAX + 64];
    char group[PATH_MAX] = "";
    while (fgets(line, sizeof(line), file)) {
        if (strncmp(line, "0::", 3) == 0) {
            size_t len = strcspn(line + 3, "\r\n");
            if (len < sizeof(group)) {
                memcpy(group, line + 3, len);
                group[len] = '\0';
            }
            break;
        }
    }
    fclose(file);
    if (!group[0] || strstr(group, "..")) return;

    char directory[PATH_MAX];
    if (snprintf(directory, sizeof(directory), "/sys/fs/cgroup%s", group) >= (int)sizeof(directory)) return;
    const char *mount = "/sys/fs/cgroup";
    for (;;) {
        char path[PATH_MAX];
        uint64_t limit, used;
        if (snprintf(path, sizeof(path), "%s/memory.max", directory) < (int)sizeof(path)
            && nl_read_u64_file(path, &limit)) {
            if (snprintf(path, sizeof(path), "%s/memory.current", directory) < (int)sizeof(path)
                && nl_read_u64_file(path, &used)) {
                uint64_t remaining = nl_min_remaining(limit, used);
                uint64_t current_remaining = nl_min_remaining(policy->memory_limit, policy->memory_used);
                if (remaining < current_remaining) {
                    policy->memory_limit = limit;
                    policy->memory_used = used;
                }
                policy->has_cgroup = 1;
            }
        }
        uint64_t swap_limit, swap_used;
        if (snprintf(path, sizeof(path), "%s/memory.swap.max", directory) < (int)sizeof(path)
            && nl_read_u64_file(path, &swap_limit)
            && snprintf(path, sizeof(path), "%s/memory.swap.current", directory) < (int)sizeof(path)
            && nl_read_u64_file(path, &swap_used)) {
            uint64_t remaining = nl_min_remaining(swap_limit, swap_used);
            uint64_t current_remaining = nl_min_remaining(policy->swap_limit, policy->swap_used);
            if (remaining < current_remaining) {
                policy->swap_limit = swap_limit;
                policy->swap_used = swap_used;
            }
        }
        if (strcmp(directory, mount) == 0) break;
        char *slash = strrchr(directory, '/');
        if (!slash || slash < directory + strlen(mount)) break;
        if (slash == directory + strlen(mount)) directory[slash - directory] = '\0';
        else *slash = '\0';
    }
#endif
}

static int nl_read_policy(nl_memory_policy *policy) {
    memset(policy, 0, sizeof(*policy));
    policy->memory_limit = UINT64_MAX;
    policy->swap_limit = UINT64_MAX;
    policy->commit_limit = UINT64_MAX;
#ifdef NLC_TEST_BUILD
    const char *injected = getenv("NLC_TEST_MEMORY_POLICY");
    if (injected && *injected) {
        char copy[512];
        if (strlen(injected) >= sizeof(copy)) return 0;
        strcpy(copy, injected);
        char *save = NULL;
        int has_commit_limit = 0;
        int has_committed = 0;
        for (char *part = strtok_r(copy, ";", &save); part; part = strtok_r(NULL, ";", &save)) {
            char key[40], value[80];
            if (sscanf(part, "%39[^=]=%79s", key, value) != 2) return 0;
            char *end = NULL;
            errno = 0;
            unsigned long long parsed = 0;
            if (strcmp(value, "max") != 0) {
                parsed = strtoull(value, &end, 10);
                if (errno || end == value || *end) return 0;
            }
            uint64_t number = strcmp(value, "max") == 0 ? UINT64_MAX : (uint64_t)parsed;
            if (strcmp(key, "mode") == 0) policy->mode = (int)number;
            else if (strcmp(key, "memory") == 0) policy->memory_limit = number;
            else if (strcmp(key, "current") == 0) policy->memory_used = number;
            else if (strcmp(key, "swap") == 0) policy->swap_limit = number;
            else if (strcmp(key, "swap_current") == 0) policy->swap_used = number;
            else if (strcmp(key, "available") == 0) { policy->host_available = number; policy->has_host = 1; }
            else if (strcmp(key, "commit") == 0) { policy->commit_limit = number; has_commit_limit = 1; }
            else if (strcmp(key, "committed") == 0) { policy->committed = number; has_committed = 1; }
            else return 0;
        }
        policy->has_cgroup = policy->memory_limit != UINT64_MAX || policy->swap_limit != UINT64_MAX;
        policy->has_commit = has_commit_limit && has_committed;
        if (!policy->has_host) policy->host_available = UINT64_MAX;
        return 1;
    }
#endif
#if defined(__linux__)
    FILE *overcommit = fopen("/proc/sys/vm/overcommit_memory", "r");
    if (!overcommit || fscanf(overcommit, "%d", &policy->mode) != 1) {
        if (overcommit) fclose(overcommit);
        return 0;
    }
    fclose(overcommit);
    nl_read_host_memory(policy);
    nl_read_cgroup_memory(policy);
    return 1;
#else
    return 0;
#endif
}

static void nl_memory_refuse(const char *reason) {
    fprintf(stderr, "nlc: startup memory guarantee failed: %s\n", reason);
    fflush(stderr);
    exit(1);
}

void nl_claim_memory(void *memory, uint64_t claim, uint64_t headroom, _Bool allow_overcommit) {
    if (allow_overcommit) {
        fputs("nlc: startup memory guarantee is off (--allow-overcommit)\n", stderr);
        fflush(stderr);
    } else {
        nl_memory_policy policy;
        if (!nl_read_policy(&policy)) nl_memory_refuse("could not read Linux overcommit or cgroup memory policy");
        uint64_t required = nl_saturating_add(claim, headroom);
        uint64_t cgroup_memory = nl_min_remaining(policy.memory_limit, policy.memory_used);
        uint64_t cgroup_swap = nl_min_remaining(policy.swap_limit, policy.swap_used);
        if (claim > cgroup_memory) nl_memory_refuse("global state does not fit the effective cgroup memory.max limit");
        uint64_t available = policy.has_host ? policy.host_available : UINT64_MAX;
        if (cgroup_memory < available) available = cgroup_memory;
        if (claim > available) nl_memory_refuse("global state does not fit currently available memory");
        if (policy.has_cgroup && required > nl_saturating_add(cgroup_memory, cgroup_swap)) {
            nl_memory_refuse("global state plus job_headroom exceeds effective cgroup memory and swap limits");
        }
        if (!policy.has_cgroup && required > available) {
            nl_memory_refuse("global state plus job_headroom exceeds currently available memory");
        }
        if (policy.mode == 2) {
            if (!policy.has_commit) nl_memory_refuse("could not read Linux strict commit limits");
            uint64_t committed = policy.committed;
            uint64_t commit_available = nl_min_remaining(policy.commit_limit, committed);
            if (required > commit_available) nl_memory_refuse("strict overcommit commit limit cannot back global state and job_headroom");
        } else if (policy.has_host && required > available && !policy.has_cgroup) {
            nl_memory_refuse("global state plus job_headroom exceeds available host memory");
        }
    }

    if (memory && claim) {
        long page_size = sysconf(_SC_PAGESIZE);
        if (page_size <= 0) nl_memory_refuse("could not determine the system page size");
        volatile unsigned char *bytes = (volatile unsigned char *)memory;
        for (uint64_t offset = 0; offset < claim; offset += (uint64_t)page_size) {
            unsigned char value = bytes[offset];
            bytes[offset] = value;
        }
        unsigned char value = bytes[claim - 1];
        bytes[claim - 1] = value;
    }

    if (!allow_overcommit) {
        nl_memory_policy after;
        if (!nl_read_policy(&after)) {
            nl_memory_refuse("could not recheck Linux memory policy after touching global state");
        }
        if (after.has_host && headroom > after.host_available) {
            nl_memory_refuse("touching global state left less than job_headroom in host memory");
        }
        if (after.mode == 2) {
            if (!after.has_commit) nl_memory_refuse("could not recheck Linux strict commit limits after touching global state");
            uint64_t commit_left = nl_min_remaining(after.commit_limit, after.committed);
            if (headroom > commit_left) {
                nl_memory_refuse("touching global state left less than job_headroom under the strict commit limit");
            }
        }
        if (after.has_cgroup) {
            uint64_t memory_left = nl_min_remaining(after.memory_limit, after.memory_used);
            uint64_t swap_left = nl_min_remaining(after.swap_limit, after.swap_used);
            if (headroom > nl_saturating_add(memory_left, swap_left)) {
                nl_memory_refuse("touching global state left less than job_headroom in the cgroup");
            }
        } else if (!after.has_host) {
            nl_memory_refuse("cannot establish remaining host memory headroom after touching global state");
        }
    }
}

static const char *nl_file_name(int32_t file_id) {
    const char *file = (file_id >= 0 && (size_t)file_id < nl_file_capacity && nl_files[file_id]) ? nl_files[file_id] : "<source>";
    return file;
}

_Noreturn void nl_fail(int32_t kind, int32_t file_id, int32_t line, int32_t col) {
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
        case 18: message = "data stack exhausted"; break;
        case 19: message = "recursion budget exhausted"; break;
        case 20: message = "standard output write failed"; break;
    }
    fprintf(stderr, "%s:%d:%d: %s\n", file, line, col, message);
    exit(nl_test_mode ? 70 : 1);
}

void nl_expect_fail_compare(int32_t file_id, int32_t line, int32_t col,
                            const char *source, int64_t left, int64_t right,
                            int32_t is_bool) {
    char left_text[32];
    char right_text[32];
    if (is_bool) {
        snprintf(left_text, sizeof(left_text), "%s", left ? "true" : "false");
        snprintf(right_text, sizeof(right_text), "%s", right ? "true" : "false");
    } else {
        snprintf(left_text, sizeof(left_text), "%lld", (long long)left);
        snprintf(right_text, sizeof(right_text), "%lld", (long long)right);
    }
    printf("  %s:%d:%d: %s\n    left:  %s\n    right: %s\n",
           nl_file_name(file_id), line, col, source, left_text, right_text);
    (void)fflush(stdout);
}

void nl_expect_fail_bool(int32_t file_id, int32_t line, int32_t col,
                         const char *source) {
    printf("  %s:%d:%d: %s\n    value: false\n",
           nl_file_name(file_id), line, col, source);
    (void)fflush(stdout);
}

static void nl_print_bytes(const unsigned char *bytes, uint64_t length) {
    if (nl_write_all(nl_print_fd, bytes, length) != 0) nl_fail(20, -1, 0, 0);
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

uint64_t nl_ascii_format_i64(int64_t value, unsigned char *destination) {
    unsigned char reversed[20];
    uint64_t length = 0;
    uint64_t magnitude;
    int negative = value < 0;
    if (negative) {
        magnitude = (uint64_t)(-(value + 1)) + 1;
    } else {
        magnitude = (uint64_t)value;
    }
    do {
        reversed[length++] = (unsigned char)('0' + magnitude % 10);
        magnitude /= 10;
    } while (magnitude != 0);
    if (negative) destination[0] = '-';
    uint64_t offset = (uint64_t)negative;
    while (length != 0) destination[offset++] = reversed[--length];
    return offset;
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

void nl_print_set_fd(int32_t fd) {
    if (fd == STDOUT_FILENO || fd == STDERR_FILENO) nl_print_fd = fd;
}

void nl_print_error_prefix(void) {
    static const unsigned char prefix[] = "error: ";
    if (nl_write_all(STDERR_FILENO, prefix, sizeof(prefix) - 1) != 0) nl_fail(20, -1, 0, 0);
}

void nl_print_int(int32_t value) {
    char buffer[32];
    int length = snprintf(buffer, sizeof(buffer), "%d\n", value);
    if (length < 0 || (size_t)length >= sizeof(buffer)) nl_fail(20, -1, 0, 0);
    nl_print_bytes((const unsigned char *)buffer, (uint64_t)length);
}

void nl_print_long(int64_t value) {
    char buffer[32];
    int length = snprintf(buffer, sizeof(buffer), "%lld\n", (long long)value);
    if (length < 0 || (size_t)length >= sizeof(buffer)) nl_fail(20, -1, 0, 0);
    nl_print_bytes((const unsigned char *)buffer, (uint64_t)length);
}

void nl_print_bool(_Bool value) {
    static const unsigned char yes[] = "true\n";
    static const unsigned char no[] = "false\n";
    nl_print_bytes(value ? yes : no, value ? sizeof(yes) - 1 : sizeof(no) - 1);
}

void nl_print_int_raw(int32_t value) {
    char buffer[32];
    int length = snprintf(buffer, sizeof(buffer), "%d", value);
    if (length < 0 || (size_t)length >= sizeof(buffer)) nl_fail(20, -1, 0, 0);
    nl_print_bytes((const unsigned char *)buffer, (uint64_t)length);
}

void nl_print_long_raw(int64_t value) {
    char buffer[32];
    int length = snprintf(buffer, sizeof(buffer), "%lld", (long long)value);
    if (length < 0 || (size_t)length >= sizeof(buffer)) nl_fail(20, -1, 0, 0);
    nl_print_bytes((const unsigned char *)buffer, (uint64_t)length);
}

void nl_print_bool_raw(_Bool value) {
    static const unsigned char yes[] = "true";
    static const unsigned char no[] = "false";
    nl_print_bytes(value ? yes : no, value ? sizeof(yes) - 1 : sizeof(no) - 1);
}

void nl_print_text(const char *value) {
    if (value) nl_print_bytes((const unsigned char *)value, (uint64_t)strlen(value));
}

void nl_print_newline(void) {
    static const unsigned char newline = '\n';
    nl_print_bytes(&newline, 1);
}

void nl_expect_fail_header(int32_t file_id, int32_t line, int32_t col,
                           const char *source) {
    printf("  %s:%d:%d: %s\n", nl_file_name(file_id), line, col, source);
    (void)fflush(stdout);
}
void nl_expect_fail_left(void) {
    fputs("    left:  ", stdout);
    (void)fflush(stdout);
}
void nl_expect_fail_right(void) {
    fputs("    right: ", stdout);
    (void)fflush(stdout);
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

static int nl_errno_error(int error) {
    if (error == ENOENT) return 0;
    if (error == EACCES || error == EPERM || error == EROFS) return 1;
    if (error == EXDEV || error == ELOOP) return 6;
    return 7;
}

static void nl_args_startup_failure(const char *message) {
    fprintf(stderr, "nlc: startup argument failure: %s\n", message);
    exit(1);
}

static void nl_remove_tree(const char *path) {
    DIR *directory = opendir(path);
    if (!directory) {
        unlink(path);
        return;
    }
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t length = strlen(path) + strlen(entry->d_name) + 2;
        char *child = (char *)malloc(length);
        if (!child) continue;
        snprintf(child, length, "%s/%s", path, entry->d_name);
        struct stat status;
        if (lstat(child, &status) == 0 && S_ISDIR(status.st_mode)) nl_remove_tree(child);
        else unlink(child);
        free(child);
    }
    closedir(directory);
    rmdir(path);
}

void *nl_env_create(int argc, char **argv, int capabilities) {
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
    if (environment->test_directory) {
        nl_remove_tree(environment->test_directory);
        free(environment->test_directory);
    }
    free(environment);
}

void *nl_env_args(void *value) { return &((nl_environment *)value)->args; }
void *nl_env_fs(void *value) { return &((nl_environment *)value)->fs; }
void *nl_env_out(void *value, int fd) {
    nl_environment *environment = (nl_environment *)value;
    return &environment->out[fd == STDERR_FILENO ? 1 : 0];
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
    if (is_argument) {
        if (!value) { *error_tag = 0; return 0; }
        length = strlen((const char *)value);
        if (length > 4096) { *error_tag = 2; return 0; }
        memcpy(output, value, (size_t)length);
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
    if (is_argument) {
        if (!value) { *error_tag = 0; return 0; }
        *bytes = (const unsigned char *)value;
        *length = strlen((const char *)value);
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
        int error = nl_write_all(fd, scratch, amount);
        if (error) return error;
        offset += amount;
    }
    return 0;
}

void nl_fs_read(void *handle, void *path_value, int path_is_argument, uint64_t path_capacity,
                void *buffer, uint64_t capacity, void *result) {
    int error_tag = -1, error_code = 0;
    char path[4097];
    if (!nl_extract_path(path_value, path_is_argument, path_capacity, path, &error_tag, &error_code)) {
        if (buffer && capacity <= (SIZE_MAX - 8) / 4) memset(buffer, 0, 8 + (size_t)capacity * 4);
        nl_io_error(result, error_tag, error_code); return;
    }
    if (capacity > (SIZE_MAX - 8) / 4 || !buffer) {
        nl_io_error(result, 2, 0); return;
    }
    memset(buffer, 0, 8 + (size_t)capacity * 4);
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
        memset(buffer, 0, 8 + (size_t)capacity * 4);
        nl_io_error(result, error_tag == 2 ? 2 : nl_errno_error(failure), failure);
        return;
    }
    *(int64_t *)buffer = (int64_t)total;
    nl_io_error(result, -1, 0);
}

typedef struct { char *name; size_t length; int kind; } nl_dir_item;
static int nl_dir_compare(const void *left_value, const void *right_value) {
    const nl_dir_item *left = (const nl_dir_item *)left_value;
    const nl_dir_item *right = (const nl_dir_item *)right_value;
    size_t common = left->length < right->length ? left->length : right->length;
    int comparison = memcmp(left->name, right->name, common);
    if (comparison) return comparison;
    return left->length < right->length ? -1 : left->length > right->length;
}

void nl_fs_list(void *handle, void *path_value, int path_is_argument, uint64_t path_capacity,
                void *output, uint64_t capacity, void *result) {
    int error_tag = -1, error_code = 0;
    char path[4097];
    if (capacity > (SIZE_MAX - 8) / 16396 || !output) { nl_io_error(result, 3, 0); return; }
    memset(output, 0, 8 + (size_t)capacity * 16396);
    if (!nl_extract_path(path_value, path_is_argument, path_capacity, path, &error_tag, &error_code)) {
        nl_io_error(result, error_tag, error_code); return;
    }
    int fd = nl_open_beneath(((nl_fs_handle *)handle)->root_fd, path, O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0);
    if (fd < 0) { int error = errno; nl_io_error(result, nl_errno_error(error), error); return; }
    DIR *directory = fdopendir(fd);
    if (!directory) { int error = errno; close(fd); nl_io_error(result, nl_errno_error(error), error); return; }
    size_t allocated = capacity < 64 ? (size_t)capacity + 1 : 65;
    if (allocated == 0) allocated = 1;
    nl_dir_item *items = (nl_dir_item *)calloc(allocated, sizeof(nl_dir_item));
    if (!items) { closedir(directory); nl_io_error(result, 7, ENOMEM); return; }
    size_t count = 0;
    int failure_tag = -1, failure_code = 0;
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t length = strlen(entry->d_name);
        if (length > 4096) { failure_tag = 4; break; }
        if ((uint64_t)count >= capacity) { failure_tag = 3; break; }
        if (count >= allocated) {
            size_t next = allocated * 2;
            if (next > (size_t)capacity + 1) next = (size_t)capacity + 1;
            nl_dir_item *grown = (nl_dir_item *)realloc(items, next * sizeof(nl_dir_item));
            if (!grown) { failure_tag = 7; failure_code = ENOMEM; break; }
            memset(grown + allocated, 0, (next - allocated) * sizeof(nl_dir_item));
            items = grown; allocated = next;
        }
        items[count].name = strdup(entry->d_name);
        if (!items[count].name) { failure_tag = 7; failure_code = ENOMEM; break; }
        items[count].length = length;
        struct stat status;
        if (fstatat(dirfd(directory), entry->d_name, &status, AT_SYMLINK_NOFOLLOW) != 0) {
            failure_tag = nl_errno_error(errno); failure_code = errno; break;
        }
        items[count].kind = S_ISREG(status.st_mode) ? 0 : S_ISDIR(status.st_mode) ? 1 : 2;
        count++;
    }
    closedir(directory);
    if (failure_tag < 0) qsort(items, count, sizeof(nl_dir_item), nl_dir_compare);
    if (failure_tag >= 0) {
        for (size_t i = 0; i < count; ++i) free(items[i].name);
        free(items);
        nl_io_error(result, failure_tag, failure_code); return;
    }
    *(int64_t *)output = (int64_t)count;
    unsigned char *base = (unsigned char *)output;
    for (size_t i = 0; i < count; ++i) {
        unsigned char *name = base + 8 + i * 16392;
        *(int64_t *)name = (int64_t)items[i].length;
        int32_t *bytes = (int32_t *)(name + 8);
        for (size_t j = 0; j < items[i].length; ++j) bytes[j] = (unsigned char)items[i].name[j];
        int32_t *kind = (int32_t *)(base + 8 + (size_t)capacity * 16392 + i * 4);
        *kind = items[i].kind;
        free(items[i].name);
    }
    free(items);
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
        if (nl_extract_raw(data_value, 1, data_capacity, scratch, &bytes, &length, &error_tag, &error_code)) failure = nl_write_all(fd, bytes, length);
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
        if (!nl_extract_raw(data_value, 1, data_capacity, scratch, &bytes, &length, &tag, &code)) error = code ? code : EINVAL;
        else error = nl_write_all(out->fd, bytes, length);
    } else error = nl_write_byte_list(out->fd, data_value, data_capacity);
    if (!error && line) error = nl_write_all(out->fd, (const unsigned char *)"\n", 1);
    nl_io_error(result, error ? nl_errno_error(error) : -1, error);
}

void nl_out_arg(void *handle, void *argument, int line, void *result) {
    nl_out_handle *out = (nl_out_handle *)handle;
    const unsigned char *bytes = argument ? (const unsigned char *)argument : (const unsigned char *)"";
    int error = nl_write_all(out->fd, bytes, strlen((const char *)bytes));
    if (!error && line) error = nl_write_all(out->fd, (const unsigned char *)"\n", 1);
    nl_io_error(result, error ? nl_errno_error(error) : -1, error);
}

void nl_out_int(void *handle, int32_t value, void *result) {
    char buffer[32]; int length = snprintf(buffer, sizeof(buffer), "%d", value);
    int error = length < 0 ? EIO : nl_write_all(((nl_out_handle *)handle)->fd, (unsigned char *)buffer, (uint64_t)length);
    nl_io_error(result, error ? nl_errno_error(error) : -1, error);
}
void nl_out_long(void *handle, int64_t value, void *result) {
    char buffer[32]; int length = snprintf(buffer, sizeof(buffer), "%lld", (long long)value);
    int error = length < 0 ? EIO : nl_write_all(((nl_out_handle *)handle)->fd, (unsigned char *)buffer, (uint64_t)length);
    nl_io_error(result, error ? nl_errno_error(error) : -1, error);
}
void nl_print_arg(void *argument) {
    if (!argument) return;
    nl_print_bytes((const unsigned char *)argument, (uint64_t)strlen((const char *)argument));
    nl_print_newline();
}
