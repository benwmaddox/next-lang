const PROGRAM: Ascii max 16 = "+-+-"

fn main() {
    var total: long = 0L
    for i in 0L..3L {
        let local: Ascii max 16 = PROGRAM
        total += local.len() + i
    }
    print(total)
}
