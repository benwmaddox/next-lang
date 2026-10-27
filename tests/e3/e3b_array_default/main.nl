fn default_seed() -> long { print(1); 7L }
struct Cell { value: long = default_seed() }
fn main() {
    var cells: Cell[2]
    print(cells)
}
