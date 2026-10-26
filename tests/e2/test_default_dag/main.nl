struct V0 { value: int = 1 }
struct V1 { left: V0 = V0 {}, right: V0 = V0 {} }
struct V2 { left: V1 = V1 {}, right: V1 = V1 {} }
struct V3 { left: V2 = V2 {}, right: V2 = V2 {} }
struct V4 { left: V3 = V3 {}, right: V3 = V3 {} }
struct V5 { left: V4 = V4 {}, right: V4 = V4 {} }
struct V6 { left: V5 = V5 {}, right: V5 = V5 {} }
struct V7 { left: V6 = V6 {}, right: V6 = V6 {} }
struct V8 { left: V7 = V7 {}, right: V7 = V7 {} }
struct V9 { left: V8 = V8 {}, right: V8 = V8 {} }
struct V10 { left: V9 = V9 {}, right: V9 = V9 {} }

test "default helpers cover a deep DAG" {
    let value = V10 {}
    let same = V10 {}
    print(value)
    expect value == same
}
