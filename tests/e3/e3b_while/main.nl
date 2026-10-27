struct Scratch {
    words: long[513],
}

fn main() {
    var index: int = 0
    var total: long = 0L
    while index < 10 {
        let scratch = Scratch { words: fill(index.to_long()) }
        total += scratch.words[512L]
        index += 1
        if index == 2 { continue }
        if index == 6 { break }
    }
    print(total)
    print(index)
}
