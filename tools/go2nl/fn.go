package main

import (
	"fmt"
	"go/ast"
	"go/token"
	"go/types"
	"strings"
)

// fnConv converts one function body (or one package variable's initialiser).
type fnConv struct {
	c      *conv
	fn     *types.Func
	names  *namer
	locals map[types.Object]string
	b      strings.Builder
	ind    int
	// Enclosing loops and switches, innermost last, for break and continue.
	targets []*target
	label   string // the label of the statement being converted
	// Results: the tuple struct for multiple results, and named result locals.
	tuple   string
	results []*types.Var
	named   []string
	// variadicParams are the parameters that hold a variadic ...T as a list.
	variadicParams map[types.Object]bool
	// tailIf is the if statement that ends the block being converted.
	tailIf *ast.IfStmt
	noPre  bool
}

func (c *conv) newFunc(fn *types.Func) *fnConv {
	return &fnConv{c: c, fn: fn, names: newNamer(c.top), locals: map[types.Object]string{}, variadicParams: map[types.Object]bool{}}
}

func (f *fnConv) line(format string, args ...any) {
	f.b.WriteString(strings.Repeat("    ", f.ind))
	fmt.Fprintf(&f.b, format, args...)
	f.b.WriteByte('\n')
}

func (f *fnConv) local(obj types.Object) string {
	name := f.names.claim(localBase(obj.Name()))
	f.locals[obj] = name
	return name
}

func (f *fnConv) tmp(base string) string { return f.names.claim(base) }

func (c *conv) funcDecl(fn *types.Func, d *ast.FuncDecl) string {
	sig := fn.Signature()
	if sig.TypeParams().Len() > 0 || (sig.Recv() != nil && sig.RecvTypeParams().Len() > 0) {
		c.fail(d, "generic", "generic function")
	}
	if d.Body == nil {
		c.fail(d, "no-body", "function without a body (assembly or linkname)")
	}
	return c.emitFunc(c.valueName(fn), fn, d.Recv, d.Type, d.Body, sig)
}

// emitFunc writes one next-lang function: a declared Go function or method
// (fn set), or a lifted function literal (fn nil).
func (c *conv) emitFunc(name string, fn *types.Func, recv *ast.FieldList, ft *ast.FuncType, body *ast.BlockStmt, sig *types.Signature) string {
	f := c.newFunc(fn)
	var pi *paramInfo
	if fn != nil {
		pi = c.modes.funcs[fn]
	}
	nparams := sig.Params().Len()
	if sig.Recv() != nil {
		nparams++
	}
	var params []string
	var copies []string
	idx := 0
	addParam := func(n *ast.Ident, t types.Type) {
		obj := types.Object(nil)
		if n != nil {
			obj = c.p.Info.Defs[n]
		}
		mode := ""
		if pi != nil && pi.write[idx] {
			mode = "write "
			if _, ok := t.Underlying().(*types.Pointer); ok {
				c.decide("pointer parameter changed through becomes a write parameter")
			} else {
				c.decide("slice or map parameter whose elements change becomes a write parameter")
			}
		}
		nt := ""
		if sig.Variadic() && idx == nparams-1 {
			nt = c.variadicType(t.(*types.Slice).Elem())
			if obj != nil {
				f.variadicParams[obj] = true
			}
		} else {
			nt = c.nlType(t, "")
		}
		if obj == nil || n.Name == "_" {
			params = append(params, fmt.Sprintf("%s: %s%s", f.tmp("unused"), mode, nt))
		} else if pi != nil && pi.copy[idx] && mode == "" {
			in := f.tmp(localBase(n.Name) + "_in")
			params = append(params, fmt.Sprintf("%s: %s", in, nt))
			copies = append(copies, fmt.Sprintf("var %s: %s = %s", f.local(obj), nt, in))
			c.decide("parameter changed by the function is copied into a local (Go passed a copy)")
		} else {
			if pi != nil && pi.copy[idx] {
				c.fail(n, "param-reassign", "parameter %s is both changed through and reassigned", n.Name)
			}
			params = append(params, fmt.Sprintf("%s: %s%s", f.local(obj), mode, nt))
		}
		idx++
	}
	if recv != nil {
		fl := recv.List[0]
		var n *ast.Ident
		if len(fl.Names) > 0 {
			n = fl.Names[0]
		}
		addParam(n, sig.Recv().Type())
		c.decide("method becomes a function taking the receiver first")
	}
	for _, fl := range ft.Params.List {
		t := c.p.Info.TypeOf(fl.Type)
		if len(fl.Names) == 0 {
			addParam(nil, t)
		}
		for _, n := range fl.Names {
			addParam(n, t)
		}
	}
	res := ""
	rs := sig.Results()
	for i := 0; i < rs.Len(); i++ {
		f.results = append(f.results, rs.At(i))
	}
	if rs.Len() == 1 {
		res = " -> " + c.nlType(rs.At(0).Type(), "")
	} else if rs.Len() > 1 {
		if fn == nil {
			c.fail(ft, "multi-return", "function literal with several results")
		}
		f.tuple = c.tupleType(fn)
		res = " -> " + f.tuple
	}
	f.ind = 1
	for _, cp := range copies {
		f.line("%s", cp)
	}
	if rs.Len() > 0 && rs.At(0).Name() != "" {
		for i := 0; i < rs.Len(); i++ {
			v := rs.At(i)
			n := f.local(v)
			f.named = append(f.named, n)
			f.line("var %s: %s = %s", n, c.nlType(v.Type(), ""), c.zero(v.Type(), ""))
		}
		c.decide("named results become locals")
	}
	for _, s := range body.List {
		f.stmt(s)
	}
	if rs.Len() > 0 && !endsInReturn(body) {
		// Go proved the end unreachable (a terminating statement); next-lang
		// needs a value there.
		f.line("%s", f.zeroResult())
		c.decide("unreachable function end gets a zero result")
	}
	kw := "fn"
	if fn != nil && c.recursive[fn] {
		kw = "recursive fn"
		c.decide("function on a call cycle is marked recursive")
	}
	return fmt.Sprintf("%s %s(%s)%s {\n%s}\n", kw, name, strings.Join(params, ", "), res, f.b.String())
}

