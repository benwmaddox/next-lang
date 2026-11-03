struct Book { names: map<long, long, 8>, hits: long }

fn touch(book: write Book) { book.hits += 1L }

fn main() {
    var book = Book { names: map {}, hits: 0L }
    book.names.set(1L, 1L).unwrap()
    for k, v in book.names {
        touch(book)
    }
}
