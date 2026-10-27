package main

import (
	"fmt"
	"go/ast"
	"go/token"
	"go/types"
	"io"
	"sort"
	"strings"
)

// Census counts Go constructs in the reachable declarations, by category, with
// every site's location, so the report says exactly what blocks a conversion.
type Census struct {
	Sites  map[string][]string // category -> "file:line symbol"
	Funcs  int
	Types  int
	Vars   int
	Consts int
	Lines  int
}

// Category descriptions, in report order. Keep these short and plain.
var censusCategories = []struct{ key, about string }{
	{"closure", "function literal (closure); next-lang has no closures"},
	{"func-value", "function or method used as a value"},
	{"defer", "defer statement"},
	{"goroutine", "go statement, channel or select"},
	{"panic-recover", "panic or recover call"},
	{"interface-type", "interface type declared or used as a value type"},
	{"interface-call", "method call through an interface value"},
	{"type-switch", "type switch or type assertion"},
	{"any-conversion", "value converted to an interface (boxing)"},
	{"variadic", "variadic function declared or called with ..."},
	{"float", "float32/float64 value (stage 0 has no floats)"},
	{"unsigned-wide", "uint, uint32, uint64 or uintptr value"},
	{"generic", "generic function or type, or an instantiation"},
	{"range-func", "range over a function (iterator)"},
	{"range-map", "range over a map (Go's order is random)"},
	{"range-string", "range over a string (decodes runes)"},
	{"goto-label", "goto, labeled statement or fallthrough"},
	{"multi-return", "function with more than one result"},
	{"pointer-field", "struct field or element of pointer type (object graph)"},
	{"address-of", "& address-of"},
	{"pointer-param", "pointer parameter or receiver"},
	{"mutable-global", "package variable written after initialisation"},
	{"readonly-global", "package variable only read (can become const)"},
	{"map", "map type"},
	{"slice", "slice type"},
	{"slice-expr", "slicing expression a[i:j]"},
	{"append", "append call"},
	{"string-conv", "conversion between string, []byte, []rune and rune"},
	{"embedding", "embedded struct field"},
	{"method", "method declaration"},
	{"stdlib-call", "call into the Go standard library"},
}

func (p *Program) census(r *Reach) *Census {
	c := &Census{Sites: map[string][]string{}}
	note := func(cat string, n ast.Node, sym string) {
		c.Sites[cat] = append(c.Sites[cat], p.pos(n)+" "+sym)
	}
	written := p.writtenGlobals(r)
	for _, obj := range r.Order {
		decl := p.Decls[obj]
		if decl == nil {
			continue
		}
		sym := p.objName(obj)
		switch d := decl.(type) {
		case *ast.FuncDecl:
			c.Funcs++
			c.Lines += p.Fset.Position(d.End()).Line - p.Fset.Position(d.Pos()).Line + 1
			sig := obj.(*types.Func).Signature()
			if sig.Recv() != nil {
				note("method", d, sym)
				if _, ok := sig.Recv().Type().(*types.Pointer); ok {
					note("pointer-param", d, sym+" (receiver)")
				}
			}
			if sig.Results().Len() > 1 {
				note("multi-return", d, sym)
			}
			if sig.Variadic() {
				note("variadic", d, sym)
			}
			if sig.TypeParams().Len() > 0 || (sig.Recv() != nil && sig.RecvTypeParams().Len() > 0) {
				note("generic", d, sym)
			}
			for i := 0; i < sig.Params().Len(); i++ {
				if _, ok := sig.Params().At(i).Type().(*types.Pointer); ok {
					note("pointer-param", d, sym+" ("+sig.Params().At(i).Name()+")")
				}
			}
			if d.Body != nil {
				p.censusBody(d.Body, sym, note)
			}
		case *ast.TypeSpec:
			c.Types++
			tn := obj.(*types.TypeName)
			if d.TypeParams != nil {
				note("generic", d, sym)
			}
			switch u := tn.Type().Underlying().(type) {
			case *types.Interface:
				note("interface-type", d, sym)
			case *types.Struct:
				for i := 0; i < u.NumFields(); i++ {
					f := u.Field(i)
					if f.Embedded() {
						note("embedding", d, sym+"."+f.Name())
					}
					if hasPointer(f.Type()) {
						note("pointer-field", d, sym+"."+f.Name())
					}
					p.censusType(f.Type(), d, sym+"."+f.Name(), note)
				}
			default:
				p.censusType(u, d, sym, note)
			}
		case *ast.ValueSpec:
			if _, ok := obj.(*types.Const); ok {
				c.Consts++
				continue
			}
			c.Vars++
			c.Lines += p.Fset.Position(d.End()).Line - p.Fset.Position(d.Pos()).Line + 1
			if written[obj] {
				note("mutable-global", d, sym)
			} else {
				note("readonly-global", d, sym)
			}
			p.censusType(obj.Type(), d, sym, note)
			for _, v := range d.Values {
				p.censusBody(v, sym, note)
			}
		}
	}
	for k := range c.Sites {
		sort.Strings(c.Sites[k])
	}
	return c
}

