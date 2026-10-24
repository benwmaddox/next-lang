# Reply to review 16

All points are accepted. The section is rewritten, and its heading says it was corrected by review 16.

1. **Target dependence:**
   - LLVM's passes now "run the same, but their choices depend on the target" (TargetTransformInfo);
   - the 1.5–3× and 10–20% figures are gone;
   - gains from a target level are measured on named workloads, so the Validation intro now records the CPU and target level and reports baseline vs v3.
2. **Levels:** v3 is named as a bundle (AVX2, FMA, BMI1/2, MOVBE; Haswell 2013, and some newer low-end CPUs lack it); v4 is an AVX-512 subset.
3. **Platforms:** a target is OS + ABI + executable format + minimum OS + CPU features. The baselines per platform are listed: Android arm64-v8a is Armv8.0-A with Neon and FMA, Android x86-64 is at least v2, macOS arm64 is M1-class, and macOS ships two slices in a universal binary.
4. **`native`:** for local runs only. Shared or deployed builds name a target, and the resolved features, OS, ABI, compiler and flags go into cache keys and artifact identity.
5. **Safe start:** startup, the check, the dispatcher and the refusal message are baseline-only, and LTO is kept from moving newer instructions into them. Detection uses CPUID plus OSXSAVE/XGETBV on x86, and HWCAP on Linux/Android arm64. On mixed cores or VMs, only features every core has count.
6. **Multiversioning:** tested per format (PE, ELF, Mach-O), with a function-pointer dispatcher as fallback. The calling interface is stable, and each variant can be forced for tests.
7. **Profiles:** kept in the repository, keyed by source, compiler, flags, dependencies and workload; stale profiles are rejected. Gains are measured. BOLT is a later option for Linux servers.
8. **Floats:**
   - LLVM's guarantee is stated with its conditions;
   - contraction is off for exact code (Clang's default allows FMA);
   - reductions are ordered or not vectorized;
   - the floating-point environment is set at startup and restored after foreign calls;
   - there's no NaN-payload promise;
   - the text notes that results can match even when instructions differ.
9. **Math functions:** `sin`/`exp`/`pow` are exact only through the language's own implementations; the C library is allowed but outside the promise. Replays record the runtime identity. The Numbers bullet now says the same.

**Smaller:** the JIT comparison now lists loop lengths, alignment, branches and startup values. Guarded fast paths cover some of them, chosen by measurement, and "small, rare loss" is gone.
