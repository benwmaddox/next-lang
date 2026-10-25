use std::fs;
use std::path::Path;
use std::process::Command;

#[test]
fn reset_reuses_the_same_dirty_stack_region() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let temporary =
        std::env::temp_dir().join(format!("next-lang-stack-reuse-{}", std::process::id()));
    fs::create_dir_all(&temporary).expect("create temporary stack probe directory");
    let source = temporary.join("probe.c");
    let binary = temporary.join("probe");
    fs::write(
        &source,
        r#"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern void *nl_context_create(uint64_t, uint64_t);
extern void *nl_context_base(void *);
extern void nl_context_set_top(void *, void *);
extern void *nl_stack_alloc(void *, void *, uint64_t, uint64_t, int32_t, int32_t, int32_t);
extern void nl_context_destroy(void *);

int main(void) {
    const uint64_t bytes = 8 + 4096 * 8;
    void *context = nl_context_create(1024 * 1024, 0);
    void *base = nl_context_base(context);
    unsigned char *first = nl_stack_alloc(context, base, bytes, 8, 0, 1, 1);
    memset(first, 0xA5, bytes);
    nl_context_set_top(context, base);
    unsigned char *second = nl_stack_alloc(context, base, bytes, 8, 0, 2, 1);
    int reused = first == second;
    int dirty = 1;
    for (uint64_t i = 0; i < bytes; ++i) dirty &= second[i] == 0xA5;
    printf("same address: %s; dirty bytes retained: %s\n",
           reused ? "yes" : "no", dirty ? "yes" : "no");
    nl_context_destroy(context);
    return reused && dirty ? 0 : 1;
}
"#,
    )
    .expect("write temporary C probe");

    let build = Command::new("clang")
        .args(["-O1", "-pthread"])
        .arg(&source)
        .arg(root.join("runtime/nl_runtime.c"))
        .arg("-o")
        .arg(&binary)
        .output()
        .expect("start clang for the runtime stack probe");
    assert!(
        build.status.success(),
        "runtime probe failed to compile: {}",
        String::from_utf8_lossy(&build.stderr)
    );
    let run = Command::new(&binary)
        .output()
        .expect("run the runtime stack probe");
    assert_eq!(run.status.code(), Some(0));
    assert_eq!(
        String::from_utf8_lossy(&run.stdout),
        "same address: yes; dirty bytes retained: yes\n"
    );
    fs::remove_dir_all(&temporary).expect("remove temporary stack probe directory");
}
