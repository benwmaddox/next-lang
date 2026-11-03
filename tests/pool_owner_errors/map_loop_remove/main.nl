struct Book { names: map<long, long, 8>, hits: long }

fn main() {
    var book = Book { names: map {}, hits: 0L }
    book.names.set(1L, 1L).unwrap()
    for k in book.names {
        book.hits += 1L
        book.names.remove(k); ()
    }
}
