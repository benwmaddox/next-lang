// The shapes the typescript-go scanner uses: an embedded state struct, a
// diagnostics table of &Message{...} globals, an error callback stored in a
// field and called with variadic ...any, and closures passed to a helper.
package main

import "fmt"

type Message struct {
	code int32
	text string
}

func (m *Message) Code() int32 { return m.code }

var Unexpected_character = &Message{code: 1127, text: "Invalid character."}
var Digit_expected = &Message{code: 1124, text: "Digit expected."}

type ErrorCallback func(diagnostic *Message, start, length int, args ...any)

type State struct {
	pos   int
	token int
}

type Scanner struct {
	text    string
	onError ErrorCallback
	State
	errors int
}

func defaultScanner() Scanner { return Scanner{} }

func NewScanner() *Scanner {
	s := defaultScanner()
	return &s
}

func (s *Scanner) SetOnError(cb ErrorCallback) { s.onError = cb }

func (s *Scanner) errorAt(d *Message, pos, length int, args ...any) {
	s.errors++
	if s.onError != nil {
		s.onError(d, pos, length, args...)
	}
}

func (s *Scanner) Mark() State      { return s.State }
func (s *Scanner) Rewind(st State)  { s.State = st }
func (s *Scanner) advance(n int)    { s.pos += n }

func (s *Scanner) scanWhile(pred func(byte) bool) {
	for s.pos < len(s.text) && pred(s.text[s.pos]) {
		s.pos++
	}
}

func isSpace(b byte) bool { return b == ' ' }

func (s *Scanner) Scan() int {
	s.scanWhile(isSpace)
	if s.pos >= len(s.text) {
		s.token = 0
		return 0
	}
	ch := s.text[s.pos]
	if ch >= '0' && ch <= '9' {
		s.scanWhile(func(b byte) bool { return b >= '0' && b <= '9' })
		s.token = 1
	} else if ch >= 'a' && ch <= 'z' {
		s.scanWhile(func(b byte) bool { return b >= 'a' && b <= 'z' })
		s.token = 2
	} else if ch == '#' {
		s.advance(1)
		if s.pos >= len(s.text) || s.text[s.pos] < '0' || s.text[s.pos] > '9' {
			s.errorAt(Digit_expected, s.pos, 0)
		}
		s.token = 3
	} else {
		s.errorAt(Unexpected_character, s.pos, 1, "char", int(ch), true)
		s.advance(1)
		s.token = 4
	}
	return s.token
}

func report(d *Message, start, length int, args ...any) {
	fmt.Println(int(d.Code()))
	fmt.Println(start)
	fmt.Println(length)
	fmt.Println(len(args))
}

func main() {
	s := NewScanner()
	s.text = "  abc 12 @ #x"
	s.SetOnError(report)
	for {
		mark := s.Mark()
		k := s.Scan()
		if k == 0 {
			break
		}
		fmt.Println(k)
		fmt.Println(s.pos - mark.pos)
	}
	saved := s.Mark()
	s.Rewind(State{pos: 2})
	fmt.Println(s.Scan())
	s.Rewind(saved)
	s.SetOnError(nil)
	s.errorAt(Digit_expected, 0, 0)
	fmt.Println(s.errors)
}
