struct Tag {
    id: int
    name: Ascii max 6
}
fn main() {
    var tags: list<Tag, 3> = list {}
    discard tags.push(Tag { id: 1, name: "aa" })
    discard tags.push(Tag { id: 2, name: "bbbb" })
    tags[0L].id = 9
    tags[1L].name = "cc"
    print(tags[0L].id)
    print(tags[1L].name.len())
    let copy = tags[1L]
    print(copy.name.len() + (long)copy.id)
    var total: long = 0L
    for t in tags { total += t.name.len() + (long)t.id }
    print(total)
}
