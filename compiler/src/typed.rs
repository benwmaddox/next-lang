use crate::ast::{AssignOp, BinaryOp, Span, UnaryOp};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Ty(pub usize);

#[allow(non_upper_case_globals)]
impl Ty {
    pub const Int: Ty = Ty(0);
    pub const Long: Ty = Ty(1);
    pub const Bool: Ty = Ty(2);
    pub const Unit: Ty = Ty(3);
    pub const Never: Ty = Ty(4);

    pub fn is_numeric(self) -> bool {
        matches!(self, Ty::Int | Ty::Long)
    }

    pub fn name(self) -> &'static str {
        match self {
            Ty::Int => "int",
            Ty::Long => "long",
            Ty::Bool => "bool",
            Ty::Unit => "()",
            Ty::Never => "never",
            _ => "aggregate",
        }
    }
}

#[derive(Clone, Debug)]
pub struct TType {
    pub name: String,
    pub kind: TTypeKind,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub enum TTypeKind {
    Int,
    Long,
    Bool,
    Unit,
    Never,
    Enum(Vec<TCase>),
    Option(Ty),
    Result(Ty, Ty),
}

#[derive(Clone, Debug)]
pub struct TCase {
    pub name: String,
    pub payload: Vec<Ty>,
    #[allow(dead_code)]
    pub span: Span,
}

impl TType {
    pub fn cases(&self) -> Vec<TCase> {
        match &self.kind {
            TTypeKind::Enum(cases) => cases.clone(),
            TTypeKind::Option(value) => vec![
                TCase {
                    name: "some".to_owned(),
                    payload: vec![*value],
                    span: self.span,
                },
                TCase {
                    name: "none".to_owned(),
                    payload: Vec::new(),
                    span: self.span,
                },
            ],
            TTypeKind::Result(ok, err) => vec![
                TCase {
                    name: "ok".to_owned(),
                    payload: vec![*ok],
                    span: self.span,
                },
                TCase {
                    name: "err".to_owned(),
                    payload: vec![*err],
                    span: self.span,
                },
            ],
            _ => Vec::new(),
        }
    }

    pub fn is_sum(&self) -> bool {
        matches!(
            self.kind,
            TTypeKind::Enum(_) | TTypeKind::Option(_) | TTypeKind::Result(..)
        )
    }
}

#[derive(Clone, Debug)]
#[allow(dead_code)] // The checker preserves the call graph for later analyses.
pub struct TProgram {
    pub functions: Vec<TFunction>,
    pub tests: Vec<TTest>,
    pub files: Vec<String>,
    pub call_graph: Vec<Vec<TCallEdge>>,
    pub types: Vec<TType>,
}

#[derive(Clone, Copy, Debug)]
#[allow(dead_code)]
pub struct TCallEdge {
    pub target: usize,
    pub span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct TTest {
    pub name: String,
    pub function_id: usize,
    pub span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)] // Keep source locations and source names in the typed form for later diagnostics.
pub struct TFunction {
    pub id: usize,
    pub name: String,
    pub params: Vec<TParam>,
    pub result: Ty,
    pub body: TBlock,
    pub span: Span,
    pub is_test: bool,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct TParam {
    pub id: usize,
    pub name: String,
    pub ty: Ty,
    pub span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct TBlock {
    pub statements: Vec<TStmt>,
    pub tail: Option<Box<TExpr>>,
    pub falls_through: bool,
    pub scope_id: usize,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct TStmt {
    pub kind: TStmtKind,
    pub span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)] // Mutability and names remain explicit after name resolution.
pub enum TStmtKind {
    Let {
        id: usize,
        name: String,
        ty: Ty,
        mutable: bool,
        value: TExpr,
    },
    Assign {
        id: usize,
        ty: Ty,
        op: AssignOp,
        operator_span: Span,
        value: TExpr,
    },
    Return(Option<TExpr>),
    Expr(TExpr),
    If {
        condition: TExpr,
        then_block: TBlock,
        else_block: Option<TBlock>,
    },
    For {
        id: usize,
        ty: Ty,
        start: TExpr,
        end: TExpr,
        inclusive: bool,
        body: TBlock,
    },
    Break,
    Continue,
    Expect {
        source: String,
        kind: TExpectKind,
    },
    Block(TBlock),
}

#[derive(Clone, Debug)]
pub enum TExpectKind {
    Bool(TExpr),
    Compare {
        op: BinaryOp,
        left: TExpr,
        right: TExpr,
    },
}

#[derive(Clone, Debug)]
pub struct TExpr {
    pub kind: TExprKind,
    pub ty: Ty,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub enum CallTarget {
    Function(usize),
    Print,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Effect {
    None,
    Observable,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MethodKind {
    IsNone,
    IsSome,
    IsOk,
    IsErr,
    ResultOk,
    UnwrapOption,
    UnwrapResult,
}

#[derive(Clone, Debug)]
pub enum TPattern {
    Wildcard,
    Integer(i128),
    Bool(bool),
    Case {
        ty: Ty,
        case_index: usize,
        bindings: Vec<Option<usize>>,
    },
}

#[derive(Clone, Debug)]
pub struct TMatchArm {
    pub pattern: TPattern,
    pub body: TBlock,
}

#[derive(Clone, Debug)]
pub enum TExprKind {
    Unit,
    Integer(i128),
    Bool(bool),
    Local(usize),
    Call {
        target: CallTarget,
        args: Vec<TExpr>,
        effect: Effect,
    },
    Construct {
        case_index: usize,
        args: Vec<TExpr>,
    },
    Method {
        kind: MethodKind,
        receiver: Box<TExpr>,
    },
    OptionalCall {
        receiver: Box<TExpr>,
        function_id: usize,
        args: Vec<TExpr>,
        wraps_result: bool,
    },
    Try {
        value: Box<TExpr>,
        success_ty: Ty,
        error_ty: Option<Ty>,
        propagated_ty: Ty,
    },
    Coalesce {
        option: Box<TExpr>,
        fallback: Box<TExpr>,
    },
    Match {
        scrutinee: Box<TExpr>,
        arms: Vec<TMatchArm>,
    },
    Return(Option<Box<TExpr>>),
    LoopExit(bool),
    ToLong(Box<TExpr>),
    Cast {
        cast_span: Span,
        value: Box<TExpr>,
    },
    Unary {
        op: UnaryOp,
        operator_span: Span,
        value: Box<TExpr>,
    },
    Binary {
        op: BinaryOp,
        operator_span: Span,
        left: Box<TExpr>,
        right: Box<TExpr>,
    },
    If {
        condition: Box<TExpr>,
        then_block: TBlock,
        else_block: Option<TBlock>,
    },
}

pub fn llvm_type(ty: Ty, types: &[TType]) -> String {
    match ty {
        Ty::Int => "i32".to_owned(),
        Ty::Long => "i64".to_owned(),
        Ty::Bool => "i1".to_owned(),
        Ty::Unit | Ty::Never => "void".to_owned(),
        Ty(id) => {
            debug_assert!(id < types.len());
            format!("%nl.ty.{id}")
        }
    }
}
