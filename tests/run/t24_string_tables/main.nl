type Word = Ascii max 8
type Label = Text max 8
type Raw = Bytes max 8

const KEYWORDS: (Ascii max 8)[3] = ["fn", "let", "match"]
global MORE_KEYWORDS: list<Word, 3> = ["if", "else"]
global LABELS: (Text max 8)[2] = ["ready", "λ"]
const MORE_LABELS: list<Label, 3> = ["open", "closed"]
const BYTE_VALUES: (Bytes max 8)[2] = [b"op", b"\xff"]
global MORE_BYTES: list<Raw, 3> = [b"xy", b"z"]

fn main() {
    print(KEYWORDS[1])
    for word in KEYWORDS {
        print(word)
    }
    print(MORE_KEYWORDS[0])
    for word in MORE_KEYWORDS {
        print(word)
    }

    print(LABELS[1])
    for label in LABELS {
        print(label)
    }
    print(MORE_LABELS[0])
    for label in MORE_LABELS {
        print(label)
    }

    print(BYTE_VALUES[0].len())
    for bytes in BYTE_VALUES {
        print(bytes.len())
    }
    print(MORE_BYTES[1].len())
    for bytes in MORE_BYTES {
        print(bytes.len())
    }

    let selected_word = match 0 {
        0 => KEYWORDS[2]
        _ => KEYWORDS[0]
    }
    print(selected_word)
    let selected_label = match 1 {
        0 => LABELS[0]
        _ => LABELS[1]
    }
    print(selected_label)
    print(match 1 {
        0 => BYTE_VALUES[0].len(),
        _ => BYTE_VALUES[1].len()
    })
}
