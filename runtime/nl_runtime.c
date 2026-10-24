#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

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
