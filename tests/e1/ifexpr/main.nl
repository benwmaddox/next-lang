fn choose(flag: bool) -> int {
    if flag { 1 } else { 2 }
}

fn main() {
    let first = if true { 7 } else { 9 }
    print(first)
    print(choose(false))
    let second = if false { print(99); 3 } else { print(4); 5 }
    print(second)
}