func endsInReturn(b *ast.BlockStmt) bool {
	if len(b.List) == 0 {
		return false
	}
	_, ok := b.List[len(b.List)-1].(*ast.ReturnStmt)
	return ok
}

func (f *fnConv) zeroResult() string {
	if f.tuple != "" {
		return f.tuple + " {}"
	}
	t := f.results[0].Type()
	if p, ok := t.Underlying().(*types.Pointer); ok {
		t = p.Elem()
	}
	return f.c.zero(t, "")
}

// tupleType declares the struct that carries a function's several results.
func (c *conv) tupleType(fn *types.Func) string {
	if name, ok := c.tuples[fn]; ok {
		return name
	}
	rs := fn.Signature().Results()
	name := c.top.claim("Ret_" + c.valueName(fn))
	var b strings.Builder
	fmt.Fprintf(&b, "struct %s {\n", name)
	for i := 0; i < rs.Len(); i++ {
		t := rs.At(i).Type()
		zt := t
		if p, ok := t.Underlying().(*types.Pointer); ok {
			zt = p.Elem()
		}
		fmt.Fprintf(&b, "    r%d: %s = %s\n", i, c.nlType(t, ""), c.zero(zt, ""))
	}
	b.WriteString("}\n")
	c.extra = append(c.extra, b.String())
	c.tuples[fn] = name
	c.decide("several results become a struct with fields r0, r1, ...")
	return name
}

// ---- statements ----

func (f *fnConv) block(stmts []ast.Stmt) {
	f.ind++
	for i, s := range stmts {
		if is, ok := s.(*ast.IfStmt); ok && i == len(stmts)-1 {
			f.tailIf = is
		}
		f.stmt(s)
	}
	f.ind--
}

