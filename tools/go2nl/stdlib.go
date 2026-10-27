package main

import (
	"fmt"
	"go/ast"
	"go/constant"
	"go/types"
	"strings"
)

// The standard library as converted code sees it: each Go function maps to a
// hand-written function in shim/gostd.nl. Several results come back as a
// struct with fields r0, r1 (as converted functions do). A Builder method
// changes its receiver, so the receiver is passed as a write parameter.
type stdFn struct {
	shim      string
	tuple     bool // returns several results
	writeRecv bool // method whose receiver it changes
}

var stdlibTable = map[string]stdFn{
	"strings.HasPrefix":                   {shim: "go_strings_HasPrefix"},
	"strings.HasSuffix":                   {shim: "go_strings_HasSuffix"},
	"strings.IndexByte":                   {shim: "go_strings_IndexByte"},
	"strings.Repeat":                      {shim: "go_strings_Repeat"},
	"strings.TrimSuffix":                  {shim: "go_strings_TrimSuffix"},
	"strings.TrimPrefix":                  {shim: "go_strings_TrimPrefix"},
	"strings.Builder.WriteString":         {shim: "go_strings_Builder_WriteString", writeRecv: true},
	"strings.Builder.WriteByte":           {shim: "go_strings_Builder_WriteByte", writeRecv: true},
	"strings.Builder.WriteRune":           {shim: "go_strings_Builder_WriteRune", writeRecv: true},
	"strings.Builder.Grow":                {shim: "go_strings_Builder_Grow", writeRecv: true},
	"strings.Builder.Reset":               {shim: "go_strings_Builder_Reset", writeRecv: true},
	"strings.Builder.String":              {shim: "go_strings_Builder_String"},
	"strings.Builder.Len":                 {shim: "go_strings_Builder_Len"},
	"strconv.Itoa":                        {shim: "go_strconv_Itoa"},
	"strconv.FormatInt":                   {shim: "go_strconv_FormatInt"},
	"strconv.ParseInt":                    {shim: "go_strconv_ParseInt", tuple: true},
	"strconv.Atoi":                        {shim: "go_strconv_Atoi", tuple: true},
	"unicode/utf8.DecodeRuneInString":     {shim: "go_utf8_DecodeRuneInString", tuple: true},
	"unicode/utf8.DecodeLastRuneInString": {shim: "go_utf8_DecodeLastRuneInString", tuple: true},
	"unicode/utf8.RuneLen":                {shim: "go_utf8_RuneLen"},
	"unicode/utf16.IsSurrogate":           {shim: "go_utf16_IsSurrogate"},
	"unicode/utf16.DecodeRune":            {shim: "go_utf16_DecodeRune"},
	"unicode/utf16.EncodeRune":            {shim: "go_utf16_EncodeRune", tuple: true},
}

// stdlibType maps the standard-library types converted code may hold.
func (c *conv) stdlibType(t *types.Named) (string, string, bool) {
	switch t.Obj().Pkg().Path() + "." + t.Obj().Name() {
	case "strings.Builder":
		c.decide("strings.Builder becomes a Bytes builder")
		return "Bytes max go_string_max", `b""`, true
	}
	return "", "", false
}

// Go's error, as converted code needs it: nil or one of a few known errors.
// Code that formats an error's text is refused.
const errorType = "GoError"

var stdlibErrors = map[string]string{
	"strconv.ErrRange":  "1L",
	"strconv.ErrSyntax": "2L",
}

func isErrorType(t types.Type) bool {
	n, ok := t.(*types.Named)
	return ok && n.Obj().Pkg() == nil && n.Obj().Name() == "error"
}

