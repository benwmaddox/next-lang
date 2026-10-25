use std::fs;
use std::path::Path;
use std::process::Command;

#[test]
fn decimal_fast_path_matches_the_general_formatter() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let temporary =
        std::env::temp_dir().join(format!("next-lang-number-format-{}", std::process::id()));
    fs::create_dir_all(&temporary).expect("create temporary number-format probe directory");
    let source = temporary.join("probe.c");
    let binary = temporary.join("probe");
    fs::write(
        &source,
        r#"
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern uint64_t nl_ascii_format_i64(int64_t, unsigned char *);
extern uint64_t nl_ascii_format_i64_radix(int64_t, int32_t, unsigned char *);
extern uint64_t nl_ascii_format_i64_radix_general(int64_t, int32_t, unsigned char *);
extern uint64_t nl_ascii_decimal_length_i64(int64_t);

static int check_decimal(int64_t value) {
    unsigned char fast[32];
    unsigned char general[32];
    memset(fast, 0xa5, sizeof(fast));
    memset(general, 0xa5, sizeof(general));
    uint64_t fast_length = nl_ascii_format_i64(value, fast);
    uint64_t general_length = nl_ascii_format_i64_radix_general(value, 10, general);
    return fast_length == general_length &&
           fast_length == nl_ascii_decimal_length_i64(value) &&
           memcmp(fast, general, (size_t)fast_length) == 0 &&
           fast[fast_length] == 0xa5 && general[general_length] == 0xa5;
}

static int check_other_radix(int64_t value, int32_t radix) {
    unsigned char selected[80];
    unsigned char general[80];
    uint64_t selected_length = nl_ascii_format_i64_radix(value, radix, selected);
    uint64_t general_length = nl_ascii_format_i64_radix_general(value, radix, general);
    return selected_length == general_length &&
           memcmp(selected, general, (size_t)selected_length) == 0;
}

int main(void) {
    const int64_t fixed[] = {
        0, 1, -1, INT32_MIN, INT32_MIN + 1, INT32_MAX - 1, INT32_MAX,
        INT64_MIN, INT64_MIN + 1, INT64_MAX - 1, INT64_MAX,
        -1000000000000000000LL, -100000000000000000LL,
        100000000000000000LL, 1000000000000000000LL,
    };
    for (size_t i = 0; i < sizeof(fixed) / sizeof(fixed[0]); ++i) {
        if (!check_decimal(fixed[i])) {
            fprintf(stderr, "decimal mismatch at fixed value %" PRId64 "\n", fixed[i]);
            return 1;
        }
        const int32_t other_radices[] = { 2, 8, 16 };
        for (size_t radix_index = 0;
             radix_index < sizeof(other_radices) / sizeof(other_radices[0]);
             ++radix_index) {
            int32_t radix = other_radices[radix_index];
            if (!check_other_radix(fixed[i], radix)) {
                fprintf(stderr, "radix %d mismatch at fixed value %" PRId64 "\n",
                        radix, fixed[i]);
                return 1;
            }
        }
    }

    int64_t power = 1;
    for (int exponent = 1; exponent <= 18; ++exponent) {
        power *= 10;
        const int64_t boundary[] = { power - 1, power, power + 1,
                                     -(power - 1), -power, -(power + 1) };
        for (size_t i = 0; i < sizeof(boundary) / sizeof(boundary[0]); ++i) {
            if (!check_decimal(boundary[i])) {
                fprintf(stderr, "decimal mismatch at 10^%d boundary %" PRId64 "\n",
                        exponent, boundary[i]);
                return 1;
            }
        }
    }

    uint64_t state = UINT64_C(0x9e3779b97f4a7c15);
    for (uint64_t i = 0; i < UINT64_C(3000000); ++i) {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        int64_t value;
        memcpy(&value, &state, sizeof(value));
        if (!check_decimal(value)) {
            fprintf(stderr, "decimal mismatch at random value %" PRId64
                            " (case %" PRIu64 ")\n", value, i);
            return 1;
        }
    }
    puts("decimal formatter matches the general routine for boundaries and 3000000 random values");
    return 0;
}
"#,
    )
    .expect("write temporary C probe");

    let build = Command::new("clang")
        .args(["-O2", "-pthread"])
        .arg(&source)
        .arg(root.join("runtime/nl_runtime.c"))
        .arg("-o")
        .arg(&binary)
        .output()
        .expect("start clang for the number-format probe");
    assert!(
        build.status.success(),
        "number-format probe failed to compile: {}",
        String::from_utf8_lossy(&build.stderr)
    );
    let run = Command::new(&binary)
        .output()
        .expect("run the number-format probe");
    assert_eq!(
        run.status.code(),
        Some(0),
        "number-format probe failed: {}",
        String::from_utf8_lossy(&run.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&run.stdout),
        "decimal formatter matches the general routine for boundaries and 3000000 random values\n"
    );
    fs::remove_dir_all(&temporary).expect("remove temporary number-format probe directory");
}

#[test]
fn decimal_builder_appends_write_directly_into_the_builder() {
    let temporary =
        std::env::temp_dir().join(format!("next-lang-number-format-ir-{}", std::process::id()));
    fs::create_dir_all(&temporary).expect("create temporary number-format package");
    fs::write(
        temporary.join("main.nl"),
        r#"
fn append_ascii(out: grow Ascii max 32, value: long) {
    out.try_append(str(value)).unwrap()
}

fn append_text(out: grow Text max 32 bytes max 32, value: long) {
    out.try_append(str(value)).unwrap()
}

fn append_bytes(out: grow Bytes max 32, value: long) {
    out.try_append(str(value).bytes()).unwrap()
}

fn main() {
    var ascii: Ascii max 32 = Ascii.empty()
    var text: Text max 32 bytes max 32 = Text.empty()
    var bytes: Bytes max 32 = Bytes.empty()
    append_ascii(ascii, 123L)
    append_text(text, 123L)
    append_bytes(bytes, 123L)
}
"#,
    )
    .expect("write temporary number-format package");

    let compiled = next_lang::compile_package(&temporary).expect("compile builder append package");
    for function in ["append_ascii", "append_text", "append_bytes"] {
        let marker = format!("; function {function}\n");
        let start = compiled
            .llvm_ir
            .find(&marker)
            .unwrap_or_else(|| panic!("generated IR is missing {function}"));
        let body = &compiled.llvm_ir[start..];
        let end = body.find("\n}\n").expect("function body closes") + 3;
        let body = &body[..end];
        assert!(
            body.contains("@nl_ascii_decimal_length_i64") && body.contains("@nl_ascii_format_i64"),
            "{function} should check the digit length and format into its destination"
        );
        assert!(
            !body.contains("@llvm.memmove"),
            "{function} should not stage and copy formatted digits"
        );
    }
    fs::remove_dir_all(&temporary).expect("remove temporary number-format package");
}
