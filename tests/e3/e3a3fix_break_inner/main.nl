// A break out of an inner loop from an if block that holds an 8 KB region
// local. Neither loop body has region slots of its own.
fn main() {
    var total = 0L
    for outer in 0L..2000000L {
        for inner in 0L..4L {
            if inner == 1L {
                var big: list<long, 1000> = list{}
                big.push(outer).unwrap()
                total += big.count() + big[0L]
                break
            }
            total += inner
        }
    }
    print(total)
}
