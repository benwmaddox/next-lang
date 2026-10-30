// spawn starts a function on its own thread with copies of its arguments; the program waits for every job.
fn count(label: int, steps: long) {
    var total = 0L
    for step in 0L..steps {
        total += step
    }
    print(total + label.to_long())
}

fn main() {
    spawn count(1, 1000L)
    spawn count(2, 2000L)
    spawn count(3, 3000L)
    print(0L)
}
