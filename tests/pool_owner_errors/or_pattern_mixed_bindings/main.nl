enum Op { Add(int), Sub(long) }

fn main() {
    let op = Op.Add(1)
    let v = match op {
        Add(x) | Sub(x) => 1
    }
    print(v)
}
