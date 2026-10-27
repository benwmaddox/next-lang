// A small scanner written the way typescript-go's scanner is: a struct with a
// text, a position and the current token, methods with pointer receivers, a
// keyword map, switch-heavy dispatch and flags.
package main

import "fmt"

type Kind int16

const (
	KindUnknown Kind = iota
	KindEndOfFile
	KindIdentifier
	KindNumericLiteral
	KindStringLiteral
	KindOpenParen
	KindCloseParen
	KindPlus
	KindPlusPlus
	KindEquals
	KindEqualsEquals
	KindIfKeyword
	KindReturnKeyword
	KindLetKeyword
)

type TokenFlags int32

const (
	TokenFlagsNone              TokenFlags = 0
	TokenFlagsPrecedingLineBreak TokenFlags = 1 << 0
	TokenFlagsUnterminated      TokenFlags = 1 << 1
)

var textToKeyword = map[string]Kind{
	"if":     KindIfKeyword,
	"return": KindReturnKeyword,
	"let":    KindLetKeyword,
}

type Scanner struct {
	text       string
	pos        int
	tokenStart int
	token      Kind
	tokenValue string
	tokenFlags TokenFlags
	errors     int
}

func NewScanner() *Scanner {
	return &Scanner{}
}

func (s *Scanner) SetText(text string) {
	s.text = text
	s.pos = 0
}

func (s *Scanner) char() byte {
	if s.pos < len(s.text) {
		return s.text[s.pos]
	}
	return 0
}

func isIdentifierStart(ch byte) bool {
	return ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' || ch == '_' || ch == '$'
}

func isDigit(ch byte) bool { return ch >= '0' && ch <= '9' }

func (s *Scanner) Scan() Kind {
	s.tokenFlags = TokenFlagsNone
	for {
		s.tokenStart = s.pos
		if s.pos >= len(s.text) {
			s.token = KindEndOfFile
			return s.token
		}
		ch := s.char()
		switch ch {
		case '\n':
			s.tokenFlags |= TokenFlagsPrecedingLineBreak
			s.pos++
			continue
		case ' ', '\t', '\r':
			s.pos++
			continue
		case '(':
			s.pos++
			s.token = KindOpenParen
		case ')':
			s.pos++
			s.token = KindCloseParen
		case '+':
			if s.pos+1 < len(s.text) && s.text[s.pos+1] == '+' {
				s.pos += 2
				s.token = KindPlusPlus
			} else {
				s.pos++
				s.token = KindPlus
			}
		case '=':
			if s.pos+1 < len(s.text) && s.text[s.pos+1] == '=' {
				s.pos += 2
				s.token = KindEqualsEquals
			} else {
				s.pos++
				s.token = KindEquals
			}
		case '"':
			s.token = s.scanString()
		default:
			if isIdentifierStart(ch) {
				s.token = s.scanIdentifier()
			} else if isDigit(ch) {
				s.token = s.scanNumber()
			} else {
				s.errors++
				s.pos++
				s.token = KindUnknown
			}
		}
		return s.token
	}
}

func (s *Scanner) scanIdentifier() Kind {
	start := s.pos
	for s.pos < len(s.text) && (isIdentifierStart(s.text[s.pos]) || isDigit(s.text[s.pos])) {
		s.pos++
	}
	s.tokenValue = s.text[start:s.pos]
	if kw, ok := textToKeyword[s.tokenValue]; ok {
		return kw
	}
	return KindIdentifier
}

func (s *Scanner) scanNumber() Kind {
	start := s.pos
	for s.pos < len(s.text) && isDigit(s.text[s.pos]) {
		s.pos++
	}
	s.tokenValue = s.text[start:s.pos]
	return KindNumericLiteral
}

func (s *Scanner) scanString() Kind {
	s.pos++
	start := s.pos
	for {
		if s.pos >= len(s.text) {
			s.tokenFlags |= TokenFlagsUnterminated
			s.errors++
			break
		}
		if s.text[s.pos] == '"' {
			break
		}
		s.pos++
	}
	s.tokenValue = s.text[start:s.pos]
	if s.pos < len(s.text) {
		s.pos++
	}
	return KindStringLiteral
}

func (s *Scanner) TokenText() string { return s.text[s.tokenStart:s.pos] }

func (s *Scanner) HasPrecedingLineBreak() bool {
	return s.tokenFlags&TokenFlagsPrecedingLineBreak != 0
}

func main() {
	s := NewScanner()
	s.SetText("let x = 42\nif (x == y1) return x++ + \"hi\" @ \"open")
	for {
		k := s.Scan()
		if k == KindEndOfFile {
			break
		}
		fmt.Println(int(k))
		fmt.Println(s.TokenText())
		if s.HasPrecedingLineBreak() {
			fmt.Println("(after a line break)")
		}
	}
	fmt.Println(s.errors)
}