func (f *fnConv) stmt(s ast.Stmt) {
	c := f.c
	info := c.p.Info
	switch s := s.(type) {
	case *ast.EmptyStmt:
	case *ast.ExprStmt:
		f.exprStmt(s.X)
	case *ast.IncDecStmt:
		one := "1"
		if c.intBase(info.TypeOf(s.X)) == "long" {
			one = "1L"
		}
		op := "+="
		if s.Tok == token.DEC {
			op = "-="
		}
		if ix, ok := ast.Unparen(s.X).(*ast.IndexExpr); ok && isMap(info.TypeOf(ix.X)) {
			bin := "+"
			if s.Tok == token.DEC {
				bin = "-"
			}
			f.mapSet(ix, fmt.Sprintf("%s %s %s", f.expr(ix), bin, one))
			return
		}
		f.line("%s %s %s", f.place(s.X), op, one)
	case *ast.AssignStmt:
		f.assign(s)
	case *ast.DeclStmt:
		gd := s.Decl.(*ast.GenDecl)
		switch gd.Tok {
		case token.CONST:
			// Folded into literals at each use.
		case token.TYPE:
			c.fail(s, "local-type", "type declared inside a function")
		case token.VAR:
			for _, sp := range gd.Specs {
				vs := sp.(*ast.ValueSpec)
				for i, n := range vs.Names {
					obj := info.Defs[n]
					if n.Name == "_" {
						if i < len(vs.Values) {
							f.exprStmt(vs.Values[i])
						}
						continue
					}
					if i < len(vs.Values) {
						f.defineVar(obj, vs.Values[i])
					} else {
						t := obj.Type()
						f.line("var %s: %s = %s", f.local(obj), c.nlType(t, ""), c.zero(t, ""))
					}
				}
			}
		}
	case *ast.ReturnStmt:
		f.ret(s)
	case *ast.BlockStmt:
		f.line("{")
		f.block(s.List)
		f.line("}")
	case *ast.IfStmt:
		f.ifStmt(s, false)
	case *ast.ForStmt:
		f.forStmt(s)
	case *ast.RangeStmt:
		f.rangeStmt(s)
	case *ast.SwitchStmt:
		f.switchStmt(s)
	case *ast.BranchStmt:
		f.branch(s)
	case *ast.LabeledStmt:
		f.labeled(s)
	case *ast.DeferStmt:
		c.fail(s, "defer", "defer")
	case *ast.GoStmt, *ast.SelectStmt, *ast.SendStmt:
		c.fail(s, "goroutine", "goroutines and channels")
	case *ast.TypeSwitchStmt:
		c.fail(s, "type-switch", "type switch")
	default:
		c.fail(s, "statement", "statement %T", s)
	}
}

func isMap(t types.Type) bool {
	_, ok := t.Underlying().(*types.Map)
	return ok
}

func (f *fnConv) exprStmt(e ast.Expr) {
	c := f.c
	if call, ok := ast.Unparen(e).(*ast.CallExpr); ok {
		if id, ok := ast.Unparen(call.Fun).(*ast.Ident); ok {
			if b, ok := c.p.Info.Uses[id].(*types.Builtin); ok {
				switch b.Name() {
				case "panic":
					f.line("go_panic()")
					c.decide("panic stops the program with a failure (exit status 1, Go's is 2)")
					return
				case "clear":
					if isMap(c.p.Info.TypeOf(call.Args[0])) {
						f.line("%s = map {}", f.place(call.Args[0]))
						c.decide("clear(m) becomes m = map {}")
					} else {
						c.fail(call, "builtin", "clear of a slice")
					}
					return
				case "delete":
					m := call.Args[0]
					f.line("%s.remove(%s)", f.place(m), f.mapKey(info(c).TypeOf(m), call.Args[1]))
					return
				}
			}
		}
		f.line("%s", f.expr(call))
		return
	}
	c.fail(e, "statement", "expression statement %s", c.exprString(e))
}

func info(c *conv) *types.Info { return c.p.Info }

// defineVar declares a new local with an initial value.
func (f *fnConv) defineVar(obj types.Object, value ast.Expr) {
	c := f.c
	t := obj.Type()
	if _, ok := t.Underlying().(*types.Pointer); ok {
		f.checkFresh(value)
	}
	if call, ok := ast.Unparen(value).(*ast.CallExpr); ok && isAppend(c, call) {
		c.fail(value, "append", "append result stored in a new variable (only s = append(s, ...) is converted)")
	}
	rhs := f.valueExpr(value, t)
	f.line("var %s: %s = %s", f.local(obj), c.nlType(t, ""), rhs)
}

// checkFresh refuses a pointer copy: in Go both names would point at one value,
// in next-lang they'd be two values.
func (f *fnConv) checkFresh(value ast.Expr) {
	c := f.c
	switch v := ast.Unparen(value).(type) {
	case *ast.UnaryExpr:
		if v.Op == token.AND {
			if _, ok := ast.Unparen(v.X).(*ast.CompositeLit); ok {
				return
			}
		}
	case *ast.CallExpr:
		if callee := calleeFunc(c, v); callee != nil && c.p.inModule(callee) && c.returnsFresh(callee) {
			return
		}
	}
	c.fail(value, "pointer-alias", "pointer copied from %s: two Go names for one value", c.exprString(value))
}

