package main

import (
	"go/ast"
	"go/token"
	"go/types"
)

// Parameter modes. Go passes everything by value, and a pointer lets the callee
// change the caller's value. next-lang parameters are read-only unless marked
// `write`, so the converter works out, across the whole call graph, which
// parameters a function changes:
//
//   - a pointer parameter (or receiver) the function changes through becomes
//     `write`; one it only reads becomes a plain parameter;
//   - a slice or map parameter whose elements the function changes becomes
//     `write` (Go shares the backing array with the caller);
//   - any other parameter the function reassigns or changes is copied into a
//     local at the top of the function, since in Go it was the callee's copy.
type paramInfo struct {
	write []bool // per parameter, receiver first
	copy  []bool
}

type modes struct {
	c     *conv
	funcs map[*types.Func]*paramInfo
	// index of each parameter object: function and position
	paramOf map[types.Object]paramRef
}

type paramRef struct {
	fn  *types.Func
	idx int
}

func sigParams(f *types.Func) []*types.Var {
	sig := f.Signature()
	var out []*types.Var
	if sig.Recv() != nil {
		out = append(out, sig.Recv())
	}
	for i := 0; i < sig.Params().Len(); i++ {
		out = append(out, sig.Params().At(i))
	}
	return out
}

func (c *conv) computeModes() *modes {
	m := &modes{c: c, funcs: map[*types.Func]*paramInfo{}, paramOf: map[types.Object]paramRef{}}
	var fns []*types.Func
	for _, obj := range c.r.Order {
		f, ok := obj.(*types.Func)
		if !ok {
			continue
		}
		fd, ok := c.p.Decls[f].(*ast.FuncDecl)
		if !ok || fd.Body == nil {
			continue
		}
		fns = append(fns, f)
		ps := sigParams(f)
		m.funcs[f] = &paramInfo{write: make([]bool, len(ps)), copy: make([]bool, len(ps))}
		// Parameter objects are the ones defined by the declaration's idents.
		idx := 0
		if fd.Recv != nil {
			for _, fl := range fd.Recv.List {
				for _, n := range fl.Names {
					if obj := c.p.Info.Defs[n]; obj != nil {
						m.paramOf[obj] = paramRef{f, 0}
					}
				}
			}
			idx = 1
		}
		for _, fl := range fd.Type.Params.List {
			if len(fl.Names) == 0 {
				idx++
				continue
			}
			for _, n := range fl.Names {
				if obj := c.p.Info.Defs[n]; obj != nil {
					m.paramOf[obj] = paramRef{f, idx}
				}
				idx++
			}
		}
	}
	for changed := true; changed; {
		changed = false
		for _, f := range fns {
			fd := c.p.Decls[f].(*ast.FuncDecl)
			ast.Inspect(fd.Body, func(n ast.Node) bool {
				for _, place := range m.mutatedPlaces(n) {
					if m.markMutation(place.e, place.viaCall) {
						changed = true
					}
				}
				return true
			})
		}
	}
	return m
}

// mutatedPlaces lists the expressions node n changes.
type mutation struct {
	e       ast.Expr
	viaCall bool // passed to a write parameter: a pointer passed on is changed through
}

func (m *modes) mutatedPlaces(n ast.Node) []mutation {
	plain := func(es ...ast.Expr) []mutation {
		var out []mutation
		for _, e := range es {
			out = append(out, mutation{e, false})
		}
		return out
	}
	info := m.c.p.Info
	switch n := n.(type) {
	case *ast.AssignStmt:
		if n.Tok == token.DEFINE {
			return nil
		}
		return plain(n.Lhs...)
	case *ast.IncDecStmt:
		return plain(n.X)
	case *ast.UnaryExpr:
		if n.Op == token.AND {
			// Taking an address outside a call argument is checked (and refused)
			// by the emitter; as a call argument it is handled below.
			return nil
		}
	case *ast.CallExpr:
		var out []mutation
		fun := ast.Unparen(n.Fun)
		var callee *types.Func
		var recvExpr ast.Expr
		switch f := fun.(type) {
		case *ast.Ident:
			callee, _ = info.Uses[f].(*types.Func)
			if b, ok := info.Uses[f].(*types.Builtin); ok && b.Name() == "delete" && len(n.Args) > 0 {
				out = append(out, mutation{&ast.IndexExpr{X: n.Args[0]}, false})
			}
		case *ast.SelectorExpr:
			if s := info.Selections[f]; s != nil && s.Kind() == types.MethodVal {
				callee, _ = s.Obj().(*types.Func)
				recvExpr = f.X
			} else {
				callee, _ = info.Uses[f.Sel].(*types.Func)
			}
		}
		if callee == nil {
			return out
		}
		callee = callee.Origin()
		pi := m.funcs[callee]
		if pi == nil {
			return out
		}
		off := 0
		if recvExpr != nil {
			if pi.write[0] {
				out = append(out, mutation{recvExpr, true})
			}
			off = 1
		}
		for i, a := range n.Args {
			if off+i < len(pi.write) && pi.write[off+i] {
				out = append(out, mutation{a, true})
			}
		}
		return out
	}
	return nil
}

