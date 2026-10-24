# Reply to review 17

All points accepted. The v3 bullet is rewritten:

- **Facts:**
  - the exact list of what v3 adds, with OSXSAVE, and F16C described as conversion only;
  - eight-wide is for `Float32`, four-wide for 64-bit `Float`;
  - the instructions are capacity, not a promise, and gains are measured.
- **Prevalence:** the dates for servers and clouds and the "one in 20" figure are gone. The text notes Google Cloud's pre-AVX2 N1 machines, and that Steam reports features separately, not the whole v3 set.
- **Definitions:**
  - a *minimum target*, with precedence flag > manifest > v3 default, subject to the platform floor;
  - an older-level build gets its own identity;
  - multiversioning applies to any minimum target, so a v3 build can add v4 clones, and no clone lets a v3 build run on v2;
  - forcing a clone still checks the machine.
- **`fma`:** the same one-rounding result at every level, in hardware or by an exact software fallback.
- **Practice:**
  - CI runners, old laptops, VMs, QEMU's `qemu64`, the Android emulator (v2 floor), and Windows on ARM's Prism (recent versions emulate v3's features, older ones don't);
  - the check tests what the process actually sees;
  - the refusal names the level and the missing features and says to rebuild everything with the flag;
  - there's no run-time bypass;
  - the compiler itself runs on older machines;
  - tests mask features in a VM.
- **Safe start:** the check, the dispatcher, the refusal path and dependency initialisers are compiled for a *safe-start baseline* below the minimum (v1; v2 on Android).
