#define NLC_STACK_MODE_OFFSET 1
#include "../../runtime/stage0/nl_runtime.c"

#include <stddef.h>
#include <stdio.h>

int main(void) {
    printf("%zu %zu %zu %zu %zu %zu %zu %zu %zu %zu %zu %zu %zu %zu %zu\n",
           offsetof(nl_data_stack_context, header_mapping),
           offsetof(nl_data_stack_context, header_bytes),
           offsetof(nl_data_stack_context, mapping),
           offsetof(nl_data_stack_context, mapping_bytes),
           offsetof(nl_data_stack_context, reservation_bytes),
           offsetof(nl_data_stack_context, peak_used_bytes),
           offsetof(nl_data_stack_context, entry_name),
           offsetof(nl_data_stack_context, base),
           offsetof(nl_data_stack_context, top),
           offsetof(nl_data_stack_context, limit),
           offsetof(nl_data_stack_context, top_offset),
           offsetof(nl_data_stack_context, growth_count),
           offsetof(nl_data_stack_context, relocation_count),
           offsetof(nl_data_stack_context, growth_nanoseconds),
           offsetof(nl_data_stack_context, poisoned_mappings));
    return 0;
}
