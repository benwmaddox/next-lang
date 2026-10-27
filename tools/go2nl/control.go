package main

import (
	"fmt"
	"go/ast"
	"go/token"
	"go/types"
	"strings"
)

// Loops, switches, break, continue, labels and fallthrough.
//
// A Go switch becomes an if / else-if chain. When a switch contains a break
// that leaves it, the chain runs inside a one-pass loop (`for once in 0L..1L`)
// so next-lang's break leaves it too. A jump that has to leave more than one
// next-lang loop (continue inside such a switch, or a labeled break out of an
// inner loop) sets a flag and breaks; every loop it crosses checks the flag as
// it closes and passes the jump on, until it reaches its target.

type target struct {
	isLoop   bool     // a Go loop
	isSwitch bool     // a Go switch
	wrapped  bool     // a switch wrapped in a one-pass loop
	label    string   // the Go label naming this statement, if any
	post     []string // a 3-clause loop's post statement, run before continue
	flags    []string // flag variables to declare before the statement
	pending  []pendingJump
}

// pendingJump is a flagged jump passing through a next-lang loop.
type pendingJump struct {
	flag   string
	to     *target
	isCont bool
}

// nlLoop: the target is a loop in the next-lang output.
func (t *target) nlLoop() bool { return t.isLoop || t.wrapped }

// enter starts a loop or switch: its text goes to a buffer of its own, so that
// flag declarations found while converting it can go in front.
func (f *fnConv) enter(t *target) strings.Builder {
	if f.label != "" {
		t.label = f.label
		f.label = ""
	}
	f.targets = append(f.targets, t)
	outer := f.b
	f.b = strings.Builder{}
	return outer
}

func (f *fnConv) leave(t *target, outer strings.Builder) {
	f.targets = f.targets[:len(f.targets)-1]
	inner := f.b.String()
	f.b = outer
	for _, fl := range t.flags {
		f.line("var %s = false", fl)
	}
	f.b.WriteString(inner)
	if !t.nlLoop() {
		return
	}
	// Jumps flagged inside this loop that go further out.
	for _, p := range t.pending {
		direct := true
		for i := len(f.targets) - 1; i >= 0 && f.targets[i] != p.to; i-- {
			if f.targets[i].nlLoop() {
				direct = false
				f.targets[i].pending = append(f.targets[i].pending, p)
				break
			}
		}
		switch {
		case !direct:
			f.line("if %s { break }", p.flag)
		case p.isCont:
			f.line("if %s {", p.flag)
			f.ind++
			f.line("%s = false", p.flag)
			for _, s := range p.to.post {
				f.line("%s", s)
			}
			f.line("continue")
			f.ind--
			f.line("}")
		case p.to.nlLoop():
			f.line("if %s { break }", p.flag)
		default:
			f.c.fail(nil, "goto-label", "break out of a switch that isn't a loop")
		}
	}
}

func (f *fnConv) labeled(s *ast.LabeledStmt) {
	switch s.Stmt.(type) {
	case *ast.ForStmt, *ast.RangeStmt, *ast.SwitchStmt:
		f.label = s.Label.Name
		f.stmt(s.Stmt)
		f.label = ""
	default:
		f.c.fail(s, "goto-label", "label on a %T", s.Stmt)
	}
}

func (f *fnConv) branch(s *ast.BranchStmt) {
	c := f.c
	if s.Tok == token.GOTO || s.Tok == token.FALLTHROUGH {
		c.fail(s, "goto-label", "%s", s.Tok)
	}
	isCont := s.Tok == token.CONTINUE
	// Find the target.
	ti := -1
	for i := len(f.targets) - 1; i >= 0; i-- {
		t := f.targets[i]
		if s.Label != nil {
			if t.label == s.Label.Name {
				ti = i
				break
			}
			continue
		}
		if t.isLoop || (!isCont && t.isSwitch) {
			ti = i
			break
		}
	}
	if ti < 0 {
		c.fail(s, "goto-label", "%s target not found", s.Tok)
	}
	to := f.targets[ti]
	if isCont && !to.isLoop {
		c.fail(s, "goto-label", "continue to a switch")
	}
	// The innermost next-lang loop strictly inside the target.
	var innermost *target
	for i := len(f.targets) - 1; i > ti; i-- {
		if f.targets[i].nlLoop() {
			innermost = f.targets[i]
			break
		}
	}
	if innermost == nil {
		if isCont {
			f.continueTo(to)
			return
		}
		if !to.nlLoop() {
			c.fail(s, "goto-label", "break out of a switch that isn't wrapped")
		}
		f.line("break")
		return
	}
	kind := "break"
	if isCont {
		kind = "continue"
	}
	flag := f.tmp(kind + "_out")
	to.flags = append(to.flags, flag)
	innermost.pending = append(innermost.pending, pendingJump{flag: flag, to: to, isCont: isCont})
	f.line("%s = true", flag)
	f.line("break")
	c.decide("a break or continue that leaves several next-lang loops sets a flag each loop checks")
}

func (f *fnConv) continueTo(t *target) {
	if len(t.post) == 0 {
		f.line("continue")
		return
	}
	f.line("{")
	f.ind++
	for _, p := range t.post {
		f.line("%s", p)
	}
	f.line("continue")
	f.ind--
	f.line("}")
}

