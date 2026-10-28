// A continue from an if block that holds an 8 KB region local, in a loop
// body with no region slots of its own. The jump must release the if block's
// reservation, or the data-stack top climbs by 8 KB every iteration.
fn main() {
    var total = 0L
    for i in 0L..2000000L {
        if i % 2L == 0L {
            var big: list<long, 1000> = list{}
            big.push(i).unwrap()
            total += big.count() + big[0L]
            continue
        }
        total += 1L
    }
    print(total)
}