// returnsFresh: every return of fn gives a new value (&T{...} or another such
// call), so a pointer it returns is the only one.
func (c *conv) returnsFresh(fn *types.Func) bool {
	fd, ok := c.p.Decls[fn].(*ast.FuncDecl)
	if !ok || fd.Body == nil {
		return false
	}
	fresh := true
	ast.Inspect(fd.Body, func(n ast.Node) bool {
		if _, ok := n.(*ast.FuncLit); ok {
			return false
		}
		r, ok := n.(*ast.ReturnStmt)
		if !ok || len(r.Results) != 1 {
			return true
		}
		switch v := ast.Unparen(r.Results[0]).(type) {
		case *ast.UnaryExpr:
			if _, ok := ast.Unparen(v.X).(*ast.CompositeLit); ok && v.Op == token.AND {
				return true
			}
			if id := addrOfLocal(c, v); id != nil && !addressTakenElsewhere(c, fd.Body, id) {
				return true
			}
		case *ast.CallExpr:
			if callee := calleeFunc(c, v); callee != nil && callee != fn && c.p.inModule(callee) && c.returnsFresh(callee) {
				return true
			}
		}
		fresh = false
		return true
	})
	return fresh
}

func calleeFunc(c *conv, call *ast.CallExpr) *types.Func {
	switch fun := ast.Unparen(call.Fun).(type) {
	case *ast.Ident:
		f, _ := c.p.Info.Uses[fun].(*types.Func)
		return f
	case *ast.SelectorExpr:
		if s := c.p.Info.Selections[fun]; s != nil {
			f, _ := s.Obj().(*types.Func)
			return f
		}
		f, _ := c.p.Info.Uses[fun.Sel].(*types.Func)
		return f
	}
	return nil
}

func isAppend(c *conv, call *ast.CallExpr) bool {
	id, ok := ast.Unparen(call.Fun).(*ast.Ident)
	if !ok {
		return false
	}
	b, ok := c.p.Info.Uses[id].(*types.Builtin)
	return ok && b.Name() == "append"
}

func (f *fnConv) assign(s *ast.AssignStmt) {
	c := f.c
	info := c.p.Info
	if s.Tok != token.DEFINE && s.Tok != token.ASSIGN {
		f.opAssign(s)
		return
	}
	if len(s.Lhs) == len(s.Rhs) && len(s.Lhs) == 1 {
		f.assignOne(s.Lhs[0], s.Rhs[0], s.Tok == token.DEFINE)
		return
	}
	if len(s.Rhs) == 1 {
		rhs := ast.Unparen(s.Rhs[0])
		switch r := rhs.(type) {
		case *ast.CallExpr:
			callee := calleeFunc(c, r)
			if callee == nil || (!c.p.inModule(callee) && !stdlibTable[stdlibName(callee)].tuple) {
				c.fail(s, "multi-return", "several results from %s", c.exprString(r))
			}
			t := f.tmp("results")
			f.line("let %s = %s", t, f.expr(r))
			for i, l := range s.Lhs {
				f.assignFrom(l, fmt.Sprintf("%s.r%d", t, i), s.Tok == token.DEFINE)
			}
			return
		case *ast.IndexExpr:
			if isMap(info.TypeOf(r.X)) {
				t := f.tmp("found")
				f.line("let %s = %s", t, f.mapGetOption(r))
				vt := info.TypeOf(r.X).Underlying().(*types.Map).Elem()
				f.assignFrom(s.Lhs[0], fmt.Sprintf("%s ?? %s", t, c.zero(vt, "")), s.Tok == token.DEFINE)
				f.assignFrom(s.Lhs[1], t+".is_some()", s.Tok == token.DEFINE)
				c.decide("v, ok := m[k] reads the map once into an Option")
				return
			}
		case *ast.TypeAssertExpr:
			c.fail(s, "type-switch", "type assertion")
		}
		c.fail(s, "multi-return", "assignment of several values from %s", c.exprString(rhs))
	}
	// a, b = x, y: evaluate every value first, as Go does.
	var temps []string
	for _, r := range s.Rhs {
		t := f.tmp("value")
		lt := info.TypeOf(r)
		f.line("let %s: %s = %s", t, c.nlType(lt, ""), f.valueExpr(r, lt))
		temps = append(temps, t)
	}
	for i, l := range s.Lhs {
		f.assignFrom(l, temps[i], s.Tok == token.DEFINE)
	}
}

