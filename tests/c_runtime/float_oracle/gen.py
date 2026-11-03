#!/usr/bin/env python3
"""Generates main.nl and expected.stdout for the float text oracle test.

Expected text comes from Python (repr / float() for double; an exact Fraction search for float), never from the
compiler. Run from the repository root:  python3 tests/c_runtime/float_oracle/gen.py
The format is JavaScript's Number-to-string: plain digits for 1e-6 <= |x| < 1e21, else 1.5e+21 / 1e-7; -0 is "0".
"""
import math
import random
import re
import struct
from decimal import Decimal, getcontext
from fractions import Fraction
from pathlib import Path

getcontext().prec = 4000
HERE = Path(__file__).resolve().parent


def layout(digits, k, negative):
    n = len(digits)
    if n <= k <= 21:
        body = digits + "0" * (k - n)
    elif 0 < k <= 21:
        body = digits[:k] + "." + digits[k:]
    elif -6 < k <= 0:
        body = "0." + "0" * (-k) + digits
    else:
        e = k - 1
        body = digits[0] + ("." + digits[1:] if n > 1 else "") + "e" + ("+" if e >= 0 else "-") + str(abs(e))
    return ("-" if negative else "") + body


def js_double(x):
    if x == 0:
        return "0"
    if math.isinf(x):
        return "Infinity" if x > 0 else "-Infinity"
    t = Decimal(repr(abs(x))).as_tuple()
    digits = "".join(map(str, t.digits)).rstrip("0") or "0"
    stripped = len(t.digits) - len(digits)
    return layout(digits, len(digits) + t.exponent + stripped, x < 0)


