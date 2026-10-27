// The same jumps from a while loop: a continue from an if block and a break
// from an inner while loop, each holding an 8 KB region local.
fn main() {
    var total = 0L
    var i = 0L
    while i < 2000000L {
        i += 1L
        if i % 2L == 0L {
            var big: list<long, 1000> = list{}
            big.push(i).unwrap()
            total += big.count() + big[0L]
            continue
        }
        total += 1L
    }
    print(total)
    var other = 0L
    var outer = 0L
    while outer < 1000000L {
        outer += 1L
        var inner = 0L
        while inner < 4L {
            inner += 1L
            if inner == 2L {
                var big: list<long, 1000> = list{}
                big.push(outer).unwrap()
                other += big.count() + big[0L]
                break
            }
            other += inner
        }
    }
    print(other)
}
