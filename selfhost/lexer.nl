enum TokenKind {
    Ident,
    Number,
    String,
    Newline,
    LParen,
    RParen,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    Comma,
    Colon,
    Semicolon,
    Dot,
    Question,
    QuestionDot,
    QuestionQuestion,
    Range,
    RangeInclusive,
    Arrow,
    FatArrow,
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    WrapPlus,
    WrapMinus,
    WrapStar,
    PlusEq,
    MinusEq,
    StarEq,
    SlashEq,
    PercentEq,
    ShrEq,
    Eq,
    EqEq,
    Bang,
    BangEq,
    Lt,
    Le,
    Gt,
    Ge,
    And,
    AndAnd,
    Or,
    OrOr,
    Caret,
    Shl,
    Shr,
    Eof,
}

struct Token {
    kind: TokenKind
    start: long
    length: long
}

struct LexSummary {
    token_count: long
    end_line: long
    end_col: long
}

fn token_error(kind: LexProblemKind, start: long, line: long, col: long, byte: byte) -> LexProblem {
    LexProblem { kind, start, line, col, byte }
}

fn is_ident_start(value: byte) -> bool {
    (value >= 65 && value <= 90) || (value >= 97 && value <= 122) || value == 95
}

fn is_ident_continue(value: byte) -> bool {
    is_ident_start(value) || (value >= 48 && value <= 57)
}

fn is_hex_digit(value: byte) -> bool {
    (value >= 48 && value <= 57) || (value >= 65 && value <= 70) || (value >= 97 && value <= 102)
}

fn utf8_width(first: byte) -> long {
    if first < 128 { 1L }
    else if first < 224 { 2L }
    else if first < 240 { 3L }
    else { 4L }
}

fn matches_ascii(source: Bytes max 67108864, start: long, remaining: long, expected: Ascii max 3) -> bool {
    if remaining < expected.len() { return false }
    for index in 0L..expected.len() {
        if source[start + index] != expected.bytes()[index] { return false }
    }
    true
}

fn emit_token(
    tokens: write list<Token, TOKEN_STORAGE_CAPACITY>,
    file_token_count: write long,
    kind: TokenKind,
    start: long,
    length: long,
    line: long,
    col: long,
) -> Result<(), LexProblem> {
    if file_token_count >= MAX_TOKENS_PER_FILE {
        return err(token_error(LexProblemKind.TokenLimit, start, line, col, 0))
    }
    let token = Token { kind, start, length }
    match tokens.push(token) {
        ok(_) => {
            file_token_count += 1L
            ok(())
        },
        err(Full) => err(token_error(LexProblemKind.TokenLimit, start, line, col, 0)),
    }
}

fn emit_newline(
    tokens: write list<Token, TOKEN_STORAGE_CAPACITY>,
    file_token_count: write long,
    last_kind: TokenKind,
    start: long,
    line: long,
    col: long,
) -> Result<(), LexProblem> {
    if last_kind == TokenKind.Newline || last_kind == TokenKind.Semicolon { return ok(()) }
    emit_token(tokens, file_token_count, TokenKind.Newline, start, 1L, line, col)
}