func (f *fnConv) switchStmt(s *ast.SwitchStmt) {
	c := f.c
	if s.Init != nil {
		f.stmt(s.Init)
	}
	t := &target{isSwitch: true, wrapped: switchBreaks(s.Body)}
	outer := f.enter(t)
	tag := ""
	var tagType types.Type
	if s.Tag != nil {
		tagType = c.p.Info.TypeOf(s.Tag)
		tag = f.tmp("tag")
		f.line("let %s: %s = %s", tag, c.nlType(tagType, ""), f.valueExpr(s.Tag, tagType))
	}
	if t.wrapped {
		f.line("for %s in 0L..1L {", f.tmp("once"))
		f.ind++
		c.decide("switch containing break runs inside a one-pass loop, so break leaves it")
	}
	clauses := s.Body.List
	var def int = -1
	first := true
	for i, st := range clauses {
		cc := st.(*ast.CaseClause)
		if cc.List == nil {
			def = i
			continue
		}
		var conds []string
		f.noPre = !first
		for _, e := range cc.List {
			if tag != "" {
				conds = append(conds, tag+" == "+f.paren(f.valueExpr(e, tagType)))
			} else {
				conds = append(conds, f.paren(f.expr(e)))
			}
		}
		f.noPre = false
		head := "} else if"
		if first {
			head = "if"
		}
		first = false
		f.line("%s %s {", head, condText(strings.Join(conds, " || ")))
		f.caseBody(clauses, i)
	}
	if def >= 0 {
		if first {
			f.line("{")
		} else {
			f.line("} else {")
		}
		f.caseBody(clauses, def)
		f.line("}")
	} else if !first {
		f.line("} else {")
		f.line("}")
	}
	if t.wrapped {
		f.ind--
		f.line("}")
	}
	f.leave(t, outer)
	c.decide("switch becomes an if / else if chain (default last, as Go picks it last)")
}

// caseBody writes clause i's statements; a final fallthrough continues with
// the next clause's statements, as Go runs them.
func (f *fnConv) caseBody(clauses []ast.Stmt, i int) {
	var body []ast.Stmt
	for {
		cc := clauses[i].(*ast.CaseClause)
		stmts := cc.Body
		falls := false
		if n := len(stmts); n > 0 {
			if br, ok := stmts[n-1].(*ast.BranchStmt); ok && br.Tok == token.FALLTHROUGH {
				stmts = stmts[:n-1]
				falls = true
			}
		}
		body = append(body, stmts...)
		if !falls || i+1 >= len(clauses) {
			break
		}
		i++
		f.c.decide("fallthrough runs the next clause's statements (copied in)")
	}
	f.block(body)
}

func (f *fnConv) paren(s string) string {
	if strings.ContainsAny(s, " ") && !(strings.HasPrefix(s, "(") && strings.HasSuffix(s, ")")) {
		return "(" + s + ")"
	}
	return s
}

// switchBreaks: the switch body has an unlabeled break that leaves it.
func switchBreaks(body *ast.BlockStmt) bool {
	found := false
	var walk func(n ast.Node, nested bool)
	walk = func(n ast.Node, nested bool) {
		ast.Inspect(n, func(m ast.Node) bool {
			if m == n {
				return true
			}
			switch m := m.(type) {
			case *ast.ForStmt, *ast.RangeStmt, *ast.SwitchStmt, *ast.TypeSwitchStmt, *ast.SelectStmt:
				walk(m, true)
				return false
			case *ast.FuncLit:
				return false
			case *ast.BranchStmt:
				if m.Label == nil && m.Tok == token.BREAK && !nested {
					found = true
				}
			}
			return true
		})
	}
	walk(body, false)
	return found
}

// rangeString converts `for i, r := range s`: Go decodes UTF-8 one rune at a
// time, giving each rune's byte offset, and U+FFFD for an invalid byte.
func (f *fnConv) rangeString(s *ast.RangeStmt, key, val types.Object) {
	c := f.c
	str := f.tmp("text")
	f.line("let %s: Bytes max go_string_max = %s", str, f.valueExpr(s.X, types.Typ[types.String]))
	pos := f.tmp("offset")
	if key != nil {
		pos = f.local(key)
	}
	f.line("var %s: long = 0L", pos)
	dec := f.tmp("decoded")
	t := &target{isLoop: true, post: []string{fmt.Sprintf("%s += %s.r1", pos, dec)}}
	outer := f.enter(t)
	f.line("for %s in 0L..%s.len() {", f.tmp("step"), str)
	f.ind++
	f.line("if %s >= %s.len() { break }", pos, str)
	f.line("let %s = go_utf8_DecodeRuneInString(%s.slice(%s..%s.len()))", dec, str, pos, str)
	if val != nil {
		f.line("var %s: int = %s.r0", f.local(val), dec)
	}
	f.ind--
	f.block(s.Body.List)
	f.ind++
	f.line("%s += %s.r1", pos, dec)
	f.ind--
	f.line("}")
	f.leave(t, outer)
	c.decide("range over a string decodes UTF-8 with the gostd shim, as Go does")
}
