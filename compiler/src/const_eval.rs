use crate::ast::{AssignOp, BinaryOp, ParamMode, RefinePolicy, Span, UnaryOp};
use crate::checker::CheckError;
use crate::typed::*;
use std::collections::HashMap;

const STEP_LIMIT: u64 = 10_000_000;
const CALL_DEPTH_LIMIT: usize = 10_000;

pub fn evaluate_constants(
    declarations: &[TConstExpr],
    functions: &[TFunction],
    call_graph: &[Vec<TCallEdge>],
    types: &[TType],
) -> Result<Vec<TConstant>, CheckError> {
    evaluate_constants_inner(declarations, functions, call_graph, types)
}

fn evaluate_constants_inner(
    declarations: &[TConstExpr],
    functions: &[TFunction],
    call_graph: &[Vec<TCallEdge>],
    types: &[TType],
) -> Result<Vec<TConstant>, CheckError> {
    if let Some((cycle, span)) = find_constant_cycle(declarations, functions, call_graph) {
        let names = cycle
            .iter()
            .map(|id| declarations[*id].name.clone())
            .collect::<Vec<_>>();
        return Err(CheckError {
            span,
            message: format!("constant dependency cycle: {}", names.join(" -> ")),
        });
    }
    for declaration in declarations {
        if let Some(problem) =
            expression_cacheability_problem(&declaration.expr, functions, call_graph, types)
        {
            let mut chain = vec![format!("constant {}", declaration.name)];
            chain.extend(problem.chain);
            return Err(CheckError {
                span: problem.span.unwrap_or(declaration.span),
                message: format!(
                    "constant '{}' is not cacheable: {}; call chain: {}",
                    declaration.name,
                    problem.reason,
                    chain.join(" -> ")
                ),
            });
        }
    }

    let mut evaluator = Evaluator {
        declarations,
        functions,
        types,
        values: vec![None; declarations.len()],
        states: vec![0; declarations.len()],
        active_constants: Vec::new(),
        constant_values: None,
        views: HashMap::new(),
        steps: 0,
        call_depth: 0,
    };
    for declaration in declarations {
        evaluator.eval_constant(declaration.id, declaration.span)?;
    }
    let result = Ok(declarations
        .iter()
        .map(|declaration| TConstant {
            id: declaration.id,
            name: declaration.name.clone(),
            ty: declaration.ty,
            value: evaluator.values[declaration.id]
                .clone()
                .expect("every constant was evaluated"),
            span: declaration.span,
        })
        .collect());
    result
}

pub fn evaluate_expression(
    name: &str,
    expr: &TExpr,
    functions: &[TFunction],
    call_graph: &[Vec<TCallEdge>],
    types: &[TType],
    constants: &[TConstant],
) -> Result<ConstValue, CheckError> {
    evaluate_expression_inner(name, expr, functions, call_graph, types, constants)
}

fn evaluate_expression_inner(
    name: &str,
    expr: &TExpr,
    functions: &[TFunction],
    call_graph: &[Vec<TCallEdge>],
    types: &[TType],
    constants: &[TConstant],
) -> Result<ConstValue, CheckError> {
    if let Some(problem) = expression_cacheability_problem(expr, functions, call_graph, types) {
        let mut chain = vec![format!("global {}", name)];
        chain.extend(problem.chain);
        return Err(CheckError {
            span: problem.span.unwrap_or(expr.span),
            message: format!(
                "global '{}' initializer is not constant: {}; call chain: {}",
                name,
                problem.reason,
                chain.join(" -> ")
            ),
        });
    }
    let values = constants
        .iter()
        .map(|constant| constant.value.clone())
        .collect::<Vec<_>>();
    let mut evaluator = Evaluator {
        declarations: &[],
        functions,
        types,
        values: Vec::new(),
        states: Vec::new(),
        active_constants: Vec::new(),
        constant_values: Some(&values),
        views: HashMap::new(),
        steps: 0,
        call_depth: 0,
    };
    match evaluator.eval_expr(expr, &mut Vec::new()) {
        Ok(Outcome::Value(value)) => Ok(value),
        Ok(Outcome::Return(_)) => Err(CheckError {
            span: expr.span,
            message: format!(
                "global '{}' initializer cannot return from compile-time evaluation",
                name
            ),
        }),
        Ok(Outcome::Break | Outcome::Continue) => Err(CheckError {
            span: expr.span,
            message: format!(
                "global '{}' initializer cannot exit a loop at top level",
                name
            ),
        }),
        Err(failure) => Err(CheckError {
            span: failure.span,
            message: format!(
                "global '{}' constant evaluation failed: {}",
                name, failure.message
            ),
        }),
    }
}

fn find_constant_cycle(
    declarations: &[TConstExpr],
    functions: &[TFunction],
    call_graph: &[Vec<TCallEdge>],
) -> Option<(Vec<usize>, Span)> {
    let mut state = vec![0u8; declarations.len()];
    let mut stack = Vec::new();
    fn visit(
        id: usize,
        declarations: &[TConstExpr],
        functions: &[TFunction],
        call_graph: &[Vec<TCallEdge>],
        state: &mut [u8],
        stack: &mut Vec<usize>,
    ) -> Option<(Vec<usize>, Span)> {
        state[id] = 1;
        stack.push(id);
        let mut references = Vec::new();
        collect_constant_references_expr(&declarations[id].expr, &mut references);
        let mut calls = Vec::new();
        let mut effects = Vec::new();
        collect_calls_expr(&declarations[id].expr, &mut calls, &mut effects);
        let mut visited = vec![false; functions.len()];
        for (target, _) in calls {
            collect_function_constant_references(
                target,
                functions,
                call_graph,
                &mut visited,
                &mut references,
            );
        }
        for (target, span) in references {
            if state[target] == 1 {
                let start = stack.iter().position(|entry| *entry == target).unwrap_or(0);
                let mut cycle = stack[start..].to_vec();
                cycle.push(target);
                return Some((cycle, span));
            }
            if state[target] == 0 {
                if let Some(cycle) =
                    visit(target, declarations, functions, call_graph, state, stack)
                {
                    return Some(cycle);
                }
            }
        }
        stack.pop();
        state[id] = 2;
        None
    }
    for id in 0..declarations.len() {
        if state[id] == 0 {
            if let Some(cycle) = visit(
                id,
                declarations,
                functions,
                call_graph,
                &mut state,
                &mut stack,
            ) {
                return Some(cycle);
            }
        }
    }
    None
}

fn collect_function_constant_references(
    id: usize,
    functions: &[TFunction],
    call_graph: &[Vec<TCallEdge>],
    visited: &mut [bool],
    references: &mut Vec<(usize, Span)>,
) {
    if visited[id] {
        return;
    }
    visited[id] = true;
    collect_constant_references_block(&functions[id].body, references);
    for edge in &call_graph[id] {
        collect_function_constant_references(
            edge.target,
            functions,
            call_graph,
            visited,
            references,
        );
    }
}

fn collect_constant_references_block(block: &TBlock, references: &mut Vec<(usize, Span)>) {
    for stmt in &block.statements {
        match &stmt.kind {
            TStmtKind::Let { value, .. }
            | TStmtKind::Assign { value, .. }
            | TStmtKind::Expr(value) => collect_constant_references_expr(value, references),
            TStmtKind::Return(value) => {
                if let Some(value) = value {
                    collect_constant_references_expr(value, references);
                }
            }
            TStmtKind::If {
                condition,
                then_block,
                else_block,
            } => {
                collect_constant_references_expr(condition, references);
                collect_constant_references_block(then_block, references);
                if let Some(other) = else_block {
                    collect_constant_references_block(other, references);
                }
            }
            TStmtKind::For {
                start, end, body, ..
            } => {
                collect_constant_references_expr(start, references);
                collect_constant_references_expr(end, references);
                collect_constant_references_block(body, references);
            }
            TStmtKind::ForEach {
                collection, body, ..
            } => {
                collect_constant_references_expr(collection, references);
                collect_constant_references_block(body, references);
            }
            TStmtKind::Discard(value) => collect_constant_references_expr(value, references),
            TStmtKind::Expect { kind, .. } => match kind {
                TExpectKind::Bool(value) => collect_constant_references_expr(value, references),
                TExpectKind::Compare { left, right, .. } => {
                    collect_constant_references_expr(left, references);
                    collect_constant_references_expr(right, references);
                }
                TExpectKind::StackPeak { .. } => {}
            },
            TStmtKind::Block(inner) => collect_constant_references_block(inner, references),
            TStmtKind::Break | TStmtKind::Continue => {}
        }
    }
    if let Some(tail) = &block.tail {
        collect_constant_references_expr(tail, references);
    }
}

fn collect_constant_references_expr(expr: &TExpr, references: &mut Vec<(usize, Span)>) {
    match &expr.kind {
        TExprKind::Constant(id) => references.push((*id, expr.span)),
        TExprKind::Call { args, .. } | TExprKind::Construct { args, .. } => {
            for arg in args {
                collect_constant_references_expr(arg, references);
            }
        }
        TExprKind::IndirectCall { callee, args, .. } => {
            collect_constant_references_expr(callee, references);
            for arg in args {
                collect_constant_references_expr(arg, references);
            }
        }
        TExprKind::Method { receiver, .. }
        | TExprKind::OptionalToLong(receiver)
        | TExprKind::Field { receiver, .. }
        | TExprKind::ToLong(receiver)
        | TExprKind::Convert {
            value: receiver, ..
        }
        | TExprKind::Fit {
            value: receiver, ..
        }
        | TExprKind::Try {
            value: receiver, ..
        }
        | TExprKind::AsciiUpper(receiver)
        | TExprKind::TextUpper(receiver)
        | TExprKind::AsciiCast(receiver)
        | TExprKind::BytesView(receiver)
        | TExprKind::BytesValidateUtf8(receiver)
        | TExprKind::TextConvert {
            value: receiver, ..
        }
        | TExprKind::Take(receiver)
        | TExprKind::Cast {
            value: receiver, ..
        }
        | TExprKind::Unary {
            value: receiver, ..
        } => collect_constant_references_expr(receiver, references),
        TExprKind::AsciiFormat { value, .. }
        | TExprKind::ParseInteger {
            receiver: value, ..
        } => collect_constant_references_expr(value, references),
        TExprKind::AsciiPad { value, width, .. } | TExprKind::AsciiZeroPad { value, width } => {
            collect_constant_references_expr(value, references);
            collect_constant_references_expr(width, references);
        }
        TExprKind::OptionalCall { receiver, args, .. } => {
            collect_constant_references_expr(receiver, references);
            for arg in args {
                collect_constant_references_expr(arg, references);
            }
        }
        TExprKind::Index {
            receiver,
            index,
            grid,
            ..
        } => {
            collect_constant_references_expr(receiver, references);
            collect_constant_references_expr(index, references);
            if let Some(grid) = grid {
                collect_constant_references_expr(&grid.x, references);
                collect_constant_references_expr(&grid.y, references);
            }
        }
        TExprKind::BytesIndex {
            receiver, index, ..
        } => {
            collect_constant_references_expr(receiver, references);
            collect_constant_references_expr(index, references);
        }
        TExprKind::Fill { value, .. } => collect_constant_references_expr(value, references),
        TExprKind::CollectionLiteral(values) => {
            for value in values {
                collect_constant_references_expr(value, references);
            }
        }
        TExprKind::AsciiSlice {
            receiver,
            start,
            end,
        }
        | TExprKind::TextSlice {
            receiver,
            start,
            end,
        }
        | TExprKind::BytesSlice {
            receiver,
            start,
            end,
        } => {
            collect_constant_references_expr(receiver, references);
            collect_constant_references_expr(start, references);
            collect_constant_references_expr(end, references);
        }
        TExprKind::CollectionOp { receiver, args, .. } => {
            collect_constant_references_expr(receiver, references);
            for arg in args {
                collect_constant_references_expr(arg, references);
            }
        }
        TExprKind::PoolOp { receiver, args, .. }
        | TExprKind::MapOp { receiver, args, .. }
        | TExprKind::SetOp { receiver, args, .. } => {
            collect_constant_references_expr(receiver, references);
            for arg in args {
                collect_constant_references_expr(arg, references);
            }
        }
        TExprKind::StructConstruct { fields } => {
            for (_, value) in fields {
                collect_constant_references_expr(value, references);
            }
        }
        TExprKind::Coalesce { option, fallback } => {
            collect_constant_references_expr(option, references);
            collect_constant_references_expr(fallback, references);
        }
        TExprKind::Match { scrutinee, arms } => {
            collect_constant_references_expr(scrutinee, references);
            for arm in arms {
                collect_constant_references_block(&arm.body, references);
            }
        }
        TExprKind::Return(value) => {
            if let Some(value) = value {
                collect_constant_references_expr(value, references);
            }
        }
        TExprKind::Binary { left, right, .. } => {
            collect_constant_references_expr(left, references);
            collect_constant_references_expr(right, references);
        }
        TExprKind::If {
            condition,
            then_block,
            else_block,
        } => {
            collect_constant_references_expr(condition, references);
            collect_constant_references_block(then_block, references);
            if let Some(other) = else_block {
                collect_constant_references_block(other, references);
            }
        }
        TExprKind::Unit
        | TExprKind::Integer(_)
        | TExprKind::Bool(_)
        | TExprKind::ByteString(_)
        | TExprKind::Local(_)
        | TExprKind::Global(_)
        | TExprKind::FunctionValue(_)
        | TExprKind::EmptyArray
        | TExprKind::EmptyList
        | TExprKind::EmptyPool
        | TExprKind::EmptyMap
        | TExprKind::EmptySet
        | TExprKind::EmptyGrid
        | TExprKind::EmptyQueue
        | TExprKind::EmptyRing
        | TExprKind::LoopExit(_)
        | TExprKind::AsciiEmpty
        | TExprKind::TextEmpty
        | TExprKind::BytesEmpty => {}
        TExprKind::AsciiFit { value, .. } => collect_constant_references_expr(value, references),
        TExprKind::AsciiTryAppend { receiver, argument }
        | TExprKind::TextTryAppend { receiver, argument }
        | TExprKind::BytesTryAppend { receiver, argument } => {
            collect_constant_references_expr(receiver, references);
            collect_constant_references_expr(argument, references);
        }
        TExprKind::BytesPush { receiver, byte, .. } => {
            collect_constant_references_expr(receiver, references);
            collect_constant_references_expr(byte, references);
        }
    }
}

struct CacheabilityProblem {
    reason: String,
    chain: Vec<String>,
    span: Option<Span>,
}

