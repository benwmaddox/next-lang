// Generic helpers as typescript-go's core package writes them, a bound method
// value passed as a callback, lazily created maps, unicode.Is over a range
// table, strings.Join, and string([]byte{...}).
package main

import (
	"fmt"
	"strings"
	"unicode"
)

type Kind int16

const (
	KindA Kind = 1
	KindB Kind = 2
)

func IfElse[T any](b bool, whenTrue T, whenFalse T) T {
	if b {
		return whenTrue
	}
	return whenFalse
}

func cleared[M ~map[K]V, K comparable, V any](m M) M {
	clear(m)
	return m
}

func Max[T int | int32](a, b T) T {
	if a > b {
		return a
	}
	return b
}

type Message struct{ code int32 }

var Conflict = &Message{code: 1185}

type Scanner struct {
	text   string
	pos    int
	errs   int
	last   int32
	cache  map[string]string
	digits map[string]string
}

func (s *Scanner) errorAt(d *Message, pos, length int, args ...any) {
	s.errs++
	s.last = d.code
}

func skipMarker(text string, pos int, report func(d *Message, pos, length int, args ...any)) int {
	if report != nil {
		report(Conflict, pos, 7)
	}
	for pos < len(text) && text[pos] == '=' {
		pos++
	}
	return pos
}

func (s *Scanner) scan() {
	s.pos = skipMarker(s.text, s.pos, s.errorAt)
}

func (s *Scanner) value(key string) string {
	if s.cache == nil {
		s.cache = make(map[string]string)
	}
	if v, ok := s.cache[key]; ok {
		return v
	}
	v := strings.Join([]string{"<", key, ">"}, "")
	s.cache[key] = v
	return v
}

func (s *Scanner) reset() {
	s.cache = cleared(s.cache)
	s.digits = cleared(s.digits)
}

var smallTable = &unicode.RangeTable{
	R16: []unicode.Range16{
		{0x41, 0x5A, 1},
		{0x61, 0x7A, 1},
		{0xAA, 0xB5, 11},
		{0x370, 0x37D, 2},
	},
	R32: []unicode.Range32{
		{0x10000, 0x1000B, 1},
		{0x1F600, 0x1F64F, 1},
	},
	LatinOffset: 3,
}

func main() {
	fmt.Println(int(IfElse(true, KindA, KindB)))
	fmt.Println(int(IfElse(false, KindA, KindB)))
	fmt.Println(IfElse(len("ab") == 2, "two", "other"))
	fmt.Println(Max(3, 9))
	fmt.Println(int(Max(int32(-4), int32(-8))))

	s := &Scanner{text: "=====x"}
	s.scan()
	fmt.Println(s.pos)
	fmt.Println(s.errs)
	fmt.Println(int(s.last))
	fmt.Println(skipMarker("==", 0, nil))

	fmt.Println(s.value("k"))
	fmt.Println(s.value("k"))
	fmt.Println(len(s.cache))
	s.reset()
	fmt.Println(len(s.cache))
	fmt.Println(s.value("j"))

	for _, r := range []rune{'A', 'z', '[', 0xAA, 0xAB, 0xB5, 0x372, 0x373, 0x10005, 0x1F600, 0x1F650, -1} {
		fmt.Println(unicode.Is(smallTable, r))
	}
	fmt.Println(strings.Join([]string{"a", "b", "c"}, ", "))
	fmt.Println(len(string([]byte{0xED, 0xA0, 0x80})))
}
