fn steps(start: i64) -> i64 {
    let mut n = start;
    let mut count = 0i64;
    while n != 1 {
        if n % 2 == 0 {
            n /= 2;
        } else {
            n = 3 * n + 1;
        }
        count += 1;
    }
    count
}

fn main() {
    let mut total = 0i64;
    let mut longest = 0i64;
    let mut best = 0i64;
    for start in 1..3000000i64 {
        let s = steps(start);
        total += s;
        if s > longest {
            longest = s;
            best = start;
        }
    }
    println!("{}", total);
    println!("{}", best);
    println!("{}", longest);
}