func hasPointer(t types.Type) bool {
	switch t := t.(type) {
	case *types.Pointer:
		return true
	case *types.Slice:
		return hasPointer(t.Elem())
	case *types.Array:
		return hasPointer(t.Elem())
	case *types.Map:
		return hasPointer(t.Key()) || hasPointer(t.Elem())
	}
	return false
}

func (p *Program) censusType(t types.Type, n ast.Node, sym string, note func(string, ast.Node, string)) {
	switch t := t.(type) {
	case *types.Basic:
		switch t.Kind() {
		case types.Float32, types.Float64, types.UntypedFloat:
			note("float", n, sym)
		case types.Uint, types.Uint32, types.Uint64, types.Uintptr:
			note("unsigned-wide", n, sym)
		}
	case *types.Map:
		note("map", n, sym)
	case *types.Slice:
		note("slice", n, sym)
	case *types.Signature:
		note("func-value", n, sym)
	case *types.Interface:
		note("interface-type", n, sym)
	case *types.Chan:
		note("goroutine", n, sym)
	}
}

func (p *Program) censusBody(body ast.Node, sym string, note func(string, ast.Node, string)) {
	info := p.Info
	seenType := map[string]bool{}
	ast.Inspect(body, func(n ast.Node) bool {
		switch n := n.(type) {
		case *ast.FuncLit:
			note("closure", n, sym)
		case *ast.DeferStmt:
			note("defer", n, sym)
		case *ast.GoStmt, *ast.SelectStmt, *ast.SendStmt:
			note("goroutine", n, sym)
		case *ast.TypeSwitchStmt, *ast.TypeAssertExpr:
			note("type-switch", n, sym)
		case *ast.BranchStmt:
			if n.Tok == token.GOTO || n.Tok == token.FALLTHROUGH {
				note("goto-label", n, sym)
			}
		case *ast.LabeledStmt:
			note("goto-label", n, sym)
		case *ast.SliceExpr:
			note("slice-expr", n, sym)
		case *ast.UnaryExpr:
			if n.Op == token.AND {
				note("address-of", n, sym)
			}
			if n.Op == token.ARROW {
				note("goroutine", n, sym)
			}
		case *ast.RangeStmt:
			switch t := info.TypeOf(n.X).Underlying().(type) {
			case *types.Signature:
				note("range-func", n, sym)
			case *types.Map:
				note("range-map", n, sym)
			case *types.Basic:
				if t.Info()&types.IsString != 0 {
					note("range-string", n, sym)
				}
			}
		case *ast.CallExpr:
			p.censusCall(n, sym, note)
		case *ast.Ident:
			if obj := info.Uses[n]; obj != nil {
				if f, ok := obj.(*types.Func); ok && !p.isCalled(body, n) {
					note("func-value", n, sym+" ("+f.Name()+")")
				}
			}
		}
		if e, ok := n.(ast.Expr); ok {
			if tv, ok := info.Types[e]; ok && tv.Type != nil && !tv.IsType() {
				key := fmt.Sprint(tv.Type)
				if b, ok := tv.Type.Underlying().(*types.Basic); ok {
					switch b.Kind() {
					case types.Float32, types.Float64:
						if !seenType["f"+key] {
							seenType["f"+key] = true
							note("float", e, sym)
						}
					case types.Uint, types.Uint32, types.Uint64, types.Uintptr:
						if !seenType["u"+key] {
							seenType["u"+key] = true
							note("unsigned-wide", e, sym)
						}
					}
				}
			}
		}
		return true
	})
}