// assignFrom assigns already-converted next-lang text to a Go left-hand side.
func (f *fnConv) assignFrom(l ast.Expr, value string, define bool) {
	c := f.c
	info := c.p.Info
	if id, ok := l.(*ast.Ident); ok {
		if id.Name == "_" {
			return
		}
		if obj := info.Defs[id]; obj != nil && define {
			f.line("var %s: %s = %s", f.local(obj), c.nlType(obj.Type(), ""), value)
			return
		}
	}
	if ix, ok := ast.Unparen(l).(*ast.IndexExpr); ok && isMap(info.TypeOf(ix.X)) {
		f.mapSet(ix, value)
		return
	}
	f.line("%s = %s", f.place(l), value)
}

func (f *fnConv) assignOne(l, r ast.Expr, define bool) {
	c := f.c
	info := c.p.Info
	if id, ok := l.(*ast.Ident); ok && id.Name == "_" {
		if _, call := ast.Unparen(r).(*ast.CallExpr); call {
			f.exprStmt(r)
		}
		return
	}
	if id, ok := l.(*ast.Ident); ok && define {
		if obj := info.Defs[id]; obj != nil {
			f.defineVar(obj, r)
			return
		}
	}
	lt := info.TypeOf(l)
	if call, ok := ast.Unparen(r).(*ast.CallExpr); ok && isAppend(c, call) {
		f.appendStmt(l, call)
		return
	}
	if _, ok := lt.Underlying().(*types.Pointer); ok {
		f.checkFresh(r)
	}
	if ix, ok := ast.Unparen(l).(*ast.IndexExpr); ok && isMap(info.TypeOf(ix.X)) {
		f.mapSet(ix, f.valueExpr(r, lt))
		return
	}
	f.line("%s = %s", f.place(l), f.valueExpr(r, lt))
}

// s = append(s, a, b) becomes pushes; append(s, t...) a loop of pushes.
func (f *fnConv) appendStmt(l ast.Expr, call *ast.CallExpr) {
	c := f.c
	if len(call.Args) == 0 || c.exprString(call.Args[0]) != c.exprString(l) {
		c.fail(call, "append", "append whose result isn't assigned back to its first argument")
	}
	target := f.place(l)
	elem := c.p.Info.TypeOf(l).Underlying().(*types.Slice).Elem()
	if call.Ellipsis.IsValid() {
		src := call.Args[1]
		if isGoString(c.p.Info.TypeOf(src)) {
			c.fail(call, "append", "append of a string's bytes")
		}
		item := f.tmp("item")
		f.line("for %s in %s {", item, f.expr(src))
		f.ind++
		f.line("%s.push(%s).unwrap()", target, item)
		f.ind--
		f.line("}")
		return
	}
	for _, a := range call.Args[1:] {
		f.line("%s.push(%s).unwrap()", target, f.valueExpr(a, elem))
	}
	c.decide("s = append(s, x) becomes s.push(x).unwrap()")
}

func (f *fnConv) opAssign(s *ast.AssignStmt) {
	c := f.c
	info := c.p.Info
	l, r := s.Lhs[0], s.Rhs[0]
	op := strings.TrimSuffix(s.Tok.String(), "=")
	lt := info.TypeOf(l)
	if ix, ok := ast.Unparen(l).(*ast.IndexExpr); ok && isMap(info.TypeOf(ix.X)) {
		f.mapSet(ix, f.binary(op, f.expr(ix), r, lt, lt))
		return
	}
	if isGoString(lt) && op == "+" {
		f.line("%s = go_concat(%s, %s)", f.place(l), f.place(l), f.valueExpr(r, lt))
		return
	}
	switch op {
	case "+", "-", "*", "/", "%":
		f.line("%s %s= %s", f.place(l), op, f.valueExpr(r, lt))
		return
	case ">>":
		f.line("%s >>= %s", f.place(l), f.shiftCount(r, lt))
		return
	}
	if !simplePlace(l) {
		c.fail(s, "op-assign", "%s= on a place with calls in it", op)
	}
	if op == "&^" {
		value := fmt.Sprintf("(%s & (%s ^ %s))", f.place(l), f.valueExpr(r, lt), f.allOnes(lt))
		if isNarrow(lt) {
			value = c.narrowCast(value, lt)
		}
		f.line("%s = %s", f.place(l), value)
		return
	}
	value := f.binary(op, f.place(l), r, lt, lt)
	if isNarrow(lt) {
		value = c.narrowCast(value, lt)
	}
	f.line("%s = %s", f.place(l), value)
}

// simplePlace: evaluating the place twice is the same as once.
func simplePlace(e ast.Expr) bool {
	switch x := ast.Unparen(e).(type) {
	case *ast.Ident:
		return true
	case *ast.SelectorExpr:
		return simplePlace(x.X)
	case *ast.StarExpr:
		return simplePlace(x.X)
	case *ast.IndexExpr:
		_, lit := ast.Unparen(x.Index).(*ast.BasicLit)
		return simplePlace(x.X) && (lit || simplePlace(x.Index))
	}
	return false
}

