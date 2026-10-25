struct Fields {
    ascii: Ascii max 8
    text: Text max 8
    bytes: Bytes max 8
}

struct Nested { fields: Fields, count: int }

enum Payload {
    Stored(Nested),
    Raw(Ascii max 8, Text max 8, Bytes max 8),
    Empty
}

const CONSTANT: Nested = Nested {
    fields: Fields { ascii: "const", text: "hé😀", bytes: b"cbytes" },
    count: 7
}

const CONSTANT_OPTION: Option<Fields> = some(Fields {
    ascii: "option", text: "text", bytes: b"bytes"
})
const CONSTANT_ENUM: Payload = Payload.Raw("constant", "enum", b"case")
const CONSTANT_RESULT: Result<Nested, Fields> = err(Fields {
    ascii: "error", text: "constant", bytes: b"err"
})

global CURRENT: Nested = Nested {
    fields: Fields { ascii: "global", text: "世界", bytes: b"global" },
    count: 9
}
global CURRENT_OPTION: Option<Fields> = some(Fields {
    ascii: "global", text: "option", bytes: b"global"
})
global CURRENT_RESULT: Result<Nested, Fields> = err(Fields {
    ascii: "global", text: "error", bytes: b"global"
})

fn copy_fields(value: Fields) -> Fields { value }
fn copy_nested(value: Nested) -> Nested { value }
fn copy_payload(value: Payload) -> Payload { value }
fn copy_option(value: Option<Fields>) -> Option<Fields> { value }
fn copy_result(value: Result<Nested, Fields>) -> Result<Nested, Fields> { value }

fn read_fields(value: Fields) -> long {
    value.ascii.len() + value.text.len() + value.bytes.len()
}

fn replace_fields(value: write Fields) {
    value.text = "é😀"
    value.bytes = b"done"
}

fn replace_strings(
    ascii: write Ascii max 8,
    text: write Text max 8,
    bytes: write Bytes max 8
) {
    text = "文字"
    bytes = b"arg"
}

fn main() {
    let fields = Fields { ascii: "name", text: "hé😀", bytes: b"abc" }
    let copied_fields = copy_fields(fields)
    print(copied_fields)
    print(copied_fields == fields)
    print(read_fields(copied_fields))

    let nested = Nested { fields: copied_fields, count: 42 }
    let returned = copy_nested(nested)
    print(returned)
    print(returned == nested)

    let stored: Payload = Payload.Stored(nested)
    let stored_copy = copy_payload(stored)
    print(stored_copy == stored)
    print(stored_copy)
    let raw: Payload = Payload.Raw("raw", "多字", b"binary")
    let raw_copy = copy_payload(raw)
    print(raw_copy == raw)
    print(raw_copy)

    let maybe: Option<Fields> = some(fields)
    let maybe_copy = copy_option(maybe)
    print(maybe_copy == maybe)
    print(maybe_copy)
    let absent: Option<Fields> = none
    print(copy_option(absent) == absent)

    let success: Result<Nested, Fields> = ok(nested)
    let success_copy = copy_result(success)
    print(success_copy == success)
    print(success_copy)
    let failure: Result<Nested, Fields> = err(fields)
    let failure_copy = copy_result(failure)
    print(failure_copy == failure)
    print(failure_copy)

    print(CONSTANT)
    print(CONSTANT_OPTION)
    print(CONSTANT_ENUM)
    print(CONSTANT_RESULT)
    print(read_fields(CONSTANT_OPTION.unwrap()))
    print(CURRENT)
    print(CURRENT_OPTION)
    print(CURRENT_RESULT)
    replace_fields(CURRENT.fields)
    print(CURRENT)

    var ascii: Ascii max 8 = "old"
    var text: Text max 8 = "old"
    var bytes: Bytes max 8 = b"old"
    replace_strings(ascii, text, bytes)
    print(ascii)
    print(text)
    print(bytes)
}
