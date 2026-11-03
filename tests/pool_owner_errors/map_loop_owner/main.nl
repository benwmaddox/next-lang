struct Node { v: long }
struct Label { text: Ascii max 8 }

struct World {
    nodes: pool<Node, 8>
    labels: pool<Label, 8>
    label_of: map<Id<nodes>, Id<labels>, 8>
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {}, label_of: map {} }
    for n, l in world.label_of {
        print(world.labels[n].text)
    }
}
