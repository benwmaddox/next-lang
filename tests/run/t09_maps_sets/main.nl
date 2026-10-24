struct Key { left: int, flag: bool }
struct PairKey { key: Key, sequence: int }
struct Value { score: int }
struct Rock { score: int }
enum Color { Red, Green, Blue }
enum TaggedKey { Empty, Has(Key) }

fn make_map() -> map<int, int, 4> {
    var items: map<int, int, 4> = map {}
    items.set(1, 10).unwrap()
    items.set(5, 50).unwrap()
    items
}
const BUILT: map<int, int, 4> = make_map()
const BUILT_VALUE: Option<int> = BUILT.get(5)

fn main() {
    var collisions: map<int, int, 4> = map {}
    collisions.set(1, 10).unwrap()
    collisions.set(5, 50).unwrap()
    collisions.set(9, 90).unwrap()
    collisions.set(13, 130).unwrap()
    print(collisions)
    collisions.set(5, 55).unwrap()
    print(collisions)
    print(collisions.remove(5))
    print(collisions.contains(9))
    print(collisions.contains(13))
    print(collisions.contains(5))
    collisions.set(5, 56).unwrap()
    print(collisions)
    print(collisions == collisions)

    let update_full = collisions.set(9, 99)
    let new_full = collisions.set(17, 170)
    print(update_full.is_ok())
    print(new_full.is_err())
    print(collisions)

    collisions.remove(1)
    collisions.remove(9)
    collisions.remove(13)
    collisions.remove(5)
    print(collisions.contains(21))
    collisions.set(21, 210).unwrap()
    print(collisions)

    var left: map<int, int, 4> = map {}
    var right: map<int, int, 4> = map {}
    left.set(1, 10).unwrap()
    left.set(5, 50).unwrap()
    right.set(5, 50).unwrap()
    right.set(1, 10).unwrap()
    print(left == right)
    right.set(5, 51).unwrap()
    print(left == right)

    print(BUILT)
    print(BUILT_VALUE)
    print(BUILT == make_map())

    var keys: map<Key, int, 2> = map {}
    keys.set(Key { left: 4, flag: true }, 40).unwrap()
    print(keys.get(Key { left: 4, flag: true }))
    var nested_keys: map<PairKey, int, 2> = map {}
    let first_pair = PairKey { key: Key { left: 7, flag: false }, sequence: 2 }
    let second_pair = PairKey { key: Key { left: 9, flag: false }, sequence: 2 }
    let third_pair = PairKey { key: Key { left: 11, flag: false }, sequence: 2 }
    nested_keys.set(first_pair, 72).unwrap()
    nested_keys.set(second_pair, 82).unwrap()
    nested_keys.remove(first_pair)
    nested_keys.set(third_pair, 92).unwrap()
    print(nested_keys)
    print(nested_keys.get(second_pair))
    var tagged: map<TaggedKey, int, 2> = map {}
    tagged.set(TaggedKey.Has(Key { left: 8, flag: true }), 80).unwrap()
    print(tagged.get(TaggedKey.Has(Key { left: 8, flag: true })))

    var rocks: pool<Rock, 2> = pool {}
    let rock_id: rocks.Id = rocks.add(Rock { score: 7 }).unwrap()
    var by_id: map<rocks.Id, int, 2> = map {}
    by_id.set(rock_id, 77).unwrap()
    print(by_id.contains(rock_id))
    print(by_id.get(rock_id))
    rocks.remove(rock_id)
    let next_rock_id: rocks.Id = rocks.add(Rock { score: 8 }).unwrap()
    by_id.set(next_rock_id, 88).unwrap()
    print(by_id.count())
    print(by_id.get(rock_id))
    print(by_id.get(next_rock_id))

    var values: map<int, Value, 2> = map {}
    values.set(1, Value { score: 8 }).unwrap()
    values.set(2, Value { score: 9 }).unwrap()
    for value, key in values { value.score += key }
    print(values)
    print(values == values)

    var members: set<int, 4> = set {}
    members.add(1).unwrap()
    members.add(5).unwrap()
    members.add(9).unwrap()
    members.add(13).unwrap()
    members.add(5).unwrap()
    print(members)
    print(members.remove(1))
    print(members.contains(13))
    members.add(1).unwrap()
    print(members)
    var reversed: set<int, 4> = set {}
    reversed.add(13).unwrap()
    reversed.add(9).unwrap()
    reversed.add(5).unwrap()
    reversed.add(1).unwrap()
    print(members == reversed)
    print(members.count())
    for key in members { print(key) }

    var full_set: set<int, 2> = set {}
    full_set.add(2).unwrap()
    full_set.add(6).unwrap()
    print(full_set.add(10).is_err())
    print(full_set.add(2).is_ok())
    print(full_set)
    full_set.remove(2)
    full_set.remove(6)
    print(full_set.contains(14))
    full_set.add(14).unwrap()
    print(full_set)

    var struct_set: set<Key, 2> = set {}
    struct_set.add(Key { left: 3, flag: false }).unwrap()
    print(struct_set.contains(Key { left: 3, flag: false }))
    print(struct_set == struct_set)
    var colors: map<Color, int, 2> = map {}
    colors.set(Color.Green, 2).unwrap()
    print(colors.get(Color.Green))
    var flags: map<bool, int, 2> = map {}
    flags.set(true, 1).unwrap()
    flags.set(false, 0).unwrap()
    print(flags.get(false))
    var wide_keys: map<long, int, 2> = map {}
    wide_keys.set(-5L, 6).unwrap()
    wide_keys.set(5000000000L, 7).unwrap()
    print(wide_keys)
    print(wide_keys.contains(-5L))
    print(wide_keys.get(5000000000L))
    print(wide_keys.get(-5L))

    var proven_map: map<int, int, 1> = map {}
    proven_map.set(3, 30)
    print(proven_map)
    var proven_set: set<int, 1> = set {}
    proven_set.add(3)
    print(proven_set)
    var zero_map: map<int, int, 0> = map {}
    discard zero_map.set(3, 30)
    print(zero_map.count())
}
