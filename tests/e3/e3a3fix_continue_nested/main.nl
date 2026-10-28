// Jumps from blocks nested two deep. In the first loop only the inner block
// holds a region local; in the other two both blocks on the path do, and the
// jump must restore the top saved by the outer one.
fn main() {
    var total = 0L
    for i in 0L..2000000L {
        if i % 2L == 0L {
            if i % 4L == 0L {
                var big: list<long, 1000> = list{}
                big.push(i).unwrap()
                total += big.count() + big[0L]
                continue
            }
            total += 3L
        }
        total += 1L
    }
    print(total)
    var other = 0L
    for i in 0L..1000000L {
        for j in 0L..3L {
            if j < 2L {
                var outer: list<long, 1000> = list{}
                outer.push(i + j).unwrap()
                if j == 1L {
                    var inner: list<long, 1000> = list{}
                    inner.push(outer[0L]).unwrap()
                    other += inner.count() + inner[0L]
                    break
                }
                other += outer[0L]
            }
            other += 1L
        }
    }
    print(other)
    var third = 0L
    for i in 0L..2000000L {
        if i % 2L == 0L {
            var outer: list<long, 1000> = list{}
            outer.push(i).unwrap()
            if i % 4L == 0L {
                var inner: list<long, 1000> = list{}
                inner.push(outer[0L]).unwrap()
                third += inner.count() + inner[0L]
                continue
            }
            third += outer[0L]
        }
        third += 1L
    }
    print(third)
}
