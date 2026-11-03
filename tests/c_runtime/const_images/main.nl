struct Point { x: long, y: long }
struct Label { name: Ascii max 8, shown: bool, level: int }
struct Config { origin: Point, label: Label, scale: byte, ids: long[3] }

const ORIGIN: Point = Point { x: 3, y: -4 }
const LABEL: Label = Label { name: "hello", shown: true, level: 7 }
const CONFIG: Config = Config { origin: Point { x: 1, y: 2 }, label: Label { name: "cfg", shown: false, level: 2 }, scale: 9, ids: [10, 20, 30] }
const FLAGS: bool[3] = [true, false, true]
const GRID: long[2][2] = [[1, 2], [3, 4]]
const NO_LIST: list<long, 4> = list {}
const NO_MAP: map<Ascii max 8, long, 4> = map {}
const POINTS: Point[2] = [Point { x: 5, y: 6 }, Point { x: 7, y: 8 }]

fn shift(p: Point) -> Point { Point { x: p.x + 1, y: p.y + 1 } }

fn main() {
    print(ORIGIN.x + ORIGIN.y)
    let moved = shift(ORIGIN)
    print(moved.x)
    print(LABEL.name)
    print(LABEL.shown)
    print(LABEL.level)
    print(CONFIG.origin.y)
    print(CONFIG.label.name)
    print(CONFIG.scale)
    print(CONFIG.ids[2])
    print(FLAGS[0])
    print(FLAGS[1])
    print(GRID[1][0])
    var list_copy = NO_LIST
    list_copy.push(5L).unwrap()
    print(list_copy.count())
    print(NO_LIST.count())
    var map_copy = NO_MAP
    map_copy.set("k", 2L).unwrap()
    print(map_copy.get("k") ?? -1L)
    print(NO_MAP.count())
    print(POINTS[1].y)
    var edited = ORIGIN
    edited.x = 100
    print(edited.x)
    print(ORIGIN.x)
}
