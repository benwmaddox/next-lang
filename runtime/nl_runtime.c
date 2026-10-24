#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static const char **nl_files;
static size_t nl_file_capacity;

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

void nl_fail(int32_t kind, int32_t file_id, int32_t line, int32_t col) {
    const char *file = (file_id >= 0 && (size_t)file_id < nl_file_capacity && nl_files[file_id]) ? nl_files[file_id] : "<source>";
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
    }
    fprintf(stderr, "%s:%d:%d: %s\n", file, line, col, message);
    exit(1);
}

void nl_print_int(int32_t value) { printf("%d\n", value); }
void nl_print_long(int64_t value) { printf("%lld\n", (long long)value); }
void nl_print_bool(_Bool value) { puts(value ? "true" : "false"); }
