type Slot = long 0..=512
type Small = int 0..10
type Alias = Slot

fn main() {
    let p: long = 300L
    let q: int = 9
    let a: long = (Slot)(p)
    let b: int = (Small)(q)
    let c: long = (Alias)(512L)
    print(a + c)
    print(b)
}
