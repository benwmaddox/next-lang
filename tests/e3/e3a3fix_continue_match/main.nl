// A continue from a match arm that holds an 8 KB region local, in a loop
// body with no region slots of its own.
enum Shape { Small, Large }

fn main() {
    var total = 0L
    for i in 0L..2000000L {
        let shape = if i % 2L == 0L { Shape.Small } else { Shape.Large }
        match shape {
            Shape.Small => {
                var other: list<long, 1000> = list{}
                other.push(i).unwrap()
                total += other.count() + other[0L]
                continue
            }
            Shape.Large => {
                total += 2L
            }
        }
        total += 1L
    }
    print(total)
}
