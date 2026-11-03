struct Node { v: long }
struct Label { text: Ascii max 8 }

struct World {
    nodes: pool<Node, 8>
    labels: pool<Label, 8>
    label_of: map<Id<nodes>, Id<labels>, 8>
    children: map<Id<nodes>, list<Id<nodes>, 4>, 8>
    by_name: map<Ascii max 8, Id<nodes>, 8>
}

fn link(world: write World, n: Id<nodes>, l: Id<labels>) {
    world.label_of.set(n, l).unwrap()
}

fn label_text(world: World, n: Id<nodes>) -> Ascii max 8 {
    match world.label_of.get(n) {
        some(l) => world.labels[l].text,
        none => "-",
    }
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {}, label_of: map {}, children: map {}, by_name: map {} }
    let root = world.nodes.add(Node { v: 1 }).unwrap()
    let kid = world.nodes.add(Node { v: 2 }).unwrap()
    let other = world.nodes.add(Node { v: 3 }).unwrap()
    let red = world.labels.add(Label { text: "red" }).unwrap()
    let blue = world.labels.add(Label { text: "blue" }).unwrap()
    link(world, root, red)
    link(world, kid, blue)
    print(label_text(world, root))
    print(label_text(world, kid))
    print(label_text(world, other))
    print(world.label_of.contains(kid))
    print(world.label_of.contains(other))

    var kids: list<Id<nodes>, 4> = list {}
    kids.push(kid).unwrap()
    kids.push(other).unwrap()
    world.children.set(root, kids).unwrap()
    match world.children.get(root) {
        some(list) => {
            for c in list { print(world.nodes[c].v) }
        },
        none => print(-1L),
    }
    world.by_name.set("root", root).unwrap()
    match world.by_name.get("root") { some(n) => print(world.nodes[n].v), none => print(-1L) }
    match world.label_of.remove(root) { some(l) => print(world.labels[l].text), none => print("none") }
    print(world.label_of.count())

    // a local map keyed by ids
    var seen: map<Id<nodes>, long, 8> = map {}
    seen.set(kid, 5L).unwrap()
    print(seen.get(kid) ?? -1L)
    print(seen.get(other) ?? -1L)
}