func (f *fnConv) ret(s *ast.ReturnStmt) {
	c := f.c
	if len(s.Results) == 0 {
		switch {
		case len(f.named) == 1:
			f.line("return %s", f.named[0])
		case len(f.named) > 1:
			var fields []string
			for i, n := range f.named {
				fields = append(fields, fmt.Sprintf("r%d: %s", i, n))
			}
			f.line("return %s { %s }", f.tuple, strings.Join(fields, ", "))
		default:
			f.line("return")
		}
		return
	}
	if f.tuple == "" {
		if id := addrOfLocal(c, s.Results[0]); id != nil {
			if name, ok := f.locals[c.p.Info.Uses[id]]; ok {
				f.line("return %s", name)
				c.decide("return &local becomes return local (the local is not used after)")
				return
			}
		}
		f.line("return %s", f.valueExpr(s.Results[0], f.results[0].Type()))
		return
	}
	if len(s.Results) == 1 {
		// return g(), where g has the same results.
		t := f.tmp("results")
		f.line("let %s = %s", t, f.expr(s.Results[0]))
		var fields []string
		for i := range f.results {
			fields = append(fields, fmt.Sprintf("r%d: %s.r%d", i, t, i))
		}
		f.line("return %s { %s }", f.tuple, strings.Join(fields, ", "))
		return
	}
	var fields []string
	for i, r := range s.Results {
		fields = append(fields, fmt.Sprintf("r%d: %s", i, f.valueExpr(r, f.results[i].Type())))
	}
	_ = c
	f.line("return %s { %s }", f.tuple, strings.Join(fields, ", "))
}

func (f *fnConv) ifStmt(s *ast.IfStmt, chained bool) {
	if s.Init != nil {
		if chained {
			panic("chained if with init")
		}
		f.stmt(s.Init)
		f.c.decide("if's init statement moves before the if (names are unique, so scope is kept)")
	}
	head := "if"
	if chained {
		head = "} else if"
	}
	f.noPre = chained
	ctext := f.cond(s.Cond)
	f.noPre = false
	f.line("%s %s {", head, ctext)
	f.block(s.Body.List)
	switch e := s.Else.(type) {
	case nil:
		if chained || f.tailIf == s {
			// next-lang reads an `if` ending a block as that block's value,
			// which needs an else; an else-if chain's last `if` is such a tail.
			f.line("} else {")
		}
		f.line("}")
	case *ast.IfStmt:
		if e.Init == nil {
			f.ifStmt(e, true)
			return
		}
		f.line("} else {")
		f.ind++
		f.ifStmt(e, false)
		f.ind--
		f.line("}")
	case *ast.BlockStmt:
		f.line("} else {")
		f.block(e.List)
		f.line("}")
	}
}

// cond writes a condition; a capitalised struct literal in an if head would be
// parsed as the name, so heads are wrapped when they contain a brace.
func (f *fnConv) cond(e ast.Expr) string { return condText(f.expr(e)) }

func condText(s string) string {
	if strings.Contains(s, "{") {
		return "(" + s + ")"
	}
	return s
}

const loopForever = "0L..9223372036854775807L"

func (f *fnConv) forStmt(s *ast.ForStmt) {
	c := f.c
	if i, lo, hi, incl, ok := f.countedLoop(s); ok {
		t := &target{isLoop: true}
		outer := f.enter(t)
		f.line("for %s in %s..%s%s {", i, lo, map[bool]string{true: "=", false: ""}[incl], hi)
		f.block(s.Body.List)
		f.line("}")
		f.leave(t, outer)
		c.decide("counted for loop becomes for i in a..b")
		return
	}
	if s.Init != nil {
		f.stmt(s.Init)
	}
	// The post statement, converted once, is repeated before each continue.
	var post []string
	if s.Post != nil {
		saved := f.b
		savedInd := f.ind
		f.b = strings.Builder{}
		f.ind = 0
		f.stmt(s.Post)
		post = strings.Split(strings.TrimRight(f.b.String(), "\n"), "\n")
		f.b = saved
		f.ind = savedInd
	}
	t := &target{isLoop: true, post: post}
	outer := f.enter(t)
	f.line("for %s in %s {", f.tmp("step"), loopForever)
	f.ind++
	if s.Cond != nil {
		f.line("if !(%s) { break }", f.expr(s.Cond))
	}
	f.ind--
	f.block(s.Body.List)
	f.ind++
	for _, p := range post {
		f.line("%s", p)
	}
	f.ind--
	f.line("}")
	f.leave(t, outer)
	c.decide("for loop without a range becomes a for over 0..2^63-1 that breaks on the condition")
}

