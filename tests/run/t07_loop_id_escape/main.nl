struct Rock { value: int }

fn main() {
    var stable: pool<Rock, 1> = pool {}
    var saved = stable.add(Rock { value: 0 }).unwrap()
    for iteration in 0..2 {
        var each_time: pool<Rock, 1> = pool {}
        let fresh = each_time.add(Rock { value: iteration }).unwrap()
        saved = fresh
    }
}
