enum Shape { Circle(int), Empty }
fn main() {
    let shape = Shape.Circle(2)
    print(match shape { Circle => 0, Empty => 1 })
}