def f32_bits(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def f32_from_bits(b):
    return struct.unpack("<f", struct.pack("<I", b))[0]


def f64_bits(x):
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def f64_from_bits(b):
    return struct.unpack("<d", struct.pack("<Q", b))[0]


def shortest_exact(bits, from_bits):
    """Shortest digits, closest to the value, inside the rounding interval (exact Fractions)."""
    v = Fraction(from_bits(bits))
    top = from_bits(bits + 1)
    up = Fraction(top) if not math.isinf(top) else 2 * v - Fraction(from_bits(bits - 1))
    down = Fraction(from_bits(bits - 1)) if bits > 1 else Fraction(0)
    lo, hi = (v + down) / 2, (v + up) / 2
    inclusive = (bits & 1) == 0
    inside = (lambda c: lo <= c <= hi) if inclusive else (lambda c: lo < c < hi)
    k = 0
    while Fraction(10) ** k <= v:
        k += 1
    while Fraction(10) ** (k - 1) > v:
        k -= 1
    for n in range(1, 20):
        scale = Fraction(10) ** (k - n)
        base = math.floor(v / scale)
        best = None
        for c in (base, base + 1):
            cv = c * scale
            if inside(cv):
                dist = abs(cv - v)
                if best is None or dist < best[0] or (dist == best[0] and c % 2 == 0):
                    best = (dist, c)
        if best:
            c = best[1]
            kk = k + 1 if c == 10 ** n else k
            return str(c).rstrip("0") or "0", kk
    raise AssertionError


def js_float(x):
    if x == 0:
        return "0"
    d, k = shortest_exact(f32_bits(abs(x)), f32_from_bits)
    return layout(d, k, x < 0)


def literal(x):
    s = repr(x)
    if "e" in s:
        mant, exp = s.split("e")
        if "." not in mant:
            mant += ".0"
        return mant + "e" + ("+" if int(exp) >= 0 else "-") + str(abs(int(exp)))
    return s


rng = random.Random(20261103)
print_cases = []
SPECIAL = [0.0, 1.0, 0.5, 0.1, 0.2, 0.3, 0.1 + 0.2, 1.5, 100.0, 123456.789, 1e21, 1e20, 999999999999999900000.0,
           1e-6, 1e-7, 0.000001234, 9007199254740993.0, 9007199254740992.0, 5e-324, 1e-323, 2.2250738585072011e-308,
           2.2250738585072014e-308, 1.7976931348623157e308, 4.9406564584124654e-324, 1.2345678901234567e-300,
           123456789012345680000.0, 1.5e300, 4.35, 0.3 - 0.1, 5e-5, 1234.5e-9, 2.0 ** 53, 2.0 ** 63, 2.0 ** 64,
           2.0 ** 70, 2.0 ** -20, 8.41e21, 5.0e-324 * 3, 3.0e-310, 1.1e-308, 9.5367431640625e-7]
print_cases += SPECIAL + [-x for x in SPECIAL if x != 0.0] + [-0.0]
for k in range(-1074, 1024, 3):
    print_cases.append(math.ldexp(1.0, k))
for k in range(-323, 309):
    x = float("1e%d" % k)
    print_cases += [x, f64_from_bits(f64_bits(x) + 1), f64_from_bits(f64_bits(x) - 1)]
while len(print_cases) < 3300:
    b = rng.getrandbits(63)
    if (b >> 52) == 2047:
        continue
    x = f64_from_bits(b)
    print_cases.append(-x if rng.random() < 0.3 else x)
for _ in range(500):
    print_cases.append(round(rng.uniform(-1, 1) * 10 ** rng.randint(-8, 22), rng.randint(0, 9)))
# the longest outputs, to pin the 25-byte bound
print_cases += [-1.7976931348623157e308, -0.000001234567890123456, -0.0000012345678901234567]
assert max(len(js_double(x)) for x in print_cases) <= 25

float_cases = []
F_SPECIAL = [1.0, 0.1, 0.5, 3.4028234663852886e38, 1.401298464324817e-45, 1.1754943508222875e-38, 16777216.0,
             16777217.0, 1e-6, 1e-7, 1e21, 1e20, 0.3, 123456.789, 33554432.0, 8.5e-10, 7.0e22, 1e10]
for x in F_SPECIAL:
    float_cases += [f32_from_bits(f32_bits(x)), -f32_from_bits(f32_bits(x))]
for k in range(-149, 128, 2):
    float_cases.append(f32_from_bits(f32_bits(math.ldexp(1.0, k))))
while len(float_cases) < 700:
    b = rng.getrandbits(31)
    if (b >> 23) == 255:
        continue
    x = f32_from_bits(b)
    float_cases.append(-x if rng.random() < 0.3 else x)
assert max(len(js_float(x)) for x in float_cases) <= 22
# cross-check the exact search against repr on doubles
for x in rng.sample(print_cases, 200):
    if x != 0 and not math.isinf(x):
        d, k = shortest_exact(f64_bits(abs(x)), f64_from_bits)
        assert layout(d, k, x < 0) == js_double(x), x

VALID = re.compile(r"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$")


def js_parse(s):
    if s in ("Infinity", "+Infinity"):
        return "Infinity"
    if s == "-Infinity":
        return "-Infinity"
    if not VALID.match(s):
        return "none"
    return js_double(float(s))


def exact_decimal(fr):
    return format(Decimal(fr.numerator) / Decimal(fr.denominator), "f")


parse_cases = []
parse_cases += ["0", "1.5", "-2.25", "+7", "1e3", "1.5e-3", "123456.789", "0.1", ".5", "5.", "0.000001", "-0", "-0.0",
                "12345678901234.5", "1e15", "100000000000000000", "1E5", "00012", "1e+2", "1.0E-2", "2.2250738585072011e-308",
                "9007199254740993", "9007199254740992.5", "9007199254740991", "5e-324", "4.9406564584124654e-324",
                "2.4703282292062327e-324", "2.4703282292062328e-324", "2.4703282292062326e-324", "1e-324", "1e-400",
                "1.7976931348623157e308", "1.7976931348623158e308", "1.7976931348623159e308", "1.797693134862315807e308",
                "1e309", "1e310", "1e999", "1e99999999999999999999", "1e-99999999999999999999", "0e99999999999999999999",
                "Infinity", "-Infinity", "+Infinity", "0.0000000000000000000000000000000000001", "1e22", "1e23", "8.5e-6",
                "123456789012345678901234567890", "0.3", "2.5e-324"]
parse_cases += ["", "-", "+", ".", "e5", "1e", "1e+", "1e-", "1.2.3", "abc", "0x10", "1 ", " 1", "1_000", "--1", "1..2", "inf",
                "nan", "NaN", "infinity", "Inf", "1e5.5", "1,5", "-.", ".e1", "1ee1", "+-1", "Infinit", "Infinityx"]
for _ in range(36):  # exact halfway points between neighbouring doubles, and a hair either side
    b = rng.getrandbits(63)
    if (b >> 52) >= 2046:
        continue
    lo, hi = Fraction(f64_from_bits(b)), Fraction(f64_from_bits(b + 1))
    mid = exact_decimal((lo + hi) / 2)
    parse_cases.append(mid)
    d = Decimal(mid)
    tiny = Decimal(1).scaleb(d.adjusted() - 790)
    parse_cases.append(format(d + tiny, "f"))
    parse_cases.append(format(d - tiny, "f"))
for b in (0, 1, 2, 4503599627370495, 4503599627370496, 0x7FEFFFFFFFFFFFFE):  # subnormal and largest halfways
    lo, hi = Fraction(f64_from_bits(b)), Fraction(f64_from_bits(b + 1))
    d = Decimal(exact_decimal((lo + hi) / 2))
    tiny = Decimal(1).scaleb(d.adjusted() - 790)
    parse_cases += [format(d, "f"), format(d + tiny, "f"), format(d - tiny, "f")]
for _ in range(500):  # short and medium decimals
    digits = "".join(rng.choice("0123456789") for _ in range(rng.randint(1, 40)))
    point = rng.randint(0, len(digits))
    s = digits[:point] + ("." if rng.random() < 0.8 else "") + digits[point:]
    if s in ("", "."):
        continue
    if rng.random() < 0.5:
        s += rng.choice("eE") + rng.choice(["", "+", "-"]) + str(rng.randint(0, 340))
    if rng.random() < 0.2:
        s = rng.choice("+-") + s
    parse_cases.append(s)
for _ in range(60):  # hundreds of digits
    digits = "".join(rng.choice("0123456789") for _ in range(rng.randint(100, 900)))
    parse_cases.append(digits[: rng.randint(1, 100)] + "." + digits[100:] + ("e" + str(rng.randint(-1200, 100)) if rng.random() < 0.5 else ""))
for _ in range(120):  # shortest texts of random doubles, which must read back exactly
    x = f64_from_bits(rng.getrandbits(63) & 0x7FEFFFFFFFFFFFFF)
    parse_cases.append(repr(x))
parse_cases.append("0." + "0" * 600 + "1" + "0" * 100 + "1")
parse_cases.append("1" + "0" * 400 + "e-400")
parse_cases.append("0" * 500 + "1")
assert max(len(s) for s in parse_cases) <= 1300

out = ["// Generated by gen.py: print(double), print(float), interpolation, and parse_double against Python's answers.", ""]
out.append("fn p(x: double) {\n    print(x)\n    let text = str(x)\n    match text.parse_double() {\n        some(v) => { if v != x && x != 0.0 { print(\"ROUNDTRIP FAILED\") } }\n        none => print(\"ROUNDTRIP NONE\"),\n    }\n}")
out.append("fn pf(x: float) {\n    print(x)\n}")
out.append("fn q(text: Ascii max 1300) {\n    match text.parse_double() {\n        some(v) => print(v),\n        none => print(\"none\"),\n    }\n}")
expected = []
calls = []


def chunk(name, lines):
    out.append("fn %s() {\n%s\n}" % (name, "\n".join("    " + l for l in lines)))


def add(prefix, items, make, shown):
    for i in range(0, len(items), 100):
        name = "%s%d" % (prefix, i // 100)
        chunk(name, [make(x) for x in items[i:i + 100]])
        calls.append(name)
    expected.extend(shown(x) for x in items)


add("pd", print_cases, lambda x: "p(%s)" % literal(x), js_double)
add("pg", float_cases, lambda x: "pf(%s)" % literal(x), js_float)
add("pp", parse_cases, lambda s: 'q("%s")' % s, js_parse)
out.append("fn main() {\n%s\n    let a: double = 0.1 + 0.2\n    let b: float = 0.1\n    print($\"a={a} b={b} sum={a + 1.0}\")\n}" % "\n".join("    %s()" % c for c in calls))
expected.append("a=0.30000000000000004 b=0.1 sum=1.3")
(HERE / "main.nl").write_text("\n".join(out) + "\n")
(HERE / "expected.stdout").write_text("\n".join(expected) + "\n")
(HERE / "package.toml").write_text('capabilities = ["out"]\n')
print(len(print_cases), len(float_cases), len(parse_cases))
