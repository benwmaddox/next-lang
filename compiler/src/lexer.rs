use crate::ast::Span;

pub const MAX_TOKENS_PER_FILE: usize = 1_000_000;
pub const MAX_DELIMITER_NESTING: usize = 2_048;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TokenKind {
    Ident(String),
    Number(String),
    String {
        value: String,
        bytes: Vec<u8>,
        has_non_ascii_hex_escape: bool,
    },
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

#[derive(Clone, Debug)]
pub struct Token {
    pub kind: TokenKind,
    pub span: Span,
    pub start_offset: usize,
    pub end_offset: usize,
}

#[derive(Clone, Debug)]
pub struct LexError {
    pub span: Span,
    pub message: String,
}

pub fn lex(source: &str, file: usize) -> Result<Vec<Token>, LexError> {
    let bytes = source.as_bytes();
    let mut pos = 0;
    let mut line = 1;
    let mut col = 1;
    let mut delimiters = Vec::<(u8, Span)>::new();
    let mut out = Vec::new();

    while pos < bytes.len() {
        let b = bytes[pos];
        if b == b' ' || b == b'\t' || b == b'\r' {
            pos += 1;
            col += 1;
            continue;
        }
        if b == b'\n' {
            let span = Span {
                file,
                line,
                col,
                start_offset: pos,
                end_offset: pos + 1,
            };
            pos += 1;
            line += 1;
            col = 1;
            if delimiters.is_empty() {
                push_newline(&mut out, span, pos - 1)?;
            }
            continue;
        }
        if b == b'/' && bytes.get(pos + 1) == Some(&b'/') {
            while pos < bytes.len() && bytes[pos] != b'\n' {
                pos += 1;
                col += 1;
            }
            continue;
        }
        let span = Span {
            file,
            line,
            col,
            start_offset: pos,
            end_offset: pos,
        };
        if is_ident_start(b) {
            let start = pos;
            while pos < bytes.len() && is_ident_continue(bytes[pos]) {
                pos += 1;
                col += 1;
            }
            push_token(
                &mut out,
                Token {
                    kind: TokenKind::Ident(source[start..pos].to_owned()),
                    span: Span {
                        end_offset: pos,
                        ..span
                    },
                    start_offset: start,
                    end_offset: pos,
                },
            )?;
            continue;
        }
        if b.is_ascii_digit() {
            let start = pos;
            pos += 1;
            col += 1;
            while pos < bytes.len() && (bytes[pos].is_ascii_alphanumeric() || bytes[pos] == b'_') {
                pos += 1;
                col += 1;
            }
            push_token(
                &mut out,
                Token {
                    kind: TokenKind::Number(source[start..pos].to_owned()),
                    span: Span {
                        end_offset: pos,
                        ..span
                    },
                    start_offset: start,
                    end_offset: pos,
                },
            )?;
            continue;
        }

        if b == b'"' {
            let start = pos;
            pos += 1;
            col += 1;
            let mut value = String::new();
            let mut string_bytes = Vec::new();
            let mut has_non_ascii_hex_escape = false;
            let mut closed = false;
            while pos < bytes.len() {
                match bytes[pos] {
                    b'"' => {
                        pos += 1;
                        col += 1;
                        closed = true;
                        break;
                    }
                    b'\\' => {
                        pos += 1;
                        col += 1;
                        let Some(&escaped) = bytes.get(pos) else {
                            break;
                        };
                        match escaped {
                            b'"' => push_string_char(&mut value, &mut string_bytes, '"'),
                            b'\\' => push_string_char(&mut value, &mut string_bytes, '\\'),
                            b'n' => push_string_char(&mut value, &mut string_bytes, '\n'),
                            b't' => push_string_char(&mut value, &mut string_bytes, '\t'),
                            b'0' => push_string_char(&mut value, &mut string_bytes, '\0'),
                            b'x' => {
                                let Some(first) = bytes.get(pos + 1).copied() else {
                                    return Err(invalid_hex_escape(span));
                                };
                                let Some(second) = bytes.get(pos + 2).copied() else {
                                    return Err(invalid_hex_escape(span));
                                };
                                let (Some(high), Some(low)) = (hex_value(first), hex_value(second))
                                else {
                                    return Err(invalid_hex_escape(span));
                                };
                                let byte = high * 16 + low;
                                has_non_ascii_hex_escape |= byte > 0x7f;
                                value.push(char::from(byte));
                                string_bytes.push(byte);
                                pos += 3;
                                col += 3;
                                continue;
                            }
                            _ => {
                                return Err(LexError {
                                    span,
                                    message: "unsupported string escape; use \", \\\\, \\n, \\t, \\0, or \\xNN"
                                        .to_owned(),
                                });
                            }
                        }
                        pos += 1;
                        col += 1;
                    }
                    b'\n' => {
                        return Err(LexError {
                            span,
                            message: "string literals cannot contain a newline; escape it as \\n"
                                .to_owned(),
                        });
                    }
                    _ => {
                        let ch = source[pos..].chars().next().expect("valid UTF-8 source");
                        push_string_char(&mut value, &mut string_bytes, ch);
                        let width = ch.len_utf8();
                        pos += width;
                        col += width;
                    }
                }
            }
            if !closed {
                return Err(LexError {
                    span,
                    message: "unclosed string literal; add a closing quote".to_owned(),
                });
            }
            push_token(
                &mut out,
                Token {
                    kind: TokenKind::String {
                        value,
                        bytes: string_bytes,
                        has_non_ascii_hex_escape,
                    },
                    span: Span {
                        end_offset: pos,
                        ..span
                    },
                    start_offset: start,
                    end_offset: pos,
                },
            )?;
            continue;
        }

        let (kind, width) = if bytes.get(pos..pos + 3) == Some(b"..=".as_slice()) {
            Some((TokenKind::RangeInclusive, 3))
        } else if bytes.get(pos..pos + 3) == Some(b">>=".as_slice()) {
            Some((TokenKind::ShrEq, 3))
        } else if bytes.get(pos..pos + 2) == Some(b"=>".as_slice()) {
            Some((TokenKind::FatArrow, 2))
        } else {
            match_two_or_one(bytes, pos)
        }
        .ok_or_else(|| LexError {
            span,
            message: format!(
                "unexpected character '{}'; remove it or use a supported operator",
                b as char
            ),
        })?;
        if matches!(kind, TokenKind::LParen | TokenKind::LBracket) {
            if delimiters.len() >= MAX_DELIMITER_NESTING {
                return Err(LexError {
                    span,
                    message: format!("delimiter nesting limit of {MAX_DELIMITER_NESTING} exceeded"),
                });
            }
            delimiters.push((
                if kind == TokenKind::LParen {
                    b'('
                } else {
                    b'['
                },
                span,
            ));
        } else if matches!(kind, TokenKind::RParen | TokenKind::RBracket) {
            let expected = if kind == TokenKind::RParen {
                b'('
            } else {
                b'['
            };
            if delimiters.last().is_none_or(|(open, _)| *open != expected) {
                return Err(LexError {
                    span,
                    message: "unmatched closing delimiter; add a matching opener".to_owned(),
                });
            }
            delimiters.pop();
        }
        let start_offset = pos;
        pos += width;
        col += width;
        push_token(
            &mut out,
            Token {
                kind,
                span: Span {
                    end_offset: pos,
                    ..span
                },
                start_offset,
                end_offset: pos,
            },
        )?;
    }
    if let Some((open, _)) = delimiters.last() {
        return Err(LexError {
            span: Span {
                file,
                line,
                col,
                start_offset: pos,
                end_offset: pos,
            },
            message: if *open == b'(' {
                "unclosed '('; add a matching ')'".to_owned()
            } else {
                "unclosed '['; add a matching ']'".to_owned()
            },
        });
    }
    let span = Span {
        file,
        line,
        col,
        start_offset: pos,
        end_offset: pos,
    };
    push_token(
        &mut out,
        Token {
            kind: TokenKind::Eof,
            span,
            start_offset: pos,
            end_offset: pos,
        },
    )?;
    Ok(out)
}

fn push_token(out: &mut Vec<Token>, token: Token) -> Result<(), LexError> {
    if out.len() >= MAX_TOKENS_PER_FILE {
        return Err(LexError {
            span: token.span,
            message: format!("token limit of {MAX_TOKENS_PER_FILE} per file exceeded"),
        });
    }
    out.push(token);
    Ok(())
}

fn push_string_char(value: &mut String, bytes: &mut Vec<u8>, ch: char) {
    value.push(ch);
    let mut encoded = [0; 4];
    bytes.extend_from_slice(ch.encode_utf8(&mut encoded).as_bytes());
}

fn hex_value(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn invalid_hex_escape(span: Span) -> LexError {
    LexError {
        span,
        message: "\\x escape needs exactly two hexadecimal digits".to_owned(),
    }
}

fn push_newline(out: &mut Vec<Token>, span: Span, offset: usize) -> Result<(), LexError> {
    if !matches!(
        out.last().map(|t| &t.kind),
        Some(TokenKind::Newline | TokenKind::Semicolon)
    ) {
        push_token(
            out,
            Token {
                kind: TokenKind::Newline,
                span: Span {
                    start_offset: offset,
                    end_offset: offset + 1,
                    ..span
                },
                start_offset: offset,
                end_offset: offset + 1,
            },
        )?;
    }
    Ok(())
}

fn is_ident_start(b: u8) -> bool {
    b.is_ascii_alphabetic() || b == b'_'
}

fn is_ident_continue(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

fn match_two_or_one(b: &[u8], p: usize) -> Option<(TokenKind, usize)> {
    let two = b.get(p..p + 2);
    if let Some(pair) = two {
        let kind = match pair {
            b"->" => Some(TokenKind::Arrow),
            b"?." => Some(TokenKind::QuestionDot),
            b"??" => Some(TokenKind::QuestionQuestion),
            b".." => Some(TokenKind::Range),
            b"+%" => Some(TokenKind::WrapPlus),
            b"-%" => Some(TokenKind::WrapMinus),
            b"*%" => Some(TokenKind::WrapStar),
            b"+=" => Some(TokenKind::PlusEq),
            b"-=" => Some(TokenKind::MinusEq),
            b"*=" => Some(TokenKind::StarEq),
            b"/=" => Some(TokenKind::SlashEq),
            b"%=" => Some(TokenKind::PercentEq),
            b"==" => Some(TokenKind::EqEq),
            b"!=" => Some(TokenKind::BangEq),
            b"<=" => Some(TokenKind::Le),
            b">=" => Some(TokenKind::Ge),
            b"&&" => Some(TokenKind::AndAnd),
            b"||" => Some(TokenKind::OrOr),
            b"<<" => Some(TokenKind::Shl),
            b">>" => Some(TokenKind::Shr),
            _ => None,
        };
        if let Some(k) = kind {
            return Some((k, 2));
        }
    }
    let kind = match b[p] {
        b'(' => TokenKind::LParen,
        b')' => TokenKind::RParen,
        b'{' => TokenKind::LBrace,
        b'}' => TokenKind::RBrace,
        b'[' => TokenKind::LBracket,
        b']' => TokenKind::RBracket,
        b',' => TokenKind::Comma,
        b':' => TokenKind::Colon,
        b';' => TokenKind::Semicolon,
        b'.' => TokenKind::Dot,
        b'?' => TokenKind::Question,
        b'+' => TokenKind::Plus,
        b'-' => TokenKind::Minus,
        b'*' => TokenKind::Star,
        b'/' => TokenKind::Slash,
        b'%' => TokenKind::Percent,
        b'=' => TokenKind::Eq,
        b'!' => TokenKind::Bang,
        b'<' => TokenKind::Lt,
        b'>' => TokenKind::Gt,
        b'&' => TokenKind::And,
        b'|' => TokenKind::Or,
        b'^' => TokenKind::Caret,
        _ => return None,
    };
    Some((kind, 1))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn newlines_continue_inside_parentheses() {
        let tokens = lex("fn f(\na: int,\nb: int\n) {\n a +\n b\n}", 0).unwrap();
        assert_eq!(
            tokens
                .iter()
                .filter(|t| t.kind == TokenKind::Newline)
                .count(),
            3
        );
    }

    #[test]
    fn comments_keep_the_line_ending() {
        let tokens = lex("let x = 1 // value\nprint(x)", 0).unwrap();
        assert!(tokens.iter().any(|t| t.kind == TokenKind::Newline));
    }
}
