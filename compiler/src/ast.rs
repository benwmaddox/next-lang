#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Span {
    pub file: usize,
    pub line: usize,
    pub col: usize,
}

#[derive(Clone, Debug)]
pub struct TypeAst {
    pub name: String,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct Program {
    pub functions: Vec<Function>,
}

#[derive(Clone, Debug)]
pub struct Function {
    pub name: String,
    pub params: Vec<Param>,
    pub result: Option<TypeAst>,
    pub body: Block,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct Param {
    pub name: String,
    pub ty: TypeAst,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct Block {
    pub statements: Vec<Stmt>,
    pub tail: Option<Box<Expr>>,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct Stmt {
    pub kind: StmtKind,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub enum StmtKind {
    Let {
        mutable: bool,
        name: String,
        annotation: Option<TypeAst>,
        value: Expr,
    },
    Assign {
        name: String,
        op: AssignOp,
        operator_span: Span,
        value: Expr,
    },
    Return(Option<Expr>),
    Expr(Expr),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AssignOp {
    Set,
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

#[derive(Clone, Debug)]
pub struct Expr {
    pub kind: ExprKind,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub enum ExprKind {
    Integer {
        magnitude: u128,
        negative: bool,
        long_suffix: bool,
    },
    Bool(bool),
    Name(String),
    Call {
        name: String,
        call_span: Span,
        args: Vec<Expr>,
    },
    ToLong(Box<Expr>),
    Cast {
        ty: TypeAst,
        cast_span: Span,
        value: Box<Expr>,
    },
    Unary {
        op: UnaryOp,
        operator_span: Span,
        value: Box<Expr>,
    },
    Binary {
        op: BinaryOp,
        operator_span: Span,
        left: Box<Expr>,
        right: Box<Expr>,
    },
    If {
        condition: Box<Expr>,
        then_block: Block,
        else_block: Option<Block>,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnaryOp {
    Neg,
    Not,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BinaryOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    WrapAdd,
    WrapSub,
    WrapMul,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    And,
    Or,
    BitAnd,
    BitOr,
    BitXor,
    Shl,
    Shr,
}