fn lex_file(
    source: Bytes max 67108864,
    base: long,
    length: long,
    tokens: write list<Token, TOKEN_STORAGE_CAPACITY>,
    delimiters: write list<DelimiterKind, MAX_DELIMITER_NESTING>,
) -> Result<LexSummary, LexProblem> {
    delimiters.clear()
    var pos = 0L
    var line = 1L
    var col = 1L
    var file_token_count = 0L
    var last_kind = TokenKind.Eof

    for step in 0L..length {
        if pos >= length { break }
        let absolute = base + pos
        let value = source[absolute]

        if value == 32 || value == 9 || value == 13 {
            pos += 1L
            col += 1L
            continue
        }
        if value == 10 {
            let newline_start = pos
            let newline_line = line
            let newline_col = col
            pos += 1L
            line += 1L
            col = 1L
            if delimiters.count() == 0L {
                match emit_newline(tokens, file_token_count, last_kind, newline_start, newline_line, newline_col) {
                    ok(_) => {
                        if file_token_count > 0L && tokens[tokens.count() - 1L].kind == TokenKind.Newline {
                            last_kind = TokenKind.Newline
                        }
                    },
                    err(problem) => return err(problem),
                }
            }
            continue
        }
        if value == 47 && pos + 1L < length && source[absolute + 1L] == 47 {
            for comment_step in 0L..length {
                if pos >= length || source[base + pos] == 10 { break }
                pos += 1L
                col += 1L
            }
            continue
        }

        let start = pos
        let start_line = line
        let start_col = col
        if is_ident_start(value) {
            pos += 1L
            col += 1L
            for ident_step in 0L..length {
                if pos >= length || !is_ident_continue(source[base + pos]) { break }
                pos += 1L
                col += 1L
            }
            match emit_token(tokens, file_token_count, TokenKind.Ident, start, pos - start, start_line, start_col) {
                ok(_) => { last_kind = TokenKind.Ident },
                err(problem) => return err(problem),
            }
            continue
        }
        if value >= 48 && value <= 57 {
            pos += 1L
            col += 1L
            for number_step in 0L..length {
                if pos >= length { break }
                let next = source[base + pos]
                if (next >= 48 && next <= 57) || (next >= 65 && next <= 90) || (next >= 97 && next <= 122) || next == 95 {
                    pos += 1L
                    col += 1L
                } else {
                    break
                }
            }
            match emit_token(tokens, file_token_count, TokenKind.Number, start, pos - start, start_line, start_col) {
                ok(_) => { last_kind = TokenKind.Number },
                err(problem) => return err(problem),
            }
            continue
        }
        if value == 34 {
            pos += 1L
            col += 1L
            var closed = false
            for string_step in 0L..length {
                if pos >= length { break }
                let current = source[base + pos]
                if current == 34 {
                    pos += 1L
                    col += 1L
                    closed = true
                    break
                }
                if current == 92 {
                    pos += 1L
                    col += 1L
                    if pos >= length { break }
                    let escaped = source[base + pos]
                    if escaped == 120 {
                        if pos + 2L >= length || !is_hex_digit(source[base + pos + 1L]) || !is_hex_digit(source[base + pos + 2L]) {
                            return err(token_error(LexProblemKind.InvalidHexEscape, start, start_line, start_col, 0))
                        }
                        pos += 3L
                        col += 3L
                        continue
                    }
                    if escaped == 34 || escaped == 92 || escaped == 110 || escaped == 116 || escaped == 48 {
                        pos += 1L
                        col += 1L
                        continue
                    }
                    return err(token_error(LexProblemKind.UnsupportedEscape, start, start_line, start_col, 0))
                }
                if current == 10 {
                    return err(token_error(LexProblemKind.NewlineInString, start, start_line, start_col, 0))
                }
                let width = utf8_width(current)
                pos += width
                col += width
            }
            if !closed {
                return err(token_error(LexProblemKind.UnclosedString, start, start_line, start_col, 0))
            }
            match emit_token(tokens, file_token_count, TokenKind.String, start, pos - start, start_line, start_col) {
                ok(_) => { last_kind = TokenKind.String },
                err(problem) => return err(problem),
            }
            continue
        }

        var kind = TokenKind.Eof
        var width = 0L
        let remaining = length - pos
        if matches_ascii(source, absolute, remaining, "..=") {
            kind = TokenKind.RangeInclusive
            width = 3L
        } else if matches_ascii(source, absolute, remaining, ">>=") {
            kind = TokenKind.ShrEq
            width = 3L
        } else if matches_ascii(source, absolute, remaining, "=>") {
            kind = TokenKind.FatArrow
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "->") {
            kind = TokenKind.Arrow
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "?.") {
            kind = TokenKind.QuestionDot
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "??") {
            kind = TokenKind.QuestionQuestion
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "..") {
            kind = TokenKind.Range
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "+%") {
            kind = TokenKind.WrapPlus
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "-%") {
            kind = TokenKind.WrapMinus
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "*%") {
            kind = TokenKind.WrapStar
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "+=") {
            kind = TokenKind.PlusEq
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "-=") {
            kind = TokenKind.MinusEq
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "*=") {
            kind = TokenKind.StarEq
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "/=") {
            kind = TokenKind.SlashEq
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "%=") {
            kind = TokenKind.PercentEq
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "==") {
            kind = TokenKind.EqEq
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "!=") {
            kind = TokenKind.BangEq
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "<=") {
            kind = TokenKind.Le
            width = 2L
        } else if matches_ascii(source, absolute, remaining, ">=") {
            kind = TokenKind.Ge
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "&&") {
            kind = TokenKind.AndAnd
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "||") {
            kind = TokenKind.OrOr
            width = 2L
        } else if matches_ascii(source, absolute, remaining, "<<") {
            kind = TokenKind.Shl
            width = 2L
        } else if matches_ascii(source, absolute, remaining, ">>") {
            kind = TokenKind.Shr
            width = 2L
        } else {
            if value == 40 { kind = TokenKind.LParen }
            else if value == 41 { kind = TokenKind.RParen }
            else if value == 123 { kind = TokenKind.LBrace }
            else if value == 125 { kind = TokenKind.RBrace }
            else if value == 91 { kind = TokenKind.LBracket }
            else if value == 93 { kind = TokenKind.RBracket }
            else if value == 44 { kind = TokenKind.Comma }
            else if value == 58 { kind = TokenKind.Colon }
            else if value == 59 { kind = TokenKind.Semicolon }
            else if value == 46 { kind = TokenKind.Dot }
            else if value == 63 { kind = TokenKind.Question }
            else if value == 43 { kind = TokenKind.Plus }
            else if value == 45 { kind = TokenKind.Minus }
            else if value == 42 { kind = TokenKind.Star }
            else if value == 47 { kind = TokenKind.Slash }
            else if value == 37 { kind = TokenKind.Percent }
            else if value == 61 { kind = TokenKind.Eq }
            else if value == 33 { kind = TokenKind.Bang }
            else if value == 60 { kind = TokenKind.Lt }
            else if value == 62 { kind = TokenKind.Gt }
            else if value == 38 { kind = TokenKind.And }
            else if value == 124 { kind = TokenKind.Or }
            else if value == 94 { kind = TokenKind.Caret }
            else { return err(token_error(LexProblemKind.UnexpectedCharacter, start, start_line, start_col, value)) }
            width = 1L
        }

        if kind == TokenKind.LParen || kind == TokenKind.LBracket {
            if delimiters.count() >= MAX_DELIMITER_NESTING {
                return err(token_error(LexProblemKind.DelimiterNesting, start, start_line, start_col, 0))
            }
            let delimiter = if kind == TokenKind.LParen { DelimiterKind.Parenthesis } else { DelimiterKind.Bracket }
            match delimiters.push(delimiter) {
                ok(_) => (),
                err(Full) => return err(token_error(LexProblemKind.DelimiterNesting, start, start_line, start_col, 0)),
            }
        } else if kind == TokenKind.RParen || kind == TokenKind.RBracket {
            let wanted = if kind == TokenKind.RParen { DelimiterKind.Parenthesis } else { DelimiterKind.Bracket }
            if delimiters.count() == 0L || delimiters[delimiters.count() - 1L] != wanted {
                return err(token_error(LexProblemKind.UnmatchedClosing, start, start_line, start_col, 0))
            }
            match delimiters.pop() {
                some(_) => (),
                none => (),
            }
        } else {
            ()
        }

        pos += width
        col += width
        match emit_token(tokens, file_token_count, kind, start, width, start_line, start_col) {
            ok(_) => { last_kind = kind },
            err(problem) => return err(problem),
        }
    }

    if delimiters.count() > 0L {
        let kind = if delimiters[delimiters.count() - 1L] == DelimiterKind.Parenthesis {
            LexProblemKind.UnclosedParen
        } else {
            LexProblemKind.UnclosedBracket
        }
        return err(token_error(kind, length, line, col, 0))
    }
    emit_token(tokens, file_token_count, TokenKind.Eof, length, 0L, line, col)?
    ok(LexSummary { token_count: file_token_count, end_line: line, end_col: col })
}
