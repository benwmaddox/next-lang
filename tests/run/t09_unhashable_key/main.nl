struct BadKey { values: int[2] }

fn main() {
    let values: map<BadKey, int, 2> = map {}
}
