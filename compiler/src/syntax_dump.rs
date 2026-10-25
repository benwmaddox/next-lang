use std::fmt::Write;

use crate::ast::*;
use crate::lexer::{Token, TokenKind};

pub const MAX_TREE_NODES: usize = 2_000_000;
pub const MAX_TREE_EDGES: usize = 2_000_000;

#[derive(Clone, Copy, Debug)]
pub struct TreeLimit {
    pub nodes: usize,
    pub edges: usize,
}

pub fn token_dump(file_name: &str, source: &str, tokens: &[Token]) -> String {
    let mut out = String::new();
    writeln!(out, "file {}", quote(file_name)).unwrap();
    for token in tokens {
        let text = source
            .get(token.start_offset..token.end_offset)
            .unwrap_or("");
        writeln!(
            out,
            "{} {} {} {} {} {}",
            token_kind(&token.kind),
            token.start_offset,
            token.end_offset - token.start_offset,
            token.span.line,
            token.span.col,
            quote(text)
        )
        .unwrap();
    }
    out
}

pub fn tree_dump(
    file_name: &str,
    source_len: usize,
    program: &Program,
) -> Result<(String, usize, usize), TreeLimit> {
    let mut writer = TreeWriter {
        out: String::new(),
        nodes: 0,
        edges: 0,
    };
    writeln!(writer.out, "file {}", quote(file_name)).unwrap();
    writer.row(
        0,
        Span {
            start_offset: 0,
            end_offset: source_len,
            ..Span::default()
        },
        "Program",
        "",
    )?;

    let mut items = Vec::new();
    items.extend(program.enums.iter().map(|item| TopItem::Enum(item)));
    items.extend(program.structs.iter().map(|item| TopItem::Struct(item)));
    items.extend(program.aliases.iter().map(|item| TopItem::Alias(item)));
    items.extend(program.constants.iter().map(|item| TopItem::Const(item)));
    items.extend(program.globals.iter().map(|item| TopItem::Global(item)));
    items.extend(program.functions.iter().map(|item| TopItem::Function(item)));
    items.extend(program.tests.iter().map(|item| TopItem::Test(item)));
    items.sort_by_key(TopItem::start_offset);
    for item in items {
        match item {
            TopItem::Enum(item) => writer.enum_decl(item, 1)?,
            TopItem::Struct(item) => writer.struct_decl(item, 1)?,
            TopItem::Alias(item) => writer.alias_decl(item, 1)?,
            TopItem::Const(item) => writer.const_decl(item, 1)?,
            TopItem::Global(item) => writer.global_decl(item, 1)?,
            TopItem::Function(item) => writer.function(item, 1)?,
            TopItem::Test(item) => writer.test(item, 1)?,
        }
    }
    Ok((writer.out, writer.nodes, writer.edges))
}