func (f *fnConv) stdlibCall(name string, e *ast.CallExpr) string {
	c := f.c
	info := c.p.Info
	switch name {
	case "fmt.Println":
		if len(e.Args) != 1 {
			c.fail(e, "stdlib-call", "fmt.Println with %d arguments", len(e.Args))
		}
		t := info.TypeOf(e.Args[0])
		if b, ok := t.Underlying().(*types.Basic); ok && b.Info()&(types.IsInteger|types.IsBoolean|types.IsString) != 0 {
			c.decide("fmt.Println of one integer, bool or string becomes print")
			return "print(" + f.valueExpr(e.Args[0], types.Default(t)) + ")"
		}
		c.fail(e, "stdlib-call", "fmt.Println of %s", t)
	case "fmt.Sprintf":
		return f.sprintf(e)
	case "fmt.Sprint":
		// Only debug.Fail's panic message uses it; panics don't keep messages.
		c.decide("fmt.Sprint for a panic message becomes an empty string (panics keep no message)")
		return `b""`
	case "errors.Is":
		return "(" + f.valueExpr(e.Args[0], nil) + " == " + f.valueExpr(e.Args[1], nil) + ")"
	}
	sf, ok := stdlibTable[name]
	if !ok {
		c.fail(e, "stdlib-call", "%s has no shim yet", name)
	}
	c.decide("standard-library call goes to the gostd shim")
	callee := calleeFunc(c, e)
	sig := callee.Signature()
	var args []string
	if sel, ok := ast.Unparen(e.Fun).(*ast.SelectorExpr); ok {
		if s := info.Selections[sel]; s != nil && s.Kind() == types.MethodVal {
			if sf.writeRecv {
				args = append(args, f.place(sel.X))
			} else {
				args = append(args, f.expr(sel.X))
			}
		}
	}
	for i, a := range e.Args {
		args = append(args, f.valueExpr(a, sig.Params().At(i).Type()))
	}
	return sf.shim + "(" + strings.Join(args, ", ") + ")"
}

// sprintf compiles a constant format string into concatenations, for the
// verbs converted code uses: %s, %d, %x and %X with an optional zero-padded
// width, and %%.
func (f *fnConv) sprintf(e *ast.CallExpr) string {
	c := f.c
	tv := c.p.Info.Types[e.Args[0]]
	if tv.Value == nil || tv.Value.Kind() != constant.String {
		c.fail(e, "stdlib-call", "fmt.Sprintf with a format that isn't a constant")
	}
	format := constant.StringVal(tv.Value)
	args := e.Args[1:]
	var parts []string
	lit := strings.Builder{}
	flush := func() {
		if lit.Len() > 0 {
			parts = append(parts, bytesLiteral(lit.String()))
			lit.Reset()
		}
	}
	ai := 0
	for i := 0; i < len(format); i++ {
		ch := format[i]
		if ch != '%' {
			lit.WriteByte(ch)
			continue
		}
		i++
		if i < len(format) && format[i] == '%' {
			lit.WriteByte('%')
			continue
		}
		width := 0
		zero := false
		if i < len(format) && format[i] == '0' {
			zero = true
			i++
		}
		for i < len(format) && format[i] >= '0' && format[i] <= '9' {
			width = width*10 + int(format[i]-'0')
			i++
		}
		if i >= len(format) || ai >= len(args) {
			c.fail(e, "stdlib-call", "fmt.Sprintf format %q", format)
		}
		verb := format[i]
		a := args[ai]
		ai++
		flush()
		var piece string
		at := c.p.Info.TypeOf(a)
		switch verb {
		case 's':
			if !isGoString(at) {
				c.fail(e, "stdlib-call", "%%s of %s", at)
			}
			piece = f.valueExpr(a, types.Typ[types.String])
		case 'd', 'x', 'X':
			if c.intBase(at) == "" {
				c.fail(e, "stdlib-call", "%%%c of %s", verb, at)
			}
			base := map[byte]string{'d': "10L", 'x': "16L", 'X': "16L"}[verb]
			v := f.valueExpr(a, nil)
			if c.intBase(at) != "long" || isU32(at) || isNarrow(at) {
				v = f.convertInt(v, at, types.Typ[types.Int])
			}
			piece = "go_strconv_FormatInt(" + v + ", " + base + ")"
			if verb == 'X' {
				piece = "go_ascii_upper(" + piece + ")"
			}
		default:
			c.fail(e, "stdlib-call", "fmt.Sprintf verb %%%c", verb)
		}
		if width > 0 {
			pad := "32"
			if zero {
				pad = "48"
			}
			piece = fmt.Sprintf("go_pad_left(%s, %dL, %s)", piece, width, pad)
		}
		parts = append(parts, piece)
	}
	flush()
	if ai != len(args) {
		c.fail(e, "stdlib-call", "fmt.Sprintf with extra arguments")
	}
	c.decide("fmt.Sprintf with a constant format becomes concatenation")
	if len(parts) == 0 {
		return `b""`
	}
	out := parts[0]
	for _, p := range parts[1:] {
		out = "go_concat(" + out + ", " + p + ")"
	}
	return out
}
