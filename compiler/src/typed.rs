use crate::ast::{AssignOp, BinaryOp, Span, UnaryOp};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Ty {
    Int,
    Long,
    Bool,
    Unit,
    Never,
}

impl Ty {
    pub fn name(self) -> &'static str {
        match self {
            Ty::Int => "int",
            Ty::Long => "long",
            Ty::Bool => "bool",
            Ty::Unit => "()",
            Ty::Never => "never",
        }
    }

    pub fn is_numeric(self) -> bool {
        matches!(self, Ty::Int | Ty::Long)
    }
}

#[derive(Clone, Debug)]
#[allow(dead_code)] // The checker preserves the call graph for later analyses.
pub struct TProgram {
    pub functions: Vec<TFunction>,
    pub files: Vec<String>,
    pub call_graph: Vec<Vec<TCallEdge>>,
}

#[derive(Clone, Copy, Debug)]
#[allow(dead_code)]
pub struct TCallEdge {
    pub target: usize,
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
}

#[derive(Clone, Debug)]
#[allow(dead_code)] // Parameter names and locations are useful to diagnostics and future ABI lowering.
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

#[derive(Clone, Debug)]
pub enum TExprKind {
    Integer(i128),
    Bool(bool),
    Local(usize),
    Call {
        target: CallTarget,
        args: Vec<TExpr>,
        effect: Effect,
    },
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

pub fn llvm_type(ty: Ty) -> &'static str {
    match ty {
        Ty::Int => "i32",
        Ty::Long => "i64",
        Ty::Bool => "i1",
        Ty::Unit | Ty::Never => "void",
    }
}
