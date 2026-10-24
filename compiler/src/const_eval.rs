use crate::ast::{AssignOp, BinaryOp, ParamMode, RefinePolicy, Span, UnaryOp};
use crate::checker::CheckError;
use crate::typed::*;

const STEP_LIMIT: u64 = 10_000_000;

pub fn evaluate_constants(
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
        steps: 0,
    };
    for declaration in declarations {
        evaluator.eval_constant(declaration.id, declaration.span)?;
    }
    Ok(declarations
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
        .collect())
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
            TStmtKind::Expect { kind, .. } => match kind {
                TExpectKind::Bool(value) => collect_constant_references_expr(value, references),
                TExpectKind::Compare { left, right, .. } => {
                    collect_constant_references_expr(left, references);
                    collect_constant_references_expr(right, references);
                }
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
        | TExprKind::Cast {
            value: receiver, ..
        }
        | TExprKind::Unary {
            value: receiver, ..
        } => collect_constant_references_expr(receiver, references),
        TExprKind::OptionalCall { receiver, args, .. } => {
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
        | TExprKind::Local(_)
        | TExprKind::LoopExit(_) => {}
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
    let mut calls = Vec::<(usize, Span)>::new();
    let mut effects = Vec::<Span>::new();
    collect_calls_expr(expr, &mut calls, &mut effects);
    if let Some(span) = effects.first() {
        return Some(CacheabilityProblem {
            reason: "compile-time evaluation cannot reach an effect".to_owned(),
            chain: vec!["print".to_owned()],
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

fn function_cacheability_problem(
    id: usize,
    functions: &[TFunction],
    call_graph: &[Vec<TCallEdge>],
    types: &[TType],
    memo: &mut [Option<Option<(String, Vec<String>)>>],
) -> Option<(String, Vec<String>)> {
    if let Some(cached) = &memo[id] {
        return cached.clone();
    }
    let function = &functions[id];
    if function
        .params
        .iter()
        .any(|param| param.mode == ParamMode::Write)
    {
        let problem = Some((
            "cacheable functions cannot have write parameters".to_owned(),
            vec![function.name.clone(), "write parameter".to_owned()],
        ));
        memo[id] = Some(problem.clone());
        return problem;
    }
    let mut calls = Vec::new();
    let mut effects = Vec::new();
    collect_calls_block(&function.body, &mut calls, &mut effects);
    if !effects.is_empty() {
        let problem = Some((
            "compile-time evaluation cannot reach an effect".to_owned(),
            vec![function.name.clone(), "print".to_owned()],
        ));
        memo[id] = Some(problem.clone());
        return problem;
    }
    for edge in &call_graph[id] {
        if let Some((reason, mut chain)) =
            function_cacheability_problem(edge.target, functions, call_graph, types, memo)
        {
            chain.insert(0, function.name.clone());
            let problem = Some((reason, chain));
            memo[id] = Some(problem.clone());
            return problem;
        }
    }
    // The typed call graph records user calls. This scan also catches an optional call if
    // a future checker path forgets to add its edge.
    for (target, _) in calls {
        if let Some((reason, mut chain)) =
            function_cacheability_problem(target, functions, call_graph, types, memo)
        {
            chain.insert(0, function.name.clone());
            let problem = Some((reason, chain));
            memo[id] = Some(problem.clone());
            return problem;
        }
    }
    memo[id] = Some(None);
    None
}

fn collect_calls_block(block: &TBlock, calls: &mut Vec<(usize, Span)>, effects: &mut Vec<Span>) {
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
            TStmtKind::Expect { kind, .. } => match kind {
                TExpectKind::Bool(value) => collect_calls_expr(value, calls, effects),
                TExpectKind::Compare { left, right, .. } => {
                    collect_calls_expr(left, calls, effects);
                    collect_calls_expr(right, calls, effects);
                }
            },
            TStmtKind::Block(inner) => collect_calls_block(inner, calls, effects),
            TStmtKind::Break | TStmtKind::Continue => {}
        }
    }
    if let Some(tail) = &block.tail {
        collect_calls_expr(tail, calls, effects);
    }
}

fn collect_calls_expr(expr: &TExpr, calls: &mut Vec<(usize, Span)>, effects: &mut Vec<Span>) {
    match &expr.kind {
        TExprKind::Call { target, args, .. } => {
            match target {
                CallTarget::Function(id) => calls.push((*id, expr.span)),
                CallTarget::Print => effects.push(expr.span),
                CallTarget::Min | CallTarget::Max => {}
            }
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
        TExprKind::StructConstruct { fields } => {
            for (_, value) in fields {
                collect_calls_expr(value, calls, effects);
            }
        }
        TExprKind::Convert { value, .. }
        | TExprKind::Fit { value, .. }
        | TExprKind::Try { value, .. }
        | TExprKind::Cast { value, .. }
        | TExprKind::Unary { value, .. } => collect_calls_expr(value, calls, effects),
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
        | TExprKind::Local(_)
        | TExprKind::Constant(_)
        | TExprKind::LoopExit(_) => {}
    }
}

#[derive(Clone, Debug)]
struct EvalFailure {
    span: Span,
    message: String,
    chain: Vec<String>,
    step_limit: bool,
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
    steps: u64,
}

impl Evaluator<'_> {
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
        let evaluated = self.eval_expr(&declaration.expr, &mut Vec::new());
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
        }
    }

    fn eval_block(
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
                    let rhs = value_or_flow!(self.eval_expr(value, locals));
                    let new_value = if *op == AssignOp::Set {
                        rhs
                    } else {
                        let old = get_place(locals, place).ok_or_else(|| {
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
                    set_place(locals, place, new_value)
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
        if let Some(tail) = &block.tail {
            self.eval_expr(tail, locals)
        } else {
            Ok(Outcome::Value(ConstValue::Unit))
        }
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
            TExprKind::Local(id) => get_local(locals, *id).ok_or_else(|| {
                self.failure(expr.span, "constant evaluator could not read a local")
            })?,
            TExprKind::Constant(id) => {
                return self
                    .eval_constant(*id, expr.span)
                    .map(Outcome::Value)
                    .map_err(|error| EvalFailure {
                        span: error.span,
                        message: error.message,
                        chain: Vec::new(),
                        step_limit: false,
                    });
            }
            TExprKind::Call { target, args, .. } => match target {
                CallTarget::Function(id) => {
                    let mut values = Vec::with_capacity(args.len());
                    for arg in args {
                        values.push(value_or_flow!(self.eval_expr(arg, locals)));
                    }
                    self.call_function(*id, values, expr.span)?
                }
                CallTarget::Print => {
                    return Err(self.failure(
                        expr.span,
                        "effect 'print' reached during constant evaluation",
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
            },
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
            TExprKind::Binary {
                op,
                operator_span,
                left,
                right,
            } => {
                let left = value_or_flow!(self.eval_expr(left, locals));
                if *op == BinaryOp::And && !as_bool(&left) {
                    return Ok(Outcome::Value(ConstValue::Bool(false)));
                }
                if *op == BinaryOp::Or && as_bool(&left) {
                    return Ok(Outcome::Value(ConstValue::Bool(true)));
                }
                if *op == BinaryOp::Coalesce {
                    return match left {
                        ConstValue::Enum {
                            case_index: 0,
                            payload,
                        } => Ok(Outcome::Value(payload[0].clone())),
                        ConstValue::Enum { case_index: 1, .. } => self.eval_expr(right, locals),
                        _ => Err(self.failure(*operator_span, "'??' operand was not an Option")),
                    };
                }
                let right = value_or_flow!(self.eval_expr(right, locals));
                self.eval_binary(*op, expr.ty, left, right, *operator_span)?
            }
            TExprKind::If {
                condition,
                then_block,
                else_block,
            } => {
                let condition = value_or_flow!(self.eval_expr(condition, locals));
                if as_bool(&condition) {
                    return self.eval_block(then_block, locals);
                }
                if let Some(other) = else_block {
                    return self.eval_block(other, locals);
                }
                ConstValue::Unit
            }
        };
        Ok(Outcome::Value(value))
    }

    fn call_function(
        &mut self,
        id: usize,
        args: Vec<ConstValue>,
        call_span: Span,
    ) -> Result<ConstValue, EvalFailure> {
        let function = self.functions[id].clone();
        if function.is_test || function.params.len() != args.len() {
            return Err(self.failure(
                call_span,
                "invalid function call during constant evaluation",
            ));
        }
        let mut locals = Vec::new();
        for (param, value) in function.params.iter().zip(args) {
            if param.mode == ParamMode::Write {
                return Err(self.failure(
                    call_span,
                    "write parameters cannot be evaluated at compile time",
                ));
            }
            set_local(&mut locals, param.id, value);
        }
        let outcome = self.eval_block(&function.body, &mut locals);
        outcome
            .map_err(|mut failure| {
                failure.chain.insert(0, function.name.clone());
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
        let ConstValue::Enum {
            case_index,
            payload,
        } = receiver
        else {
            return Err(self.failure(span, "enum method receiver was not an enum"));
        };
        Ok(match kind {
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
            let equal = left == right;
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
                if a == min && b == -1 { 0 } else { a % b }
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

fn get_place(locals: &[Option<ConstValue>], place: &TPlace) -> Option<ConstValue> {
    let mut value = get_local(locals, place.root)?;
    for field in &place.fields {
        let ConstValue::Struct(fields) = value else {
            return None;
        };
        value = fields.get(*field)?.clone();
    }
    Some(value)
}

fn set_place(
    locals: &mut Vec<Option<ConstValue>>,
    place: &TPlace,
    value: ConstValue,
) -> Result<(), String> {
    if place.fields.is_empty() {
        set_local(locals, place.root, value);
        return Ok(());
    }
    let Some(mut root) = get_local(locals, place.root) else {
        return Err("constant evaluator could not write an uninitialised local".to_owned());
    };
    set_nested_field(&mut root, &place.fields, value)?;
    set_local(locals, place.root, root);
    Ok(())
}

fn set_nested_field(
    value: &mut ConstValue,
    path: &[usize],
    replacement: ConstValue,
) -> Result<(), String> {
    let Some((field, tail)) = path.split_first() else {
        *value = replacement;
        return Ok(());
    };
    let ConstValue::Struct(fields) = value else {
        return Err("constant evaluator assignment path crossed a non-struct".to_owned());
    };
    let child = fields
        .get_mut(*field)
        .ok_or_else(|| "constant evaluator assignment field was invalid".to_owned())?;
    set_nested_field(child, tail, replacement)
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
