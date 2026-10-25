use next_lang::compile_package;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

static ENV_LOCK: Mutex<()> = Mutex::new(());

struct EnvRestore(Vec<(&'static str, Option<OsString>)>);

impl EnvRestore {
    fn set(key: &'static str, value: &str) -> Self {
        let previous = std::env::var_os(key);
        unsafe { std::env::set_var(key, value) };
        Self(vec![(key, previous)])
    }
}

impl Drop for EnvRestore {
    fn drop(&mut self) {
        for (key, value) in self.0.drain(..).rev() {
            unsafe {
                if let Some(value) = value {
                    std::env::set_var(key, value);
                } else {
                    std::env::remove_var(key);
                }
            }
        }
    }
}

struct TempWorkspace(PathBuf);

impl TempWorkspace {
    fn new() -> Self {
        let path =
            std::env::temp_dir().join(format!("next-lang-r1-heap-calls-{}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("create heap-call test workspace");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempWorkspace {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

const HEAP_COUNTERS: &str = r#"
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern void *__real_malloc(size_t);
extern void *__real_calloc(size_t, size_t);
extern void *__real_realloc(void *, size_t);
extern char *__real_strdup(const char *);
extern void __real_free(void *);
extern void __real_nl_env_destroy(void *);

static volatile int tracking_operations;
static uint64_t startup_calls[5];
static uint64_t operation_calls[5];

static void count_call(size_t index) {
    if (tracking_operations) ++operation_calls[index];
    else ++startup_calls[index];
}

void *__wrap_malloc(size_t size) { count_call(0); return __real_malloc(size); }
void *__wrap_calloc(size_t count, size_t size) { count_call(1); return __real_calloc(count, size); }
void *__wrap_realloc(void *pointer, size_t size) { count_call(2); return __real_realloc(pointer, size); }
char *__wrap_strdup(const char *value) { count_call(3); return __real_strdup(value); }
void __wrap_free(void *pointer) { count_call(4); __real_free(pointer); }

void nl_heap_count_begin(void) {
    tracking_operations = 1;
}

void __wrap_nl_env_destroy(void *environment) {
    tracking_operations = 0;
    dprintf(STDERR_FILENO,
            "heap_calls startup=%llu,%llu,%llu,%llu,%llu operations=%llu,%llu,%llu,%llu,%llu\n",
            (unsigned long long)startup_calls[0], (unsigned long long)startup_calls[1],
            (unsigned long long)startup_calls[2], (unsigned long long)startup_calls[3],
            (unsigned long long)startup_calls[4],
            (unsigned long long)operation_calls[0], (unsigned long long)operation_calls[1],
            (unsigned long long)operation_calls[2], (unsigned long long)operation_calls[3],
            (unsigned long long)operation_calls[4]);
    __real_nl_env_destroy(environment);
}
"#;

const OFFSET_RUNTIME_PROBE: &str = r#"
#include <stdint.h>
#include <string.h>

extern void *nl_context_create(uint64_t, uint64_t, const char *);
extern void nl_context_destroy(void *);
extern void *nl_env_create(int, char **, int);
extern void nl_env_destroy(void *);
extern void *nl_env_fs(void *);
extern void *nl_env_out(void *, int);
extern void nl_heap_count_begin(void);
extern void nl_fs_write(void *, void *, int, uint64_t, void *, int, uint64_t, void *);
extern void nl_fs_read(void *, void *, int, uint64_t, void *, uint64_t, void *);
extern void nl_fs_read_string(void *, void *, int, uint64_t, unsigned char *, uint64_t,
                              int, uint64_t, int64_t *, int64_t *, void *);
extern void nl_fs_list(void *, void *, int, uint64_t, void *, uint64_t, void *);
extern void nl_fs_list_with_extension(void *, void *, int, uint64_t, const unsigned char *,
                                      uint64_t, void *, uint64_t, void *);
extern void nl_out_write(void *, void *, int, uint64_t, int, void *);
extern void nl_print_int(int32_t);
extern uint64_t nl_ascii_format_i64(int64_t, unsigned char *);

static int result_ok(const unsigned char *result) {
    return *(const int32_t *)result == 0;
}

int main(int argc, char **argv) {
    void *context = nl_context_create(1024 * 1024, 0, "heap-probe");
    void *environment = nl_env_create(argc, argv, 3);
    void *fs = nl_env_fs(environment);
    void *out = nl_env_out(environment, 1);
    unsigned char result[12];

    nl_heap_count_begin();
    nl_fs_write(fs, "text.txt", 1, 0, "hello", 1, 0, result);
    if (!result_ok(result)) return 10;
    nl_fs_write(fs, "raw.bin", 1, 0, "ab", 1, 0, result);
    if (!result_ok(result)) return 11;

    unsigned char text[32];
    int64_t text_length = 0;
    int64_t codepoints = 0;
    nl_fs_read_string(fs, "text.txt", 1, 0, text, sizeof(text), 1, 32,
                      &text_length, &codepoints, result);
    if (!result_ok(result) || text_length != 5 || codepoints != 5 ||
        memcmp(text, "hello", 5) != 0) return 12;

    struct byte_list { int64_t count; int32_t bytes[8]; } bytes = { 0 };
    nl_fs_read(fs, "raw.bin", 1, 0, &bytes, 8, result);
    if (!result_ok(result) || bytes.count != 2 || bytes.bytes[0] != 'a' ||
        bytes.bytes[1] != 'b') return 13;

    enum { capacity = 8 };
    unsigned char listing[8 + capacity * 16392 + capacity * 4]
        __attribute__((aligned(8))) = { 0 };
    nl_fs_list(fs, ".", 1, 0, listing, capacity, result);
    if (!result_ok(result) || *(int64_t *)listing != 4) return 14;
    unsigned char filtered[8 + capacity * 16392 + capacity * 4]
        __attribute__((aligned(8))) = { 0 };
    nl_fs_list_with_extension(fs, ".", 1, 0, (const unsigned char *)"txt", 3,
                              filtered, capacity, result);
    if (!result_ok(result) || *(int64_t *)filtered != 1) return 15;

    unsigned char formatted[32];
    uint64_t formatted_length = nl_ascii_format_i64(12345, formatted);
    if (formatted_length != 5 || memcmp(formatted, "12345", 5) != 0) return 16;
    nl_print_int(42);
    nl_out_write(out, "runtime", 1, 0, 1, result);
    if (!result_ok(result)) return 17;

    nl_env_destroy(environment);
    nl_context_destroy(context);
    return 0;
}
"#;

const INTERLEAVED_TTY_OUTPUT_PROBE: &str = r#"
#define _GNU_SOURCE
#include <errno.h>
#include <pty.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

extern void *nl_context_create(uint64_t, uint64_t, const char *);
extern void nl_context_destroy(void *);
extern void nl_print_set_fd(int32_t);
extern void nl_print_ascii(const unsigned char *, uint64_t);

int main(void) {
    int master = -1, slave = -1;
    int saved_stdout = dup(STDOUT_FILENO);
    int saved_stderr = dup(STDERR_FILENO);
    if (saved_stdout < 0 || saved_stderr < 0 || openpty(&master, &slave, NULL, NULL, NULL) != 0)
        return 10;
    if (dup2(slave, STDOUT_FILENO) < 0 || dup2(slave, STDERR_FILENO) < 0) return 11;
    close(slave);

    void *context = nl_context_create(1024 * 1024, 0, "tty-order-probe");
    static const unsigned char before[] = "stdout-before";
    static const unsigned char middle[] = "stderr-middle";
    static const unsigned char after[] = "stdout-after";
    nl_print_set_fd(STDOUT_FILENO);
    nl_print_ascii(before, sizeof(before) - 1);
    nl_print_set_fd(STDERR_FILENO);
    nl_print_ascii(middle, sizeof(middle) - 1);
    nl_print_set_fd(STDOUT_FILENO);
    nl_print_ascii(after, sizeof(after) - 1);
    nl_context_destroy(context);

    if (dup2(saved_stdout, STDOUT_FILENO) < 0 || dup2(saved_stderr, STDERR_FILENO) < 0)
        return 12;
    close(saved_stdout);
    close(saved_stderr);
    unsigned char captured[128];
    size_t length = 0;
    for (;;) {
        ssize_t amount = read(master, captured + length, sizeof(captured) - length);
        if (amount < 0 && errno == EINTR) continue;
        if (amount < 0 && errno == EIO) break;
        if (amount < 0) return 13;
        if (amount == 0) break;
        length += (size_t)amount;
        if (length == sizeof(captured)) return 14;
    }
    static const unsigned char expected[] = "stdout-beforestderr-middlestdout-after";
    if (length != sizeof(expected) - 1 || memcmp(captured, expected, length) != 0)
        return 15;
    if (write(STDOUT_FILENO, captured, length) != (ssize_t)length) return 16;
    close(master);
    return 0;
}
"#;

#[test]
fn runtime_file_output_and_collection_operations_make_no_heap_calls_in_either_stack_mode() {
    let _lock = ENV_LOCK.lock().expect("environment lock");
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let runtime = root.join("runtime/nl_runtime.c");

    for mode in ["pointer", "offset"] {
        let _environment = EnvRestore::set("NLC_STACK_MODE", mode);
        let workspace = TempWorkspace::new();
        let package = workspace.path().join("package");
        fs::create_dir_all(&package).expect("create test package");
        fs::write(
            package.join("package.toml"),
            "capabilities = [\"fs\", \"out\"]\n",
        )
        .expect("write package capabilities");
        fs::write(
            package.join("main.nl"),
            r#"
fn main(env: Env) -> Result<(), IoError> {
    let fs = env.fs
    let out = env.out
    fs.write("text.txt", "hello")?
    fs.write("raw.bin", b"ab")?

    var text: Text max 8 bytes max 16 = Text.empty()
    fs.read("text.txt", text)?
    var bytes: Bytes max 8 = Bytes.empty()
    fs.read("raw.bin", bytes)?

    var entries: list<DirEntry, 8> = list {}
    fs.list(".", entries)?
    var values: list<long, 4> = list {}
    values.push(123L).unwrap()

    print(text)
    out.line(bytes)?
    print(str(values[0L] + entries.count()))
    ok(())
}
"#,
        )
        .expect("write heap-call program");
        if mode == "offset" {
            let counters = workspace.path().join("heap-counters.c");
            let probe = workspace.path().join("offset-runtime-probe.c");
            let binary = workspace.path().join("program");
            fs::write(&counters, HEAP_COUNTERS).expect("write allocation counter wrappers");
            fs::write(&probe, OFFSET_RUNTIME_PROBE).expect("write offset runtime probe");
            let mut build = Command::new("clang");
            build
                .args(["-O1", "-pthread", "-DNLC_STACK_MODE_OFFSET=1"])
                .arg(&probe)
                .arg(&runtime)
                .arg(&counters);
            for symbol in [
                "malloc",
                "calloc",
                "realloc",
                "strdup",
                "free",
                "nl_env_destroy",
            ] {
                build.arg(format!("-Wl,--wrap={symbol}"));
            }
            let built = build
                .arg("-o")
                .arg(&binary)
                .output()
                .expect("start clang for the offset runtime allocation probe");
            assert!(
                built.status.success(),
                "offset runtime probe failed to compile: {}",
                String::from_utf8_lossy(&built.stderr)
            );
            let output = Command::new(&binary)
                .current_dir(&package)
                .output()
                .expect("run offset runtime allocation probe");
            assert_eq!(
                output.status.code(),
                Some(0),
                "offset runtime probe failed: stdout={} stderr={}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
            assert_eq!(output.stdout, b"42\nruntime\n");
            let stderr = String::from_utf8_lossy(&output.stderr);
            let counts = stderr
                .lines()
                .find(|line| line.starts_with("heap_calls "))
                .unwrap_or_else(|| panic!("offset heap counters were not reported: {stderr}"));
            let (startup, operations) = counts
                .strip_prefix("heap_calls startup=")
                .and_then(|rest| rest.split_once(" operations="))
                .expect("heap report separates startup and operation counts");
            let startup_calls = startup
                .split(',')
                .map(|count| count.parse::<u64>().expect("numeric startup count"))
                .collect::<Vec<_>>();
            let operation_calls = operations
                .split(',')
                .map(|count| count.parse::<u64>().expect("numeric operation count"))
                .collect::<Vec<_>>();
            assert_eq!(startup_calls.len(), 5);
            assert_eq!(operation_calls, [0, 0, 0, 0, 0], "offset: {counts}");
            assert!(
                startup_calls[1] > 0,
                "startup allocations were not counted: {counts}"
            );
            assert!(
                stderr.trim_end() == counts,
                "unexpected runtime stderr: {stderr}"
            );
            continue;
        }
        let compiled = compile_package(&package)
            .unwrap_or_else(|error| panic!("{mode} package failed to compile: {error}"));
        let ir = workspace.path().join("module.ll");
        let counters = workspace.path().join("heap-counters.c");
        let binary = workspace.path().join("program");
        let mut llvm_ir = compiled.llvm_ir.clone();
        let main_start = llvm_ir
            .find("define i32 @main(")
            .expect("generated wrapper main exists");
        let main_end = llvm_ir[main_start..]
            .find("\n}\n")
            .map(|offset| main_start + offset)
            .expect("generated wrapper main closes");
        let entry_call = llvm_ir[main_start..main_end]
            .find("  call void @nl_fn_")
            .map(|offset| main_start + offset)
            .expect("generated wrapper calls the language main function");
        llvm_ir.insert_str(entry_call, "  call void @nl_heap_count_begin()\n");
        llvm_ir.insert_str(main_start, "declare void @nl_heap_count_begin()\n\n");
        fs::write(&ir, llvm_ir).expect("write generated LLVM IR");
        fs::write(&counters, HEAP_COUNTERS).expect("write allocation counter wrappers");

        let mut build = Command::new("clang");
        build
            .args(["-O1", "-pthread"])
            .arg(&ir)
            .arg(&runtime)
            .arg(&counters);
        if mode == "offset" {
            build.arg("-DNLC_STACK_MODE_OFFSET=1");
        }
        for symbol in [
            "malloc",
            "calloc",
            "realloc",
            "strdup",
            "free",
            "nl_env_destroy",
        ] {
            build.arg(format!("-Wl,--wrap={symbol}"));
        }
        let built = build
            .arg("-o")
            .arg(&binary)
            .output()
            .expect("start clang for the allocation-counted program");
        assert!(
            built.status.success(),
            "{mode} allocation-counted build failed: {}",
            String::from_utf8_lossy(&built.stderr)
        );

        let output = Command::new(&binary)
            .current_dir(&package)
            .output()
            .expect("run allocation-counted program");
        assert_eq!(
            output.status.code(),
            Some(0),
            "{mode} program failed: stdout={} stderr={}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(output.stdout, b"hello\nab\n127\n");
        let stderr = String::from_utf8_lossy(&output.stderr);
        let counts = stderr
            .lines()
            .find(|line| line.starts_with("heap_calls "))
            .unwrap_or_else(|| panic!("{mode} heap counters were not reported: {stderr}"));
        let (startup, operations) = counts
            .strip_prefix("heap_calls startup=")
            .and_then(|rest| rest.split_once(" operations="))
            .expect("heap report separates startup and operation counts");
        let startup_calls = startup
            .split(',')
            .map(|count| count.parse::<u64>().expect("numeric startup count"))
            .collect::<Vec<_>>();
        let operation_calls = operations
            .split(',')
            .map(|count| count.parse::<u64>().expect("numeric operation count"))
            .collect::<Vec<_>>();
        assert_eq!(startup_calls.len(), 5);
        assert_eq!(operation_calls, [0, 0, 0, 0, 0], "{mode}: {counts}");
        assert!(
            startup_calls[1] > 0,
            "startup allocations were not counted: {counts}"
        );
        assert!(
            stderr.trim_end() == counts,
            "unexpected runtime stderr: {stderr}"
        );
    }

    let workspace = TempWorkspace::new();
    let probe = workspace.path().join("tty-order-probe.c");
    let binary = workspace.path().join("tty-order-probe");
    fs::write(&probe, INTERLEAVED_TTY_OUTPUT_PROBE).expect("write terminal-order probe");
    let built = Command::new("clang")
        .args(["-O1", "-pthread"])
        .arg(&probe)
        .arg(&runtime)
        .arg("-lutil")
        .arg("-o")
        .arg(&binary)
        .output()
        .expect("start clang for the terminal-order probe");
    assert!(
        built.status.success(),
        "terminal-order probe failed to compile: {}",
        String::from_utf8_lossy(&built.stderr)
    );
    let output = Command::new(&binary)
        .output()
        .expect("run terminal-order probe");
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(output.stdout, b"stdout-beforestderr-middlestdout-after");
    assert!(output.stderr.is_empty());
}
