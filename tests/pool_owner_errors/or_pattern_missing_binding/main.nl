enum Op { Add(int), Sub(int), Nop }

fn main() {
    let op = Op.Add(1)
    let v = match op {
        Add(x) | Nop => 1
        Sub(_) => 2
    }
    print(v)
}
