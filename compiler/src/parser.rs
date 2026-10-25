use crate::ast::*;
use crate::lexer::{Token, TokenKind};

const EXPRESSION_NESTING_LIMIT: usize = 1000;
const EXPRESSION_PARSER_STACK_LIMIT: usize = 2048;

#[derive(Clone, Debug)]
pub struct ParseError {
    pub span: Span,
    pub message: String,
}

pub fn parse(tokens: Vec<Token>, source: &str) -> Result<Program, ParseError> {
    Parser {
        tokens,
        pos: 0,
        source,
        allow_struct_literals: true,
        expression_depth: 0,
        parenthesis_depth: 0,
        block_depth: 0,
    }
    .program()
}

struct Parser<'a> {
    tokens: Vec<Token>,
    pos: usize,
    source: &'a str,
    allow_struct_literals: bool,
    expression_depth: usize,
    parenthesis_depth: usize,
    block_depth: usize,
}

impl Parser<'_> {
    fn program(mut self) -> Result<Program, ParseError> {
        let mut enums = Vec::new();
        let mut structs = Vec::new();
        let mut aliases = Vec::new();
        let mut constants = Vec::new();
        let mut globals = Vec::new();
        let mut functions = Vec::new();
        let mut tests = Vec::new();
        self.skip_separators();
        while !self.at(&TokenKind::Eof) {
            if self.word_is("enum") {
                enums.push(self.enum_decl()?);
            } else if self.word_is("struct") {
                structs.push(self.struct_decl()?);
            } else if self.word_is("type") {
                aliases.push(self.type_alias_decl()?);
            } else if self.word_is("const") {
                constants.push(self.const_decl()?);
            } else if self.word_is("global") {
                globals.push(self.global_decl()?);
            } else if self.word_is("test") {
                tests.push(self.test()?);
            } else {
                functions.push(self.function()?);
            }
            self.require_separator_or_eof()?;
            self.skip_separators();
        }
        Ok(Program {
            enums,
            structs,
            aliases,
            constants,
            globals,
            functions,
            tests,
        })
    }

    fn struct_decl(&mut self) -> Result<StructDecl, ParseError> {
        let start = self.expect_word("struct", "expected 'struct'")?.span;
        let (name, _) = self.expect_ident("expected a struct name")?;
        let generic_params = self.generic_params()?;
        self.skip_newlines();
        self.expect(&TokenKind::LBrace, "expected '{' after the struct name")?;
        self.skip_separators();
        let mut fields = Vec::new();
        while !self.at(&TokenKind::RBrace) && !self.at(&TokenKind::Eof) {
            let (field_name, field_span) = self.expect_ident("expected a field name")?;
            self.expect(&TokenKind::Colon, "expected ':' after the field name")?;
            let ty = self.type_name()?;
            let default = if self.take(&TokenKind::Eq) {
                Some(self.expression(0)?)
            } else {
                None
            };
            fields.push(StructFieldDecl {
                name: field_name,
                ty,
                default,
                span: field_span,
            });
            let separated = self.skip_separators() > 0;
            if self.take(&TokenKind::Comma) {
                self.skip_separators();
            } else if !self.at(&TokenKind::RBrace) && !separated {
                return Err(self.error_here("expected a comma or newline between struct fields"));
            }
        }
        self.expect(&TokenKind::RBrace, "expected '}' to close the struct")?;
        Ok(StructDecl {
            name,
            generic_params,
            fields,
            span: start,
        })
    }

    fn type_alias_decl(&mut self) -> Result<TypeAliasDecl, ParseError> {
        let start = self.expect_word("type", "expected 'type'")?.span;
        let (name, _) = self.expect_ident("expected a type name")?;
        self.expect(&TokenKind::Eq, "expected '=' in a type alias")?;
        let ty = self.type_name()?;
        Ok(TypeAliasDecl {
            name,
            ty,
            span: start,
        })
    }

    fn const_decl(&mut self) -> Result<ConstDecl, ParseError> {
        let start = self.expect_word("const", "expected 'const'")?.span;
        let (name, _) = self.expect_ident("expected a constant name")?;
        self.expect(&TokenKind::Colon, "expected ':' after the constant name")?;
        let ty = self.type_name()?;
        self.expect(&TokenKind::Eq, "expected '=' in a constant declaration")?;
        let value = self.expression(0)?;
        Ok(ConstDecl {
            name,
            ty,
            value,
            span: start,
        })
    }

    fn global_decl(&mut self) -> Result<GlobalDecl, ParseError> {
        let start = self.expect_word("global", "expected 'global'")?.span;
        let (name, _) = self.expect_ident("expected a global name")?;
        self.expect(&TokenKind::Colon, "expected ':' after the global name")?;
        let ty = self.type_name()?;
        let mut prefault = false;
        while self.word_is("prefault") {
            if prefault {
                return Err(self.error_here("'prefault' may only appear once on a global"));
            }
            self.next();
            prefault = true;
        }
        if self.word_is("locked") {
            return Err(self.error_here(
                "'locked' globals are unsupported; remove the modifier instead of silently ignoring it",
            ));
        }
        // The Linux startup policy already touches every global page.
        self.expect(&TokenKind::Eq, "expected '=' in a global declaration")?;
        let value = self.expression(0)?;
        Ok(GlobalDecl {
            name,
            ty,
            value,
            span: start,
        })
    }

    fn enum_decl(&mut self) -> Result<EnumDecl, ParseError> {
        let start = self.expect_word("enum", "expected 'enum'")?.span;
        let (name, _) = self.expect_ident("expected an enum name after 'enum'")?;
        self.skip_newlines();
        self.expect(&TokenKind::LBrace, "expected '{' after the enum name")?;
        self.skip_separators();
        let mut cases = Vec::new();
        while !self.at(&TokenKind::RBrace) && !self.at(&TokenKind::Eof) {
            let (case_name, case_span) = self.expect_ident("expected an enum case name")?;
            let mut payload = Vec::new();
            if self.take(&TokenKind::LParen) {
                self.skip_newlines();
                if !self.at(&TokenKind::RParen) {
                    loop {
                        payload.push(self.type_name()?);
                        self.skip_newlines();
                        if !self.take(&TokenKind::Comma) {
                            break;
                        }
                        self.skip_newlines();
                        if self.at(&TokenKind::RParen) {
                            break;
                        }
                    }
                }
                self.expect(&TokenKind::RParen, "expected ')' after enum payload types")?;
            }
            cases.push(EnumCase {
                name: case_name,
                payload,
                span: case_span,
            });
            let separated = self.skip_separators() > 0;
            if self.take(&TokenKind::Comma) {
                self.skip_separators();
            } else if !self.at(&TokenKind::RBrace) && !separated {
                return Err(self.error_here("expected a comma or newline between enum cases"));
            }
        }
        if cases.is_empty() {
            return Err(ParseError {
                span: start,
                message: "an enum needs at least one case".to_owned(),
            });
        }
        self.expect(&TokenKind::RBrace, "expected '}' to close the enum")?;
        Ok(EnumDecl {
            name,
            cases,
            span: start,
        })
    }

    fn test(&mut self) -> Result<Test, ParseError> {
        let start = self.expect_word("test", "expected 'test'")?.span;
        let token = self.next().clone();
        let name = if let TokenKind::String(name) = token.kind {
            name
        } else {
            return Err(ParseError {
                span: token.span,
                message: "expected a quoted test name after 'test'".to_owned(),
            });
        };
        self.skip_newlines();
        let mut params = Vec::new();
        if self.take(&TokenKind::LParen) {
            self.skip_newlines();
            if !self.at(&TokenKind::RParen) {
                loop {
                    self.skip_newlines();
                    let (param_name, pspan) =
                        self.expect_ident("expected a test parameter name")?;
                    self.expect(
                        &TokenKind::Colon,
                        "expected ':' after the test parameter name",
                    )?;
                    let mode = if self.word_is("write") {
                        self.next();
                        ParamMode::Write
                    } else {
                        ParamMode::Read
                    };
                    let ty = self.type_name()?;
                    params.push(Param {
                        name: param_name,
                        mode,
                        ty,
                        span: pspan,
                    });
                    self.skip_newlines();
                    if !self.take(&TokenKind::Comma) {
                        break;
                    }
                    self.skip_newlines();
                    if self.at(&TokenKind::RParen) {
                        break;
                    }
                }
            }
            self.expect(&TokenKind::RParen, "expected ')' after the test parameters")?;
            self.skip_newlines();
        }
        let body = self.block()?;
        Ok(Test {
            name,
            params,
            body,
            span: start,
        })
    }

    fn function(&mut self) -> Result<Function, ParseError> {
        let recursive = self.word_is("recursive");
        let start = if recursive {
            let start = self.next().span;
            self.expect_word("fn", "expected 'fn' after 'recursive'")?;
            start
        } else {
            self.expect_word("fn", "expected a function declaration starting with 'fn'")?
                .span
        };
        let (name, _) = self.expect_ident("expected a function name after 'fn'")?;
        let generic_params = self.generic_params()?;
        self.expect(&TokenKind::LParen, "expected '(' after the function name")?;
        let mut params = Vec::new();
        self.skip_newlines();
        if !self.at(&TokenKind::RParen) {
            loop {
                self.skip_newlines();
                let (param_name, pspan) = self.expect_ident("expected a parameter name")?;
                self.expect(&TokenKind::Colon, "expected ':' after the parameter name")?;
                let mode = if self.word_is("write") {
                    self.next();
                    ParamMode::Write
                } else {
                    ParamMode::Read
                };
                let ty = self.type_name()?;
                params.push(Param {
                    name: param_name,
                    mode,
                    ty,
                    span: pspan,
                });
                self.skip_newlines();
                if !self.take(&TokenKind::Comma) {
                    break;
                }
                self.skip_newlines();
                if self.at(&TokenKind::RParen) {
                    break;
                }
            }
        }
        self.expect(&TokenKind::RParen, "expected ')' after the parameters")?;
        self.skip_newlines();
        let result = if self.take(&TokenKind::Arrow) {
            self.skip_newlines();
            Some(self.type_name()?)
        } else {
            None
        };
        self.skip_newlines();
        let body = self.block()?;
        Ok(Function {
            name,
            recursive,
            generic_params,
            params,
            result,
            body,
            span: start,
        })
    }

    fn type_name(&mut self) -> Result<TypeAst, ParseError> {
        if self.word_is("fn") {
            let function = self.function_type()?;
            let span = function.span;
            let mut array_caps = Vec::new();
            while self.take(&TokenKind::LBracket) {
                array_caps.push(self.expression(8)?);
                self.expect(
                    &TokenKind::RBracket,
                    "expected ']' after the array capacity",
                )?;
            }
            return Ok(TypeAst {
                name: "fn".to_owned(),
                args: Vec::new(),
                const_args: Vec::new(),
                array_caps,
                range: None,
                policy: RefinePolicy::Checked,
                function: Some(function),
                span,
            });
        }
        if self.take(&TokenKind::LParen) {
            let span = self.tokens[self.pos.saturating_sub(1)].span;
            if self.take(&TokenKind::RParen) {
                return Ok(TypeAst {
                    name: "()".to_owned(),
                    args: Vec::new(),
                    const_args: Vec::new(),
                    array_caps: Vec::new(),
                    range: None,
                    policy: RefinePolicy::Checked,
                    function: None,
                    span,
                });
            }
            let mut inner = self.type_name()?;
            self.expect(&TokenKind::RParen, "expected ')' after the grouped type")?;
            while self.take(&TokenKind::LBracket) {
                inner.array_caps.push(self.expression(8)?);
                self.expect(
                    &TokenKind::RBracket,
                    "expected ']' after the array capacity",
                )?;
            }
            inner.span = span;
            return Ok(inner);
        }
        let (mut name, span) = self.expect_ident("expected a type name")?;
        while self.take(&TokenKind::Dot) {
            let (part, _) = self.expect_ident("expected a name after '.' in a type path")?;
            name.push('.');
            name.push_str(&part);
        }
        let mut args = Vec::new();
        let mut const_args = Vec::new();
        if self.take(&TokenKind::Lt) {
            args.push(self.type_name()?);
            if matches!(name.as_str(), "list" | "pool" | "queue" | "ring")
                && self.take(&TokenKind::Comma)
            {
                const_args.push(self.expression(8)?);
                if name == "pool" && self.take(&TokenKind::Comma) {
                    self.skip_newlines();
                    args.push(self.type_name()?);
                }
            } else if name == "grid" {
                self.expect(
                    &TokenKind::Comma,
                    "expected a width after the grid element type",
                )?;
                self.skip_newlines();
                const_args.push(self.expression(8)?);
                self.expect(&TokenKind::Comma, "expected a height after the grid width")?;
                self.skip_newlines();
                const_args.push(self.expression(8)?);
            } else if name == "map" {
                self.expect(
                    &TokenKind::Comma,
                    "expected a value type after the map key type",
                )?;
                self.skip_newlines();
                args.push(self.type_name()?);
                self.expect(
                    &TokenKind::Comma,
                    "expected a capacity after the map value type",
                )?;
                self.skip_newlines();
                const_args.push(self.expression(8)?);
            } else if name == "set" {
                self.expect(
                    &TokenKind::Comma,
                    "expected a capacity after the set key type",
                )?;
                self.skip_newlines();
                const_args.push(self.expression(8)?);
            } else {
                while self.take(&TokenKind::Comma) {
                    self.skip_newlines();
                    args.push(self.type_name()?);
                }
            }
            self.expect_type_gt("expected '>' after generic type arguments")?;
        }
        let range = if matches!(self.peek().kind, TokenKind::Number(_) | TokenKind::Minus) {
            let lower = self.range_bound()?;
            let inclusive = if self.take(&TokenKind::RangeInclusive) {
                true
            } else {
                self.expect(&TokenKind::Range, "expected '..' or '..=' in a range type")?;
                false
            };
            let upper = self.range_bound()?;
            Some(TypeRangeAst {
                lower,
                upper,
                inclusive,
                span,
            })
        } else {
            None
        };
        let policy = if self.word_is("wrap") {
            self.next();
            RefinePolicy::Wrap
        } else if self.word_is("clamp") {
            self.next();
            RefinePolicy::Clamp
        } else {
            RefinePolicy::Checked
        };
        if range.is_none() && policy != RefinePolicy::Checked {
            return Err(ParseError {
                span,
                message: "'wrap' and 'clamp' need an integer range type".to_owned(),
            });
        }
        let mut array_caps = Vec::new();
        while self.take(&TokenKind::LBracket) {
            array_caps.push(self.expression(8)?);
            self.expect(
                &TokenKind::RBracket,
                "expected ']' after the array capacity",
            )?;
        }
        Ok(TypeAst {
            name,
            args,
            const_args,
            array_caps,
            range,
            policy,
            function: None,
            span,
        })
    }

    fn function_type(&mut self) -> Result<FunctionTypeAst, ParseError> {
        let start = self.expect_word("fn", "expected 'fn'")?.span;
        if self.take(&TokenKind::Lt) {
            return Err(ParseError {
                span: start,
                message: "owner- or capacity-generic function values are not supported yet; use a concrete signature".to_owned(),
            });
        }
        self.expect(&TokenKind::LParen, "expected '(' after 'fn'")?;
        let mut params = Vec::new();
        self.skip_newlines();
        if !self.at(&TokenKind::RParen) {
            loop {
                self.skip_newlines();
                let mode = if self.word_is("write") {
                    self.next();
                    ParamMode::Write
                } else {
                    ParamMode::Read
                };
                let ty = self.type_name()?;
                params.push(FunctionTypeParamAst { mode, ty });
                self.skip_newlines();
                if !self.take(&TokenKind::Comma) {
                    break;
                }
                self.skip_newlines();
                if self.at(&TokenKind::RParen) {
                    break;
                }
            }
        }
        self.expect(
            &TokenKind::RParen,
            "expected ')' after function type parameters",
        )?;
        self.skip_newlines();
        let result = if self.take(&TokenKind::Arrow) {
            self.skip_newlines();
            Some(Box::new(self.type_name()?))
        } else {
            None
        };
        let mut effects = Vec::new();
        if self.word_is("effects") {
            self.next();
            loop {
                let (effect, effect_span) =
                    self.expect_ident("expected an effect after 'effects'")?;
                match effect.as_str() {
                    "out" => effects.push(FunctionEffectAst::Out),
                    "env" => effects.push(FunctionEffectAst::Env),
                    "fs" => {
                        self.expect(&TokenKind::Dot, "expected '.read' or '.write' after 'fs'")?;
                        let (operation, operation_span) =
                            self.expect_ident("expected 'read' or 'write' after 'fs.'")?;
                        match operation.as_str() {
                            "read" => effects.push(FunctionEffectAst::FsRead),
                            "write" => effects.push(FunctionEffectAst::FsWrite),
                            _ => {
                                return Err(ParseError {
                                    span: operation_span,
                                    message: "filesystem effects are 'fs.read' and 'fs.write'"
                                        .to_owned(),
                                });
                            }
                        }
                    }
                    "reads" | "writes" => {
                        let (root, root_span) = self.expect_ident(if effect == "reads" {
                            "expected a global path after 'reads'"
                        } else {
                            "expected a global path after 'writes'"
                        })?;
                        let mut path = root;
                        while self.take(&TokenKind::Dot) {
                            let (part, _) = self.expect_ident("expected a field name after '.'")?;
                            path.push('.');
                            path.push_str(&part);
                        }
                        effects.push(if effect == "reads" {
                            FunctionEffectAst::Reads {
                                path,
                                span: root_span,
                            }
                        } else {
                            FunctionEffectAst::Writes {
                                path,
                                span: root_span,
                            }
                        });
                    }
                    _ => {
                        return Err(ParseError {
                            span: effect_span,
                            message: format!(
                                "unknown function effect '{}'; use out, env, fs.read, fs.write, reads global, or writes global",
                                effect
                            ),
                        });
                    }
                }
                if !matches!(self.peek().kind, TokenKind::Comma) {
                    break;
                }
                let next = match &self.peek_n(1).kind {
                    TokenKind::Ident(name) => name.as_str(),
                    _ => break,
                };
                if !matches!(next, "out" | "env" | "fs" | "reads" | "writes") {
                    break;
                }
                self.next();
            }
        }
        Ok(FunctionTypeAst {
            params,
            result,
            effects,
            span: start,
        })
    }

    fn generic_params(&mut self) -> Result<Vec<String>, ParseError> {
        if !self.take(&TokenKind::Lt) {
            return Ok(Vec::new());
        }
        let mut params = Vec::new();
        loop {
            let (name, span) = self.expect_ident("expected a generic parameter name")?;
            if params.contains(&name) {
                return Err(ParseError {
                    span,
                    message: format!("generic parameter '{}' is repeated", name),
                });
            }
            params.push(name);
            if !self.take(&TokenKind::Comma) {
                break;
            }
        }
        self.expect_type_gt("expected '>' after generic parameters")?;
        Ok(params)
    }

    fn range_bound(&mut self) -> Result<i128, ParseError> {
        let negative = self.take(&TokenKind::Minus);
        let token = self.next().clone();
        let TokenKind::Number(raw) = token.kind else {
            return Err(ParseError {
                span: token.span,
                message: "range bounds must be integer literals".to_owned(),
            });
        };
        let parsed = self.integer(raw, token.span, negative)?;
        if let ExprKind::Integer {
            magnitude,
            negative,
            ..
        } = parsed.kind
        {
            if magnitude > i128::MAX as u128 + u128::from(negative) {
                return Err(ParseError {
                    span: token.span,
                    message: "range bound is too large to represent".to_owned(),
                });
            }
            Ok(if negative {
                if magnitude == i128::MAX as u128 + 1 {
                    i128::MIN
                } else {
                    -(magnitude as i128)
                }
            } else {
                magnitude as i128
            })
        } else {
            unreachable!()
        }
    }

    fn block(&mut self) -> Result<Block, ParseError> {
        if self.block_depth > EXPRESSION_NESTING_LIMIT {
            return Err(ParseError {
                span: self.peek().span,
                message: format!("expression nesting limit of {EXPRESSION_NESTING_LIMIT} exceeded"),
            });
        }
        self.block_depth += 1;
        let start = self
            .expect(&TokenKind::LBrace, "expected '{' to start a block")?
            .span;
        let mut statements = Vec::new();
        let mut tail = None;
        self.skip_separators();
        while !self.at(&TokenKind::RBrace) && !self.at(&TokenKind::Eof) {
            let parsed = self.statement_candidate()?;
            match parsed {
                Candidate::Statement(stmt) => statements.push(stmt),
                Candidate::Expression(expr) => {
                    let had_separator = self.skip_separators() > 0;
                    if self.at(&TokenKind::RBrace) {
                        tail = Some(Box::new(expr));
                        break;
                    }
                    if !had_separator {
                        return Err(self.error_here("expected a newline or ';' between statements"));
                    }
                    statements.push(Stmt {
                        span: expr.span,
                        kind: StmtKind::Expr(expr),
                    });
                    continue;
                }
            }
            let had_separator = self.skip_separators() > 0;
            if !self.at(&TokenKind::RBrace) && !had_separator {
                return Err(self.error_here("expected a newline or ';' between statements"));
            }
        }
        self.expect(&TokenKind::RBrace, "expected '}' to close this block")?;
        let block = Block {
            statements,
            tail,
            span: start,
        };
        self.block_depth -= 1;
        Ok(block)
    }

    fn statement_candidate(&mut self) -> Result<Candidate, ParseError> {
        if self.word_is("for")
            || self.word_is("break")
            || self.word_is("continue")
            || self.word_is("expect")
            || self.word_is("discard")
            || self.at(&TokenKind::LBrace)
            || self.word_is("let")
            || self.word_is("var")
            || self.word_is("return")
        {
            self.keyword_statement_candidate()
        } else {
            self.expression_statement_candidate()
        }
    }

    fn keyword_statement_candidate(&mut self) -> Result<Candidate, ParseError> {
        if self.word_is("for") {
            return Ok(Candidate::Statement(self.for_statement()?));
        }
        if self.word_is("break") || self.word_is("continue") {
            let token = self.next().clone();
            return Ok(Candidate::Statement(Stmt {
                span: token.span,
                kind: if matches!(&token.kind, TokenKind::Ident(word) if word == "break") {
                    StmtKind::Break
                } else {
                    StmtKind::Continue
                },
            }));
        }
        if self.word_is("expect") {
            let start = self.next().clone();
            if self.at(&TokenKind::Newline) || self.at(&TokenKind::Semicolon) {
                return Err(self.error_here("expected a bool expression after 'expect'"));
            }
            let first = self.pos;
            let value = self.expression(0)?;
            let end = self.tokens[self.pos.saturating_sub(1)].end_offset;
            let begin = self.tokens[first].start_offset;
            let expression_source = self.source.get(begin..end).unwrap_or("").trim_start();
            return Ok(Candidate::Statement(Stmt {
                span: start.span,
                kind: StmtKind::Expect {
                    value,
                    source: format!("expect {expression_source}"),
                },
            }));
        }
        if self.word_is("discard") {
            let start = self.next().span;
            let value = self.expression(0)?;
            return Ok(Candidate::Statement(Stmt {
                span: start,
                kind: StmtKind::Discard(value),
            }));
        }
        if self.at(&TokenKind::LBrace) {
            return Ok(Candidate::Statement(Stmt {
                span: self.peek().span,
                kind: StmtKind::Block(self.block()?),
            }));
        }
        if self.word_is("let") || self.word_is("var") {
            let mutable = self.word_is("var");
            let start = self.next().span;
            let (name, _) = self.expect_ident("expected a binding name after 'let' or 'var'")?;
            let annotation = if self.take(&TokenKind::Colon) {
                Some(self.type_name()?)
            } else {
                None
            };
            let value = if self.take(&TokenKind::Eq) {
                self.expression(0)?
            } else if annotation.is_some()
                && (self.at(&TokenKind::Newline)
                    || self.at(&TokenKind::Semicolon)
                    || self.at(&TokenKind::RBrace))
            {
                Expr {
                    kind: ExprKind::Call {
                        name: "default".to_owned(),
                        call_span: start,
                        args: Vec::new(),
                    },
                    span: start,
                }
            } else {
                return Err(self.error_here(
                    "expected '=' and an initial value; an omitted value needs an explicit type with a valid default",
                ));
            };
            return Ok(Candidate::Statement(Stmt {
                span: start,
                kind: StmtKind::Let {
                    mutable,
                    name,
                    annotation,
                    value,
                },
            }));
        }
        if self.word_is("return") {
            let start = self.next().span;
            let value = if self.at(&TokenKind::Newline)
                || self.at(&TokenKind::Semicolon)
                || self.at(&TokenKind::RBrace)
            {
                None
            } else {
                Some(self.expression(0)?)
            };
            return Ok(Candidate::Statement(Stmt {
                span: start,
                kind: StmtKind::Return(value),
            }));
        }

        unreachable!("keyword statement dispatch did not match")
    }

    fn expression_statement_candidate(&mut self) -> Result<Candidate, ParseError> {
        let expression = self.expression(0)?;
        self.finish_expression_statement_candidate(expression)
    }

    fn finish_expression_statement_candidate(
        &mut self,
        expression: Expr,
    ) -> Result<Candidate, ParseError> {
        let assignment = match self.peek().kind {
            TokenKind::Eq => Some(AssignOp::Set),
            TokenKind::PlusEq => Some(AssignOp::Add),
            TokenKind::MinusEq => Some(AssignOp::Sub),
            TokenKind::StarEq => Some(AssignOp::Mul),
            TokenKind::SlashEq => Some(AssignOp::Div),
            TokenKind::PercentEq => Some(AssignOp::Rem),
            TokenKind::ShrEq => Some(AssignOp::Shr),
            _ => None,
        };
        if let Some(op) = assignment {
            let span = expression.span;
            let target = match &expression.kind {
                ExprKind::Name(_)
                | ExprKind::Field { .. }
                | ExprKind::Index { .. }
                | ExprKind::GridIndex { .. } => expression,
                _ => {
                    return Err(ParseError {
                        span,
                        message: "the left side of an assignment must be a variable name"
                            .to_owned(),
                    });
                }
            };
            let operator_span = self.next().span;
            let value = self.expression(0)?;
            return Ok(Candidate::Statement(Stmt {
                span,
                kind: StmtKind::Assign {
                    target,
                    op,
                    operator_span,
                    value,
                },
            }));
        }
        if matches!(
            &expression.kind,
            ExprKind::If {
                else_block: None,
                ..
            }
        ) {
            let span = expression.span;
            return Ok(Candidate::Statement(Stmt {
                span,
                kind: StmtKind::Expr(expression),
            }));
        }
        Ok(Candidate::Expression(expression))
    }

    fn for_statement(&mut self) -> Result<Stmt, ParseError> {
        let start = self.expect_word("for", "expected 'for'")?.span;
        let (name, _) = self.expect_ident("expected a counter name after 'for'")?;
        let index_name = if self.take(&TokenKind::Comma) {
            Some(self.expect_ident("expected an index name after ','")?.0)
        } else {
            None
        };
        let second_index_name = if self.take(&TokenKind::Comma) {
            Some(
                self.expect_ident("expected a second index name after ','")?
                    .0,
            )
        } else {
            None
        };
        if self.take(&TokenKind::Comma) {
            return Err(self.error_here("collection loops support at most three bindings"));
        }
        let annotation = if self.take(&TokenKind::Colon) {
            Some(self.type_name()?)
        } else {
            None
        };
        self.expect_word("in", "expected 'in' after the loop counter")?;
        let first = self.expression(0)?;
        self.skip_newlines();
        let inclusive = self.take(&TokenKind::RangeInclusive);
        let is_range = inclusive || self.take(&TokenKind::Range);
        if is_range {
            if index_name.is_some() || second_index_name.is_some() {
                return Err(ParseError {
                    span: start,
                    message: "range loops have one counter; use 'for value, index in collection' for collection iteration".to_owned(),
                });
            }
            let allow_struct_literals = self.allow_struct_literals;
            self.allow_struct_literals = false;
            let end = self.expression(0);
            self.allow_struct_literals = allow_struct_literals;
            let end = end?;
            self.skip_newlines();
            let body = self.block()?;
            Ok(Stmt {
                kind: StmtKind::For {
                    name,
                    annotation,
                    start: first,
                    end,
                    inclusive,
                    body,
                },
                span: start,
            })
        } else {
            if annotation.is_some() {
                return Err(ParseError {
                    span: start,
                    message: "collection loop bindings take their element type from the collection; remove the annotation".to_owned(),
                });
            }
            let body = self.block()?;
            Ok(Stmt {
                kind: StmtKind::ForEach {
                    name,
                    index_name,
                    second_index_name,
                    collection: first,
                    body,
                },
                span: start,
            })
        }
    }

    fn expression(&mut self, min_precedence: u8) -> Result<Expr, ParseError> {
        if self.expression_depth >= EXPRESSION_PARSER_STACK_LIMIT {
            return Err(ParseError {
                span: self.peek().span,
                message: format!("expression nesting limit of {EXPRESSION_NESTING_LIMIT} exceeded"),
            });
        }
        let check_tree_depth = self.expression_depth == 0;
        self.expression_depth += 1;
        let parsed = self.expression_inner(min_precedence);
        self.expression_depth -= 1;
        if check_tree_depth {
            if let Ok(expr) = &parsed {
                if let Some(span) = expression_nesting_exceeded(expr, EXPRESSION_NESTING_LIMIT) {
                    return Err(ParseError {
                        span,
                        message: format!(
                            "expression nesting limit of {EXPRESSION_NESTING_LIMIT} exceeded"
                        ),
                    });
                }
            }
        }
        parsed
    }

    fn expression_inner(&mut self, min_precedence: u8) -> Result<Expr, ParseError> {
        let mut left = self.prefix()?;
        loop {
            let Some((op, precedence)) = binary_op(&self.peek().kind) else {
                break;
            };
            if precedence < min_precedence {
                break;
            }
            let op_span = self.next().span;
            let right = self.expression(if op == BinaryOp::Coalesce {
                precedence
            } else {
                precedence + 1
            })?;
            left = Expr {
                kind: ExprKind::Binary {
                    op,
                    operator_span: op_span,
                    left: Box::new(left),
                    right: Box::new(right),
                },
                span: op_span,
            };
        }
        Ok(left)
    }

    fn prefix(&mut self) -> Result<Expr, ParseError> {
        self.skip_newlines();
        let token = self.next().clone();
        let span = token.span;
        match token.kind {
            TokenKind::Minus => self.prefix_negation_postfix(span),
            TokenKind::Bang => self.prefix_not_postfix(span),
            TokenKind::LParen => self.parenthesized_postfix(span),
            TokenKind::Ident(name) if name == "if" => self.if_postfix(span),
            TokenKind::Ident(name) if name == "match" => self.match_postfix(span),
            TokenKind::Ident(name) if name == "return" => self.return_postfix(span),
            TokenKind::Ident(name)
                if name == "b"
                    && matches!(self.peek().kind, TokenKind::String(_))
                    && self.peek().span.line == span.line
                    && self.peek().span.col == span.col + 1 =>
            {
                let TokenKind::String(value) = self.next().kind.clone() else {
                    unreachable!()
                };
                self.postfix(Expr {
                    kind: ExprKind::ByteString(value.into_bytes()),
                    span,
                })
            }
            kind => self.prefix_leaf_postfix(kind, span),
        }
    }

    fn prefix_negation_postfix(&mut self, span: Span) -> Result<Expr, ParseError> {
        let expr = self.prefix_negation(span)?;
        self.postfix(expr)
    }

    fn prefix_not_postfix(&mut self, span: Span) -> Result<Expr, ParseError> {
        let expr = self.prefix_not(span)?;
        self.postfix(expr)
    }

    fn parenthesized_postfix(&mut self, span: Span) -> Result<Expr, ParseError> {
        let expr = self.parenthesized_expression(span)?;
        self.postfix(expr)
    }

    fn if_postfix(&mut self, span: Span) -> Result<Expr, ParseError> {
        let expr = self.if_expression(span)?;
        self.postfix(expr)
    }

    fn match_postfix(&mut self, span: Span) -> Result<Expr, ParseError> {
        let expr = self.match_expression(span)?;
        self.postfix(expr)
    }

    fn return_postfix(&mut self, span: Span) -> Result<Expr, ParseError> {
        let expr = self.return_expression(span)?;
        self.postfix(expr)
    }

    fn prefix_leaf_postfix(&mut self, kind: TokenKind, span: Span) -> Result<Expr, ParseError> {
        let expr = self.prefix_leaf(kind, span)?;
        self.postfix(expr)
    }

    fn prefix_negation(&mut self, span: Span) -> Result<Expr, ParseError> {
        if let TokenKind::Number(raw) = self.peek().kind.clone() {
            let _number_span = self.next().span;
            self.integer(raw, span, true).map(|mut expr| {
                expr.span = span;
                expr
            })
        } else {
            let value = self.expression(11)?;
            Ok(Expr {
                kind: ExprKind::Unary {
                    op: UnaryOp::Neg,
                    operator_span: span,
                    value: Box::new(value),
                },
                span,
            })
        }
    }

    fn prefix_not(&mut self, span: Span) -> Result<Expr, ParseError> {
        let value = self.expression(11)?;
        Ok(Expr {
            kind: ExprKind::Unary {
                op: UnaryOp::Not,
                operator_span: span,
                value: Box::new(value),
            },
            span,
        })
    }

    fn return_expression(&mut self, span: Span) -> Result<Expr, ParseError> {
        let value = if self.at(&TokenKind::Newline)
            || self.at(&TokenKind::Semicolon)
            || self.at(&TokenKind::RBrace)
            || self.at(&TokenKind::Comma)
        {
            None
        } else {
            Some(Box::new(self.expression(0)?))
        };
        Ok(Expr {
            kind: ExprKind::Return(value),
            span,
        })
    }

    fn prefix_leaf(&mut self, kind: TokenKind, span: Span) -> Result<Expr, ParseError> {
        Ok(match kind {
            TokenKind::Number(raw) => self.integer(raw, span, false)?,
            TokenKind::String(value) => Expr {
                kind: ExprKind::ByteString(value.into_bytes()),
                span,
            },
            TokenKind::Ident(name) if name == "true" => Expr {
                kind: ExprKind::Bool(true),
                span,
            },
            TokenKind::Ident(name) if name == "false" => Expr {
                kind: ExprKind::Bool(false),
                span,
            },
            TokenKind::Ident(name) if name == "fn" => {
                return Err(ParseError {
                    span,
                    message:
                        "anonymous functions are not supported; use a named top-level function"
                            .to_owned(),
                });
            }
            TokenKind::Ident(name) if name == "break" || name == "continue" => Expr {
                kind: ExprKind::LoopExit(name == "break"),
                span,
            },
            TokenKind::Ident(name) => Expr {
                kind: ExprKind::Name(name),
                span,
            },
            _ => {
                return Err(ParseError {
                    span,
                    message: "expected a value, a function call, or an if expression".to_owned(),
                });
            }
        })
    }

    fn parenthesized_expression(&mut self, span: Span) -> Result<Expr, ParseError> {
        if self.take(&TokenKind::RParen) {
            return Ok(Expr {
                kind: ExprKind::Unit,
                span,
            });
        }
        if matches!((&self.peek().kind, &self.peek_n(1).kind), (TokenKind::Ident(name), TokenKind::RParen)
            if matches!(name.as_str(), "int" | "long" | "bool")
                || name.chars().next().is_some_and(char::is_uppercase))
        {
            return self.cast_expression(span);
        }
        self.grouped_expression(span)
    }

    fn cast_expression(&mut self, span: Span) -> Result<Expr, ParseError> {
        let ty = self.type_name()?;
        self.expect(&TokenKind::RParen, "expected ')' after the cast type")?;
        self.skip_newlines();
        let value = self.prefix()?;
        Ok(Expr {
            kind: ExprKind::Cast {
                ty,
                cast_span: span,
                value: Box::new(value),
            },
            span,
        })
    }

    fn postfix(&mut self, mut expr: Expr) -> Result<Expr, ParseError> {
        loop {
            if self.at(&TokenKind::LBracket) {
                expr = self.postfix_index(expr)?;
            } else if self.at(&TokenKind::LParen) {
                expr = self.postfix_call(expr)?;
            } else if self.allow_struct_literals
                && self.at(&TokenKind::LBrace)
                && self.can_start_struct_literal(&expr)
            {
                expr = self.postfix_struct_literal(expr)?;
            } else if self.at(&TokenKind::Question) {
                expr = self.postfix_try(expr)?;
            } else if self.at(&TokenKind::QuestionDot) {
                expr = self.postfix_optional_call(expr)?;
            } else if self.at(&TokenKind::Dot) {
                expr = self.postfix_dot(expr)?;
            } else {
                break;
            }
        }
        Ok(expr)
    }

    #[inline(never)]
    fn postfix_index(&mut self, expr: Expr) -> Result<Expr, ParseError> {
        self.expect(&TokenKind::LBracket, "expected '['")?;
        let index = self.expression(0)?;
        let index_span = index.span;
        let span = expr.span;
        if self.take(&TokenKind::Comma) {
            self.skip_newlines();
            let y = self.expression(0)?;
            self.expect(&TokenKind::RBracket, "expected ']' after the grid indexes")?;
            Ok(Expr {
                kind: ExprKind::GridIndex {
                    receiver: Box::new(expr),
                    x: Box::new(index),
                    y: Box::new(y),
                    x_span: index_span,
                },
                span,
            })
        } else {
            self.expect(&TokenKind::RBracket, "expected ']' after the index")?;
            Ok(Expr {
                kind: ExprKind::Index {
                    receiver: Box::new(expr),
                    index: Box::new(index),
                    index_span,
                },
                span,
            })
        }
    }

    #[inline(never)]
    fn postfix_call(&mut self, expr: Expr) -> Result<Expr, ParseError> {
        self.expect(&TokenKind::LParen, "expected '('")?;
        let args = self.arguments_after_lparen()?;
        let old = expr;
        Ok(match old.kind {
            ExprKind::Name(name) => Expr {
                kind: ExprKind::Call {
                    name,
                    call_span: old.span,
                    args,
                },
                span: old.span,
            },
            ExprKind::QualifiedCase {
                enum_name,
                case_name,
                case_span,
                ..
            } => Expr {
                kind: ExprKind::QualifiedCase {
                    enum_name,
                    case_name,
                    case_span,
                    args,
                },
                span: old.span,
            },
            callee => Expr {
                kind: ExprKind::IndirectCall {
                    callee: Box::new(Expr {
                        kind: callee,
                        span: old.span,
                    }),
                    args,
                },
                span: old.span,
            },
        })
    }

    #[inline(never)]
    fn can_start_struct_literal(&self, expr: &Expr) -> bool {
        matches!(
            &expr.kind,
            ExprKind::Name(name)
                if matches!(name.as_str(), "list" | "pool" | "map" | "set" | "queue" | "ring")
                    || name.chars().next().is_some_and(char::is_uppercase)
        )
    }

    #[inline(never)]
    fn postfix_struct_literal(&mut self, expr: Expr) -> Result<Expr, ParseError> {
        let name = match &expr.kind {
            ExprKind::Name(name)
                if matches!(
                    name.as_str(),
                    "list" | "pool" | "map" | "set" | "queue" | "ring"
                ) || name.chars().next().is_some_and(char::is_uppercase) =>
            {
                Some(name.clone())
            }
            _ => None,
        };
        let name = name.expect("struct literal start was validated");
        if matches!(
            name.as_str(),
            "list" | "pool" | "map" | "set" | "queue" | "ring"
        ) {
            self.expect(&TokenKind::LBrace, "expected '{' after a collection name")?;
            self.skip_separators();
            if !self.at(&TokenKind::RBrace) {
                let message = match name.as_str() {
                    "list" => "list literals start empty; push values after construction",
                    "pool" => "pool literals start empty; add values after construction",
                    "map" => "map literals start empty; set values after construction",
                    "set" => "set literals start empty; add values after construction",
                    "queue" => "queue literals start empty; push values after construction",
                    "ring" => "ring literals start empty; push values after construction",
                    _ => unreachable!(),
                };
                return Err(self.error_here(message));
            }
            let kind = match name.as_str() {
                "list" => ExprKind::ListLiteral,
                "pool" => ExprKind::PoolLiteral,
                "map" => ExprKind::MapLiteral,
                "set" => ExprKind::SetLiteral,
                "queue" => ExprKind::QueueLiteral,
                "ring" => ExprKind::RingLiteral,
                _ => unreachable!(),
            };
            self.expect(
                &TokenKind::RBrace,
                &format!("expected '}}' after the empty {name} literal"),
            )?;
            Ok(Expr {
                kind,
                span: expr.span,
            })
        } else {
            let fields = self.struct_init_fields()?;
            Ok(Expr {
                kind: ExprKind::StructInit { name, fields },
                span: expr.span,
            })
        }
    }

    #[inline(never)]
    fn postfix_try(&mut self, expr: Expr) -> Result<Expr, ParseError> {
        self.expect(&TokenKind::Question, "expected '?' after this expression")?;
        let span = expr.span;
        Ok(Expr {
            kind: ExprKind::Try(Box::new(expr)),
            span,
        })
    }

    #[inline(never)]
    fn postfix_optional_call(&mut self, expr: Expr) -> Result<Expr, ParseError> {
        self.expect(&TokenKind::QuestionDot, "expected '?.'")?;
        let (name, method_span) = self.expect_ident("expected a function name after '?.'")?;
        self.expect(
            &TokenKind::LParen,
            "expected '(' after the optional call name",
        )?;
        let args = self.arguments_after_lparen()?;
        let span = expr.span;
        Ok(Expr {
            kind: ExprKind::OptionalCall {
                receiver: Box::new(expr),
                name,
                method_span,
                args,
            },
            span,
        })
    }

    #[inline(never)]
    fn postfix_dot(&mut self, expr: Expr) -> Result<Expr, ParseError> {
        self.expect(&TokenKind::Dot, "expected '.'")?;
        let (method, method_span) = self.expect_ident("expected a method name after '.'")?;
        let qualifier = match &expr.kind {
            ExprKind::Name(name) => Some(name.clone()),
            _ => None,
        };
        let is_type_qualifier = qualifier
            .as_deref()
            .and_then(|name| name.chars().next())
            .is_some_and(char::is_uppercase);
        if method == "fit" && self.take(&TokenKind::Lt) {
            let ty = self.type_name()?;
            self.expect_type_gt("expected '>' after the fit type")?;
            self.expect(&TokenKind::LParen, "expected '()' after the fit type")?;
            self.expect(&TokenKind::RParen, "fit takes no arguments")?;
            let span = expr.span;
            return Ok(Expr {
                kind: ExprKind::Fit {
                    value: Box::new(expr),
                    ty,
                    method_span,
                },
                span,
            });
        }
        if self.take(&TokenKind::LParen) {
            let args = self.arguments_after_lparen()?;
            let span = expr.span;
            let is_builtin_method = matches!(
                method.as_str(),
                "to_long"
                    | "ok"
                    | "unwrap"
                    | "is_none"
                    | "is_some"
                    | "is_ok"
                    | "is_err"
                    | "len"
                    | "count"
                    | "peek"
                    | "width"
                    | "height"
                    | "add"
                    | "set"
                    | "get"
                    | "contains"
                    | "push"
                    | "pop"
                    | "insert"
                    | "remove"
                    | "clear"
            );
            if let Some(enum_name) = qualifier.filter(|_| !is_builtin_method && is_type_qualifier) {
                Ok(Expr {
                    kind: ExprKind::QualifiedCase {
                        enum_name,
                        case_name: method,
                        case_span: method_span,
                        args,
                    },
                    span,
                })
            } else if method == "to_long" && args.is_empty() {
                Ok(Expr {
                    kind: ExprKind::ToLong {
                        value: Box::new(expr),
                        method_span,
                    },
                    span,
                })
            } else {
                Ok(Expr {
                    kind: ExprKind::MethodCall {
                        receiver: Box::new(expr),
                        name: method,
                        method_span,
                        args,
                    },
                    span,
                })
            }
        } else {
            let span = expr.span;
            Ok(Expr {
                kind: ExprKind::Field {
                    receiver: Box::new(expr),
                    name: method,
                    field_span: method_span,
                },
                span,
            })
        }
    }

    fn grouped_expression(&mut self, span: Span) -> Result<Expr, ParseError> {
        self.parenthesis_depth += 1;
        if self.parenthesis_depth > EXPRESSION_NESTING_LIMIT {
            self.parenthesis_depth -= 1;
            return Err(ParseError {
                span,
                message: format!("expression nesting limit of {EXPRESSION_NESTING_LIMIT} exceeded"),
            });
        }
        let parsed = (|| {
            let inner = self.expression(0)?;
            self.expect(&TokenKind::RParen, "expected ')' after this expression")?;
            Ok(Expr { span, ..inner })
        })();
        self.parenthesis_depth -= 1;
        parsed
    }

    fn arguments_after_lparen(&mut self) -> Result<Vec<Expr>, ParseError> {
        let mut args = Vec::new();
        self.skip_newlines();
        if !self.at(&TokenKind::RParen) {
            loop {
                args.push(self.expression(0)?);
                self.skip_newlines();
                if !self.take(&TokenKind::Comma) {
                    break;
                }
                self.skip_newlines();
                if self.at(&TokenKind::RParen) {
                    break;
                }
            }
        }
        self.expect(&TokenKind::RParen, "expected ')' after the arguments")?;
        Ok(args)
    }

    fn struct_init_fields(&mut self) -> Result<Vec<StructInitField>, ParseError> {
        self.expect(&TokenKind::LBrace, "expected '{' to start a struct literal")?;
        self.skip_separators();
        let mut fields = Vec::new();
        while !self.at(&TokenKind::RBrace) && !self.at(&TokenKind::Eof) {
            let (name, span) = self.expect_ident("expected a field name in the struct literal")?;
            let value = if self.take(&TokenKind::Colon) {
                self.expression(0)?
            } else {
                Expr {
                    kind: ExprKind::Name(name.clone()),
                    span,
                }
            };
            fields.push(StructInitField { name, value, span });
            let separated = self.skip_separators() > 0;
            if self.take(&TokenKind::Comma) {
                self.skip_separators();
            } else if !self.at(&TokenKind::RBrace) && !separated {
                return Err(self.error_here("expected a comma or newline between struct fields"));
            }
        }
        self.expect(
            &TokenKind::RBrace,
            "expected '}' to close the struct literal",
        )?;
        Ok(fields)
    }

    fn match_expression(&mut self, span: Span) -> Result<Expr, ParseError> {
        let scrutinee = self.expression(0)?;
        self.skip_newlines();
        self.expect(&TokenKind::LBrace, "expected '{' after the match value")?;
        self.skip_separators();
        let mut arms = Vec::new();
        while !self.at(&TokenKind::RBrace) && !self.at(&TokenKind::Eof) {
            let arm_span = self.peek().span;
            let pattern = self.pattern()?;
            self.expect(
                &TokenKind::FatArrow,
                "expected '=>' after the match pattern",
            )?;
            self.skip_newlines();
            let body = if self.at(&TokenKind::LBrace) {
                self.block()?
            } else {
                let value = self.expression(0)?;
                Block {
                    statements: Vec::new(),
                    tail: Some(Box::new(value)),
                    span: arm_span,
                }
            };
            arms.push(MatchArm {
                pattern,
                body,
                span: arm_span,
            });
            let separated = self.skip_separators() > 0;
            if self.take(&TokenKind::Comma) {
                self.skip_separators();
            } else if !self.at(&TokenKind::RBrace) && !separated {
                return Err(self.error_here("expected a comma or newline between match arms"));
            }
        }
        self.expect(&TokenKind::RBrace, "expected '}' to close the match")?;
        Ok(Expr {
            kind: ExprKind::Match {
                scrutinee: Box::new(scrutinee),
                arms,
            },
            span,
        })
    }

    fn pattern(&mut self) -> Result<Pattern, ParseError> {
        let token = self.next().clone();
        match token.kind {
            TokenKind::Number(raw) => Ok(Pattern::Integer(self.integer(raw, token.span, false)?)),
            TokenKind::Minus => {
                if let TokenKind::Number(raw) = self.peek().kind.clone() {
                    self.next();
                    Ok(Pattern::Integer(self.integer(raw, token.span, true)?))
                } else {
                    Err(ParseError {
                        span: token.span,
                        message: "expected an integer literal after '-' in a pattern".to_owned(),
                    })
                }
            }
            TokenKind::Ident(name) if name == "_" => Ok(Pattern::Wildcard),
            TokenKind::Ident(name) if name == "true" => Ok(Pattern::Bool(true, token.span)),
            TokenKind::Ident(name) if name == "false" => Ok(Pattern::Bool(false, token.span)),
            TokenKind::Ident(first) => {
                let (enum_name, name, name_span) = if self.take(&TokenKind::Dot) {
                    let (case_name, case_span) =
                        self.expect_ident("expected an enum case after '.'")?;
                    (Some(first), case_name, case_span)
                } else {
                    (None, first, token.span)
                };
                let mut bindings = Vec::new();
                if self.take(&TokenKind::LParen) {
                    self.skip_newlines();
                    if !self.at(&TokenKind::RParen) {
                        loop {
                            let (binding, binding_span) = self
                                .expect_ident("expected a payload name or '_' in this pattern")?;
                            bindings.push(if binding == "_" {
                                None
                            } else {
                                Some((binding, binding_span))
                            });
                            self.skip_newlines();
                            if !self.take(&TokenKind::Comma) {
                                break;
                            }
                            self.skip_newlines();
                            if self.at(&TokenKind::RParen) {
                                break;
                            }
                        }
                    }
                    self.expect(&TokenKind::RParen, "expected ')' after pattern payload")?;
                }
                Ok(Pattern::Case {
                    enum_name,
                    name,
                    name_span,
                    bindings,
                })
            }
            _ => Err(ParseError {
                span: token.span,
                message: "expected an enum case, bool or integer literal, or '_' pattern"
                    .to_owned(),
            }),
        }
    }

    fn if_expression(&mut self, span: Span) -> Result<Expr, ParseError> {
        let condition = self.expression(0)?;
        let then_block = self.block()?;
        let saved = self.pos;
        self.skip_newlines();
        let else_block = if self.word_is("else") {
            self.next();
            self.skip_newlines();
            if self.at(&TokenKind::LBrace) {
                Some(self.block()?)
            } else if self.word_is("if") {
                let if_span = self.next().span;
                let nested = self.if_expression(if_span)?;
                Some(Block {
                    statements: Vec::new(),
                    tail: Some(Box::new(nested)),
                    span: if_span,
                })
            } else {
                return Err(self.error_here("expected a block or another 'if' after 'else'"));
            }
        } else {
            self.pos = saved;
            None
        };
        Ok(Expr {
            kind: ExprKind::If {
                condition: Box::new(condition),
                then_block,
                else_block,
            },
            span,
        })
    }

    fn integer(&self, raw: String, span: Span, negative: bool) -> Result<Expr, ParseError> {
        let long_suffix = raw.ends_with('L') || raw.ends_with('l');
        let mut digits = raw.as_str();
        if long_suffix {
            digits = &digits[..digits.len() - 1];
        }
        let cleaned: String = digits.chars().filter(|c| *c != '_').collect();
        let (base, payload) = if cleaned.starts_with("0x") || cleaned.starts_with("0X") {
            (16, &cleaned[2..])
        } else if cleaned.starts_with("0b") || cleaned.starts_with("0B") {
            (2, &cleaned[2..])
        } else {
            (10, cleaned.as_str())
        };
        let magnitude = u128::from_str_radix(payload, base).map_err(|_| ParseError {
            span,
            message: "integer literal is too large to represent; use a smaller value".to_owned(),
        })?;
        Ok(Expr {
            kind: ExprKind::Integer {
                magnitude,
                negative,
                long_suffix,
            },
            span,
        })
    }

    fn skip_newlines(&mut self) {
        while self.at(&TokenKind::Newline) {
            self.pos += 1;
        }
    }

    fn skip_separators(&mut self) -> usize {
        let mut n = 0;
        while self.at(&TokenKind::Newline) || self.at(&TokenKind::Semicolon) {
            self.pos += 1;
            n += 1;
        }
        n
    }

    fn require_separator_or_eof(&self) -> Result<(), ParseError> {
        if self.at(&TokenKind::Newline)
            || self.at(&TokenKind::Semicolon)
            || self.at(&TokenKind::Eof)
        {
            Ok(())
        } else {
            Err(self.error_here("expected a newline or ';' after the function"))
        }
    }

    fn expect_word(&mut self, word: &str, message: &str) -> Result<Token, ParseError> {
        if self.word_is(word) {
            Ok(self.next().clone())
        } else {
            Err(self.error_here(message))
        }
    }

    fn expect_ident(&mut self, message: &str) -> Result<(String, Span), ParseError> {
        let token = self.next().clone();
        if let TokenKind::Ident(name) = token.kind {
            Ok((name, token.span))
        } else {
            Err(ParseError {
                span: token.span,
                message: message.to_owned(),
            })
        }
    }

    fn expect(&mut self, kind: &TokenKind, message: &str) -> Result<Token, ParseError> {
        if self.at(kind) {
            Ok(self.next().clone())
        } else {
            Err(self.error_here(message))
        }
    }

    fn expect_type_gt(&mut self, message: &str) -> Result<Token, ParseError> {
        let token = self.peek().clone();
        let split_count = match &token.kind {
            TokenKind::Shr => Some(2),
            TokenKind::ShrEq => Some(3),
            _ => None,
        };
        if let Some(split_count) = split_count {
            let pieces = (0..split_count)
                .map(|index| Token {
                    kind: if index < 2 {
                        TokenKind::Gt
                    } else {
                        TokenKind::Eq
                    },
                    span: Span {
                        col: token.span.col + index,
                        ..token.span
                    },
                    start_offset: token.start_offset + index,
                    end_offset: token.start_offset + index + 1,
                })
                .collect::<Vec<_>>();
            self.tokens.splice(self.pos..=self.pos, pieces);
        }
        self.expect(&TokenKind::Gt, message)
    }

    fn take(&mut self, kind: &TokenKind) -> bool {
        if self.at(kind) {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn at(&self, kind: &TokenKind) -> bool {
        &self.peek().kind == kind
    }

    fn word_is(&self, word: &str) -> bool {
        matches!(&self.peek().kind, TokenKind::Ident(actual) if actual == word)
    }

    fn next(&mut self) -> &Token {
        let i = self.pos.min(self.tokens.len() - 1);
        self.pos = (self.pos + 1).min(self.tokens.len() - 1);
        &self.tokens[i]
    }

    fn peek(&self) -> &Token {
        self.peek_n(0)
    }

    fn peek_n(&self, n: usize) -> &Token {
        &self.tokens[(self.pos + n).min(self.tokens.len() - 1)]
    }

    fn error_here(&self, message: &str) -> ParseError {
        ParseError {
            span: self.peek().span,
            message: message.to_owned(),
        }
    }
}

enum NestingTask<'a> {
    Expr(&'a Expr, usize),
    Block(&'a Block, usize),
    Type(&'a TypeAst, usize),
}

fn expression_nesting_exceeded(root: &Expr, limit: usize) -> Option<Span> {
    let root_depth = if matches!(&root.kind, ExprKind::Call { name, .. } if name == "print") {
        0
    } else {
        1
    };
    let mut pending = vec![NestingTask::Expr(root, root_depth)];
    while let Some(task) = pending.pop() {
        match task {
            NestingTask::Expr(expr, depth) => {
                let has_nested_expression = matches!(
                    &expr.kind,
                    ExprKind::Call { .. }
                        | ExprKind::IndirectCall { .. }
                        | ExprKind::QualifiedCase { .. }
                        | ExprKind::MethodCall { .. }
                        | ExprKind::Index { .. }
                        | ExprKind::OptionalCall { .. }
                        | ExprKind::Field { .. }
                        | ExprKind::StructInit { .. }
                        | ExprKind::GridIndex { .. }
                        | ExprKind::Fit { .. }
                        | ExprKind::Try(_)
                        | ExprKind::Return(_)
                        | ExprKind::Match { .. }
                        | ExprKind::ToLong { .. }
                        | ExprKind::Cast { .. }
                        | ExprKind::Unary { .. }
                        | ExprKind::Binary { .. }
                        | ExprKind::If { .. }
                );
                if has_nested_expression && depth > limit {
                    return Some(expr.span);
                }
                let child_depth = depth + usize::from(has_nested_expression);
                match &expr.kind {
                    ExprKind::Call { args, .. } | ExprKind::QualifiedCase { args, .. } => {
                        pending.extend(args.iter().map(|arg| NestingTask::Expr(arg, child_depth)));
                    }
                    ExprKind::IndirectCall { callee, args } => {
                        pending.push(NestingTask::Expr(callee, child_depth));
                        pending.extend(args.iter().map(|arg| NestingTask::Expr(arg, child_depth)));
                    }
                    ExprKind::MethodCall { receiver, args, .. }
                    | ExprKind::OptionalCall { receiver, args, .. } => {
                        pending.push(NestingTask::Expr(receiver, child_depth));
                        pending.extend(args.iter().map(|arg| NestingTask::Expr(arg, child_depth)));
                    }
                    ExprKind::Index {
                        receiver, index, ..
                    } => {
                        pending.push(NestingTask::Expr(receiver, child_depth));
                        pending.push(NestingTask::Expr(index, child_depth));
                    }
                    ExprKind::Field { receiver, .. } => {
                        pending.push(NestingTask::Expr(receiver, child_depth));
                    }
                    ExprKind::StructInit { fields, .. } => {
                        pending.extend(
                            fields
                                .iter()
                                .map(|field| NestingTask::Expr(&field.value, child_depth)),
                        );
                    }
                    ExprKind::GridIndex { receiver, x, y, .. } => {
                        pending.push(NestingTask::Expr(receiver, child_depth));
                        pending.push(NestingTask::Expr(x, child_depth));
                        pending.push(NestingTask::Expr(y, child_depth));
                    }
                    ExprKind::Fit { value, ty, .. } => {
                        pending.push(NestingTask::Expr(value, child_depth));
                        pending.push(NestingTask::Type(ty, child_depth));
                    }
                    ExprKind::Cast { value, ty, .. } => {
                        pending.push(NestingTask::Expr(value, child_depth));
                        pending.push(NestingTask::Type(ty, child_depth));
                    }
                    ExprKind::Try(value)
                    | ExprKind::ToLong { value, .. }
                    | ExprKind::Unary { value, .. } => {
                        pending.push(NestingTask::Expr(value, child_depth));
                    }
                    ExprKind::Return(Some(value)) => {
                        pending.push(NestingTask::Expr(value, child_depth));
                    }
                    ExprKind::Match { scrutinee, arms } => {
                        pending.push(NestingTask::Expr(scrutinee, child_depth));
                        pending.extend(arms.iter().map(|arm| NestingTask::Block(&arm.body, depth)));
                    }
                    ExprKind::Binary { left, right, .. } => {
                        pending.push(NestingTask::Expr(left, child_depth));
                        pending.push(NestingTask::Expr(right, child_depth));
                    }
                    ExprKind::If {
                        condition,
                        then_block,
                        else_block,
                    } => {
                        pending.push(NestingTask::Expr(condition, child_depth));
                        pending.push(NestingTask::Block(then_block, depth));
                        if let Some(block) = else_block {
                            pending.push(NestingTask::Block(block, depth));
                        }
                    }
                    ExprKind::Unit
                    | ExprKind::Integer { .. }
                    | ExprKind::Bool(_)
                    | ExprKind::ByteString(_)
                    | ExprKind::Name(_)
                    | ExprKind::ListLiteral
                    | ExprKind::PoolLiteral
                    | ExprKind::MapLiteral
                    | ExprKind::SetLiteral
                    | ExprKind::QueueLiteral
                    | ExprKind::RingLiteral
                    | ExprKind::Return(None)
                    | ExprKind::LoopExit(_) => {}
                }
            }
            NestingTask::Block(block, depth) => {
                let child_depth = depth + 1;
                if let Some(tail) = &block.tail {
                    pending.push(NestingTask::Expr(tail, child_depth));
                }
                for statement in &block.statements {
                    match &statement.kind {
                        StmtKind::Let {
                            value, annotation, ..
                        } => {
                            pending.push(NestingTask::Expr(value, child_depth));
                            if let Some(ty) = annotation {
                                pending.push(NestingTask::Type(ty, child_depth));
                            }
                        }
                        StmtKind::Expr(value)
                        | StmtKind::Discard(value)
                        | StmtKind::Expect { value, .. } => {
                            pending.push(NestingTask::Expr(value, child_depth));
                        }
                        StmtKind::Assign { target, value, .. } => {
                            pending.push(NestingTask::Expr(target, child_depth));
                            pending.push(NestingTask::Expr(value, child_depth));
                        }
                        StmtKind::Return(Some(value)) => {
                            pending.push(NestingTask::Expr(value, child_depth));
                        }
                        StmtKind::For {
                            start,
                            end,
                            body,
                            annotation,
                            ..
                        } => {
                            pending.push(NestingTask::Expr(start, child_depth));
                            pending.push(NestingTask::Expr(end, child_depth));
                            pending.push(NestingTask::Block(body, child_depth));
                            if let Some(ty) = annotation {
                                pending.push(NestingTask::Type(ty, child_depth));
                            }
                        }
                        StmtKind::ForEach {
                            collection, body, ..
                        } => {
                            pending.push(NestingTask::Expr(collection, child_depth));
                            pending.push(NestingTask::Block(body, child_depth));
                        }
                        StmtKind::Block(block) => {
                            pending.push(NestingTask::Block(block, child_depth));
                        }
                        StmtKind::Return(None) | StmtKind::Break | StmtKind::Continue => {}
                    }
                }
            }
            NestingTask::Type(ty, depth) => {
                let child_depth = depth + 1;
                pending.extend(
                    ty.args
                        .iter()
                        .map(|nested| NestingTask::Type(nested, child_depth)),
                );
                pending.extend(
                    ty.const_args
                        .iter()
                        .chain(&ty.array_caps)
                        .map(|expr| NestingTask::Expr(expr, child_depth)),
                );
                if let Some(function) = &ty.function {
                    pending.extend(
                        function
                            .params
                            .iter()
                            .map(|param| NestingTask::Type(&param.ty, child_depth)),
                    );
                    if let Some(result) = &function.result {
                        pending.push(NestingTask::Type(result, child_depth));
                    }
                }
            }
        }
    }
    None
}

enum Candidate {
    Statement(Stmt),
    Expression(Expr),
}

fn binary_op(kind: &TokenKind) -> Option<(BinaryOp, u8)> {
    Some(match kind {
        TokenKind::QuestionQuestion => (BinaryOp::Coalesce, 0),
        TokenKind::OrOr => (BinaryOp::Or, 1),
        TokenKind::AndAnd => (BinaryOp::And, 2),
        TokenKind::Or => (BinaryOp::BitOr, 3),
        TokenKind::Caret => (BinaryOp::BitXor, 4),
        TokenKind::And => (BinaryOp::BitAnd, 5),
        TokenKind::EqEq => (BinaryOp::Eq, 6),
        TokenKind::BangEq => (BinaryOp::Ne, 6),
        TokenKind::Lt => (BinaryOp::Lt, 7),
        TokenKind::Le => (BinaryOp::Le, 7),
        TokenKind::Gt => (BinaryOp::Gt, 7),
        TokenKind::Ge => (BinaryOp::Ge, 7),
        TokenKind::Shl => (BinaryOp::Shl, 8),
        TokenKind::Shr => (BinaryOp::Shr, 8),
        TokenKind::Plus => (BinaryOp::Add, 9),
        TokenKind::Minus => (BinaryOp::Sub, 9),
        TokenKind::WrapPlus => (BinaryOp::WrapAdd, 9),
        TokenKind::WrapMinus => (BinaryOp::WrapSub, 9),
        TokenKind::Star => (BinaryOp::Mul, 10),
        TokenKind::Slash => (BinaryOp::Div, 10),
        TokenKind::Percent => (BinaryOp::Rem, 10),
        TokenKind::WrapStar => (BinaryOp::WrapMul, 10),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lexer::lex;

    #[test]
    fn block_keeps_tail_expression_and_continued_operator() {
        let source = "fn value(a: int) -> int {\n let x = a +\n 2\n x\n}\nfn main() {}";
        let parsed = parse(lex(source, 0).unwrap(), source).unwrap();
        let body = &parsed.functions[0].body;
        assert_eq!(body.statements.len(), 1);
        assert!(body.tail.is_some());
        let StmtKind::Let { value, .. } = &body.statements[0].kind else {
            panic!("expected let statement")
        };
        assert!(matches!(
            value.kind,
            ExprKind::Binary {
                op: BinaryOp::Add,
                ..
            }
        ));
    }

    #[test]
    fn final_if_without_else_is_a_statement() {
        let source = "fn main() { if true { print(1) } }";
        let parsed = parse(lex(source, 0).unwrap(), source).unwrap();
        let body = &parsed.functions[0].body;
        assert!(body.tail.is_none());
        assert!(matches!(
            body.statements[0].kind,
            StmtKind::Expr(Expr {
                kind: ExprKind::If {
                    else_block: None,
                    ..
                },
                ..
            })
        ));
    }
}
