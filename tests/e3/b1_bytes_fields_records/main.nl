struct Record {
    id: int,
    name: Bytes max 4096,
    key: Bytes max 3,
    payload: Bytes max 17,
    score: long,
    active: bool,
}

fn first_list_name_byte(values: list<Record, 4>, index: long) -> byte {
    values[index].name[0L]
}

fn last_list_name_byte(values: list<Record, 4>, index: long) -> byte {
    values[index].name[4095L]
}

fn first_array_name_byte(values: Record[2], index: long) -> byte {
    values[index].name[0L]
}

fn first_record_name_byte(value: Record) -> byte {
    value.name[0L]
}

fn replace_list_name(values: write list<Record, 4>, index: long, value: Bytes max 4096) {
    values[index].name = value
}

fn check_after_move(values: list<Record, 4>) {
    let scratch: list<bool, 300000> = list {}
    print(values[3L].name.len())
    print(first_list_name_byte(values, 3L))
    print(last_list_name_byte(values, 3L))
    var copied: list<Record, 4> = values
    print(copied[3L] == values[3L])
    print(copied[3L].name == values[3L].name)
    copied[3L].name = b"changed"
    print(copied[3L] == values[3L])
    print(copied[3L].name == values[3L].name)
    print(copied[3L].name[6L])
}

fn main() {
    let longest: Bytes max 4096 = b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    let short_name: Bytes max 4096 = b"short"
    let template = Record {
        id: 8,
        name: b"array",
        key: b"arr",
        payload: b"array-data",
        score: 80L,
        active: true,
    }
    let array: Record[2] = fill(template)
    print(first_array_name_byte(array, 1L))
    print(array[1L].name[4L])
    print(array[0L].name == array[1L].name)

    var records: list<Record, 4> = [
        Record { id: 1, name: b"", key: b"a", payload: b"empty", score: 10L, active: true },
        Record { id: 2, name: b"short", key: b"xyz", payload: b"1234567890abcdefg", score: 20L, active: false },
        Record { id: 3, name: b"shifted", key: b"xy", payload: b"payload-3", score: 30L, active: true },
    ]
    print(records.count())
    print(records[0L].name.len())
    print(records[1L].name.len())
    print(first_list_name_byte(records, 1L))
    print(first_record_name_byte(records[1L]))
    print(records[1L].name == short_name)
    print(records[1L].name == records[2L].name)
    print(records[1L].key[2L])
    print(records[1L].payload.len())
    print(records[1L].payload[16L])
    print(records[1L].id)
    print(records[1L].score)
    print(records[1L])
    print(records)

    var element_copy: Record = records[1L]
    print(element_copy == records[1L])
    element_copy.name = b"copy"
    print(element_copy == records[1L])
    print(element_copy.name == b"copy")
    print(records[1L].name == short_name)

    var list_copy: list<Record, 4> = records
    print(list_copy == records)
    list_copy[2L].name = b"copy"
    print(list_copy == records)
    print(list_copy[2L].name == b"copy")
    print(records[2L].name == b"shifted")
    replace_list_name(records, 2L, b"function")
    print(records[2L].name == b"function")
    records[2L].name = b"Xunction"
    print(first_list_name_byte(records, 2L))
    records = records
    print(records[2L].name == b"Xunction")

    for item, index in records {
        print(index)
        print(item.id)
        print(item.name.len())
        if item.name.len() > 0L { print(item.name[0L]) }
    }
    print(records)

    print(records.push(Record { id: 4, name: longest, key: b"max", payload: b"max-payload", score: 40L, active: false }))
    print(records.count())
    print(records[3L].name.len())
    print(first_list_name_byte(records, 3L))
    print(last_list_name_byte(records, 3L))
    print(records[3L].name == longest)
    print(records[3L].key.len())
    print(records[3L].payload[3L])
    check_after_move(records)

    print(records.remove(1L))
    print(records.count())
    print(records[1L].name == b"Xunction")
    print(last_list_name_byte(records, 2L))
    print(records.insert(1L, Record { id: 5, name: b"insert", key: b"ins", payload: b"insert-data", score: 50L, active: true }))
    print(records.count())
    print(records[1L])
    print(records[3L].name[4095L])
    var removed_max: Record = records.remove(3L)
    print(removed_max.name.len())
    print(removed_max.name[4095L])
    print(records.count())
    print(records)
    match records.pop() {
        some(value) => {
            print(value.id)
            print(value.name.len())
            print(value.name[0L])
        },
        none => print(-1L),
    }
    print(records.count())
    print(records)

    records.clear()
    print(records.count())
    print(records)
    match records.pop() {
        some(value) => print(value.name.len()),
        none => print(0L),
    }
    print(records.count())
    discard records.push(Record { id: 6, name: b"refilled", key: b"ref", payload: b"refill-data", score: 60L, active: true })
    discard records.push(Record { id: 7, name: b"again", key: b"two", payload: b"again-data", score: 70L, active: false })
    print(records.count())
    print(records[1L].name == b"again")
    print(records)

    var empty: list<Record, 0> = list {}
    let empty_copy: list<Record, 0> = empty
    print(empty.count())
    print(empty_copy.count())
}