// isCalled reports whether id is the function part of a call or the selector
// part of a called method.
func (p *Program) isCalled(body ast.Node, id *ast.Ident) bool {
	called := false
	ast.Inspect(body, func(n ast.Node) bool {
		if called {
			return false
		}
		call, ok := n.(*ast.CallExpr)
		if !ok {
			return true
		}
		fun := ast.Unparen(call.Fun)
		if ix, ok := fun.(*ast.IndexExpr); ok {
			fun = ix.X
		}
		if ix, ok := fun.(*ast.IndexListExpr); ok {
			fun = ix.X
		}
		switch f := fun.(type) {
		case *ast.Ident:
			called = f == id
		case *ast.SelectorExpr:
			called = f.Sel == id
		}
		return !called
	})
	return called
}

func (p *Program) censusCall(call *ast.CallExpr, sym string, note func(string, ast.Node, string)) {
	info := p.Info
	if call.Ellipsis.IsValid() {
		note("variadic", call, sym+" (spread)")
	}
	fun := ast.Unparen(call.Fun)
	// Conversions.
	if tv, ok := info.Types[fun]; ok && tv.IsType() && len(call.Args) == 1 {
		to := tv.Type.Underlying()
		from := info.TypeOf(call.Args[0])
		if from != nil {
			if types.IsInterface(to) && !types.IsInterface(from) {
				note("any-conversion", call, sym)
			}
			if isStringish(to) && isStringish(from.Underlying()) && !types.Identical(to, from.Underlying()) {
				note("string-conv", call, sym)
			}
		}
		return
	}
	if id, ok := fun.(*ast.Ident); ok {
		if b, ok := info.Uses[id].(*types.Builtin); ok {
			switch b.Name() {
			case "append":
				note("append", call, sym)
			case "panic", "recover":
				note("panic-recover", call, sym)
			}
		}
	}
	// Implicit boxing at call arguments.
	if sig, ok := info.TypeOf(fun).(*types.Signature); ok {
		for i, a := range call.Args {
			var pt types.Type
			if sig.Variadic() && i >= sig.Params().Len()-1 && !call.Ellipsis.IsValid() {
				pt = sig.Params().At(sig.Params().Len() - 1).Type().(*types.Slice).Elem()
			} else if i < sig.Params().Len() {
				pt = sig.Params().At(i).Type()
			}
			at := info.TypeOf(a)
			if pt != nil && at != nil && types.IsInterface(pt) && !types.IsInterface(at) && !isNil(at) {
				note("any-conversion", a, sym)
			}
		}
	}
	if sel, ok := fun.(*ast.SelectorExpr); ok {
		if s := info.Selections[sel]; s != nil && s.Kind() == types.MethodVal && types.IsInterface(s.Recv()) {
			note("interface-call", call, sym+" ("+sel.Sel.Name+")")
		}
		if obj := info.Uses[sel.Sel]; obj != nil && obj.Pkg() != nil && !p.inModule(obj) {
			note("stdlib-call", call, sym+" ("+stdlibName(obj)+")")
		}
	}
	if id, ok := fun.(*ast.Ident); ok {
		if inst, ok := info.Instances[id]; ok && inst.TypeArgs.Len() > 0 {
			note("generic", call, sym+" ("+id.Name+")")
		}
	}
}

func isNil(t types.Type) bool {
	b, ok := t.(*types.Basic)
	return ok && b.Kind() == types.UntypedNil
}

func isStringish(t types.Type) bool {
	switch t := t.(type) {
	case *types.Basic:
		return t.Info()&types.IsString != 0 || t.Kind() == types.Int32 || t.Kind() == types.UntypedRune
	case *types.Slice:
		if b, ok := t.Elem().Underlying().(*types.Basic); ok {
			return b.Kind() == types.Byte || b.Kind() == types.Int32
		}
	}
	return false
}

