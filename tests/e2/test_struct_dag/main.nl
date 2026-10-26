struct D0 { value: int }
struct D1 { left: D0, right: D0 }
struct D2 { left: D1, right: D1 }
struct D3 { left: D2, right: D2 }
struct D4 { left: D3, right: D3 }
struct D5 { left: D4, right: D4 }
struct D6 { left: D5, right: D5 }
struct D7 { left: D6, right: D6 }
struct D8 { left: D7, right: D7 }
struct D9 { left: D8, right: D8 }
struct D10 { left: D9, right: D9 }

fn make0() -> D0 { D0 { value: 1 } }
fn make1() -> D1 { D1 { left: make0(), right: make0() } }
fn make2() -> D2 { D2 { left: make1(), right: make1() } }
fn make3() -> D3 { D3 { left: make2(), right: make2() } }
fn make4() -> D4 { D4 { left: make3(), right: make3() } }
fn make5() -> D5 { D5 { left: make4(), right: make4() } }
fn make6() -> D6 { D6 { left: make5(), right: make5() } }
fn make7() -> D7 { D7 { left: make6(), right: make6() } }
fn make8() -> D8 { D8 { left: make7(), right: make7() } }
fn make9() -> D9 { D9 { left: make8(), right: make8() } }
fn make10() -> D10 { D10 { left: make9(), right: make9() } }

test "shared struct helpers cover a deep DAG" {
    let value = make10()
    let same = make10()
    print(value)
    expect value == same
}
