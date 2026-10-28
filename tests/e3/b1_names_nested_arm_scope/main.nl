fn main() {
    match some(1) {
        some(v) => {
            match some(2) {
                some(inner) => print(inner),
                none => (),
            }
            let inner = 3
            print(inner)
        },
        none => (),
    }

    let absent: Option<int> = none
    match absent {
        some(other) => (),
        none => {
            let inner = 4
            print(inner)
        },
    }
}
