#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Span {
    pub file: usize,
    pub line: usize,
    pub col: usize,
}

#[derive(Clone, Debug)]
pub struct TypeAst {
    pub name: String,
    pub args: Vec<TypeAst>,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct Program {
    pub enums: Vec<EnumDecl>,
    pub functions: Vec<Function>,
    pub tests: Vec<Test>,
}

#[derive(Clone, Debug)]
pub struct EnumDecl {
    pub name: String,
    pub cases: Vec<EnumCase>,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct EnumCase {
    pub name: String,
    pub payload: Vec<TypeAst>,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct Test {
    pub name: String,
    pub body: Block,
    pub span: Span,
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
    For {
        name: String,
        annotation: Option<TypeAst>,
        start: Expr,
        end: Expr,
        inclusive: bool,
        body: Block,
    },
    Break,
    Continue,
    Expect {
        value: Expr,
        source: String,
    },
    Block(Block),
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
    Unit,
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
    QualifiedCase {
        enum_name: String,
        case_name: String,
        case_span: Span,
        args: Vec<Expr>,
    },
    MethodCall {
        receiver: Box<Expr>,
        name: String,
        method_span: Span,
        args: Vec<Expr>,
    },
    OptionalCall {
        receiver: Box<Expr>,
        name: String,
        method_span: Span,
        args: Vec<Expr>,
    },
    Try(Box<Expr>),
    Return(Option<Box<Expr>>),
    LoopExit(bool),
    Match {
        scrutinee: Box<Expr>,
        arms: Vec<MatchArm>,
    },
    ToLong {
        value: Box<Expr>,
        method_span: Span,
    },
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

#[derive(Clone, Debug)]
pub struct MatchArm {
    pub pattern: Pattern,
    pub body: Block,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub enum Pattern {
    Wildcard,
    Integer(Expr),
    Bool(bool, Span),
    Case {
        enum_name: Option<String>,
        name: String,
        name_span: Span,
        bindings: Vec<Option<(String, Span)>>,
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
    Coalesce,
}