// countedLoop recognises `for i := a; i < b; i++` where neither i nor b
// changes in the body, which is exactly next-lang's `for i in a..b`.
func (f *fnConv) countedLoop(s *ast.ForStmt) (string, string, string, bool, bool) {
	c := f.c
	info := c.p.Info
	init, ok := s.Init.(*ast.AssignStmt)
	if !ok || init.Tok != token.DEFINE || len(init.Lhs) != 1 || len(init.Rhs) != 1 {
		return "", "", "", false, false
	}
	id, ok := init.Lhs[0].(*ast.Ident)
	if !ok {
		return "", "", "", false, false
	}
	obj := info.Defs[id]
	if obj == nil || c.intBase(obj.Type()) != "long" {
		return "", "", "", false, false
	}
	if _, named := obj.Type().(*types.Named); named {
		return "", "", "", false, false
	}
	post, ok := s.Post.(*ast.IncDecStmt)
	if !ok || post.Tok != token.INC {
		return "", "", "", false, false
	}
	if pid, ok := post.X.(*ast.Ident); !ok || info.Uses[pid] != obj {
		return "", "", "", false, false
	}
	cond, ok := s.Cond.(*ast.BinaryExpr)
	if !ok || (cond.Op != token.LSS && cond.Op != token.LEQ) {
		return "", "", "", false, false
	}
	if cid, ok := cond.X.(*ast.Ident); !ok || info.Uses[cid] != obj {
		return "", "", "", false, false
	}
	if changedIn(c, s.Body, obj) || !stableIn(c, s.Body, cond.Y) {
		return "", "", "", false, false
	}
	lo := f.valueExpr(init.Rhs[0], obj.Type())
	hi := f.valueExpr(cond.Y, obj.Type())
	return f.local(obj), lo, hi, cond.Op == token.LEQ, true
}

// changedIn reports whether body may change obj (assigns it, increments it, or
// takes its address).
func changedIn(c *conv, body ast.Node, obj types.Object) bool {
	changed := false
	ast.Inspect(body, func(n ast.Node) bool {
		var targets []ast.Expr
		switch n := n.(type) {
		case *ast.AssignStmt:
			targets = n.Lhs
		case *ast.IncDecStmt:
			targets = []ast.Expr{n.X}
		case *ast.UnaryExpr:
			if n.Op == token.AND {
				targets = []ast.Expr{n.X}
			}
		case *ast.FuncLit:
			targets = nil
		}
		for _, t := range targets {
			if root := rootIdent(t); root != nil && c.p.Info.Uses[root] == obj {
				changed = true
			}
		}
		return true
	})
	return changed
}

func rootIdent(e ast.Expr) *ast.Ident {
	for {
		switch x := e.(type) {
		case *ast.Ident:
			return x
		case *ast.SelectorExpr:
			e = x.X
		case *ast.IndexExpr:
			e = x.X
		case *ast.StarExpr:
			e = x.X
		case *ast.ParenExpr:
			e = x.X
		case *ast.UnaryExpr:
			e = x.X
		default:
			return nil
		}
	}
}

// stableIn: e is a constant, or a local the body doesn't change, or len(x) of
// a local the body doesn't change; so Go evaluating it every pass gives the
// same value as next-lang evaluating it once.
func stableIn(c *conv, body ast.Node, e ast.Expr) bool {
	info := c.p.Info
	if tv, ok := info.Types[e]; ok && tv.Value != nil {
		return true
	}
	switch x := ast.Unparen(e).(type) {
	case *ast.Ident:
		obj := info.Uses[x]
		v, ok := obj.(*types.Var)
		return ok && !isPackageLevel(v) && !changedIn(c, body, obj) && !callsWrite(c, body, obj)
	case *ast.CallExpr:
		if id, ok := ast.Unparen(x.Fun).(*ast.Ident); ok && len(x.Args) == 1 {
			if b, ok := info.Uses[id].(*types.Builtin); ok && b.Name() == "len" {
				if aid, ok := ast.Unparen(x.Args[0]).(*ast.Ident); ok {
					obj := info.Uses[aid]
					return obj != nil && !changedIn(c, body, obj) && !callsWrite(c, body, obj)
				}
			}
		}
	}
	return false
}