fn expression_cacheability_problem(
    expr: &TExpr,
    functions: &[TFunction],
    call_graph: &[Vec<TCallEdge>],
    types: &[TType],
) -> Option<CacheabilityProblem> {
    if expression_reads_global(expr) {
        return Some(CacheabilityProblem {
            reason: "compile-time evaluation cannot read global state".to_owned(),
            chain: vec!["global read".to_owned()],
            span: Some(expr.span),
        });
    }
    let mut calls = Vec::<(usize, Span)>::new();
    let mut effects = Vec::<(Span, &'static str)>::new();
    collect_calls_expr(expr, &mut calls, &mut effects);
    if let Some((span, effect)) = effects.first() {
        return Some(CacheabilityProblem {
            reason: "compile-time evaluation cannot reach an effect".to_owned(),
            chain: vec![(*effect).to_owned()],
            span: Some(*span),
        });
    }
    let mut memo = vec![None; functions.len()];
    for (id, span) in calls {
        if let Some((reason, chain)) =
            function_cacheability_problem(id, functions, call_graph, types, &mut memo)
        {
            return Some(CacheabilityProblem {
                reason,
                chain,
                span: Some(span),
            });
        }
    }
    None
}

fn expression_reads_global(expr: &TExpr) -> bool {
    fn block_reads(block: &TBlock) -> bool {
        block
            .statements
            .iter()
            .any(|statement| match &statement.kind {
                TStmtKind::Let { value, .. }
                | TStmtKind::Assign { value, .. }
                | TStmtKind::Expr(value)
                | TStmtKind::Discard(value) => expression_reads_global(value),
                TStmtKind::Return(value) => value.as_ref().is_some_and(expression_reads_global),
                TStmtKind::If {
                    condition,
                    then_block,
                    else_block,
                } => {
                    expression_reads_global(condition)
                        || block_reads(then_block)
                        || else_block.as_ref().is_some_and(block_reads)
                }
                TStmtKind::For {
                    start, end, body, ..
                } => {
                    expression_reads_global(start)
                        || expression_reads_global(end)
                        || block_reads(body)
                }
                TStmtKind::ForEach {
                    collection, body, ..
                } => expression_reads_global(collection) || block_reads(body),
                TStmtKind::Expect { kind, .. } => match kind {
                    TExpectKind::Bool(value) => expression_reads_global(value),
                    TExpectKind::Compare { left, right, .. } => {
                        expression_reads_global(left) || expression_reads_global(right)
                    }
                    TExpectKind::StackPeak { .. } => false,
                },
                TStmtKind::Block(inner) => block_reads(inner),
                TStmtKind::Break | TStmtKind::Continue => false,
            })
            || block.tail.as_deref().is_some_and(expression_reads_global)
    }
    match &expr.kind {
        TExprKind::Global(_) => true,
        TExprKind::Call { args, .. } | TExprKind::Construct { args, .. } => {
            args.iter().any(expression_reads_global)
        }
        TExprKind::IndirectCall { callee, args, .. } => {
            expression_reads_global(callee) || args.iter().any(expression_reads_global)
        }
        TExprKind::Method { receiver, .. }
        | TExprKind::OptionalToLong(receiver)
        | TExprKind::Field { receiver, .. }
        | TExprKind::ToLong(receiver)
        | TExprKind::Convert {
            value: receiver, ..
        }
        | TExprKind::Fit {
            value: receiver, ..
        }
        | TExprKind::Try {
            value: receiver, ..
        }
        | TExprKind::AsciiUpper(receiver)
        | TExprKind::TextUpper(receiver)
        | TExprKind::AsciiCast(receiver)
        | TExprKind::BytesView(receiver)
        | TExprKind::BytesValidateUtf8(receiver)
        | TExprKind::TextConvert {
            value: receiver, ..
        }
        | TExprKind::Take(receiver)
        | TExprKind::Cast {
            value: receiver, ..
        }
        | TExprKind::Unary {
            value: receiver, ..
        } => expression_reads_global(receiver),
        TExprKind::AsciiFormat { value, .. }
        | TExprKind::ParseInteger {
            receiver: value, ..
        } => expression_reads_global(value),
        TExprKind::AsciiPad { value, width, .. } | TExprKind::AsciiZeroPad { value, width } => {
            expression_reads_global(value) || expression_reads_global(width)
        }
        TExprKind::OptionalCall { receiver, args, .. } => {
            expression_reads_global(receiver) || args.iter().any(expression_reads_global)
        }
        TExprKind::Index {
            receiver,
            index,
            grid,
            ..
        } => {
            expression_reads_global(receiver)
                || expression_reads_global(index)
                || grid.as_ref().is_some_and(|grid| {
                    expression_reads_global(&grid.x) || expression_reads_global(&grid.y)
                })
        }
        TExprKind::BytesIndex {
            receiver, index, ..
        } => expression_reads_global(receiver) || expression_reads_global(index),
        TExprKind::Fill { value, .. } => expression_reads_global(value),
        TExprKind::CollectionLiteral(values) => values.iter().any(expression_reads_global),
        TExprKind::AsciiSlice {
            receiver,
            start,
            end,
        }
        | TExprKind::TextSlice {
            receiver,
            start,
            end,
        }
        | TExprKind::BytesSlice {
            receiver,
            start,
            end,
        } => {
            expression_reads_global(receiver)
                || expression_reads_global(start)
                || expression_reads_global(end)
        }
        TExprKind::AsciiFit { value, .. } => expression_reads_global(value),
        TExprKind::AsciiTryAppend { receiver, argument }
        | TExprKind::TextTryAppend { receiver, argument }
        | TExprKind::BytesTryAppend { receiver, argument } => {
            expression_reads_global(receiver) || expression_reads_global(argument)
        }
        TExprKind::BytesPush { receiver, byte, .. } => {
            expression_reads_global(receiver) || expression_reads_global(byte)
        }
        TExprKind::CollectionOp { receiver, args, .. }
        | TExprKind::PoolOp { receiver, args, .. }
        | TExprKind::MapOp { receiver, args, .. }
        | TExprKind::SetOp { receiver, args, .. } => {
            expression_reads_global(receiver) || args.iter().any(expression_reads_global)
        }
        TExprKind::StructConstruct { fields } => fields
            .iter()
            .any(|(_, value)| expression_reads_global(value)),
        TExprKind::Coalesce { option, fallback } => {
            expression_reads_global(option) || expression_reads_global(fallback)
        }
        TExprKind::Match { scrutinee, arms } => {
            expression_reads_global(scrutinee) || arms.iter().any(|arm| block_reads(&arm.body))
        }
        TExprKind::Return(value) => value.as_deref().is_some_and(expression_reads_global),
        TExprKind::Binary { left, right, .. } => {
            expression_reads_global(left) || expression_reads_global(right)
        }
        TExprKind::If {
            condition,
            then_block,
            else_block,
        } => {
            expression_reads_global(condition)
                || block_reads(then_block)
                || else_block.as_ref().is_some_and(block_reads)
        }
        TExprKind::Unit
        | TExprKind::Integer(_)
        | TExprKind::Bool(_)
        | TExprKind::ByteString(_)
        | TExprKind::Local(_)
        | TExprKind::Constant(_)
        | TExprKind::FunctionValue(_)
        | TExprKind::LoopExit(_)
        | TExprKind::EmptyArray
        | TExprKind::EmptyList
        | TExprKind::EmptyPool
        | TExprKind::EmptyMap
        | TExprKind::EmptySet
        | TExprKind::EmptyGrid
        | TExprKind::EmptyQueue
        | TExprKind::EmptyRing
        | TExprKind::AsciiEmpty
        | TExprKind::TextEmpty
        | TExprKind::BytesEmpty => false,
    }
}

fn block_reads_global(block: &TBlock) -> bool {
    block
        .statements
        .iter()
        .any(|statement| match &statement.kind {
            TStmtKind::Let { value, .. }
            | TStmtKind::Assign { value, .. }
            | TStmtKind::Expr(value)
            | TStmtKind::Discard(value) => expression_reads_global(value),
            TStmtKind::Return(value) => value.as_ref().is_some_and(expression_reads_global),
            TStmtKind::If {
                condition,
                then_block,
                else_block,
            } => {
                expression_reads_global(condition)
                    || block_reads_global(then_block)
                    || else_block.as_ref().is_some_and(block_reads_global)
            }
            TStmtKind::For {
                start, end, body, ..
            } => {
                expression_reads_global(start)
                    || expression_reads_global(end)
                    || block_reads_global(body)
            }
            TStmtKind::ForEach {
                collection, body, ..
            } => expression_reads_global(collection) || block_reads_global(body),
            TStmtKind::Expect { kind, .. } => match kind {
                TExpectKind::Bool(value) => expression_reads_global(value),
                TExpectKind::Compare { left, right, .. } => {
                    expression_reads_global(left) || expression_reads_global(right)
                }
                TExpectKind::StackPeak { .. } => false,
            },
            TStmtKind::Block(inner) => block_reads_global(inner),
            TStmtKind::Break | TStmtKind::Continue => false,
        })
        || block.tail.as_deref().is_some_and(expression_reads_global)
}

fn function_cacheability_problem(
    id: usize,
    functions: &[TFunction],
    call_graph: &[Vec<TCallEdge>],
    types: &[TType],
    memo: &mut [Option<Option<(String, Vec<String>)>>],
) -> Option<(String, Vec<String>)> {
    let _ = (types, memo);
    let mut pending = vec![id];
    let mut predecessor = vec![None; functions.len()];
    let mut seen = vec![false; functions.len()];
    seen[id] = true;
    while let Some(current) = pending.pop() {
        let function = &functions[current];
        let problem = if function
            .params
            .iter()
            .any(|param| param.mode == ParamMode::Write)
        {
            Some((
                "cacheable functions cannot have write parameters".to_owned(),
                "write parameter".to_owned(),
            ))
        } else if block_reads_global(&function.body) {
            Some((
                "cacheable functions cannot read global state".to_owned(),
                "global read".to_owned(),
            ))
        } else {
            let mut calls = Vec::new();
            let mut effects = Vec::<(Span, &'static str)>::new();
            collect_calls_block(&function.body, &mut calls, &mut effects);
            effects.first().map(|(_, effect)| {
                (
                    "compile-time evaluation cannot reach an effect".to_owned(),
                    (*effect).to_owned(),
                )
            })
        };
        if let Some((reason, detail)) = problem {
            let mut chain = vec![detail];
            let mut cursor = current;
            let mut path = vec![current];
            while let Some(previous) = predecessor[cursor] {
                path.push(previous);
                cursor = previous;
            }
            path.reverse();
            let mut names = path
                .into_iter()
                .map(|function| functions[function].name.clone())
                .collect::<Vec<_>>();
            names.append(&mut chain);
            return Some((reason, names));
        }
        let mut targets = call_graph[current]
            .iter()
            .map(|edge| edge.target)
            .collect::<Vec<_>>();
        let mut calls = Vec::new();
        let mut effects = Vec::<(Span, &'static str)>::new();
        collect_calls_block(&function.body, &mut calls, &mut effects);
        targets.extend(calls.into_iter().map(|(target, _)| target));
        targets.sort_unstable();
        targets.dedup();
        for target in targets {
            if target < functions.len() && !seen[target] {
                seen[target] = true;
                predecessor[target] = Some(current);
                pending.push(target);
            }
        }
    }
    None
}

fn collect_calls_block(
    block: &TBlock,
    calls: &mut Vec<(usize, Span)>,
    effects: &mut Vec<(Span, &'static str)>,
) {
    for stmt in &block.statements {
        match &stmt.kind {
            TStmtKind::Let { value, .. }
            | TStmtKind::Assign { value, .. }
            | TStmtKind::Expr(value) => collect_calls_expr(value, calls, effects),
            TStmtKind::Return(value) => {
                if let Some(value) = value {
                    collect_calls_expr(value, calls, effects);
                }
            }
            TStmtKind::If {
                condition,
                then_block,
                else_block,
            } => {
                collect_calls_expr(condition, calls, effects);
                collect_calls_block(then_block, calls, effects);
                if let Some(other) = else_block {
                    collect_calls_block(other, calls, effects);
                }
            }
            TStmtKind::For {
                start, end, body, ..
            } => {
                collect_calls_expr(start, calls, effects);
                collect_calls_expr(end, calls, effects);
                collect_calls_block(body, calls, effects);
            }
            TStmtKind::ForEach {
                collection, body, ..
            } => {
                collect_calls_expr(collection, calls, effects);
                collect_calls_block(body, calls, effects);
            }
            TStmtKind::Discard(value) => collect_calls_expr(value, calls, effects),
            TStmtKind::Expect { kind, .. } => match kind {
                TExpectKind::Bool(value) => collect_calls_expr(value, calls, effects),
                TExpectKind::Compare { left, right, .. } => {
                    collect_calls_expr(left, calls, effects);
                    collect_calls_expr(right, calls, effects);
                }
                TExpectKind::StackPeak { .. } => {}
            },
            TStmtKind::Block(inner) => collect_calls_block(inner, calls, effects),
            TStmtKind::Break | TStmtKind::Continue => {}
        }
    }
    if let Some(tail) = &block.tail {
        collect_calls_expr(tail, calls, effects);
    }
}

fn collect_calls_expr(
    expr: &TExpr,
    calls: &mut Vec<(usize, Span)>,
    effects: &mut Vec<(Span, &'static str)>,
) {
    match &expr.kind {
        TExprKind::Call { target, args, .. } => {
            match target {
                CallTarget::Function(id) => calls.push((*id, expr.span)),
                CallTarget::Print
                | CallTarget::OutWrite
                | CallTarget::OutLine
                | CallTarget::OutInt
                | CallTarget::OutLong => effects.push((expr.span, "out")),
                CallTarget::EnvArgs
                | CallTarget::EnvExit
                | CallTarget::ArgsCount
                | CallTarget::ArgsGet
                | CallTarget::ArgLength
                | CallTarget::ArgByte => effects.push((expr.span, "env")),
                CallTarget::FsRead | CallTarget::FsList | CallTarget::FsListWithExtension => {
                    effects.push((expr.span, "fs.read"))
                }
                CallTarget::FsWrite => effects.push((expr.span, "fs.write")),
                CallTarget::EnvFs
                | CallTarget::EnvOut
                | CallTarget::EnvErr
                | CallTarget::FsJoin => {}
                CallTarget::Min | CallTarget::Max | CallTarget::Abs | CallTarget::Clamp => {}
                CallTarget::Sort { .. } | CallTarget::SortBy { .. } => {
                    effects.push((expr.span, "sort"))
                }
                CallTarget::BinarySearch { .. } => {}
            }
            for arg in args {
                collect_calls_expr(arg, calls, effects);
            }
        }
        TExprKind::IndirectCall { callee, args, .. } => {
            collect_calls_expr(callee, calls, effects);
            for arg in args {
                collect_calls_expr(arg, calls, effects);
            }
        }
        TExprKind::Construct { args, .. } => {
            for arg in args {
                collect_calls_expr(arg, calls, effects);
            }
        }
        TExprKind::Method { receiver, .. }
        | TExprKind::OptionalToLong(receiver)
        | TExprKind::Field { receiver, .. }
        | TExprKind::ToLong(receiver) => collect_calls_expr(receiver, calls, effects),
        TExprKind::OptionalCall {
            receiver,
            function_id,
            args,
            ..
        } => {
            calls.push((*function_id, expr.span));
            collect_calls_expr(receiver, calls, effects);
            for arg in args {
                collect_calls_expr(arg, calls, effects);
            }
        }
        TExprKind::Index {
            receiver,
            index,
            grid,
            ..
        } => {
            collect_calls_expr(receiver, calls, effects);
            collect_calls_expr(index, calls, effects);
            if let Some(grid) = grid {
                collect_calls_expr(&grid.x, calls, effects);
                collect_calls_expr(&grid.y, calls, effects);
            }
        }
        TExprKind::BytesIndex {
            receiver, index, ..
        } => {
            collect_calls_expr(receiver, calls, effects);
            collect_calls_expr(index, calls, effects);
        }
        TExprKind::BytesValidateUtf8(value) => collect_calls_expr(value, calls, effects),
        TExprKind::TextTryAppend { receiver, argument }
        | TExprKind::BytesTryAppend { receiver, argument } => {
            collect_calls_expr(receiver, calls, effects);
            collect_calls_expr(argument, calls, effects);
        }
        TExprKind::BytesPush { receiver, byte, .. } => {
            collect_calls_expr(receiver, calls, effects);
            collect_calls_expr(byte, calls, effects);
        }
        TExprKind::Fill { value, .. } => collect_calls_expr(value, calls, effects),
        TExprKind::CollectionLiteral(values) => {
            for value in values {
                collect_calls_expr(value, calls, effects);
            }
        }
        TExprKind::AsciiSlice {
            receiver,
            start,
            end,
        }
        | TExprKind::TextSlice {
            receiver,
            start,
            end,
        }
        | TExprKind::BytesSlice {
            receiver,
            start,
            end,
        } => {
            collect_calls_expr(receiver, calls, effects);
            collect_calls_expr(start, calls, effects);
            collect_calls_expr(end, calls, effects);
        }
        TExprKind::CollectionOp { receiver, args, .. } => {
            collect_calls_expr(receiver, calls, effects);
            for arg in args {
                collect_calls_expr(arg, calls, effects);
            }
        }
        TExprKind::PoolOp { receiver, args, .. }
        | TExprKind::MapOp { receiver, args, .. }
        | TExprKind::SetOp { receiver, args, .. } => {
            collect_calls_expr(receiver, calls, effects);
            for arg in args {
                collect_calls_expr(arg, calls, effects);
            }
        }
        TExprKind::StructConstruct { fields } => {
            for (_, value) in fields {
                collect_calls_expr(value, calls, effects);
            }
        }
        TExprKind::Convert { value, .. }
        | TExprKind::Fit { value, .. }
        | TExprKind::Try { value, .. }
        | TExprKind::AsciiUpper(value)
        | TExprKind::TextUpper(value)
        | TExprKind::AsciiCast(value)
        | TExprKind::BytesView(value)
        | TExprKind::TextConvert { value, .. }
        | TExprKind::Take(value)
        | TExprKind::Cast { value, .. }
        | TExprKind::Unary { value, .. } => collect_calls_expr(value, calls, effects),
        TExprKind::AsciiFormat { value, .. }
        | TExprKind::ParseInteger {
            receiver: value, ..
        } => collect_calls_expr(value, calls, effects),
        TExprKind::AsciiPad { value, width, .. } | TExprKind::AsciiZeroPad { value, width } => {
            collect_calls_expr(value, calls, effects);
            collect_calls_expr(width, calls, effects);
        }
        TExprKind::AsciiFit { value, .. } => collect_calls_expr(value, calls, effects),
        TExprKind::AsciiTryAppend { receiver, argument } => {
            collect_calls_expr(receiver, calls, effects);
            collect_calls_expr(argument, calls, effects);
        }
        TExprKind::Coalesce { option, fallback } => {
            collect_calls_expr(option, calls, effects);
            collect_calls_expr(fallback, calls, effects);
        }
        TExprKind::Match { scrutinee, arms } => {
            collect_calls_expr(scrutinee, calls, effects);
            for arm in arms {
                collect_calls_block(&arm.body, calls, effects);
            }
        }
        TExprKind::Return(value) => {
            if let Some(value) = value {
                collect_calls_expr(value, calls, effects);
            }
        }
        TExprKind::Binary { left, right, .. } => {
            collect_calls_expr(left, calls, effects);
            collect_calls_expr(right, calls, effects);
        }
        TExprKind::If {
            condition,
            then_block,
            else_block,
        } => {
            collect_calls_expr(condition, calls, effects);
            collect_calls_block(then_block, calls, effects);
            if let Some(other) = else_block {
                collect_calls_block(other, calls, effects);
            }
        }
        TExprKind::Unit
        | TExprKind::Integer(_)
        | TExprKind::Bool(_)
        | TExprKind::ByteString(_)
        | TExprKind::Local(_)
        | TExprKind::Global(_)
        | TExprKind::Constant(_)
        | TExprKind::FunctionValue(_)
        | TExprKind::EmptyArray
        | TExprKind::EmptyList
        | TExprKind::EmptyPool
        | TExprKind::EmptyMap
        | TExprKind::EmptySet
        | TExprKind::EmptyGrid
        | TExprKind::EmptyQueue
        | TExprKind::EmptyRing
        | TExprKind::LoopExit(_)
        | TExprKind::AsciiEmpty
        | TExprKind::TextEmpty
        | TExprKind::BytesEmpty => {}
    }
}

#[derive(Clone, Debug)]
struct EvalFailure {
    span: Span,
    message: String,
    chain: Vec<String>,
    step_limit: bool,
    call_depth_limit: bool,
}

#[derive(Clone, Debug)]
enum Outcome {
    Value(ConstValue),
    Return(ConstValue),
    Break,
    Continue,
}

macro_rules! value_or_flow {
    ($value:expr) => {
        match $value? {
            Outcome::Value(value) => value,
            flow => return Ok(flow),
        }
    };
}

struct Evaluator<'a> {
    declarations: &'a [TConstExpr],
    functions: &'a [TFunction],
    types: &'a [TType],
    values: Vec<Option<ConstValue>>,
    states: Vec<u8>,
    active_constants: Vec<usize>,
    constant_values: Option<&'a [ConstValue]>,
    views: HashMap<usize, TPlace>,
    steps: u64,
    call_depth: usize,
}

#[derive(Clone, Copy)]
enum ResolvedProjection {
    Field(usize),
    Index(usize),
    MapIndex(usize),
    PoolIndex(usize),
}

impl Evaluator<'_> {
    fn canonical_place(&self, place: &TPlace) -> TPlace {
        let mut canonical = place.clone();
        let mut seen = Vec::new();
        while let Some(alias) = self.views.get(&canonical.root) {
            if seen.contains(&canonical.root) {
                break;
            }
            seen.push(canonical.root);
            let mut expanded = alias.clone();
            expanded.path.extend(canonical.path.iter().cloned());
            expanded.fields.extend(canonical.fields.iter().copied());
            expanded.ty = canonical.ty;
            canonical = expanded;
        }
        canonical
    }

    fn place_from_expr(&self, expr: &TExpr) -> Option<TPlace> {
        match &expr.kind {
            TExprKind::Local(id) => Some(self.canonical_place(&TPlace {
                root: *id,
                fields: Vec::new(),
                path: Vec::new(),
                ty: expr.ty,
            })),
            TExprKind::Field {
                receiver,
                field_index,
            } => {
                let mut place = self.place_from_expr(receiver)?;
                place.fields.push(*field_index);
                place.path.push(TProjection::Field(*field_index));
                place.ty = expr.ty;
                Some(place)
            }
            TExprKind::Index {
                receiver,
                index,
                capacity,
                is_list,
                proven,
                grid,
            } => {
                let mut place = self.place_from_expr(receiver)?;
                let constant = if let TExprKind::Integer(value) = index.kind {
                    Some(value)
                } else {
                    None
                };
                place.path.push(TProjection::Index {
                    index: (**index).clone(),
                    constant,
                    capacity: *capacity,
                    is_list: *is_list,
                    is_pool: false,
                    is_map: false,
                    proven: *proven,
                    grid: grid.as_deref().cloned(),
                });
                place.ty = expr.ty;
                Some(place)
            }
            _ => None,
        }
    }

    fn resolve_place_indices(
        &mut self,
        place: &TPlace,
        locals: &mut Vec<Option<ConstValue>>,
    ) -> Result<(usize, Vec<ResolvedProjection>), EvalFailure> {
        let canonical = self.canonical_place(place);
        let mut resolved = Vec::with_capacity(canonical.path.len());
        for projection in &canonical.path {
            match projection {
                TProjection::Field(index) => resolved.push(ResolvedProjection::Field(*index)),
                TProjection::Index {
                    index,
                    is_pool,
                    is_map,
                    grid,
                    ..
                } => {
                    if let Some(grid) = grid {
                        let x = match self.eval_expr(&grid.x, locals)? {
                            Outcome::Value(value) => as_integer(&value),
                            _ => {
                                return Err(self.failure(
                                    grid.x.span,
                                    "control flow is not valid in a grid index",
                                ));
                            }
                        };
                        if x < 0 || x >= grid.width as i128 {
                            return Err(self.failure(grid.x.span, "index out of range"));
                        }
                        let y = match self.eval_expr(&grid.y, locals)? {
                            Outcome::Value(value) => as_integer(&value),
                            _ => {
                                return Err(self.failure(
                                    grid.y.span,
                                    "control flow is not valid in a grid index",
                                ));
                            }
                        };
                        if y < 0 || y >= grid.height as i128 {
                            return Err(self.failure(grid.y.span, "index out of range"));
                        }
                        let flat = usize::try_from(y)
                            .ok()
                            .and_then(|row| row.checked_mul(grid.width))
                            .and_then(|row| {
                                usize::try_from(x).ok().and_then(|x| row.checked_add(x))
                            })
                            .ok_or_else(|| self.failure(grid.y.span, "index out of range"))?;
                        resolved.push(ResolvedProjection::Index(flat));
                        continue;
                    }
                    let value = match self.eval_expr(index, locals)? {
                        Outcome::Value(value) => value,
                        _ => {
                            return Err(self.failure(
                                index.span,
                                "control flow is not valid in a collection index",
                            ));
                        }
                    };
                    let value = as_integer(&value);
                    if value < 0 || value > usize::MAX as i128 {
                        return Err(self.failure(index.span, "index out of range"));
                    }
                    resolved.push(if *is_pool {
                        ResolvedProjection::PoolIndex(value as usize)
                    } else if *is_map {
                        ResolvedProjection::MapIndex(value as usize)
                    } else {
                        ResolvedProjection::Index(value as usize)
                    });
                }
            }
        }
        Ok((canonical.root, resolved))
    }

    fn get_resolved_place(
        &self,
        locals: &[Option<ConstValue>],
        root: usize,
        path: &[ResolvedProjection],
    ) -> Option<ConstValue> {
        let mut value = get_local(locals, root)?;
        for projection in path {
            value = match (projection, value) {
                (ResolvedProjection::Field(index), ConstValue::Struct(fields)) => {
                    fields.get(*index)?.clone()
                }
                (ResolvedProjection::Index(index), ConstValue::Array(values)) => {
                    values.get(*index)?.clone()
                }
                (ResolvedProjection::Index(index), ConstValue::List(values)) => {
                    values.get(*index)?.clone()
                }
                (ResolvedProjection::Index(index), ConstValue::Queue(values))
                | (ResolvedProjection::Index(index), ConstValue::Ring(values)) => {
                    values.get(*index)?.clone()
                }
                (ResolvedProjection::Index(index), ConstValue::Grid(values)) => {
                    values.get(*index)?.clone()
                }
                (ResolvedProjection::MapIndex(index), ConstValue::Map(entries)) => {
                    entries.get(*index)?.1.clone()
                }
                (ResolvedProjection::PoolIndex(index), ConstValue::Pool { slots, .. }) => {
                    slots.get(*index)?.as_ref()?.clone()
                }
                _ => return None,
            };
        }
        Some(value)
    }

    fn set_resolved_place(
        &self,
        locals: &mut Vec<Option<ConstValue>>,
        root: usize,
        path: &[ResolvedProjection],
        replacement: ConstValue,
    ) -> Result<(), String> {
        let Some(mut value) = get_local(locals, root) else {
            return Err("constant evaluator could not write an uninitialised local".to_owned());
        };
        fn set(
            value: &mut ConstValue,
            path: &[ResolvedProjection],
            replacement: ConstValue,
        ) -> Result<(), String> {
            let Some((head, tail)) = path.split_first() else {
                *value = replacement;
                return Ok(());
            };
            let child = match (head, value) {
                (ResolvedProjection::Field(index), ConstValue::Struct(fields)) => {
                    fields.get_mut(*index)
                }
                (ResolvedProjection::Index(index), ConstValue::Array(values)) => {
                    values.get_mut(*index)
                }
                (ResolvedProjection::Index(index), ConstValue::List(values)) => {
                    values.get_mut(*index)
                }
                (ResolvedProjection::Index(index), ConstValue::Queue(values))
                | (ResolvedProjection::Index(index), ConstValue::Ring(values)) => {
                    values.get_mut(*index)
                }
                (ResolvedProjection::Index(index), ConstValue::Grid(values)) => {
                    values.get_mut(*index)
                }
                (ResolvedProjection::MapIndex(index), ConstValue::Map(entries)) => {
                    entries.get_mut(*index).map(|entry| &mut entry.1)
                }
                (ResolvedProjection::PoolIndex(index), ConstValue::Pool { slots, .. }) => {
                    let slot = slots.get_mut(*index).ok_or_else(|| {
                        "constant evaluator assignment path was invalid".to_owned()
                    })?;
                    if tail.is_empty() {
                        *slot = Some(replacement);
                        return Ok(());
                    }
                    slot.as_mut()
                }
                _ => None,
            }
            .ok_or_else(|| "constant evaluator assignment path was invalid".to_owned())?;
            set(child, tail, replacement)
        }
        set(&mut value, path, replacement)?;
        set_local(locals, root, value);
        Ok(())
    }

    fn eval_collection_op(
        &self,
        op: CollectionOp,
        collection: &mut ConstValue,
        args: Vec<ConstValue>,
        capacity: usize,
        span: Span,
        _result_ty: Ty,
    ) -> Result<ConstValue, EvalFailure> {
        let success = || ConstValue::Enum {
            case_index: 0,
            payload: vec![ConstValue::Unit],
        };
        let full = || ConstValue::Enum {
            case_index: 1,
            payload: vec![ConstValue::Enum {
                case_index: 0,
                payload: Vec::new(),
            }],
        };
        Ok(match (op, collection) {
            (CollectionOp::Len, ConstValue::Array(values)) => {
                ConstValue::Integer(values.len() as i128)
            }
            (CollectionOp::Count, ConstValue::List(values)) => {
                ConstValue::Integer(values.len() as i128)
            }
            (CollectionOp::Count, ConstValue::Queue(values))
            | (CollectionOp::Count, ConstValue::Ring(values)) => {
                ConstValue::Integer(values.len() as i128)
            }
            (CollectionOp::Push, ConstValue::List(values)) => {
                if values.len() >= capacity {
                    full()
                } else {
                    values.push(args[0].clone());
                    success()
                }
            }
            (CollectionOp::Insert, ConstValue::List(values)) => {
                let index = as_integer(&args[0]);
                if index < 0 || index as u128 > values.len() as u128 {
                    return Err(self.failure(span, "index out of range"));
                }
                if values.len() >= capacity {
                    full()
                } else {
                    values.insert(index as usize, args[1].clone());
                    success()
                }
            }
            (CollectionOp::Pop, ConstValue::List(values)) => match values.pop() {
                Some(value) => ConstValue::Enum {
                    case_index: 0,
                    payload: vec![value],
                },
                None => ConstValue::Enum {
                    case_index: 1,
                    payload: Vec::new(),
                },
            },
            (CollectionOp::Push, ConstValue::Queue(values)) => {
                if values.len() >= capacity {
                    full()
                } else {
                    values.push(args[0].clone());
                    success()
                }
            }
            (CollectionOp::RingPush, ConstValue::Ring(values)) => {
                if capacity > 0 {
                    if values.len() == capacity {
                        values.remove(0);
                    }
                    values.push(args[0].clone());
                }
                ConstValue::Unit
            }
            (CollectionOp::Pop, ConstValue::Queue(values))
            | (CollectionOp::Pop, ConstValue::Ring(values)) => {
                if values.is_empty() {
                    ConstValue::Enum {
                        case_index: 1,
                        payload: Vec::new(),
                    }
                } else {
                    ConstValue::Enum {
                        case_index: 0,
                        payload: vec![values.remove(0)],
                    }
                }
            }
            (CollectionOp::Peek, ConstValue::Queue(values))
            | (CollectionOp::Peek, ConstValue::Ring(values)) => match values.first() {
                Some(value) => ConstValue::Enum {
                    case_index: 0,
                    payload: vec![value.clone()],
                },
                None => ConstValue::Enum {
                    case_index: 1,
                    payload: Vec::new(),
                },
            },
            (CollectionOp::Remove, ConstValue::List(values)) => {
                let index = as_integer(&args[0]);
                if index < 0 || index as u128 >= values.len() as u128 {
                    return Err(self.failure(span, "index out of range"));
                }
                values.remove(index as usize)
            }
            (CollectionOp::Clear, ConstValue::List(values)) => {
                values.clear();
                ConstValue::Unit
            }
            _ => {
                return Err(self.failure(span, "collection operation receiver had the wrong value"));
            }
        })
    }

    fn eval_pool_op(
        &self,
        op: PoolOp,
        pool: &mut ConstValue,
        args: Vec<ConstValue>,
        capacity: usize,
        span: Span,
    ) -> Result<ConstValue, EvalFailure> {
        let ConstValue::Pool {
            slots,
            generations,
            free,
            high_water,
        } = pool
        else {
            return Err(self.failure(span, "pool operation receiver had the wrong value"));
        };
        let option_none = || ConstValue::Enum {
            case_index: 1,
            payload: Vec::new(),
        };
        let result_full = || ConstValue::Enum {
            case_index: 1,
            payload: vec![ConstValue::Enum {
                case_index: 0,
                payload: Vec::new(),
            }],
        };
        match op {
            PoolOp::Count => Ok(ConstValue::Integer(
                slots.iter().filter(|slot| slot.is_some()).count() as i128,
            )),
            PoolOp::Add => {
                if slots.len() != capacity || generations.len() != capacity {
                    return Ok(result_full());
                }
                let slot = if let Some(slot) = free.pop() {
                    slot
                } else if *high_water < capacity {
                    let slot = *high_water as u32;
                    *high_water += 1;
                    slot
                } else {
                    return Ok(result_full());
                };
                let index = slot as usize;
                if index >= capacity || slots[index].is_some() {
                    return Err(self.failure(span, "constant pool free list was inconsistent"));
                }
                if generations[index] == 0 {
                    generations[index] = 1;
                }
                slots[index] = Some(args[0].clone());
                let id = ((generations[index] as u64) << 32) | slot as u64;
                Ok(ConstValue::Enum {
                    case_index: 0,
                    payload: vec![ConstValue::Integer(id as i128)],
                })
            }
            PoolOp::Get | PoolOp::Remove | PoolOp::Contains => {
                let id = match &args[0] {
                    ConstValue::Integer(id) => *id as u64,
                    _ => {
                        return Err(
                            self.failure(span, "pool id did not have an integer representation")
                        );
                    }
                };
                let slot = (id & u32::MAX as u64) as usize;
                let generation = (id >> 32) as u32;
                let valid = slot < capacity
                    && slot < *high_water
                    && slots.get(slot).is_some_and(Option::is_some)
                    && generations
                        .get(slot)
                        .is_some_and(|actual| *actual == generation);
                if op == PoolOp::Contains {
                    return Ok(ConstValue::Bool(valid));
                }
                if !valid {
                    return Ok(option_none());
                }
                if op == PoolOp::Get {
                    return Ok(ConstValue::Enum {
                        case_index: 0,
                        payload: vec![slots[slot].as_ref().unwrap().clone()],
                    });
                }
                let value = slots[slot].take().expect("validated occupied slot");
                if generations[slot] >= u32::MAX - 1 {
                    generations[slot] = u32::MAX;
                } else {
                    generations[slot] += 1;
                    free.push(slot as u32);
                }
                Ok(ConstValue::Enum {
                    case_index: 0,
                    payload: vec![value],
                })
            }
        }
    }

    fn eval_map_op(
        &self,
        op: MapOp,
        map: &mut ConstValue,
        args: Vec<ConstValue>,
        key_ty: Ty,
        _value_ty: Ty,
        capacity: usize,
        span: Span,
    ) -> Result<ConstValue, EvalFailure> {
        let ConstValue::Map(entries) = map else {
            return Err(self.failure(span, "map operation receiver had the wrong value"));
        };
        let success = || ConstValue::Enum {
            case_index: 0,
            payload: vec![ConstValue::Unit],
        };
        let full = || ConstValue::Enum {
            case_index: 1,
            payload: vec![ConstValue::Enum {
                case_index: 0,
                payload: Vec::new(),
            }],
        };
        let key = args
            .first()
            .ok_or_else(|| self.failure(span, "map operation was missing a key"))?;
        let found = entries
            .iter()
            .position(|(stored, _)| self.values_equal(key_ty, stored, key));
        Ok(match op {
            MapOp::Get => {
                match found.and_then(|index| entries.get(index).map(|entry| entry.1.clone())) {
                    Some(value) => ConstValue::Enum {
                        case_index: 0,
                        payload: vec![value],
                    },
                    None => ConstValue::Enum {
                        case_index: 1,
                        payload: Vec::new(),
                    },
                }
            }
            MapOp::Set => {
                let value = args
                    .get(1)
                    .cloned()
                    .ok_or_else(|| self.failure(span, "map set was missing a value"))?;
                if let Some(index) = found {
                    entries[index].1 = value;
                    success()
                } else if entries.len() >= capacity {
                    full()
                } else {
                    entries.push((key.clone(), value));
                    success()
                }
            }
            MapOp::Remove => match found {
                Some(index) => ConstValue::Enum {
                    case_index: 0,
                    payload: vec![entries.remove(index).1],
                },
                None => ConstValue::Enum {
                    case_index: 1,
                    payload: Vec::new(),
                },
            },
            MapOp::Contains => ConstValue::Bool(found.is_some()),
            MapOp::Count => ConstValue::Integer(entries.len() as i128),
        })
    }

    fn eval_set_op(
        &self,
        op: SetOp,
        set: &mut ConstValue,
        args: Vec<ConstValue>,
        key_ty: Ty,
        capacity: usize,
        span: Span,
    ) -> Result<ConstValue, EvalFailure> {
        let ConstValue::Set(entries) = set else {
            return Err(self.failure(span, "set operation receiver had the wrong value"));
        };
        let success = || ConstValue::Enum {
            case_index: 0,
            payload: vec![ConstValue::Unit],
        };
        let full = || ConstValue::Enum {
            case_index: 1,
            payload: vec![ConstValue::Enum {
                case_index: 0,
                payload: Vec::new(),
            }],
        };
        let key = args
            .first()
            .ok_or_else(|| self.failure(span, "set operation was missing a key"))?;
        let found = entries
            .iter()
            .position(|stored| self.values_equal(key_ty, stored, key));
        Ok(match op {
            SetOp::Add => {
                if found.is_some() {
                    success()
                } else if entries.len() >= capacity {
                    full()
                } else {
                    entries.push(key.clone());
                    success()
                }
            }
            SetOp::Remove => match found {
                Some(index) => {
                    entries.remove(index);
                    ConstValue::Bool(true)
                }
                None => ConstValue::Bool(false),
            },
            SetOp::Contains => ConstValue::Bool(found.is_some()),
            SetOp::Count => ConstValue::Integer(entries.len() as i128),
        })
    }

    fn eval_constant(&mut self, id: usize, reference_span: Span) -> Result<ConstValue, CheckError> {
        if self.states[id] == 2 {
            return Ok(self.values[id].as_ref().unwrap().clone());
        }
        if self.states[id] == 1 {
            let start = self
                .active_constants
                .iter()
                .position(|active| *active == id)
                .unwrap_or(0);
            let mut cycle = self.active_constants[start..]
                .iter()
                .map(|active| self.declarations[*active].name.clone())
                .collect::<Vec<_>>();
            cycle.push(self.declarations[id].name.clone());
            return Err(CheckError {
                span: reference_span,
                message: format!("constant dependency cycle: {}", cycle.join(" -> ")),
            });
        }

        let declaration = self.declarations[id].clone();
        let previous_steps = std::mem::replace(&mut self.steps, 0);
        self.states[id] = 1;
        self.active_constants.push(id);
        let saved_views = std::mem::take(&mut self.views);
        let evaluated = self.eval_expr(&declaration.expr, &mut Vec::new());
        self.views = saved_views;
        self.active_constants.pop();
        self.steps = previous_steps;
        let value = match evaluated {
            Ok(Outcome::Value(value)) => value,
            Ok(Outcome::Return(_)) => {
                self.states[id] = 0;
                return Err(CheckError {
                    span: declaration.span,
                    message: format!(
                        "constant '{}' initializer cannot return from its evaluation",
                        declaration.name
                    ),
                });
            }
            Ok(Outcome::Break | Outcome::Continue) => {
                self.states[id] = 0;
                return Err(CheckError {
                    span: declaration.span,
                    message: format!(
                        "constant '{}' initializer cannot exit a loop at top level",
                        declaration.name
                    ),
                });
            }
            Err(failure) => {
                self.states[id] = 0;
                if failure.step_limit {
                    return Err(CheckError {
                        span: declaration.span,
                        message: format!(
                            "constant '{}' exceeded the compile-time evaluation limit of {} steps",
                            declaration.name, STEP_LIMIT
                        ),
                    });
                }
                if failure.call_depth_limit {
                    return Err(CheckError {
                        span: failure.span,
                        message: format!(
                            "constant '{}' evaluation failed: {}",
                            declaration.name, failure.message
                        ),
                    });
                }
                let mut chain = vec![format!("constant {}", declaration.name)];
                chain.extend(failure.chain);
                return Err(CheckError {
                    span: failure.span,
                    message: format!(
                        "constant '{}' evaluation failed: {}; call chain: {}",
                        declaration.name,
                        failure.message,
                        chain.join(" -> ")
                    ),
                });
            }
        };
        self.values[id] = Some(value.clone());
        self.states[id] = 2;
        Ok(value)
    }

    fn step(&mut self, span: Span) -> Result<(), EvalFailure> {
        if self.steps >= STEP_LIMIT {
            return Err(EvalFailure {
                span,
                message: "compile-time step limit reached".to_owned(),
                chain: Vec::new(),
                step_limit: true,
                call_depth_limit: false,
            });
        }
        self.steps += 1;
        Ok(())
    }

    fn failure(&self, span: Span, message: impl Into<String>) -> EvalFailure {
        EvalFailure {
            span,
            message: message.into(),
            chain: Vec::new(),
            step_limit: false,
            call_depth_limit: false,
        }
    }

    fn eval_statements(
        &mut self,
        block: &TBlock,
        locals: &mut Vec<Option<ConstValue>>,
    ) -> Result<Outcome, EvalFailure> {
        for stmt in &block.statements {
            self.step(stmt.span)?;
            match &stmt.kind {
                TStmtKind::Let { id, value, .. } => {
                    let value = value_or_flow!(self.eval_expr(value, locals));
                    set_local(locals, *id, value);
                }
                TStmtKind::Assign {
                    place,
                    ty,
                    op,
                    operator_span,
                    value,
                } => {
                    let (place_root, place_path) = self.resolve_place_indices(place, locals)?;
                    let rhs = value_or_flow!(self.eval_expr(value, locals));
                    let new_value = if *op == AssignOp::Set {
                        rhs
                    } else {
                        let old = self
                            .get_resolved_place(locals, place_root, &place_path)
                            .ok_or_else(|| {
                                self.failure(
                                    stmt.span,
                                    "constant evaluator could not read an assignment target",
                                )
                            })?;
                        let binary_op = match op {
                            AssignOp::Add => BinaryOp::Add,
                            AssignOp::Sub => BinaryOp::Sub,
                            AssignOp::Mul => BinaryOp::Mul,
                            AssignOp::Div => BinaryOp::Div,
                            AssignOp::Rem => BinaryOp::Rem,
                            AssignOp::Shr => BinaryOp::Shr,
                            AssignOp::Set => unreachable!(),
                        };
                        self.eval_binary(binary_op, *ty, old, rhs, *operator_span)?
                    };
                    let new_value = if let Some((_, min, max, policy)) = refinement(*ty, self.types)
                    {
                        ConstValue::Integer(self.convert_integer(
                            as_integer(&new_value),
                            min,
                            max,
                            policy,
                            *operator_span,
                        )?)
                    } else {
                        new_value
                    };
                    self.set_resolved_place(locals, place_root, &place_path, new_value)
                        .map_err(|message| self.failure(stmt.span, message))?;
                }
                TStmtKind::Return(value) => {
                    let value = if let Some(value) = value {
                        value_or_flow!(self.eval_expr(value, locals))
                    } else {
                        ConstValue::Unit
                    };
                    return Ok(Outcome::Return(value));
                }
                TStmtKind::Expr(expr) => match self.eval_expr(expr, locals)? {
                    Outcome::Value(_) => {}
                    flow => return Ok(flow),
                },
                TStmtKind::If {
                    condition,
                    then_block,
                    else_block,
                } => {
                    let condition = value_or_flow!(self.eval_expr(condition, locals));
                    let selected = if as_bool(&condition) {
                        Some(then_block)
                    } else {
                        else_block.as_ref()
                    };
                    if let Some(selected) = selected {
                        match self.eval_block(selected, locals)? {
                            Outcome::Value(_) => {}
                            flow => return Ok(flow),
                        }
                    }
                }
                TStmtKind::For {
                    id,
                    ty,
                    start,
                    end,
                    inclusive,
                    body,
                } => {
                    let start_value = value_or_flow!(self.eval_expr(start, locals));
                    let end_value = value_or_flow!(self.eval_expr(end, locals));
                    let mut index = as_integer(&start_value);
                    let end = as_integer(&end_value);
                    loop {
                        self.step(stmt.span)?;
                        let in_range = if *inclusive {
                            index <= end
                        } else {
                            index < end
                        };
                        if !in_range {
                            break;
                        }
                        set_local(locals, *id, ConstValue::Integer(index));
                        match self.eval_block(body, locals)? {
                            Outcome::Value(_) | Outcome::Continue => {}
                            Outcome::Break => break,
                            flow @ Outcome::Return(_) => return Ok(flow),
                        }
                        let (_, max) = integer_bounds(*ty, self.types).ok_or_else(|| {
                            self.failure(stmt.span, "for counter is not an integer")
                        })?;
                        if *inclusive && index == end {
                            break;
                        }
                        if index == max {
                            return Err(
                                self.failure(stmt.span, "overflow in for counter increment")
                            );
                        }
                        index += 1;
                    }
                }
                TStmtKind::ForEach {
                    id,
                    index_id,
                    second_index_id,
                    counter_id,
                    source,
                    is_list,
                    is_pool,
                    is_map,
                    is_set,
                    is_grid,
                    body,
                    ..
                } => {
                    let (root, path) = self.resolve_place_indices(source, locals)?;
                    let collection =
                        self.get_resolved_place(locals, root, &path)
                            .ok_or_else(|| {
                                self.failure(
                                    stmt.span,
                                    "constant evaluator could not read a collection loop source",
                                )
                            })?;
                    let collection_ty = source.ty;
                    let (capacity, element) = match self.types[collection_ty.0].kind {
                        TTypeKind::Array { element, capacity }
                        | TTypeKind::List { element, capacity }
                        | TTypeKind::Queue { element, capacity }
                        | TTypeKind::Ring { element, capacity }
                        | TTypeKind::Grid {
                            element, capacity, ..
                        }
                        | TTypeKind::Pool {
                            element, capacity, ..
                        } => (capacity, element),
                        TTypeKind::Map {
                            value, capacity, ..
                        } => (capacity, value),
                        TTypeKind::Set { key, capacity } => (capacity, key),
                        _ => {
                            return Err(self.failure(
                                stmt.span,
                                "collection loop source was not a collection",
                            ));
                        }
                    };
                    let snapshot = if *is_pool {
                        match &collection {
                            ConstValue::Pool {
                                slots, high_water, ..
                            } => slots
                                .iter()
                                .take(*high_water)
                                .map(Option::is_some)
                                .collect::<Vec<_>>(),
                            _ => {
                                return Err(
                                    self.failure(stmt.span, "pool loop source had the wrong value")
                                );
                            }
                        }
                    } else {
                        let length = match (&collection, *is_list) {
                            (ConstValue::List(values), true) => values.len(),
                            (ConstValue::Queue(values), true)
                            | (ConstValue::Ring(values), true) => values.len(),
                            (ConstValue::Array(values), false) => values.len(),
                            (ConstValue::Grid(values), false) if *is_grid => values.len(),
                            (ConstValue::Map(entries), false) if *is_map => entries.len(),
                            (ConstValue::Set(entries), false) if *is_set => entries.len(),
                            _ => {
                                return Err(self.failure(
                                    stmt.span,
                                    "collection loop source had the wrong value",
                                ));
                            }
                        };
                        vec![true; length]
                    };
                    for (index, present_at_start) in snapshot.into_iter().enumerate() {
                        if !present_at_start {
                            continue;
                        }
                        self.step(stmt.span)?;
                        set_local(locals, *counter_id, ConstValue::Integer(index as i128));
                        let grid_width = if *is_grid {
                            match self.types[collection_ty.0].kind {
                                TTypeKind::Grid { width, .. } => width,
                                _ => unreachable!("grid loop source has grid type"),
                            }
                        } else {
                            0
                        };
                        if let Some(index_id) = index_id {
                            let id = if *is_pool {
                                let pool = self
                                    .get_resolved_place(locals, root, &path)
                                    .ok_or_else(|| {
                                        self.failure(
                                            stmt.span,
                                            "constant evaluator could not read a pool loop source",
                                        )
                                    })?;
                                let ConstValue::Pool { generations, .. } = pool else {
                                    return Err(self.failure(
                                        stmt.span,
                                        "pool loop source had the wrong value",
                                    ));
                                };
                                let generation = *generations.get(index).ok_or_else(|| {
                                    self.failure(stmt.span, "pool loop slot was out of range")
                                })?;
                                ConstValue::Integer(
                                    (((generation as u64) << 32) | index as u64) as i128,
                                )
                            } else if *is_map {
                                let ConstValue::Map(entries) = self
                                    .get_resolved_place(locals, root, &path)
                                    .ok_or_else(|| {
                                        self.failure(stmt.span, "map loop source could not be read")
                                    })?
                                else {
                                    return Err(self.failure(
                                        stmt.span,
                                        "map loop source had the wrong value",
                                    ));
                                };
                                entries
                                    .get(index)
                                    .ok_or_else(|| {
                                        self.failure(
                                            stmt.span,
                                            "map loop key index was out of range",
                                        )
                                    })?
                                    .0
                                    .clone()
                            } else if *is_grid {
                                ConstValue::Integer((index % grid_width) as i128)
                            } else {
                                ConstValue::Integer(index as i128)
                            };
                            set_local(locals, *index_id, id);
                        }
                        if let Some(second_index_id) = second_index_id {
                            set_local(
                                locals,
                                *second_index_id,
                                ConstValue::Integer((index / grid_width) as i128),
                            );
                        }
                        if *is_set {
                            let ConstValue::Set(entries) = self
                                .get_resolved_place(locals, root, &path)
                                .ok_or_else(|| {
                                    self.failure(stmt.span, "set loop source could not be read")
                                })?
                            else {
                                return Err(
                                    self.failure(stmt.span, "set loop source had the wrong value")
                                );
                            };
                            set_local(
                                locals,
                                *id,
                                entries.get(index).cloned().ok_or_else(|| {
                                    self.failure(stmt.span, "set loop key index was out of range")
                                })?,
                            );
                        }
                        let index_expr = TExpr {
                            kind: TExprKind::Local(*counter_id),
                            ty: Ty::Long,
                            span: stmt.span,
                        };
                        let mut element_place = source.clone();
                        element_place.path.push(TProjection::Index {
                            index: index_expr,
                            constant: None,
                            capacity,
                            is_list: *is_list,
                            is_pool: *is_pool,
                            is_map: *is_map,
                            proven: true,
                            grid: None,
                        });
                        element_place.ty = element;
                        let previous = if *is_set {
                            None
                        } else {
                            self.views.insert(*id, element_place)
                        };
                        let outcome = self.eval_block(body, locals);
                        if !*is_set {
                            if let Some(previous) = previous {
                                self.views.insert(*id, previous);
                            } else {
                                self.views.remove(id);
                            }
                        }
                        match outcome? {
                            Outcome::Value(_) | Outcome::Continue => {}
                            Outcome::Break => break,
                            flow @ Outcome::Return(_) => return Ok(flow),
                        }
                    }
                }
                TStmtKind::Discard(value) => match self.eval_expr(value, locals)? {
                    Outcome::Value(_) => {}
                    flow => return Ok(flow),
                },
                TStmtKind::Break => return Ok(Outcome::Break),
                TStmtKind::Continue => return Ok(Outcome::Continue),
                TStmtKind::Expect { kind, .. } => {
                    let passed = match kind {
                        TExpectKind::Bool(value) => {
                            let value = value_or_flow!(self.eval_expr(value, locals));
                            as_bool(&value)
                        }
                        TExpectKind::Compare { op, left, right } => {
                            let left_value = value_or_flow!(self.eval_expr(left, locals));
                            let right_value = value_or_flow!(self.eval_expr(right, locals));
                            as_bool(&self.eval_binary(
                                *op,
                                left.ty,
                                left_value,
                                right_value,
                                stmt.span,
                            )?)
                        }
                        TExpectKind::StackPeak { .. } => true,
                    };
                    if !passed {
                        return Err(self.failure(
                            stmt.span,
                            "expectation failed during compile-time evaluation",
                        ));
                    }
                }
                TStmtKind::Block(inner) => match self.eval_block(inner, locals)? {
                    Outcome::Value(_) => {}
                    flow => return Ok(flow),
                },
            }
        }
        Ok(Outcome::Value(ConstValue::Unit))
    }

    fn eval_block(
        &mut self,
        block: &TBlock,
        locals: &mut Vec<Option<ConstValue>>,
    ) -> Result<Outcome, EvalFailure> {
        match self.eval_statements(block, locals)? {
            Outcome::Value(_) => {}
            flow => return Ok(flow),
        }
        if let Some(tail) = &block.tail {
            self.eval_expr(tail, locals)
        } else {
            Ok(Outcome::Value(ConstValue::Unit))
        }
    }

    #[inline(never)]
    fn eval_call_expr(
        &mut self,
        expr: &TExpr,
        locals: &mut Vec<Option<ConstValue>>,
    ) -> Result<Outcome, EvalFailure> {
        let value = match &expr.kind {
            TExprKind::Call { target, args, .. } => match target {
                CallTarget::Function(id) => {
                    let mut values = Vec::with_capacity(args.len());
                    for arg in args {
                        values.push(value_or_flow!(self.eval_expr(arg, locals)));
                    }
                    self.call_function(*id, values, expr.span)?
                }
                CallTarget::Print
                | CallTarget::OutWrite
                | CallTarget::OutLine
                | CallTarget::OutInt
                | CallTarget::OutLong
                | CallTarget::EnvArgs
                | CallTarget::EnvExit
                | CallTarget::ArgsCount
                | CallTarget::ArgsGet
                | CallTarget::ArgLength
                | CallTarget::ArgByte
                | CallTarget::FsRead
                | CallTarget::FsList
                | CallTarget::FsListWithExtension
                | CallTarget::FsWrite
                | CallTarget::EnvFs
                | CallTarget::EnvOut
                | CallTarget::EnvErr
                | CallTarget::FsJoin => {
                    let effect = match target {
                        CallTarget::Print
                        | CallTarget::OutWrite
                        | CallTarget::OutLine
                        | CallTarget::OutInt
                        | CallTarget::OutLong => "out",
                        CallTarget::EnvArgs
                        | CallTarget::EnvExit
                        | CallTarget::ArgsCount
                        | CallTarget::ArgsGet
                        | CallTarget::ArgLength
                        | CallTarget::ArgByte => "env",
                        CallTarget::FsRead | CallTarget::FsList => "fs.read",
                        CallTarget::FsWrite => "fs.write",
                        _ => "capability access",
                    };
                    return Err(self.failure(
                        expr.span,
                        &format!("effect '{}' reached during constant evaluation", effect),
                    ));
                }
                CallTarget::Min | CallTarget::Max => {
                    let left = value_or_flow!(self.eval_expr(&args[0], locals));
                    let right = value_or_flow!(self.eval_expr(&args[1], locals));
                    let (left, right) = (as_integer(&left), as_integer(&right));
                    ConstValue::Integer(if matches!(target, CallTarget::Min) {
                        left.min(right)
                    } else {
                        left.max(right)
                    })
                }
                CallTarget::Abs => {
                    let value = as_integer(&value_or_flow!(self.eval_expr(&args[0], locals)));
                    let (minimum, _) = integer_bounds(expr.ty, self.types)
                        .ok_or_else(|| self.failure(expr.span, "abs needs an integer type"))?;
                    if value == minimum {
                        return Err(self.failure(expr.span, "overflow in absolute value"));
                    }
                    ConstValue::Integer(value.abs())
                }
                CallTarget::Clamp => {
                    let value = as_integer(&value_or_flow!(self.eval_expr(&args[0], locals)));
                    let lower = as_integer(&value_or_flow!(self.eval_expr(&args[1], locals)));
                    let upper = as_integer(&value_or_flow!(self.eval_expr(&args[2], locals)));
                    if lower > upper {
                        return Err(
                            self.failure(expr.span, "clamp lower bound exceeds upper bound")
                        );
                    }
                    ConstValue::Integer(value.clamp(lower, upper))
                }
                CallTarget::BinarySearch { .. } => {
                    let collection = value_or_flow!(self.eval_expr(&args[0], locals));
                    let key = value_or_flow!(self.eval_expr(&args[1], locals));
                    let key = as_integer(&key);
                    let items = match collection {
                        ConstValue::Array(items) | ConstValue::List(items) => items,
                        _ => {
                            return Err(self.failure(
                                expr.span,
                                "binary_search receiver was not an array or list",
                            ));
                        }
                    };
                    if cfg!(debug_assertions)
                        && items
                            .windows(2)
                            .any(|pair| as_integer(&pair[0]) > as_integer(&pair[1]))
                    {
                        return Err(self.failure(expr.span, "binary_search requires sorted input"));
                    }
                    let mut low = 0usize;
                    let mut high = items.len();
                    while low < high {
                        let middle = low + (high - low) / 2;
                        if as_integer(&items[middle]) < key {
                            low = middle + 1;
                        } else {
                            high = middle;
                        }
                    }
                    if items.get(low).is_some_and(|value| as_integer(value) == key) {
                        ConstValue::Enum {
                            case_index: 0,
                            payload: vec![ConstValue::Integer(low as i128)],
                        }
                    } else {
                        ConstValue::Enum {
                            case_index: 1,
                            payload: Vec::new(),
                        }
                    }
                }
                CallTarget::Sort { .. } | CallTarget::SortBy { .. } => {
                    return Err(self.failure(
                        expr.span,
                        "sorting cannot run during compile-time evaluation",
                    ));
                }
            },
            TExprKind::IndirectCall { callee, args, .. } => {
                let function_value = value_or_flow!(self.eval_expr(callee, locals));
                let ConstValue::Function(id) = function_value else {
                    return Err(self.failure(
                        expr.span,
                        "constant evaluator expected a named function value",
                    ));
                };
                let mut values = Vec::with_capacity(args.len());
                for arg in args {
                    values.push(value_or_flow!(self.eval_expr(arg, locals)));
                }
                self.call_function(id, values, expr.span)?
            }
            TExprKind::Construct { case_index, args } => {
                let mut payload = Vec::with_capacity(args.len());
                for arg in args {
                    payload.push(value_or_flow!(self.eval_expr(arg, locals)));
                }
                ConstValue::Enum {
                    case_index: *case_index,
                    payload,
                }
            }
            _ => unreachable!("eval_call_expr called for another expression kind"),
        };
        Ok(Outcome::Value(value))
    }

    #[inline(never)]
    fn eval_collection_expr(
        &mut self,
        expr: &TExpr,
        locals: &mut Vec<Option<ConstValue>>,
    ) -> Result<Outcome, EvalFailure> {
        let value = match &expr.kind {
            TExprKind::EmptyArray => ConstValue::Array(Vec::new()),
            TExprKind::EmptyGrid => ConstValue::Grid(Vec::new()),
            TExprKind::EmptyList => ConstValue::List(Vec::new()),
            TExprKind::CollectionLiteral(values) => {
                let mut items = Vec::with_capacity(values.len());
                for item in values {
                    items.push(value_or_flow!(self.eval_expr(item, locals)));
                }
                match self.types[expr.ty.0].kind {
                    TTypeKind::Array { .. } => ConstValue::Array(items),
                    TTypeKind::List { .. } => ConstValue::List(items),
                    _ => {
                        return Err(self.failure(
                            expr.span,
                            "collection literal had a non-array or non-list type",
                        ));
                    }
                }
            }
            TExprKind::EmptyQueue => ConstValue::Queue(Vec::new()),
            TExprKind::EmptyRing => ConstValue::Ring(Vec::new()),
            TExprKind::EmptyPool => {
                let capacity = match self.types[expr.ty.0].kind {
                    TTypeKind::Pool { capacity, .. } => capacity,
                    _ => 0,
                };
                ConstValue::Pool {
                    slots: vec![None; capacity],
                    generations: vec![1; capacity],
                    free: Vec::new(),
                    high_water: 0,
                }
            }
            TExprKind::EmptyMap => ConstValue::Map(Vec::new()),
            TExprKind::EmptySet => ConstValue::Set(Vec::new()),
            TExprKind::CollectionOp {
                op,
                receiver,
                args,
                capacity,
                proven_success: _,
            } => {
                if matches!(
                    op,
                    CollectionOp::Count
                        | CollectionOp::Len
                        | CollectionOp::Width
                        | CollectionOp::Height
                ) || (*op == CollectionOp::Peek && self.place_from_expr(receiver).is_none())
                {
                    let value = value_or_flow!(self.eval_expr(receiver, locals));
                    if *op == CollectionOp::Peek {
                        let option = match value {
                            ConstValue::Queue(items) | ConstValue::Ring(items) => {
                                match items.first() {
                                    Some(item) => ConstValue::Enum {
                                        case_index: 0,
                                        payload: vec![item.clone()],
                                    },
                                    None => ConstValue::Enum {
                                        case_index: 1,
                                        payload: Vec::new(),
                                    },
                                }
                            }
                            _ => {
                                return Err(self.failure(
                                    expr.span,
                                    "collection peek receiver had the wrong value",
                                ));
                            }
                        };
                        return Ok(Outcome::Value(option));
                    }
                    let count = match value {
                        ConstValue::Array(items) if *op == CollectionOp::Len => items.len(),
                        ConstValue::List(items) if *op == CollectionOp::Count => items.len(),
                        ConstValue::Queue(items) | ConstValue::Ring(items)
                            if *op == CollectionOp::Count =>
                        {
                            items.len()
                        }
                        _ if *op == CollectionOp::Width || *op == CollectionOp::Height => *capacity,
                        _ => {
                            return Err(self.failure(
                                expr.span,
                                "collection count receiver had the wrong value",
                            ));
                        }
                    };
                    return Ok(Outcome::Value(ConstValue::Integer(count as i128)));
                }
                let place = self.place_from_expr(receiver);
                let resolved = if let Some(place) = place.as_ref() {
                    Some(self.resolve_place_indices(place, locals)?)
                } else {
                    None
                };
                let mut values = Vec::with_capacity(args.len());
                for arg in args {
                    values.push(value_or_flow!(self.eval_expr(arg, locals)));
                }
                let (root, path) = resolved.ok_or_else(|| {
                    self.failure(expr.span, "collection operation requires a place")
                })?;
                let mut collection =
                    self.get_resolved_place(locals, root, &path)
                        .ok_or_else(|| {
                            self.failure(
                                expr.span,
                                "constant evaluator could not read a collection",
                            )
                        })?;
                let result = self.eval_collection_op(
                    *op,
                    &mut collection,
                    values,
                    *capacity,
                    expr.span,
                    expr.ty,
                )?;
                self.set_resolved_place(locals, root, &path, collection)
                    .map_err(|message| self.failure(expr.span, message))?;
                result
            }
            TExprKind::PoolOp {
                op,
                receiver,
                args,
                capacity,
                ..
            } => {
                if *op == PoolOp::Count {
                    let pool = value_or_flow!(self.eval_expr(receiver, locals));
                    let ConstValue::Pool { slots, .. } = pool else {
                        return Err(
                            self.failure(expr.span, "pool count receiver had the wrong value")
                        );
                    };
                    ConstValue::Integer(slots.iter().filter(|slot| slot.is_some()).count() as i128)
                } else {
                    let place = self.place_from_expr(receiver);
                    let resolved = if let Some(place) = place.as_ref() {
                        Some(self.resolve_place_indices(place, locals)?)
                    } else {
                        None
                    };
                    let mut values = Vec::with_capacity(args.len());
                    for arg in args {
                        values.push(value_or_flow!(self.eval_expr(arg, locals)));
                    }
                    let (root, path) = resolved.ok_or_else(|| {
                        self.failure(expr.span, "pool operation requires a place")
                    })?;
                    let mut pool =
                        self.get_resolved_place(locals, root, &path)
                            .ok_or_else(|| {
                                self.failure(expr.span, "constant evaluator could not read a pool")
                            })?;
                    let result = self.eval_pool_op(*op, &mut pool, values, *capacity, expr.span)?;
                    self.set_resolved_place(locals, root, &path, pool)
                        .map_err(|message| self.failure(expr.span, message))?;
                    result
                }
            }
            TExprKind::MapOp {
                op,
                receiver,
                args,
                capacity,
                ..
            } => {
                let TTypeKind::Map { key, value, .. } = self.types[receiver.ty.0].kind else {
                    return Err(
                        self.failure(expr.span, "map operation receiver had the wrong type")
                    );
                };
                if matches!(*op, MapOp::Count | MapOp::Get | MapOp::Contains) {
                    let mut map = value_or_flow!(self.eval_expr(receiver, locals));
                    if *op == MapOp::Count {
                        let ConstValue::Map(entries) = map else {
                            return Err(
                                self.failure(expr.span, "map count receiver had the wrong value")
                            );
                        };
                        ConstValue::Integer(entries.len() as i128)
                    } else {
                        let mut values = Vec::with_capacity(args.len());
                        for arg in args {
                            values.push(value_or_flow!(self.eval_expr(arg, locals)));
                        }
                        self.eval_map_op(*op, &mut map, values, key, value, *capacity, expr.span)?
                    }
                } else {
                    let place = self.place_from_expr(receiver);
                    let resolved = if let Some(place) = place.as_ref() {
                        Some(self.resolve_place_indices(place, locals)?)
                    } else {
                        None
                    };
                    let mut values = Vec::with_capacity(args.len());
                    for arg in args {
                        values.push(value_or_flow!(self.eval_expr(arg, locals)));
                    }
                    let (root, path) = resolved
                        .ok_or_else(|| self.failure(expr.span, "map operation requires a place"))?;
                    let mut map =
                        self.get_resolved_place(locals, root, &path)
                            .ok_or_else(|| {
                                self.failure(expr.span, "constant evaluator could not read a map")
                            })?;
                    let result =
                        self.eval_map_op(*op, &mut map, values, key, value, *capacity, expr.span)?;
                    self.set_resolved_place(locals, root, &path, map)
                        .map_err(|message| self.failure(expr.span, message))?;
                    result
                }
            }
            TExprKind::SetOp {
                op,
                receiver,
                args,
                capacity,
                ..
            } => {
                let TTypeKind::Set { key, .. } = self.types[receiver.ty.0].kind else {
                    return Err(
                        self.failure(expr.span, "set operation receiver had the wrong type")
                    );
                };
                if matches!(*op, SetOp::Count | SetOp::Contains) {
                    let mut set = value_or_flow!(self.eval_expr(receiver, locals));
                    if *op == SetOp::Count {
                        let ConstValue::Set(entries) = set else {
                            return Err(
                                self.failure(expr.span, "set count receiver had the wrong value")
                            );
                        };
                        ConstValue::Integer(entries.len() as i128)
                    } else {
                        let mut values = Vec::with_capacity(args.len());
                        for arg in args {
                            values.push(value_or_flow!(self.eval_expr(arg, locals)));
                        }
                        self.eval_set_op(*op, &mut set, values, key, *capacity, expr.span)?
                    }
                } else {
                    let place = self.place_from_expr(receiver);
                    let resolved = if let Some(place) = place.as_ref() {
                        Some(self.resolve_place_indices(place, locals)?)
                    } else {
                        None
                    };
                    let mut values = Vec::with_capacity(args.len());
                    for arg in args {
                        values.push(value_or_flow!(self.eval_expr(arg, locals)));
                    }
                    let (root, path) = resolved
                        .ok_or_else(|| self.failure(expr.span, "set operation requires a place"))?;
                    let mut set =
                        self.get_resolved_place(locals, root, &path)
                            .ok_or_else(|| {
                                self.failure(expr.span, "constant evaluator could not read a set")
                            })?;
                    let result =
                        self.eval_set_op(*op, &mut set, values, key, *capacity, expr.span)?;
                    self.set_resolved_place(locals, root, &path, set)
                        .map_err(|message| self.failure(expr.span, message))?;
                    result
                }
            }
            TExprKind::StructConstruct { fields } => {
                let count = match &self.types[expr.ty.0].kind {
                    TTypeKind::Struct(fields) => fields.len(),
                    _ => {
                        return Err(
                            self.failure(expr.span, "struct initializer type was not a struct")
                        );
                    }
                };
                let mut values = vec![ConstValue::Unit; count];
                for (index, field_expr) in fields {
                    values[*index] = value_or_flow!(self.eval_expr(field_expr, locals));
                }
                ConstValue::Struct(values)
            }
            _ => unreachable!("eval_collection_expr called for another expression kind"),
        };
        Ok(Outcome::Value(value))
    }

    #[inline(never)]
    fn eval_access_expr(
        &mut self,
        expr: &TExpr,
        locals: &mut Vec<Option<ConstValue>>,
    ) -> Result<Outcome, EvalFailure> {
        let value = match &expr.kind {
            TExprKind::Method { kind, receiver } => {
                let receiver = value_or_flow!(self.eval_expr(receiver, locals));
                self.eval_method(*kind, receiver, expr.span)?
            }
            TExprKind::OptionalCall {
                receiver,
                function_id,
                args,
                wraps_result,
            } => {
                let receiver = value_or_flow!(self.eval_expr(receiver, locals));
                match receiver {
                    ConstValue::Enum {
                        case_index: 0,
                        mut payload,
                    } => {
                        let mut values = vec![payload.remove(0)];
                        for arg in args {
                            values.push(value_or_flow!(self.eval_expr(arg, locals)));
                        }
                        let result = self.call_function(*function_id, values, expr.span)?;
                        if *wraps_result {
                            ConstValue::Enum {
                                case_index: 0,
                                payload: vec![result],
                            }
                        } else {
                            result
                        }
                    }
                    ConstValue::Enum { case_index: 1, .. } => ConstValue::Enum {
                        case_index: 1,
                        payload: Vec::new(),
                    },
                    _ => {
                        return Err(
                            self.failure(expr.span, "optional call receiver was not an Option")
                        );
                    }
                }
            }
            TExprKind::OptionalToLong(receiver) => {
                match value_or_flow!(self.eval_expr(receiver, locals)) {
                    ConstValue::Enum {
                        case_index: 0,
                        payload,
                    } => ConstValue::Enum {
                        case_index: 0,
                        payload: vec![ConstValue::Integer(as_integer(&payload[0]))],
                    },
                    ConstValue::Enum { case_index: 1, .. } => ConstValue::Enum {
                        case_index: 1,
                        payload: Vec::new(),
                    },
                    _ => {
                        return Err(self
                            .failure(expr.span, "optional conversion receiver was not an Option"));
                    }
                }
            }
            TExprKind::Field {
                receiver,
                field_index,
            } => match value_or_flow!(self.eval_expr(receiver, locals)) {
                ConstValue::Struct(fields) => fields
                    .get(*field_index)
                    .cloned()
                    .ok_or_else(|| self.failure(expr.span, "struct field index was invalid"))?,
                _ => return Err(self.failure(expr.span, "field access receiver was not a struct")),
            },
            TExprKind::Index {
                receiver,
                index,
                grid,
                ..
            } => {
                let collection = value_or_flow!(self.eval_expr(receiver, locals));
                if let Some(grid) = grid {
                    let x = as_integer(&value_or_flow!(self.eval_expr(&grid.x, locals)));
                    if x < 0 || x >= grid.width as i128 {
                        return Err(self.failure(grid.x.span, "index out of range"));
                    }
                    let y = as_integer(&value_or_flow!(self.eval_expr(&grid.y, locals)));
                    if y < 0 || y >= grid.height as i128 {
                        return Err(self.failure(grid.y.span, "index out of range"));
                    }
                    let flat = usize::try_from(y)
                        .ok()
                        .and_then(|row| row.checked_mul(grid.width))
                        .and_then(|row| usize::try_from(x).ok().and_then(|x| row.checked_add(x)))
                        .ok_or_else(|| self.failure(grid.y.span, "index out of range"))?;
                    return match collection {
                        ConstValue::Grid(values) => values
                            .get(flat)
                            .cloned()
                            .map(Outcome::Value)
                            .ok_or_else(|| self.failure(expr.span, "index out of range")),
                        _ => Err(self.failure(expr.span, "index receiver was not a grid")),
                    };
                }
                let index_value = as_integer(&value_or_flow!(self.eval_expr(index, locals)));
                if index_value < 0 {
                    return Err(self.failure(index.span, "index out of range"));
                }
                let index_value = usize::try_from(index_value)
                    .map_err(|_| self.failure(index.span, "index out of range"))?;
                match collection {
                    ConstValue::Array(values)
                    | ConstValue::List(values)
                    | ConstValue::Queue(values)
                    | ConstValue::Ring(values) => values
                        .get(index_value)
                        .cloned()
                        .ok_or_else(|| self.failure(index.span, "index out of range"))?,
                    _ => return Err(self.failure(expr.span, "index receiver was not a collection")),
                }
            }
            TExprKind::BytesIndex {
                receiver, index, ..
            } => {
                let bytes = value_or_flow!(self.eval_expr(receiver, locals));
                let index_value = as_integer(&value_or_flow!(self.eval_expr(index, locals)));
                let index_value = usize::try_from(index_value)
                    .map_err(|_| self.failure(index.span, "index out of range"))?;
                match bytes {
                    ConstValue::String(bytes) => ConstValue::Integer(i128::from(
                        *bytes
                            .get(index_value)
                            .ok_or_else(|| self.failure(index.span, "index out of range"))?,
                    )),
                    _ => return Err(self.failure(expr.span, "index receiver was not Bytes")),
                }
            }
            TExprKind::Fill { value, capacity } => {
                let item = value_or_flow!(self.eval_expr(value, locals));
                let items = vec![item; *capacity];
                match self.types[expr.ty.0].kind {
                    TTypeKind::Array { .. } => ConstValue::Array(items),
                    TTypeKind::Grid { .. } => ConstValue::Grid(items),
                    _ => {
                        return Err(self.failure(expr.span, "fill target was not an array or grid"));
                    }
                }
            }
            _ => unreachable!("eval_access_expr called for another expression kind"),
        };
        Ok(Outcome::Value(value))
    }

    #[inline(never)]
    fn eval_misc_expr(
        &mut self,
        expr: &TExpr,
        locals: &mut Vec<Option<ConstValue>>,
    ) -> Result<Outcome, EvalFailure> {
        let value = match &expr.kind {
            TExprKind::Convert {
                value,
                min,
                max,
                policy,
            } => {
                let integer = as_integer(&value_or_flow!(self.eval_expr(value, locals)));
                ConstValue::Integer(self.convert_integer(integer, *min, *max, *policy, expr.span)?)
            }
            TExprKind::Fit {
                value, min, max, ..
            } => {
                let integer = as_integer(&value_or_flow!(self.eval_expr(value, locals)));
                if integer >= *min && integer <= *max {
                    ConstValue::Enum {
                        case_index: 0,
                        payload: vec![ConstValue::Integer(integer)],
                    }
                } else {
                    ConstValue::Enum {
                        case_index: 1,
                        payload: Vec::new(),
                    }
                }
            }
            TExprKind::Try {
                value,
                error_ty,
                propagated_ty,
                ..
            } => match value_or_flow!(self.eval_expr(value, locals)) {
                ConstValue::Enum {
                    case_index: 0,
                    payload,
                } => payload[0].clone(),
                ConstValue::Enum {
                    case_index: 1,
                    payload,
                } => {
                    let returned = if error_ty.is_some() {
                        ConstValue::Enum {
                            case_index: 1,
                            payload,
                        }
                    } else {
                        ConstValue::Enum {
                            case_index: 1,
                            payload: Vec::new(),
                        }
                    };
                    let _ = propagated_ty;
                    return Ok(Outcome::Return(returned));
                }
                _ => return Err(self.failure(expr.span, "'?' operand was not an Option or Result")),
            },
            TExprKind::Coalesce { option, fallback } => {
                match value_or_flow!(self.eval_expr(option, locals)) {
                    ConstValue::Enum {
                        case_index: 0,
                        payload,
                    } => payload[0].clone(),
                    ConstValue::Enum { case_index: 1, .. } => {
                        value_or_flow!(self.eval_expr(fallback, locals))
                    }
                    _ => return Err(self.failure(expr.span, "'??' operand was not an Option")),
                }
            }
            TExprKind::Match { scrutinee, arms } => {
                let value = value_or_flow!(self.eval_expr(scrutinee, locals));
                let mut selected = None;
                for arm in arms {
                    if pattern_matches(&arm.pattern, &value) {
                        selected = Some(arm);
                        break;
                    }
                }
                let arm = selected.ok_or_else(|| {
                    self.failure(
                        expr.span,
                        "match was not exhaustive during constant evaluation",
                    )
                })?;
                if let TPattern::Case { bindings, .. } = &arm.pattern {
                    if let ConstValue::Enum { payload, .. } = &value {
                        for (binding, field) in bindings.iter().zip(payload) {
                            if let Some(id) = binding {
                                set_local(locals, *id, field.clone());
                            }
                        }
                    }
                }
                return self.eval_block(&arm.body, locals);
            }
            TExprKind::Return(value) => {
                let returned = if let Some(value) = value {
                    value_or_flow!(self.eval_expr(value, locals))
                } else {
                    ConstValue::Unit
                };
                return Ok(Outcome::Return(returned));
            }
            TExprKind::LoopExit(is_break) => {
                return Ok(if *is_break {
                    Outcome::Break
                } else {
                    Outcome::Continue
                });
            }
            TExprKind::ToLong(value) => value_or_flow!(self.eval_expr(value, locals)),
            TExprKind::Cast { cast_span, value } => {
                let source = as_integer(&value_or_flow!(self.eval_expr(value, locals)));
                let (min, max) = refinement(expr.ty, self.types)
                    .map(|(_, min, max, _)| (min, max))
                    .or_else(|| integer_bounds(expr.ty, self.types))
                    .ok_or_else(|| self.failure(expr.span, "cast target is not an integer"))?;
                if source < min || source > max {
                    return Err(self.failure(*cast_span, "failed cast during constant evaluation"));
                }
                ConstValue::Integer(source)
            }
            TExprKind::Unary {
                op,
                operator_span,
                value,
            } => {
                let value = value_or_flow!(self.eval_expr(value, locals));
                match op {
                    UnaryOp::Not => ConstValue::Bool(!as_bool(&value)),
                    UnaryOp::Neg => {
                        let integer = as_integer(&value);
                        let (min, max) = integer_bounds(expr.ty, self.types).unwrap();
                        let negated = integer.checked_neg().ok_or_else(|| {
                            self.failure(*operator_span, "overflow in unary negation")
                        })?;
                        if negated < min || negated > max {
                            return Err(self.failure(*operator_span, "overflow in unary negation"));
                        }
                        ConstValue::Integer(negated)
                    }
                }
            }
            _ => unreachable!("eval_misc_expr called for another expression kind"),
        };
        Ok(Outcome::Value(value))
    }

    fn eval_expr(
        &mut self,
        expr: &TExpr,
        locals: &mut Vec<Option<ConstValue>>,
    ) -> Result<Outcome, EvalFailure> {
        self.step(expr.span)?;
        let value = match &expr.kind {
            TExprKind::Unit => ConstValue::Unit,
            TExprKind::Integer(value) => ConstValue::Integer(*value),
            TExprKind::Bool(value) => ConstValue::Bool(*value),
            TExprKind::ByteString(bytes) => {
                if matches!(&self.types[expr.ty.0].kind, TTypeKind::List { .. }) {
                    ConstValue::List(
                        bytes
                            .iter()
                            .map(|byte| ConstValue::Integer(i128::from(*byte)))
                            .collect(),
                    )
                } else {
                    ConstValue::String(bytes.clone())
                }
            }
            TExprKind::FunctionValue(id) => ConstValue::Function(*id),
            TExprKind::Local(id) => {
                if let Some(view) = self.views.get(id).cloned() {
                    let (root, path) = self.resolve_place_indices(&view, locals)?;
                    self.get_resolved_place(locals, root, &path)
                        .ok_or_else(|| {
                            self.failure(
                                expr.span,
                                "constant evaluator could not read a collection view",
                            )
                        })?
                } else {
                    get_local(locals, *id).ok_or_else(|| {
                        self.failure(expr.span, "constant evaluator could not read a local")
                    })?
                }
            }
            TExprKind::Constant(id) => {
                if let Some(constants) = self.constant_values {
                    return constants
                        .get(*id)
                        .cloned()
                        .map(Outcome::Value)
                        .ok_or_else(|| {
                            self.failure(expr.span, "constant reference was out of range")
                        });
                }
                return self
                    .eval_constant(*id, expr.span)
                    .map(Outcome::Value)
                    .map_err(|error| EvalFailure {
                        span: error.span,
                        message: error.message,
                        chain: Vec::new(),
                        step_limit: false,
                        call_depth_limit: false,
                    });
            }
            TExprKind::Global(_) => {
                return Err(self.failure(
                    expr.span,
                    "compile-time evaluation cannot read global state",
                ));
            }
            TExprKind::Call { .. }
            | TExprKind::IndirectCall { .. }
            | TExprKind::Construct { .. } => return self.eval_call_expr(expr, locals),
            TExprKind::Method { .. }
            | TExprKind::OptionalCall { .. }
            | TExprKind::OptionalToLong(_)
            | TExprKind::Field { .. }
            | TExprKind::Index { .. }
            | TExprKind::BytesIndex { .. }
            | TExprKind::Fill { .. } => return self.eval_access_expr(expr, locals),
            TExprKind::EmptyArray
            | TExprKind::EmptyGrid
            | TExprKind::EmptyList
            | TExprKind::EmptyQueue
            | TExprKind::EmptyRing
            | TExprKind::EmptyPool
            | TExprKind::EmptyMap
            | TExprKind::EmptySet
            | TExprKind::CollectionOp { .. }
            | TExprKind::PoolOp { .. }
            | TExprKind::MapOp { .. }
            | TExprKind::SetOp { .. }
            | TExprKind::StructConstruct { .. }
            | TExprKind::CollectionLiteral(_) => return self.eval_collection_expr(expr, locals),
            TExprKind::Convert { .. }
            | TExprKind::Fit { .. }
            | TExprKind::Try { .. }
            | TExprKind::Coalesce { .. }
            | TExprKind::Match { .. }
            | TExprKind::Return(_)
            | TExprKind::LoopExit(_)
            | TExprKind::ToLong(_)
            | TExprKind::Cast { .. }
            | TExprKind::Unary { .. } => return self.eval_misc_expr(expr, locals),
            TExprKind::AsciiEmpty
            | TExprKind::TextEmpty
            | TExprKind::BytesEmpty
            | TExprKind::AsciiUpper(_)
            | TExprKind::TextUpper(_)
            | TExprKind::AsciiFormat { .. }
            | TExprKind::AsciiPad { .. }
            | TExprKind::AsciiZeroPad { .. }
            | TExprKind::ParseInteger { .. }
            | TExprKind::AsciiTryAppend { .. }
            | TExprKind::TextTryAppend { .. }
            | TExprKind::BytesTryAppend { .. }
            | TExprKind::BytesPush { .. }
            | TExprKind::BytesValidateUtf8(_)
            | TExprKind::AsciiCast(_)
            | TExprKind::AsciiFit { .. }
            | TExprKind::TextSlice { .. }
            | TExprKind::AsciiSlice { .. }
            | TExprKind::BytesSlice { .. }
            | TExprKind::BytesView(_)
            | TExprKind::TextConvert { .. }
            | TExprKind::Take(_) => {
                return Err(self.failure(
                    expr.span,
                    "Ascii values are not supported during compile-time evaluation",
                ));
            }
            TExprKind::Binary {
                op,
                operator_span,
                left,
                right,
            } => return self.eval_binary_expr(expr, locals, *op, *operator_span, left, right),
            TExprKind::If {
                condition,
                then_block,
                else_block,
            } => return self.eval_if_expr(locals, condition, then_block, else_block.as_ref()),
        };
        Ok(Outcome::Value(value))
    }

    #[inline(never)]
    fn eval_binary_expr(
        &mut self,
        expr: &TExpr,
        locals: &mut Vec<Option<ConstValue>>,
        op: BinaryOp,
        operator_span: Span,
        left: &TExpr,
        right: &TExpr,
    ) -> Result<Outcome, EvalFailure> {
        let left = value_or_flow!(self.eval_expr(left, locals));
        if op == BinaryOp::And && !as_bool(&left) {
            return Ok(Outcome::Value(ConstValue::Bool(false)));
        }
        if op == BinaryOp::Or && as_bool(&left) {
            return Ok(Outcome::Value(ConstValue::Bool(true)));
        }
        if op == BinaryOp::Coalesce {
            return match left {
                ConstValue::Enum {
                    case_index: 0,
                    payload,
                } => Ok(Outcome::Value(payload[0].clone())),
                ConstValue::Enum { case_index: 1, .. } => self.eval_expr(right, locals),
                _ => Err(self.failure(operator_span, "'??' operand was not an Option")),
            };
        }
        let right = value_or_flow!(self.eval_expr(right, locals));
        self.eval_binary(op, expr.ty, left, right, operator_span)
            .map(Outcome::Value)
    }

    #[inline(never)]
    fn eval_if_expr(
        &mut self,
        locals: &mut Vec<Option<ConstValue>>,
        condition: &TExpr,
        then_block: &TBlock,
        else_block: Option<&TBlock>,
    ) -> Result<Outcome, EvalFailure> {
        let condition = value_or_flow!(self.eval_expr(condition, locals));
        if as_bool(&condition) {
            return self.eval_block(then_block, locals);
        }
        if let Some(other) = else_block {
            return self.eval_block(other, locals);
        }
        Ok(Outcome::Value(ConstValue::Unit))
    }

    fn call_function(
        &mut self,
        id: usize,
        args: Vec<ConstValue>,
        call_span: Span,
    ) -> Result<ConstValue, EvalFailure> {
        if self.call_depth >= CALL_DEPTH_LIMIT {
            return Err(EvalFailure {
                span: call_span,
                message: format!(
                    "compile-time function call depth limit of {CALL_DEPTH_LIMIT} exceeded"
                ),
                chain: Vec::new(),
                step_limit: false,
                call_depth_limit: true,
            });
        }
        self.step(call_span)?;
        self.call_depth += 1;
        let function = self.functions[id].clone();
        if function.is_test || function.params.len() != args.len() {
            self.call_depth -= 1;
            return Err(self.failure(
                call_span,
                "invalid function call during constant evaluation",
            ));
        }
        let mut locals = Vec::new();
        for (param, value) in function.params.iter().zip(args) {
            if param.mode == ParamMode::Write {
                self.call_depth -= 1;
                return Err(self.failure(
                    call_span,
                    "write parameters cannot be evaluated at compile time",
                ));
            }
            set_local(&mut locals, param.id, value);
        }
        let saved_views = std::mem::take(&mut self.views);
        let outcome = self.eval_block(&function.body, &mut locals);
        self.views = saved_views;
        self.call_depth -= 1;
        outcome
            .map_err(|mut failure| {
                if !failure.call_depth_limit {
                    failure.chain.insert(0, function.name.clone());
                }
                failure
            })
            .and_then(|outcome| match outcome {
                Outcome::Value(value) | Outcome::Return(value) => Ok(value),
                Outcome::Break | Outcome::Continue => Err(self.failure(
                    function.span,
                    "loop exit escaped its loop during constant evaluation",
                )),
            })
    }

    fn eval_method(
        &self,
        kind: MethodKind,
        receiver: ConstValue,
        span: Span,
    ) -> Result<ConstValue, EvalFailure> {
        if matches!(
            kind,
            MethodKind::ByteIsDigit
                | MethodKind::ByteIsAlpha
                | MethodKind::ByteIsSpace
                | MethodKind::ByteToLower
                | MethodKind::ByteToUpper
        ) {
            let byte = as_integer(&receiver);
            return Ok(match kind {
                MethodKind::ByteIsDigit => {
                    ConstValue::Bool((b'0' as i128..=b'9' as i128).contains(&byte))
                }
                MethodKind::ByteIsAlpha => ConstValue::Bool(
                    (b'A' as i128..=b'Z' as i128).contains(&byte)
                        || (b'a' as i128..=b'z' as i128).contains(&byte),
                ),
                MethodKind::ByteIsSpace => {
                    ConstValue::Bool((9..=13).contains(&byte) || byte == b' ' as i128)
                }
                MethodKind::ByteToLower if (b'A' as i128..=b'Z' as i128).contains(&byte) => {
                    ConstValue::Integer(byte + 32)
                }
                MethodKind::ByteToUpper if (b'a' as i128..=b'z' as i128).contains(&byte) => {
                    ConstValue::Integer(byte - 32)
                }
                MethodKind::ByteToLower | MethodKind::ByteToUpper => ConstValue::Integer(byte),
                _ => unreachable!(),
            });
        }
        let ConstValue::Enum {
            case_index,
            payload,
        } = receiver
        else {
            return Err(self.failure(span, "enum method receiver was not an enum"));
        };
        Ok(match kind {
            MethodKind::AsciiLen => {
                return Err(self.failure(
                    span,
                    "Ascii values are not supported during compile-time evaluation",
                ));
            }
            MethodKind::TextLen | MethodKind::TextByteLen | MethodKind::BytesLen => {
                return Err(self.failure(
                    span,
                    "Text and Bytes values are not supported during compile-time evaluation",
                ));
            }
            MethodKind::IsNone => ConstValue::Bool(case_index == 1),
            MethodKind::IsSome => ConstValue::Bool(case_index == 0),
            MethodKind::IsOk => ConstValue::Bool(case_index == 0),
            MethodKind::IsErr => ConstValue::Bool(case_index == 1),
            MethodKind::ResultOk => {
                if case_index == 0 {
                    ConstValue::Enum {
                        case_index: 0,
                        payload: vec![payload[0].clone()],
                    }
                } else {
                    ConstValue::Enum {
                        case_index: 1,
                        payload: Vec::new(),
                    }
                }
            }
            MethodKind::UnwrapOption if case_index == 0 => payload[0].clone(),
            MethodKind::UnwrapResult if case_index == 0 => payload[0].clone(),
            MethodKind::UnwrapOption | MethodKind::UnwrapResult => {
                return Err(self.failure(span, "unwrap failed during constant evaluation"));
            }
            MethodKind::ByteIsDigit
            | MethodKind::ByteIsAlpha
            | MethodKind::ByteIsSpace
            | MethodKind::ByteToLower
            | MethodKind::ByteToUpper => unreachable!("byte methods were handled above"),
        })
    }

    fn convert_integer(
        &self,
        value: i128,
        min: i128,
        max: i128,
        policy: RefinePolicy,
        span: Span,
    ) -> Result<i128, EvalFailure> {
        if value >= min && value <= max {
            return Ok(value);
        }
        match policy {
            RefinePolicy::Checked => {
                Err(self.failure(span, "failed cast during constant evaluation"))
            }
            RefinePolicy::Clamp => Ok(value.clamp(min, max)),
            RefinePolicy::Wrap => {
                let width = max - min + 1;
                Ok(min + (value - min).rem_euclid(width))
            }
        }
    }

    fn eval_binary(
        &self,
        op: BinaryOp,
        ty: Ty,
        left: ConstValue,
        right: ConstValue,
        span: Span,
    ) -> Result<ConstValue, EvalFailure> {
        if matches!(op, BinaryOp::Eq | BinaryOp::Ne) {
            let equal = self.values_equal(ty, &left, &right);
            return Ok(ConstValue::Bool(if op == BinaryOp::Eq {
                equal
            } else {
                !equal
            }));
        }
        if matches!(op, BinaryOp::And | BinaryOp::Or) {
            let a = as_bool(&left);
            let b = as_bool(&right);
            return Ok(ConstValue::Bool(if op == BinaryOp::And {
                a && b
            } else {
                a || b
            }));
        }
        if matches!(
            op,
            BinaryOp::Lt | BinaryOp::Le | BinaryOp::Gt | BinaryOp::Ge
        ) {
            let ordering = match (&left, &right) {
                (ConstValue::Bool(a), ConstValue::Bool(b)) => a.cmp(b),
                _ => as_integer(&left).cmp(&as_integer(&right)),
            };
            return Ok(ConstValue::Bool(match op {
                BinaryOp::Lt => ordering.is_lt(),
                BinaryOp::Le => !ordering.is_gt(),
                BinaryOp::Gt => ordering.is_gt(),
                BinaryOp::Ge => !ordering.is_lt(),
                _ => unreachable!(),
            }));
        }
        let a = as_integer(&left);
        let b = as_integer(&right);
        let (min, max) = integer_bounds(ty, self.types)
            .ok_or_else(|| self.failure(span, "arithmetic operand is not an integer"))?;
        let width = if base_type(ty, self.types) == Ty::Int {
            32
        } else {
            64
        };
        let overflow = || {
            self.failure(
                span,
                format!(
                    "overflow in {} arithmetic",
                    if width == 32 { "int" } else { "long" }
                ),
            )
        };
        let result = match op {
            BinaryOp::Add => a
                .checked_add(b)
                .filter(|v| *v >= min && *v <= max)
                .ok_or_else(overflow)?,
            BinaryOp::Sub => a
                .checked_sub(b)
                .filter(|v| *v >= min && *v <= max)
                .ok_or_else(overflow)?,
            BinaryOp::Mul => a
                .checked_mul(b)
                .filter(|v| *v >= min && *v <= max)
                .ok_or_else(overflow)?,
            BinaryOp::Div => {
                if b == 0 {
                    return Err(self.failure(span, "division by zero during constant evaluation"));
                }
                if a == min && b == -1 {
                    return Err(overflow());
                }
                a / b
            }
            BinaryOp::Rem => {
                if b == 0 {
                    return Err(self.failure(span, "remainder by zero during constant evaluation"));
                }
                if a == min && b == -1 {
                    0
                } else {
                    a % b
                }
            }
            BinaryOp::WrapAdd => wrap_base(a.wrapping_add(b), width),
            BinaryOp::WrapSub => wrap_base(a.wrapping_sub(b), width),
            BinaryOp::WrapMul => wrap_base(a.wrapping_mul(b), width),
            BinaryOp::BitAnd => a & b,
            BinaryOp::BitOr => a | b,
            BinaryOp::BitXor => a ^ b,
            BinaryOp::Shl | BinaryOp::Shr => {
                if b < 0 || b >= width {
                    return Err(
                        self.failure(span, "invalid shift count during constant evaluation")
                    );
                }
                if op == BinaryOp::Shl {
                    wrap_base(a.wrapping_shl(b as u32), width)
                } else {
                    a >> b
                }
            }
            _ => {
                return Err(
                    self.failure(span, "unsupported binary operator in constant evaluation")
                );
            }
        };
        Ok(ConstValue::Integer(result))
    }

    fn values_equal(&self, ty: Ty, left: &ConstValue, right: &ConstValue) -> bool {
        match (&self.types[ty.0].kind, left, right) {
            (TTypeKind::Refinement { base, .. }, _, _) => self.values_equal(*base, left, right),
            (
                TTypeKind::Function { .. },
                ConstValue::Function(left),
                ConstValue::Function(right),
            ) => left == right,
            (
                TTypeKind::Pool {
                    element, capacity, ..
                },
                ConstValue::Pool {
                    slots: left_slots,
                    generations: left_generations,
                    ..
                },
                ConstValue::Pool {
                    slots: right_slots,
                    generations: right_generations,
                    ..
                },
            ) => {
                if left_slots.len() != *capacity
                    || right_slots.len() != *capacity
                    || left_generations.len() != *capacity
                    || right_generations.len() != *capacity
                {
                    return false;
                }
                (0..*capacity).all(|slot| match (&left_slots[slot], &right_slots[slot]) {
                    (None, None) => true,
                    (Some(left), Some(right)) => {
                        left_generations[slot] == right_generations[slot]
                            && self.values_equal(*element, left, right)
                    }
                    _ => false,
                })
            }
            (
                TTypeKind::Struct(fields),
                ConstValue::Struct(left_fields),
                ConstValue::Struct(right_fields),
            ) => {
                fields.len() == left_fields.len()
                    && fields.len() == right_fields.len()
                    && fields.iter().enumerate().all(|(index, field)| {
                        self.values_equal(field.ty, &left_fields[index], &right_fields[index])
                    })
            }
            (
                TTypeKind::Array { element, capacity },
                ConstValue::Array(left_values),
                ConstValue::Array(right_values),
            ) => {
                left_values.len() == right_values.len()
                    && left_values.len() <= *capacity
                    && left_values
                        .iter()
                        .zip(right_values)
                        .all(|(left, right)| self.values_equal(*element, left, right))
            }
            (
                TTypeKind::Grid {
                    element, capacity, ..
                },
                ConstValue::Grid(left_values),
                ConstValue::Grid(right_values),
            ) => {
                left_values.len() == *capacity
                    && right_values.len() == *capacity
                    && left_values
                        .iter()
                        .zip(right_values)
                        .all(|(left, right)| self.values_equal(*element, left, right))
            }
            (
                TTypeKind::List { element, capacity },
                ConstValue::List(left_values),
                ConstValue::List(right_values),
            )
            | (
                TTypeKind::Queue { element, capacity },
                ConstValue::Queue(left_values),
                ConstValue::Queue(right_values),
            )
            | (
                TTypeKind::Ring { element, capacity },
                ConstValue::Ring(left_values),
                ConstValue::Ring(right_values),
            ) => {
                left_values.len() == right_values.len()
                    && left_values.len() <= *capacity
                    && left_values
                        .iter()
                        .zip(right_values)
                        .all(|(left, right)| self.values_equal(*element, left, right))
            }
            (
                TTypeKind::Map {
                    key,
                    value,
                    capacity,
                },
                ConstValue::Map(left_entries),
                ConstValue::Map(right_entries),
            ) => {
                left_entries.len() == right_entries.len()
                    && left_entries.len() <= *capacity
                    && left_entries.iter().all(|(left_key, left_value)| {
                        right_entries
                            .iter()
                            .find(|(right_key, _)| self.values_equal(*key, left_key, right_key))
                            .is_some_and(|(_, right_value)| {
                                self.values_equal(*value, left_value, right_value)
                            })
                    })
            }
            (
                TTypeKind::Set { key, capacity },
                ConstValue::Set(left_entries),
                ConstValue::Set(right_entries),
            ) => {
                left_entries.len() == right_entries.len()
                    && left_entries.len() <= *capacity
                    && left_entries.iter().all(|left_key| {
                        right_entries
                            .iter()
                            .any(|right_key| self.values_equal(*key, left_key, right_key))
                    })
            }
            (
                TTypeKind::Option(_) | TTypeKind::Result(..) | TTypeKind::Enum(_),
                ConstValue::Enum {
                    case_index: left_case,
                    payload: left_payload,
                },
                ConstValue::Enum {
                    case_index: right_case,
                    payload: right_payload,
                },
            ) => {
                if left_case != right_case {
                    return false;
                }
                let cases = self.types[ty.0].cases();
                let Some(case) = cases.get(*left_case) else {
                    return false;
                };
                case.payload.len() == left_payload.len()
                    && case.payload.len() == right_payload.len()
                    && case
                        .payload
                        .iter()
                        .zip(left_payload.iter().zip(right_payload))
                        .all(|(field, (left, right))| self.values_equal(*field, left, right))
            }
            _ => left == right,
        }
    }
}

fn set_local(locals: &mut Vec<Option<ConstValue>>, id: usize, value: ConstValue) {
    if locals.len() <= id {
        locals.resize_with(id + 1, || None);
    }
    locals[id] = Some(value);
}

fn get_local(locals: &[Option<ConstValue>], id: usize) -> Option<ConstValue> {
    locals.get(id).and_then(Clone::clone)
}

fn pattern_matches(pattern: &TPattern, value: &ConstValue) -> bool {
    match pattern {
        TPattern::Wildcard => true,
        TPattern::Integer(expected) => {
            matches!(value, ConstValue::Integer(actual) if actual == expected)
        }
        TPattern::Bool(expected) => matches!(value, ConstValue::Bool(actual) if actual == expected),
        TPattern::Case { case_index, .. } => {
            matches!(value, ConstValue::Enum { case_index: actual, .. } if actual == case_index)
        }
    }
}

fn as_integer(value: &ConstValue) -> i128 {
    match value {
        ConstValue::Integer(value) => *value,
        _ => unreachable!("typed constant evaluator expected integer"),
    }
}

fn as_bool(value: &ConstValue) -> bool {
    match value {
        ConstValue::Bool(value) => *value,
        _ => unreachable!("typed constant evaluator expected bool"),
    }
}

fn integer_bounds(ty: Ty, types: &[TType]) -> Option<(i128, i128)> {
    match base_type(ty, types) {
        Ty::Int => Some((i32::MIN as i128, i32::MAX as i128)),
        Ty::Long => Some((i64::MIN as i128, i64::MAX as i128)),
        _ => None,
    }
}

fn wrap_base(value: i128, width: i128) -> i128 {
    if width == 32 {
        (value as i32) as i128
    } else {
        (value as i64) as i128
    }
}

#[cfg(test)]
mod pool_tests {
    use super::*;

    fn evaluator(types: &[TType]) -> Evaluator<'_> {
        Evaluator {
            declarations: &[],
            functions: &[],
            types,
            values: Vec::new(),
            states: Vec::new(),
            active_constants: Vec::new(),
            constant_values: None,
            views: HashMap::new(),
            steps: 0,
            call_depth: 0,
        }
    }

    #[test]
    fn pool_rejects_out_of_range_ids_and_retires_max_generation_slots() {
        let evaluator = evaluator(&[]);
        let mut pool = ConstValue::Pool {
            slots: vec![Some(ConstValue::Integer(7))],
            generations: vec![1],
            free: Vec::new(),
            high_water: 1,
        };
        let out_of_range = evaluator
            .eval_pool_op(
                PoolOp::Get,
                &mut pool,
                vec![ConstValue::Integer(1)],
                1,
                Span::default(),
            )
            .unwrap();
        assert_eq!(
            out_of_range,
            ConstValue::Enum {
                case_index: 1,
                payload: Vec::new(),
            }
        );
        assert_eq!(
            pool,
            ConstValue::Pool {
                slots: vec![Some(ConstValue::Integer(7))],
                generations: vec![1],
                free: Vec::new(),
                high_water: 1,
            }
        );

        let generation = u32::MAX - 1;
        let id = ((generation as u64) << 32) as i128;
        let mut near_retirement = ConstValue::Pool {
            slots: vec![Some(ConstValue::Integer(9))],
            generations: vec![generation],
            free: Vec::new(),
            high_water: 1,
        };
        let removed = evaluator
            .eval_pool_op(
                PoolOp::Remove,
                &mut near_retirement,
                vec![ConstValue::Integer(id)],
                1,
                Span::default(),
            )
            .unwrap();
        assert_eq!(
            removed,
            ConstValue::Enum {
                case_index: 0,
                payload: vec![ConstValue::Integer(9)],
            }
        );
        assert_eq!(
            near_retirement,
            ConstValue::Pool {
                slots: vec![None],
                generations: vec![u32::MAX],
                free: Vec::new(),
                high_water: 1,
            }
        );
        let full = evaluator
            .eval_pool_op(
                PoolOp::Add,
                &mut near_retirement,
                vec![ConstValue::Integer(10)],
                1,
                Span::default(),
            )
            .unwrap();
        assert_eq!(
            full,
            ConstValue::Enum {
                case_index: 1,
                payload: vec![ConstValue::Enum {
                    case_index: 0,
                    payload: Vec::new(),
                }],
            }
        );
        assert_eq!(
            near_retirement,
            ConstValue::Pool {
                slots: vec![None],
                generations: vec![u32::MAX],
                free: Vec::new(),
                high_water: 1,
            }
        );
    }

    #[test]
    fn pool_equality_ignores_free_list_and_vacant_generations() {
        let mut types = vec![
            TType {
                name: "int".to_owned(),
                kind: TTypeKind::Int,
                span: Span::default(),
            },
            TType {
                name: "long".to_owned(),
                kind: TTypeKind::Long,
                span: Span::default(),
            },
            TType {
                name: "bool".to_owned(),
                kind: TTypeKind::Bool,
                span: Span::default(),
            },
            TType {
                name: "()".to_owned(),
                kind: TTypeKind::Unit,
                span: Span::default(),
            },
            TType {
                name: "never".to_owned(),
                kind: TTypeKind::Never,
                span: Span::default(),
            },
        ];
        types.push(TType {
            name: "pool<int, 2>".to_owned(),
            kind: TTypeKind::Pool {
                element: Ty::Int,
                capacity: 2,
                owner: 0,
            },
            span: Span::default(),
        });
        let evaluator = evaluator(&types);
        let left = ConstValue::Pool {
            slots: vec![Some(ConstValue::Integer(7)), None],
            generations: vec![3, 10],
            free: vec![1],
            high_water: 1,
        };
        let right = ConstValue::Pool {
            slots: vec![Some(ConstValue::Integer(7)), None],
            generations: vec![3, 99],
            free: Vec::new(),
            high_water: 2,
        };
        assert!(evaluator.values_equal(Ty(5), &left, &right));
        let different_live_generation = ConstValue::Pool {
            slots: vec![Some(ConstValue::Integer(7)), None],
            generations: vec![4, 99],
            free: Vec::new(),
            high_water: 2,
        };
        assert!(!evaluator.values_equal(Ty(5), &left, &different_live_generation));
    }

    #[test]
    fn pool_reuses_freed_slots_before_growing_the_high_water_mark() {
        let evaluator = evaluator(&[]);
        let mut pool = ConstValue::Pool {
            slots: vec![None, None, None],
            generations: vec![7, 1, 1],
            free: vec![0],
            high_water: 1,
        };
        let reused = evaluator
            .eval_pool_op(
                PoolOp::Add,
                &mut pool,
                vec![ConstValue::Integer(42)],
                3,
                Span::default(),
            )
            .unwrap();
        assert_eq!(
            reused,
            ConstValue::Enum {
                case_index: 0,
                payload: vec![ConstValue::Integer((7u64 << 32) as i128)],
            }
        );
        assert_eq!(
            pool,
            ConstValue::Pool {
                slots: vec![Some(ConstValue::Integer(42)), None, None],
                generations: vec![7, 1, 1],
                free: Vec::new(),
                high_water: 1,
            }
        );

        let fresh = evaluator
            .eval_pool_op(
                PoolOp::Add,
                &mut pool,
                vec![ConstValue::Integer(43)],
                3,
                Span::default(),
            )
            .unwrap();
        assert_eq!(
            fresh,
            ConstValue::Enum {
                case_index: 0,
                payload: vec![ConstValue::Integer(((1u64 << 32) | 1) as i128)],
            }
        );
        assert!(matches!(pool, ConstValue::Pool { high_water: 2, .. }));
    }

    #[test]
    fn retired_slots_are_skipped_and_ids_past_high_water_are_stale() {
        let evaluator = evaluator(&[]);
        let mut pool = ConstValue::Pool {
            slots: vec![None, None],
            generations: vec![u32::MAX, 1],
            free: Vec::new(),
            high_water: 1,
        };
        let retired_id = ((u32::MAX as u64) << 32) as i128;
        let stale = evaluator
            .eval_pool_op(
                PoolOp::Get,
                &mut pool,
                vec![ConstValue::Integer(retired_id)],
                2,
                Span::default(),
            )
            .unwrap();
        assert_eq!(
            stale,
            ConstValue::Enum {
                case_index: 1,
                payload: Vec::new()
            }
        );

        let past_mark = evaluator
            .eval_pool_op(
                PoolOp::Get,
                &mut pool,
                vec![ConstValue::Integer(((1u64 << 32) | 1) as i128)],
                2,
                Span::default(),
            )
            .unwrap();
        assert_eq!(
            past_mark,
            ConstValue::Enum {
                case_index: 1,
                payload: Vec::new()
            }
        );

        let added = evaluator
            .eval_pool_op(
                PoolOp::Add,
                &mut pool,
                vec![ConstValue::Integer(9)],
                2,
                Span::default(),
            )
            .unwrap();
        assert_eq!(
            added,
            ConstValue::Enum {
                case_index: 0,
                payload: vec![ConstValue::Integer(((1u64 << 32) | 1) as i128)],
            }
        );
        assert!(matches!(pool, ConstValue::Pool { high_water: 2, .. }));
    }
}
