// Text fields in rows: well-formed UTF-8 within the field's limits is delivered with its code points counted; anything else
// leaves the field empty.
struct Word {
    id: long = 0L
    word: Text max 6 = Text.empty()
}

struct Wanted {
    word: Text max 6
}

fn main(env: Env) {
    var words: list<Word, 8> = list {}
    discard env.db_rows("from words order by id limit 8", 0L, words)
    for index in 0L..words.count() {
        let w = words[index]
        print($"{w.id}: {w.word.len()} {w.word.byte_len()} [{w.word}]")
    }
    var one = Word {}
    let wanted = Wanted { word: Text.empty() }
    discard wanted
    print(env.db_row("from words where id = ?1", 2L, one))
    print($"{one.word}")
}