// writtenGlobals finds package variables that reachable code assigns, increments,
// or takes the address of (other than in their own initialiser).
func (p *Program) writtenGlobals(r *Reach) map[types.Object]bool {
	w := map[types.Object]bool{}
	mark := func(e ast.Expr) {
		for {
			switch x := e.(type) {
			case *ast.SelectorExpr:
				if obj := p.Info.Uses[x.Sel]; obj != nil {
					if v, ok := obj.(*types.Var); ok && !v.IsField() && isPackageLevel(v) {
						w[obj] = true
						return
					}
				}
				e = x.X
				continue
			case *ast.IndexExpr:
				e = x.X
				continue
			case *ast.ParenExpr:
				e = x.X
				continue
			case *ast.StarExpr:
				e = x.X
				continue
			case *ast.Ident:
				if obj := p.Info.Uses[x]; obj != nil {
					if v, ok := obj.(*types.Var); ok && isPackageLevel(v) {
						w[obj] = true
					}
				}
			}
			return
		}
	}
	for _, obj := range r.Order {
		fd, ok := p.Decls[obj].(*ast.FuncDecl)
		if !ok || fd.Body == nil {
			continue
		}
		ast.Inspect(fd.Body, func(n ast.Node) bool {
			switch n := n.(type) {
			case *ast.AssignStmt:
				for _, l := range n.Lhs {
					mark(l)
				}
			case *ast.IncDecStmt:
				mark(n.X)
			case *ast.UnaryExpr:
				if n.Op == token.AND {
					mark(n.X)
				}
			case *ast.CallExpr:
				// A pointer-receiver method call on a global writes it.
				if sel, ok := n.Fun.(*ast.SelectorExpr); ok {
					if s := p.Info.Selections[sel]; s != nil && s.Kind() == types.MethodVal {
						if sig, ok := s.Obj().Type().(*types.Signature); ok && sig.Recv() != nil {
							if _, ptr := sig.Recv().Type().(*types.Pointer); ptr {
								if _, already := s.Recv().(*types.Pointer); !already {
									mark(sel.X)
								}
							}
						}
					}
				}
			}
			return true
		})
	}
	return w
}

func (c *Census) write(w io.Writer, p *Program, r *Reach, cfg *Config, detail int) {
	fmt.Fprintf(w, "# go2nl census\n\n")
	if cfg.Upstream.Repo != "" {
		fmt.Fprintf(w, "Upstream: %s at %s\n\n", cfg.Upstream.Repo, cfg.Upstream.Commit)
	}
	fmt.Fprintf(w, "Roots: %s\n\n", strings.Join(cfg.Roots, ", "))
	fmt.Fprintf(w, "Reachable: %d functions and methods (%d lines), %d types, %d package variables, %d constants.\n\n", c.Funcs, c.Lines, c.Types, c.Vars, c.Consts)
	perPkg := map[string]int{}
	for _, obj := range r.Order {
		if _, ok := p.Decls[obj].(*ast.FuncDecl); ok {
			perPkg[p.shortPkg(obj.Pkg().Path())]++
		}
	}
	var pkgs []string
	for k := range perPkg {
		pkgs = append(pkgs, k)
	}
	sort.Strings(pkgs)
	fmt.Fprintf(w, "Functions by package:")
	for _, k := range pkgs {
		fmt.Fprintf(w, " %s %d,", k, perPkg[k])
	}
	fmt.Fprintf(w, "\n\n| Construct | Sites | Meaning |\n| --- | ---: | --- |\n")
	for _, cat := range censusCategories {
		fmt.Fprintf(w, "| %s | %d | %s |\n", cat.key, len(c.Sites[cat.key]), cat.about)
	}
	fmt.Fprintf(w, "\n## Standard library uses\n\n| Name | Uses |\n| --- | ---: |\n")
	type kv struct {
		k string
		v int
	}
	var std []kv
	for k, v := range r.Stdlib {
		std = append(std, kv{k, v})
	}
	sort.Slice(std, func(i, j int) bool {
		if std[i].v != std[j].v {
			return std[i].v > std[j].v
		}
		return std[i].k < std[j].k
	})
	for _, e := range std {
		fmt.Fprintf(w, "| %s | %d |\n", e.k, e.v)
	}
	fmt.Fprintf(w, "\n## Sites\n")
	for _, cat := range censusCategories {
		sites := c.Sites[cat.key]
		if len(sites) == 0 {
			continue
		}
		fmt.Fprintf(w, "\n### %s (%d)\n\n", cat.key, len(sites))
		for i, s := range sites {
			if detail >= 0 && i >= detail {
				fmt.Fprintf(w, "- ... %d more\n", len(sites)-i)
				break
			}
			fmt.Fprintf(w, "- %s\n", s)
		}
	}
}
