#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <unistd.h>

#if defined(__linux__)
#include <sys/types.h>
#endif

static const char **nl_files;
static size_t nl_file_capacity;
static int nl_test_mode;

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
}

void nl_expect_fail_bool(int32_t file_id, int32_t line, int32_t col,
                         const char *source) {
    printf("  %s:%d:%d: %s\n    value: false\n",
           nl_file_name(file_id), line, col, source);
}

void nl_print_int(int32_t value) { printf("%d\n", value); }
void nl_print_long(int64_t value) { printf("%lld\n", (long long)value); }
void nl_print_bool(_Bool value) { puts(value ? "true" : "false"); }

void nl_print_int_raw(int32_t value) { printf("%d", value); }
void nl_print_long_raw(int64_t value) { printf("%lld", (long long)value); }
void nl_print_bool_raw(_Bool value) { fputs(value ? "true" : "false", stdout); }
void nl_print_text(const char *value) { fputs(value, stdout); }
void nl_print_newline(void) { putchar('\n'); }

void nl_expect_fail_header(int32_t file_id, int32_t line, int32_t col,
                           const char *source) {
    printf("  %s:%d:%d: %s\n", nl_file_name(file_id), line, col, source);
}
void nl_expect_fail_left(void) { fputs("    left:  ", stdout); }
void nl_expect_fail_right(void) { fputs("    right: ", stdout); }
