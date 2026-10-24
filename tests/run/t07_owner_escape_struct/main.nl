struct Rock { value: int }
struct Holder<P> { id: Option<Id<P>> }

fn insert_ephemeral<P>(target: write Holder<P>) {
    var local: pool<Rock, 1> = pool {}
    target.id = some(local.add(Rock { value: 1 }).unwrap())
}

fn main() {
    var rocks: pool<Rock, 1> = pool {}
    var holder: Holder<rocks> = Holder { id: none }
    insert_ephemeral(holder)
    insert_ephemeral(holder)
}