// markMutation records that place is changed; it reports whether that changed
// any parameter's mode.
func (m *modes) markMutation(place ast.Expr, viaCall bool) bool {
	info := m.c.p.Info
	elem := false // changed through a slice or map element
	deref := false
	e := place
	for {
		switch x := e.(type) {
		case *ast.ParenExpr:
			e = x.X
			continue
		case *ast.UnaryExpr:
			if x.Op == token.AND {
				e = x.X
				continue
			}
		case *ast.StarExpr:
			deref = true
			e = x.X
			continue
		case *ast.SelectorExpr:
			if s := info.Selections[x]; s != nil && s.Kind() == types.FieldVal {
				if _, ok := info.TypeOf(x.X).Underlying().(*types.Pointer); ok {
					deref = true
				}
				e = x.X
				continue
			}
		case *ast.IndexExpr:
			if x.X == nil {
				return false
			}
			switch info.TypeOf(x.X).Underlying().(type) {
			case *types.Slice, *types.Map:
				elem = true
			case *types.Pointer:
				deref = true
			}
			e = x.X
			continue
		case *ast.Ident:
			obj := info.Uses[x]
			if obj == nil {
				obj = info.Defs[x]
			}
			ref, ok := m.paramOf[obj]
			if !ok {
				return false
			}
			pi := m.funcs[ref.fn]
			t := obj.Type().Underlying()
			_, isPtr := t.(*types.Pointer)
			_, isSlice := t.(*types.Slice)
			_, isMap := t.(*types.Map)
			if (isPtr && (deref || viaCall)) || ((isSlice || isMap) && (elem || viaCall)) {
				if !pi.write[ref.idx] {
					pi.write[ref.idx] = true
					return true
				}
				return false
			}
			if !pi.copy[ref.idx] {
				pi.copy[ref.idx] = true
				return true
			}
			return false
		}
		return false
	}
}

// findRecursive marks every function on a call cycle: next-lang makes
// recursion opt-in (`recursive fn`), with a native-stack budget.
func (c *conv) findRecursive() map[*types.Func]bool {
	calls := map[*types.Func][]*types.Func{}
	var fns []*types.Func
	for _, obj := range c.r.Order {
		f, ok := obj.(*types.Func)
		if !ok {
			continue
		}
		fd, ok := c.p.Decls[f].(*ast.FuncDecl)
		if !ok || fd.Body == nil {
			continue
		}
		fns = append(fns, f)
		ast.Inspect(fd.Body, func(n ast.Node) bool {
			if call, ok := n.(*ast.CallExpr); ok {
				if g := calleeFunc(c, call); g != nil && c.p.inModule(g) {
					calls[f] = append(calls[f], g.Origin())
				}
			}
			return true
		})
	}
	// Tarjan's strongly connected components.
	index := map[*types.Func]int{}
	low := map[*types.Func]int{}
	onStack := map[*types.Func]bool{}
	var stack []*types.Func
	rec := map[*types.Func]bool{}
	next := 0
	var visit func(f *types.Func)
	visit = func(f *types.Func) {
		index[f] = next
		low[f] = next
		next++
		stack = append(stack, f)
		onStack[f] = true
		for _, g := range calls[f] {
			if _, seen := index[g]; !seen {
				visit(g)
				low[f] = min(low[f], low[g])
			} else if onStack[g] {
				low[f] = min(low[f], index[g])
			}
			if g == f {
				rec[f] = true
			}
		}
		if low[f] == index[f] {
			var comp []*types.Func
			for {
				g := stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				onStack[g] = false
				comp = append(comp, g)
				if g == f {
					break
				}
			}
			if len(comp) > 1 {
				for _, g := range comp {
					rec[g] = true
				}
			}
		}
	}
	for _, f := range fns {
		if _, seen := index[f]; !seen {
			visit(f)
		}
	}
	return rec
}
