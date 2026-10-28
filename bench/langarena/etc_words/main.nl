// Etc::Words: generate random words with LangArena's LCG, then count word frequencies.
const TEST_WORDS: long = 600L
const TEST_WORD_LEN: long = 1L
const TEST_ITERATIONS: long = 2L
const RUN_WORDS: long = 50000L
const RUN_WORD_LEN: long = 4L
const RUN_ITERATIONS: long = 360L
const MODULUS: long = 4294967296L
const IM: long = 139968L
const IA: long = 3877L
const IC: long = 29573L
const LCG_INIT: long = 42L

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

// LangArena's next_int(max_value): the LCG step, then floor(last / IM * max_value).
fn next_int(last: write long, max_value: long) -> long {
    last = (last * IA + IC) % IM
    last * max_value / IM
}

fn checksum_word(word: Ascii max 8) -> long {
    var hash = 5381L
    for i: long in 0L..word.len() {
        hash = (hash * 33L + word.bytes()[i].to_long()) % MODULUS
    }
    hash
}

// The text as bytes: words of 3 to 8 letters separated by single spaces.
fn generate(text: write list<byte, 400000>, words: long, word_len: long) {
    var last = LCG_INIT
    for i: long in 0L..words {
        let first = next_int(last, word_len)
        let second = next_int(last, 3L)
        let length = first + second + 3L
        for _c: long in 0L..length {
            let k = next_int(last, 26L)
            let code = 97 + (int)k
            text.push(clamp(code, 0, 255)).unwrap()
        }
        if i < words - 1L { text.push(32).unwrap() }
    }
}

// The checksum contribution of one pass: max_value count + checksum(max_value word) + distinct words.
// Distinct words are kept in first-seen order (`words`, `counts`); `slot_of` finds a word's place.
fn count_words(text: list<byte, 400000>) -> long {
    var slot_of: map<Ascii max 8, int, 65536> = map {}
    var words: list<Ascii max 8, 50000> = list {}
    var counts: list<long, 50000> = list {}
    let size = text.count()
    var start = 0L
    for i: long in 0L..(size + 1L) {
        if i == size || text[i] == 32 {
            if i > start {
                var letters: Bytes max 8 = Bytes.empty()
                for j: long in start..i { letters.push(text[j]).unwrap() }
                let word: Ascii max 8 = letters.to_ascii().unwrap()
                match slot_of.get(word) {
                    some(slot) => { counts[slot.to_long()] += 1L },
                    none => {
                        slot_of.set(word, (int)words.count()).unwrap()
                        words.push(word).unwrap()
                        counts.push(1L).unwrap()
                    }
                }
            }
            start = i + 1L
        }
    }
    var max_count = 0L
    var max_slot = 0L
    for count, slot in counts {
        if count > max_count {
            max_count = count
            max_slot = slot
        }
    }
    max_count + checksum_word(words[max_slot]) + words.count()
}

fn is_prep_mode(env: Env) -> bool {
    match env.args().get(1L) {
        some(_argument) => true,
        none => false
    }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let prep = is_prep_mode(env)
    let words = if run { RUN_WORDS } else { TEST_WORDS }
    let word_len = if run { RUN_WORD_LEN } else { TEST_WORD_LEN }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    // Crystal's prepare builds the text (untimed); prep mode here is the text plus the warmup rounds.
    let rounds = if prep { warmup } else { warmup + iterations }
    var text: list<byte, 400000> = list {}
    generate(text, words, word_len)
    var checksum = 0L
    for _round: long in 0L..rounds {
        checksum = (checksum + count_words(text)) % MODULUS
    }
    print(checksum)
}
