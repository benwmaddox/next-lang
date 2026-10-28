// Jumps out of blocks used as values: a continue from a match arm and a
// break from an if expression, each holding an 8 KB region local.
enum Shape { Small, Large }
fn main() {
    var total = 0L
    for i in 0L..2000000L {
        let shape = if i % 2L == 0L { Shape.Small } else { Shape.Large }
        total += match shape {
            Shape.Small => {
                var other: list<long, 1000> = list{}
                other.push(i).unwrap()
                total += other.count() + other[0L]
                continue
            }
            Shape.Large => 2L
        }
        let extra = if i % 3L == 0L {
            var big: list<long, 1000> = list{}
            big.push(i).unwrap()
            if big[0L] == 1999998L { break }
            big[0L]
        } else { 1L }
        total += extra
    }
    print(total)
}
