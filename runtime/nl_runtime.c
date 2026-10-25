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

#define NL_TEST_VAR_STORAGE_CAPACITY 131072
static const void *nl_test_var_descriptors[NL_TEST_VAR_STORAGE_CAPACITY];
static const void *nl_test_var_data[NL_TEST_VAR_STORAGE_CAPACITY];
static uint64_t nl_test_var_lengths[NL_TEST_VAR_STORAGE_CAPACITY];
static unsigned char *nl_test_var_metadata[NL_TEST_VAR_STORAGE_CAPACITY];
static uint64_t nl_test_var_metadata_sizes[NL_TEST_VAR_STORAGE_CAPACITY];
static size_t nl_test_var_count;

const char *nl_runtime_unicode_version(void) {
    return nl_unicode_version;
}

typedef struct {
    void *mapping;
    size_t mapping_bytes;
    uint64_t reservation_bytes;
    uint64_t peak_used_bytes;
    const char *entry_name;
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

static void nl_stack_startup_failure_for(const char *entry_name, uint64_t bytes,
                                         const char *message) {
    fprintf(stderr,
            "nlc: data stack startup failure for entry '%s' (reservation %llu bytes): %s\n",
            entry_name ? entry_name : "<unknown>",
            (unsigned long long)bytes,
            message);
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
    if (bytes == 0) {
        nl_stack_startup_failure_for(entry_name, requested_bytes,
                                     "computed data stack reservation is zero");
    }
    uint64_t page_size = (uint64_t)page;
    if (bytes > UINT64_MAX - (page_size - 1)) {
        nl_stack_startup_failure_for(entry_name, bytes, "requested reservation is too large");
    }
    bytes = ((bytes + page_size - 1) / page_size) * page_size;
    if (bytes > SIZE_MAX - page_size) {
        nl_stack_startup_failure_for(entry_name, bytes, "requested reservation is too large");
    }
    size_t total = (size_t)bytes + (size_t)page_size;
    void *mapping = mmap(NULL, total, PROT_NONE,
                         MAP_PRIVATE | MAP_ANONYMOUS
#ifdef MAP_NORESERVE
                             | MAP_NORESERVE
#endif
                         , -1, 0);
    if (mapping == MAP_FAILED) {
        nl_stack_startup_failure_for(entry_name, bytes,
                                     "could not reserve the requested address range");
    }
    if (mprotect(mapping, (size_t)bytes, PROT_READ | PROT_WRITE) != 0) {
        munmap(mapping, total);
        nl_stack_startup_failure_for(entry_name, bytes,
                                     "could not enable writable data stack pages");
    }
    nl_data_stack_context *context = calloc(1, sizeof(*context));
    if (!context) {
        munmap(mapping, total);
        nl_stack_startup_failure_for(entry_name, bytes, "could not allocate stack context");
    }
    context->mapping = mapping;
    context->mapping_bytes = total;
    context->reservation_bytes = bytes;
    context->entry_name = entry_name;
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
#if defined(NLC_TEST_BUILD)
    const char *report = getenv("NLC_TEST_REPORT_STACK_TOUCHED");
    if (report && strcmp(report, "1") == 0) {
        long page = sysconf(_SC_PAGESIZE);
        if (page > 0) {
            size_t pages = (size_t)(context->reservation_bytes / (uint64_t)page);
            unsigned char *residency = calloc(pages ? pages : 1, 1);
            if (residency && mincore(context->mapping, (size_t)context->reservation_bytes,
                                     residency) == 0) {
                uint64_t touched = 0;
                for (size_t index = 0; index < pages; ++index) {
                    if (residency[index] & 1) touched += (uint64_t)page;
                }
                fprintf(stderr,
                        "nlc stack entry '%s': reserved=%llu bytes touched=%llu bytes peak_used=%llu bytes\n",
                        context->entry_name ? context->entry_name : "<unknown>",
                        (unsigned long long)context->reservation_bytes,
                        (unsigned long long)touched,
                        (unsigned long long)context->peak_used_bytes);
            }
            free(residency);
        }
    }
#endif
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
    uint64_t used = (uint64_t)(aligned + (uintptr_t)bytes - base);
    if (used > context->peak_used_bytes) context->peak_used_bytes = used;
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

void nl_set_test_mode(void) {
    nl_test_var_count = 0;
    nl_test_mode = 1;
}

void nl_test_var_storage_reset(void) {
    if (!nl_test_mode) return;
    for (size_t index = 0; index < nl_test_var_count; ++index) {
        free(nl_test_var_metadata[index]);
        nl_test_var_metadata[index] = NULL;
        nl_test_var_metadata_sizes[index] = 0;
    }
    nl_test_var_count = 0;
}

void nl_test_var_storage_note(const void *descriptor, const void *data, uint64_t length,
                              uint64_t metadata_size) {
    if (!nl_test_mode || !descriptor) return;
    if (metadata_size > 128) {
        fprintf(stderr, "test failure: variable-size lane metadata exceeds 128 bytes\n");
        exit(70);
    }
    size_t current = nl_test_var_count;
    for (size_t index = 0; index < nl_test_var_count; ++index) {
        if (nl_test_var_descriptors[index] == descriptor) {
            current = index;
            break;
        }
    }
    for (size_t index = 0; index < nl_test_var_count; ++index) {
        if (index == current) continue;
        if (memcmp(nl_test_var_descriptors[index], nl_test_var_metadata[index],
                   nl_test_var_metadata_sizes[index]) != 0) {
            fprintf(stderr,
                    "test failure: updating one variable-size field changed another field's lane\n");
            exit(70);
        }
    }
    if (current < nl_test_var_count && length < nl_test_var_lengths[current] &&
        data != nl_test_var_data[current]) {
        fprintf(stderr,
                "test failure: shrinking a variable-size field moved it to a different slot\n");
        exit(70);
    }
    if (current == nl_test_var_count) {
        if (nl_test_var_count == NL_TEST_VAR_STORAGE_CAPACITY) {
            fprintf(stderr, "test failure: variable-size storage test hook capacity exceeded\n");
            exit(70);
        }
        nl_test_var_descriptors[current] = descriptor;
        nl_test_var_metadata[current] = malloc((size_t)metadata_size);
        if (!nl_test_var_metadata[current]) {
            fprintf(stderr, "test failure: cannot allocate variable-size metadata snapshot\n");
            exit(70);
        }
        ++nl_test_var_count;
    }
    nl_test_var_data[current] = data;
    nl_test_var_lengths[current] = length;
    nl_test_var_metadata_sizes[current] = metadata_size;
    memcpy(nl_test_var_metadata[current], descriptor, (size_t)metadata_size);
}

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
        case 21: message = "clamp lower bound is greater than its upper bound"; break;
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

uint64_t nl_ascii_format_i64_radix(int64_t value, int32_t radix,
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

uint64_t nl_ascii_format_i64(int64_t value, unsigned char *destination) {
    return nl_ascii_format_i64_radix(value, 10, destination);
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

#define NL_IO_ERROR_INVALID_UTF8 8

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

_Noreturn void nl_env_exit(int32_t code) {
    (void)fflush(stdout);
    (void)fflush(stderr);
    if (nl_test_mode) {
        fprintf(stderr, "Env.exit(%d) cannot be used in a test; this test process failed\n", code);
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
    if (buffer) *(int64_t *)buffer = 0;
    if (capacity > (SIZE_MAX - 8) / 4 || !buffer) {
        nl_io_error(result, 2, 0); return;
    }
    if (!nl_extract_path(path_value, path_is_argument, path_capacity, path, &error_tag, &error_code)) {
        nl_io_error(result, error_tag, error_code); return;
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
    int fd = nl_open_beneath(((nl_fs_handle *)handle)->root_fd,
                             path, O_RDONLY | O_CLOEXEC, 0);
    if (fd < 0) {
        int error = errno;
        nl_io_error(result, nl_errno_error(error), error);
        return;
    }
    unsigned char *staged = malloc(capacity ? (size_t)capacity : 1);
    if (!staged) {
        close(fd);
        nl_io_error(result, 7, ENOMEM);
        return;
    }
    uint64_t total = 0;
    int failure = 0;
    while (total < capacity) {
        size_t amount = (size_t)((capacity - total) < 8192 ? capacity - total : 8192);
        ssize_t got = read(fd, staged + total, amount);
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
        if (!nl_utf8_count(staged, total, &codepoints)) {
            error_tag = NL_IO_ERROR_INVALID_UTF8;
        } else if ((uint64_t)codepoints > codepoint_capacity) {
            error_tag = 2;
        }
    }
    if (failure || error_tag == 2 || error_tag == NL_IO_ERROR_INVALID_UTF8) {
        free(staged);
        nl_io_error(result, failure ? nl_errno_error(failure) : error_tag,
                    failure ? failure : error_code);
        return;
    }
    if (total) memcpy(output, staged, (size_t)total);
    free(staged);
    *output_length = (int64_t)total;
    if (output_codepoints) *output_codepoints = codepoints;
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
    if (output) *(int64_t *)output = 0;
    if (capacity > (SIZE_MAX - 8) / 16396 || !output) { nl_io_error(result, 3, 0); return; }
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
    *(int64_t *)output = (int64_t)count;
    free(items);
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
    int fd = nl_open_beneath(((nl_fs_handle *)handle)->root_fd,
                             path, O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0);
    if (fd < 0) {
        int error = errno;
        nl_io_error(result, nl_errno_error(error), error);
        return;
    }
    DIR *directory = fdopendir(fd);
    if (!directory) {
        int error = errno;
        close(fd);
        nl_io_error(result, nl_errno_error(error), error);
        return;
    }
    size_t allocated = capacity < 64 ? (size_t)capacity + 1 : 65;
    if (allocated == 0) allocated = 1;
    nl_dir_item *items = (nl_dir_item *)calloc(allocated, sizeof(nl_dir_item));
    if (!items) {
        closedir(directory);
        nl_io_error(result, 7, ENOMEM);
        return;
    }
    size_t count = 0;
    int failure_tag = -1, failure_code = 0;
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t length = strlen(entry->d_name);
        if (!nl_has_extension(entry->d_name, length, extension, extension_length)) continue;
        if (length > 4096) {
            failure_tag = 4;
            break;
        }
        int kind = nl_entry_kind_beneath(((nl_fs_handle *)handle)->root_fd,
                                         path, entry->d_name, length);
        if ((uint64_t)count >= capacity) {
            failure_tag = 3;
            break;
        }
        if (count >= allocated) {
            size_t next = allocated * 2;
            if (next > (size_t)capacity + 1) next = (size_t)capacity + 1;
            nl_dir_item *grown = (nl_dir_item *)realloc(items, next * sizeof(nl_dir_item));
            if (!grown) {
                failure_tag = 7;
                failure_code = ENOMEM;
                break;
            }
            memset(grown + allocated, 0, (next - allocated) * sizeof(nl_dir_item));
            items = grown;
            allocated = next;
        }
        items[count].name = strdup(entry->d_name);
        if (!items[count].name) {
            failure_tag = 7;
            failure_code = ENOMEM;
            break;
        }
        items[count].length = length;
        items[count].kind = kind;
        ++count;
    }
    closedir(directory);
    if (failure_tag < 0) qsort(items, count, sizeof(nl_dir_item), nl_dir_compare);
    if (failure_tag >= 0) {
        for (size_t i = 0; i < count; ++i) free(items[i].name);
        free(items);
        nl_io_error(result, failure_tag, failure_code);
        return;
    }
    unsigned char *base = (unsigned char *)output;
    for (size_t i = 0; i < count; ++i) {
        unsigned char *name = base + 8 + i * 16392;
        *(int64_t *)name = (int64_t)items[i].length;
        int32_t *bytes = (int32_t *)(name + 8);
        for (size_t j = 0; j < items[i].length; ++j) {
            bytes[j] = (unsigned char)items[i].name[j];
        }
        int32_t *kind = (int32_t *)(base + 8 + (size_t)capacity * 16392 + i * 4);
        *kind = items[i].kind;
        free(items[i].name);
    }
    *(int64_t *)output = (int64_t)count;
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