enum TopItem<'a> {
    Enum(&'a EnumDecl),
    Struct(&'a StructDecl),
    Alias(&'a TypeAliasDecl),
    Const(&'a ConstDecl),
    Global(&'a GlobalDecl),
    Function(&'a Function),
    Test(&'a Test),
}

impl TopItem<'_> {
    fn start_offset(&self) -> usize {
        match self {
            Self::Enum(item) => item.span.start_offset,
            Self::Struct(item) => item.span.start_offset,
            Self::Alias(item) => item.span.start_offset,
            Self::Const(item) => item.span.start_offset,
            Self::Global(item) => item.span.start_offset,
            Self::Function(item) => item.span.start_offset,
            Self::Test(item) => item.span.start_offset,
        }
    }
}

struct TreeWriter {
    out: String,
    nodes: usize,
    edges: usize,
}

impl TreeWriter {
    fn row(&mut self, depth: usize, span: Span, kind: &str, fields: &str) -> Result<(), TreeLimit> {
        self.nodes += 1;
        if self.nodes > MAX_TREE_NODES {
            return Err(TreeLimit {
                nodes: self.nodes,
                edges: self.edges,
            });
        }
        if depth > 0 {
            self.edges += 1;
            if self.edges > MAX_TREE_EDGES {
                return Err(TreeLimit {
                    nodes: self.nodes,
                    edges: self.edges,
                });
            }
        }
        let indentation = "  ".repeat(depth);
        if fields.is_empty() {
            writeln!(
                self.out,
                "{indentation}{kind} {}..{}",
                span.start_offset, span.end_offset
            )
            .unwrap();
        } else {
            writeln!(
                self.out,
                "{indentation}{kind} {}..{} {fields}",
                span.start_offset, span.end_offset
            )
            .unwrap();
        }
        Ok(())
    }

    fn enum_decl(&mut self, item: &EnumDecl, depth: usize) -> Result<(), TreeLimit> {
        self.row(
            depth,
            item.span,
            "Enum",
            &format!("name={}", quote(&item.name)),
        )?;
        for case in &item.cases {
            self.row(
                depth + 1,
                case.span,
                "EnumCase",
                &format!("name={}", quote(&case.name)),
            )?;
            for ty in &case.payload {
                self.ty(ty, depth + 2, "PayloadType")?;
            }
        }
        Ok(())
    }

    fn struct_decl(&mut self, item: &StructDecl, depth: usize) -> Result<(), TreeLimit> {
        self.row(
            depth,
            item.span,
            "Struct",
            &format!(
                "name={} generics={}",
                quote(&item.name),
                string_array(&item.generic_params)
            ),
        )?;
        for field in &item.fields {
            self.row(
                depth + 1,
                field.span,
                "StructField",
                &format!("name={}", quote(&field.name)),
            )?;
            self.ty(&field.ty, depth + 2, "FieldType")?;
            if let Some(value) = &field.default {
                self.expr(value, depth + 2)?;
            }
        }
        Ok(())
    }

    fn alias_decl(&mut self, item: &TypeAliasDecl, depth: usize) -> Result<(), TreeLimit> {
        self.row(
            depth,
            item.span,
            "TypeAlias",
            &format!("name={}", quote(&item.name)),
        )?;
        self.ty(&item.ty, depth + 1, "AliasedType")
    }

    fn const_decl(&mut self, item: &ConstDecl, depth: usize) -> Result<(), TreeLimit> {
        self.row(
            depth,
            item.span,
            "Const",
            &format!("name={}", quote(&item.name)),
        )?;
        self.ty(&item.ty, depth + 1, "DeclaredType")?;
        self.expr(&item.value, depth + 1)
    }

    fn global_decl(&mut self, item: &GlobalDecl, depth: usize) -> Result<(), TreeLimit> {
        self.row(
            depth,
            item.span,
            "Global",
            &format!("name={} prefault={}", quote(&item.name), item.prefault),
        )?;
        self.ty(&item.ty, depth + 1, "DeclaredType")?;
        self.expr(&item.value, depth + 1)
    }

    fn function(&mut self, item: &Function, depth: usize) -> Result<(), TreeLimit> {
        self.row(
            depth,
            item.span,
            "Function",
            &format!(
                "name={} recursive={} generics={}",
                quote(&item.name),
                item.recursive,
                string_array(&item.generic_params)
            ),
        )?;
        for param in &item.params {
            self.param(param, depth + 1)?;
        }
        if let Some(result) = &item.result {
            self.ty(result, depth + 1, "ResultType")?;
        }
        self.block(&item.body, depth + 1)
    }

    fn test(&mut self, item: &Test, depth: usize) -> Result<(), TreeLimit> {
        self.row(
            depth,
            item.span,
            "Test",
            &format!("name={}", quote(&item.name)),
        )?;
        for param in &item.params {
            self.param(param, depth + 1)?;
        }
        self.block(&item.body, depth + 1)
    }

    fn param(&mut self, param: &Param, depth: usize) -> Result<(), TreeLimit> {
        self.row(
            depth,
            param.span,
            "Parameter",
            &format!(
                "name={} mode={}",
                quote(&param.name),
                if param.mode == ParamMode::Write {
                    "write"
                } else {
                    "read"
                }
            ),
        )?;
        self.ty(&param.ty, depth + 1, "ParameterType")
    }

    fn block(&mut self, block: &Block, depth: usize) -> Result<(), TreeLimit> {
        self.row(depth, block.span, "Block", "")?;
        for statement in &block.statements {
            self.statement(statement, depth + 1)?;
        }
        if let Some(tail) = &block.tail {
            self.expr(tail, depth + 1)?;
        }
        Ok(())
    }

    fn statement(&mut self, statement: &Stmt, depth: usize) -> Result<(), TreeLimit> {
        match &statement.kind {
            StmtKind::Let {
                mutable,
                name,
                annotation,
                value,
            } => {
                self.row(
                    depth,
                    statement.span,
                    "Let",
                    &format!("mutable={mutable} name={}", quote(name)),
                )?;
                if let Some(ty) = annotation {
                    self.ty(ty, depth + 1, "Annotation")?;
                }
                self.expr(value, depth + 1)
            }
            StmtKind::Assign {
                target, op, value, ..
            } => {
                self.row(
                    depth,
                    statement.span,
                    "Assign",
                    &format!("op={}", assign_op(*op)),
                )?;
                self.expr(target, depth + 1)?;
                self.expr(value, depth + 1)
            }
            StmtKind::Return(value) => {
                self.row(depth, statement.span, "ReturnStatement", "")?;
                if let Some(value) = value {
                    self.expr(value, depth + 1)?;
                }
                Ok(())
            }
            StmtKind::Expr(value) => {
                self.row(depth, statement.span, "ExpressionStatement", "")?;
                self.expr(value, depth + 1)
            }
            StmtKind::For {
                name,
                annotation,
                start,
                end,
                inclusive,
                body,
            } => {
                self.row(
                    depth,
                    statement.span,
                    "For",
                    &format!("name={} inclusive={inclusive}", quote(name)),
                )?;
                if let Some(ty) = annotation {
                    self.ty(ty, depth + 1, "Annotation")?;
                }
                self.expr(start, depth + 1)?;
                self.expr(end, depth + 1)?;
                self.block(body, depth + 1)
            }
            StmtKind::ForEach {
                name,
                index_name,
                second_index_name,
                collection,
                body,
            } => {
                let indexes = match (index_name, second_index_name) {
                    (None, None) => "[]".to_owned(),
                    (Some(first), None) => string_array(std::slice::from_ref(first)),
                    (Some(first), Some(second)) => string_array(&[first.clone(), second.clone()]),
                    (None, Some(second)) => string_array(std::slice::from_ref(second)),
                };
                self.row(
                    depth,
                    statement.span,
                    "ForEach",
                    &format!("name={} indexes={indexes}", quote(name)),
                )?;
                self.expr(collection, depth + 1)?;
                self.block(body, depth + 1)
            }
            StmtKind::Discard(value) => {
                self.row(depth, statement.span, "Discard", "")?;
                self.expr(value, depth + 1)
            }
            StmtKind::Break => self.row(depth, statement.span, "BreakStatement", ""),
            StmtKind::Continue => self.row(depth, statement.span, "ContinueStatement", ""),
            StmtKind::Expect { value, source } => {
                self.row(
                    depth,
                    statement.span,
                    "Expect",
                    &format!("source={}", quote(source)),
                )?;
                self.expr(value, depth + 1)
            }
            StmtKind::Block(block) => self.block(block, depth),
        }
    }

    fn ty(&mut self, ty: &TypeAst, depth: usize, label: &str) -> Result<(), TreeLimit> {
        let range = ty
            .range
            .map(|range| {
                format!(
                    "{}..{}{}",
                    range.lower,
                    if range.inclusive { "=" } else { "" },
                    range.upper
                )
            })
            .unwrap_or_else(|| "none".to_owned());
        self.row(
            depth,
            ty.span,
            label,
            &format!(
                "name={} range={} policy={}",
                quote(&ty.name),
                range,
                refine_policy(ty.policy)
            ),
        )?;

        let mut type_args = ty.args.iter().peekable();
        let mut const_args = ty.const_args.iter().peekable();
        if ty.name == "pool" {
            if let Some(arg) = type_args.next() {
                self.ty(arg, depth + 1, "TypeArgument")?;
            }
            if let Some(arg) = const_args.next() {
                self.expr(arg, depth + 1)?;
            }
            if let Some(arg) = type_args.next() {
                self.ty(arg, depth + 1, "TypeArgument")?;
            }
        } else {
            for arg in type_args {
                self.ty(arg, depth + 1, "TypeArgument")?;
            }
            for arg in const_args {
                self.expr(arg, depth + 1)?;
            }
        }
        if let Some(function) = &ty.function {
            self.function_type(function, depth + 1)?;
        }
        for capacity in &ty.array_caps {
            self.expr(capacity, depth + 1)?;
        }
        Ok(())
    }

    fn function_type(&mut self, ty: &FunctionTypeAst, depth: usize) -> Result<(), TreeLimit> {
        self.row(depth, ty.span, "FunctionType", "")?;
        for param in &ty.params {
            self.row(
                depth + 1,
                param.span,
                "FunctionTypeParameter",
                &format!(
                    "mode={}",
                    if param.mode == ParamMode::Write {
                        "write"
                    } else {
                        "read"
                    }
                ),
            )?;
            self.ty(&param.ty, depth + 2, "ParameterType")?;
        }
        if let Some(result) = &ty.result {
            self.ty(result, depth + 1, "ResultType")?;
        }
        for effect in &ty.effects {
            let (kind, path, span) = match effect {
                FunctionEffectAst::Out { span } => ("out", None, *span),
                FunctionEffectAst::Env { span } => ("env", None, *span),
                FunctionEffectAst::FsRead { span } => ("fs.read", None, *span),
                FunctionEffectAst::FsWrite { span } => ("fs.write", None, *span),
                FunctionEffectAst::Reads {
                    path, node_span, ..
                } => ("reads", Some(path.as_str()), *node_span),
                FunctionEffectAst::Writes {
                    path, node_span, ..
                } => ("writes", Some(path.as_str()), *node_span),
            };
            let fields = path
                .map(|path| format!("kind={kind} path={}", quote(path)))
                .unwrap_or_else(|| format!("kind={kind}"));
            self.row(depth + 1, span, "Effect", &fields)?;
        }
        Ok(())
    }

    fn expr(&mut self, expr: &Expr, depth: usize) -> Result<(), TreeLimit> {
        match &expr.kind {
            ExprKind::Unit => self.row(depth, expr.span, "Unit", ""),
            ExprKind::Integer {
                magnitude,
                negative,
                long_suffix,
            } => self.row(
                depth,
                expr.span,
                "Integer",
                &format!("magnitude={magnitude} negative={negative} long_suffix={long_suffix}"),
            ),
            ExprKind::Bool(value) => self.row(depth, expr.span, "Bool", &format!("value={value}")),
            ExprKind::ByteString(value) => {
                let string = std::str::from_utf8(value).expect("parsed source strings are UTF-8");
                self.row(
                    depth,
                    expr.span,
                    "ByteString",
                    &format!("value={}", quote(string)),
                )
            }
            ExprKind::Name(name) => {
                self.row(depth, expr.span, "Name", &format!("name={}", quote(name)))
            }
            ExprKind::Call { name, args, .. } => {
                self.row(depth, expr.span, "Call", &format!("name={}", quote(name)))?;
                self.exprs(args, depth + 1)
            }
            ExprKind::IndirectCall { callee, args } => {
                self.row(depth, expr.span, "IndirectCall", "")?;
                self.expr(callee, depth + 1)?;
                self.exprs(args, depth + 1)
            }
            ExprKind::QualifiedCase {
                enum_name,
                case_name,
                args,
                ..
            } => {
                self.row(
                    depth,
                    expr.span,
                    "QualifiedCase",
                    &format!("enum={} case={}", quote(enum_name), quote(case_name)),
                )?;
                self.exprs(args, depth + 1)
            }
            ExprKind::MethodCall {
                receiver,
                name,
                args,
                ..
            } => {
                self.row(
                    depth,
                    expr.span,
                    "MethodCall",
                    &format!("name={}", quote(name)),
                )?;
                self.expr(receiver, depth + 1)?;
                self.exprs(args, depth + 1)
            }
            ExprKind::Index {
                receiver, index, ..
            } => {
                self.row(depth, expr.span, "Index", "")?;
                self.expr(receiver, depth + 1)?;
                self.expr(index, depth + 1)
            }
            ExprKind::OptionalCall {
                receiver,
                name,
                args,
                ..
            } => {
                self.row(
                    depth,
                    expr.span,
                    "OptionalCall",
                    &format!("name={}", quote(name)),
                )?;
                self.expr(receiver, depth + 1)?;
                self.exprs(args, depth + 1)
            }
            ExprKind::Field { receiver, name, .. } => {
                self.row(depth, expr.span, "Field", &format!("name={}", quote(name)))?;
                self.expr(receiver, depth + 1)
            }
            ExprKind::StructInit { name, fields } => {
                self.row(
                    depth,
                    expr.span,
                    "StructInit",
                    &format!("name={}", quote(name)),
                )?;
                for field in fields {
                    self.row(
                        depth + 1,
                        field.span,
                        "InitializerField",
                        &format!("name={}", quote(&field.name)),
                    )?;
                    self.expr(&field.value, depth + 2)?;
                }
                Ok(())
            }
            ExprKind::ListLiteral => self.row(depth, expr.span, "ListLiteral", ""),
            ExprKind::PoolLiteral => self.row(depth, expr.span, "PoolLiteral", ""),
            ExprKind::MapLiteral => self.row(depth, expr.span, "MapLiteral", ""),
            ExprKind::SetLiteral => self.row(depth, expr.span, "SetLiteral", ""),
            ExprKind::QueueLiteral => self.row(depth, expr.span, "QueueLiteral", ""),
            ExprKind::RingLiteral => self.row(depth, expr.span, "RingLiteral", ""),
            ExprKind::GridIndex { receiver, x, y, .. } => {
                self.row(depth, expr.span, "GridIndex", "")?;
                self.expr(receiver, depth + 1)?;
                self.expr(x, depth + 1)?;
                self.expr(y, depth + 1)
            }
            ExprKind::Fit { value, ty, .. } => {
                self.row(depth, expr.span, "Fit", "")?;
                self.expr(value, depth + 1)?;
                self.ty(ty, depth + 1, "FitType")
            }
            ExprKind::Try(value) => {
                self.row(depth, expr.span, "Try", "")?;
                self.expr(value, depth + 1)
            }
            ExprKind::Return(value) => {
                self.row(depth, expr.span, "Return", "")?;
                if let Some(value) = value {
                    self.expr(value, depth + 1)?;
                }
                Ok(())
            }
            ExprKind::LoopExit(is_break) => self.row(
                depth,
                expr.span,
                "LoopExit",
                &format!("kind={}", if *is_break { "break" } else { "continue" }),
            ),
            ExprKind::Match { scrutinee, arms } => {
                self.row(depth, expr.span, "Match", "")?;
                self.expr(scrutinee, depth + 1)?;
                for arm in arms {
                    self.row(depth + 1, arm.span, "MatchArm", "")?;
                    self.pattern(&arm.pattern, arm.pattern_span, depth + 2)?;
                    self.block(&arm.body, depth + 2)?;
                }
                Ok(())
            }
            ExprKind::ToLong { value, .. } => {
                self.row(depth, expr.span, "ToLong", "")?;
                self.expr(value, depth + 1)
            }
            ExprKind::Cast { ty, value, .. } => {
                self.row(depth, expr.span, "Cast", "")?;
                self.ty(ty, depth + 1, "CastType")?;
                self.expr(value, depth + 1)
            }
            ExprKind::Unary { op, value, .. } => {
                self.row(depth, expr.span, "Unary", &format!("op={}", unary_op(*op)))?;
                self.expr(value, depth + 1)
            }
            ExprKind::Binary {
                op, left, right, ..
            } => {
                self.row(
                    depth,
                    expr.span,
                    "Binary",
                    &format!("op={}", binary_op(*op)),
                )?;
                self.expr(left, depth + 1)?;
                self.expr(right, depth + 1)
            }
            ExprKind::If {
                condition,
                then_block,
                else_block,
            } => {
                self.row(depth, expr.span, "If", "")?;
                self.expr(condition, depth + 1)?;
                self.block(then_block, depth + 1)?;
                if let Some(block) = else_block {
                    self.block(block, depth + 1)?;
                }
                Ok(())
            }
        }
    }

    fn exprs(&mut self, expressions: &[Expr], depth: usize) -> Result<(), TreeLimit> {
        for expr in expressions {
            self.expr(expr, depth)?;
        }
        Ok(())
    }

    fn pattern(&mut self, pattern: &Pattern, span: Span, depth: usize) -> Result<(), TreeLimit> {
        match pattern {
            Pattern::Wildcard => self.row(depth, span, "WildcardPattern", ""),
            Pattern::Integer(value) => self.expr(value, depth),
            Pattern::Bool(value, bool_span) => {
                self.row(depth, *bool_span, "BoolPattern", &format!("value={value}"))
            }
            Pattern::Case {
                enum_name,
                name,
                bindings,
                binding_spans,
                ..
            } => {
                let mut fields = format!("name={}", quote(name));
                if let Some(enum_name) = enum_name {
                    fields.push_str(&format!(" enum={}", quote(enum_name)));
                }
                self.row(depth, span, "CasePattern", &fields)?;
                for (binding, binding_span) in bindings.iter().zip(binding_spans) {
                    if let Some((name, binding_span)) = binding {
                        self.row(
                            depth + 1,
                            *binding_span,
                            "PatternBinding",
                            &format!("name={}", quote(name)),
                        )?;
                    } else {
                        self.row(depth + 1, *binding_span, "IgnoredPatternBinding", "")?;
                    }
                }
                Ok(())
            }
        }
    }
}

fn token_kind(kind: &TokenKind) -> &'static str {
    match kind {
        TokenKind::Ident(_) => "Ident",
        TokenKind::Number(_) => "Number",
        TokenKind::String(_) => "String",
        TokenKind::Newline => "Newline",
        TokenKind::LParen => "LParen",
        TokenKind::RParen => "RParen",
        TokenKind::LBrace => "LBrace",
        TokenKind::RBrace => "RBrace",
        TokenKind::LBracket => "LBracket",
        TokenKind::RBracket => "RBracket",
        TokenKind::Comma => "Comma",
        TokenKind::Colon => "Colon",
        TokenKind::Semicolon => "Semicolon",
        TokenKind::Dot => "Dot",
        TokenKind::Question => "Question",
        TokenKind::QuestionDot => "QuestionDot",
        TokenKind::QuestionQuestion => "QuestionQuestion",
        TokenKind::Range => "Range",
        TokenKind::RangeInclusive => "RangeInclusive",
        TokenKind::Arrow => "Arrow",
        TokenKind::FatArrow => "FatArrow",
        TokenKind::Plus => "Plus",
        TokenKind::Minus => "Minus",
        TokenKind::Star => "Star",
        TokenKind::Slash => "Slash",
        TokenKind::Percent => "Percent",
        TokenKind::WrapPlus => "WrapPlus",
        TokenKind::WrapMinus => "WrapMinus",
        TokenKind::WrapStar => "WrapStar",
        TokenKind::PlusEq => "PlusEq",
        TokenKind::MinusEq => "MinusEq",
        TokenKind::StarEq => "StarEq",
        TokenKind::SlashEq => "SlashEq",
        TokenKind::PercentEq => "PercentEq",
        TokenKind::ShrEq => "ShrEq",
        TokenKind::Eq => "Eq",
        TokenKind::EqEq => "EqEq",
        TokenKind::Bang => "Bang",
        TokenKind::BangEq => "BangEq",
        TokenKind::Lt => "Lt",
        TokenKind::Le => "Le",
        TokenKind::Gt => "Gt",
        TokenKind::Ge => "Ge",
        TokenKind::And => "And",
        TokenKind::AndAnd => "AndAnd",
        TokenKind::Or => "Or",
        TokenKind::OrOr => "OrOr",
        TokenKind::Caret => "Caret",
        TokenKind::Shl => "Shl",
        TokenKind::Shr => "Shr",
        TokenKind::Eof => "Eof",
    }
}

fn quote(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\0' => out.push_str("\\u0000"),
            ch if ch <= '\u{001f}' => write!(out, "\\u{:04x}", ch as u32).unwrap(),
            ch => out.push(ch),
        }
    }
    out.push('"');
    out
}

fn string_array(values: &[String]) -> String {
    format!(
        "[{}]",
        values
            .iter()
            .map(|value| quote(value))
            .collect::<Vec<_>>()
            .join(",")
    )
}

fn refine_policy(policy: RefinePolicy) -> &'static str {
    match policy {
        RefinePolicy::Checked => "checked",
        RefinePolicy::Wrap => "wrap",
        RefinePolicy::Clamp => "clamp",
    }
}

fn assign_op(op: AssignOp) -> &'static str {
    match op {
        AssignOp::Set => "=",
        AssignOp::Add => "+=",
        AssignOp::Sub => "-=",
        AssignOp::Mul => "*=",
        AssignOp::Div => "/=",
        AssignOp::Rem => "%=",
        AssignOp::Shr => ">>=",
    }
}

fn unary_op(op: UnaryOp) -> &'static str {
    match op {
        UnaryOp::Neg => "neg",
        UnaryOp::Not => "not",
    }
}

fn binary_op(op: BinaryOp) -> &'static str {
    match op {
        BinaryOp::Add => "add",
        BinaryOp::Sub => "sub",
        BinaryOp::Mul => "mul",
        BinaryOp::Div => "div",
        BinaryOp::Rem => "rem",
        BinaryOp::WrapAdd => "wrap_add",
        BinaryOp::WrapSub => "wrap_sub",
        BinaryOp::WrapMul => "wrap_mul",
        BinaryOp::Eq => "eq",
        BinaryOp::Ne => "ne",
        BinaryOp::Lt => "lt",
        BinaryOp::Le => "le",
        BinaryOp::Gt => "gt",
        BinaryOp::Ge => "ge",
        BinaryOp::And => "and",
        BinaryOp::Or => "or",
        BinaryOp::BitAnd => "bit_and",
        BinaryOp::BitOr => "bit_or",
        BinaryOp::BitXor => "bit_xor",
        BinaryOp::Shl => "shl",
        BinaryOp::Shr => "shr",
        BinaryOp::Coalesce => "coalesce",
    }
}