// callsWrite: body passes obj (or part of it) to a write parameter.
func callsWrite(c *conv, body ast.Node, obj types.Object) bool {
	found := false
	ast.Inspect(body, func(n ast.Node) bool {
		if call, ok := n.(*ast.CallExpr); ok {
			for _, m := range c.modes.mutatedPlaces(call) {
				if root := rootIdent(m.e); root != nil && c.p.Info.Uses[root] == obj {
					found = true
				}
			}
		}
		return true
	})
	return found
}

func (f *fnConv) rangeStmt(s *ast.RangeStmt) {
	c := f.c
	info := c.p.Info
	if s.Tok == token.ASSIGN {
		c.fail(s, "range", "range assigning existing variables")
	}
	var key, val types.Object
	if id, ok := s.Key.(*ast.Ident); ok && id.Name != "_" {
		key = info.Defs[id]
	}
	if id, ok := s.Value.(*ast.Ident); ok && id.Name != "_" {
		val = info.Defs[id]
	}
	xt := info.TypeOf(s.X)
	enter := func(head string) {
		t := &target{isLoop: true}
		outer := f.enter(t)
		f.line("%s {", head)
		f.block(s.Body.List)
		f.line("}")
		f.leave(t, outer)
	}
	switch u := xt.Underlying().(type) {
	case *types.Basic:
		if u.Info()&types.IsInteger != 0 {
			name := f.tmp("unused_index")
			if key != nil {
				name = f.local(key)
			}
			enter(fmt.Sprintf("for %s in 0L..%s", name, f.valueExpr(s.X, types.Typ[types.Int])))
			return
		}
		if u.Info()&types.IsString != 0 {
			if key != nil && changedIn(c, s.Body, key) {
				c.fail(s, "range", "range index changed in the body")
			}
			f.rangeString(s, key, val)
			return
		}
	case *types.Slice, *types.Array:
		if val != nil && changedIn(c, s.Body, val) {
			c.fail(s, "range", "range value changed in the body (Go's is a copy)")
		}
		if val == nil {
			name := f.tmp("unused_index")
			if key != nil {
				name = f.local(key)
			}
			n := ""
			if a, ok := u.(*types.Array); ok {
				n = fmt.Sprintf("%dL", a.Len())
			} else {
				n = f.expr(s.X) + ".count()"
			}
			enter(fmt.Sprintf("for %s in 0L..%s", name, n))
			return
		}
		head := "for " + f.local(val)
		if key != nil {
			head += ", " + f.local(key)
		}
		enter(head + " in " + f.expr(s.X))
		c.decide("range over a slice becomes for value, index in list")
		return
	case *types.Map:
		c.fail(s, "range-map", "range over a map (Go's order is random)")
	case *types.Signature:
		c.fail(s, "range-func", "range over an iterator function")
	}
	c.fail(s, "range", "range over %s", xt)
}

// pre emits a statement that must run before the statement being converted
// (a typed temporary). Inside an else-if head there is no such place, since
// the statement would land in the previous branch, so that is refused.
func (f *fnConv) pre(format string, args ...any) {
	if f.noPre {
		f.c.fail(nil, "condition-temp", "a condition in an else-if or case needs a temporary")
	}
	f.line(format, args...)
}

// addrOfLocal: e is &x for a local variable x (not a parameter or global).
func addrOfLocal(c *conv, e ast.Expr) *ast.Ident {
	u, ok := ast.Unparen(e).(*ast.UnaryExpr)
	if !ok || u.Op != token.AND {
		return nil
	}
	id, ok := ast.Unparen(u.X).(*ast.Ident)
	if !ok {
		return nil
	}
	v, ok := c.p.Info.Uses[id].(*types.Var)
	if !ok || isPackageLevel(v) {
		return nil
	}
	return id
}

// addressTakenElsewhere: x's address is taken somewhere other than in a
// return statement, so returning &x may share it.
func addressTakenElsewhere(c *conv, body ast.Node, id *ast.Ident) bool {
	obj := c.p.Info.Uses[id]
	taken := false
	ast.Inspect(body, func(n ast.Node) bool {
		if r, ok := n.(*ast.ReturnStmt); ok {
			_ = r
			return false
		}
		if u, ok := n.(*ast.UnaryExpr); ok && u.Op == token.AND {
			if x, ok := ast.Unparen(u.X).(*ast.Ident); ok && c.p.Info.Uses[x] == obj {
				taken = true
			}
		}
		return true
	})
	return taken
}
