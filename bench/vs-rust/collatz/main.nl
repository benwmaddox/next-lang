fn steps(start: long) -> long {
    var n = start
    var count = 0L
    for _guard: long in 0L..100000L {
        if n == 1L {
            break
        }
        if n % 2L == 0L {
            n = n / 2L
        } else {
            n = 3L * n + 1L
        }
        count += 1L
    }
    count
}

fn main() {
    var total = 0L
    var longest = 0L
    var best = 0L
    for start: long in 1L..3000000L {
        let s = steps(start)
        total += s
        if s > longest {
            longest = s
            best = start
        }
    }
    print(total)
    print(best)
    print(longest)
}
