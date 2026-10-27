// Standard-library shims checked against Go itself, edge cases included, and
// the control flow the scanner uses: fallthrough, labeled break and continue,
// and break and continue together inside a switch in a loop.
package main

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

func decodeAll(s string) {
	for len(s) > 0 {
		r, size := utf8.DecodeRuneInString(s)
		fmt.Println(int(r))
		fmt.Println(size)
		s = s[size:]
	}
}

func runes(s string) int {
	sum := 0
	for i, r := range s {
		sum += i*1000 + int(r)
	}
	return sum
}

func classify(c byte) int {
	n := 0
	switch {
	case c == 'a':
		n += 1
		fallthrough
	case c == 'b':
		n += 10
	case c == 'c':
		n += 100
		fallthrough
	default:
		n += 1000
	}
	return n
}

func scanWords(s string) int {
	words := 0
	i := 0
	for i < len(s) {
		switch s[i] {
		case ' ':
			i++
			continue
		case '.':
			break
		default:
			words++
			for i < len(s) && s[i] != ' ' && s[i] != '.' {
				i++
			}
			continue
		}
		i++
	}
	return words
}

func findPair(xs []int, target int) int {
	found := -1
outer:
	for i := 0; i < len(xs); i++ {
		for j := i + 1; j < len(xs); j++ {
			if xs[i]+xs[j] == target {
				found = i*10 + j
				break outer
			}
			if xs[j] < 0 {
				continue outer
			}
		}
	}
	return found
}

func parse(s string, base int) {
	v, err := strconv.ParseInt(s, base, 32)
	fmt.Println(v)
	fmt.Println(err == nil)
	fmt.Println(errors.Is(err, strconv.ErrRange))
}

func main() {
	decodeAll("aé€😀")
	decodeAll("\xff\xc3\x28\xe2\x82\xf0\x9f\x98")
	decodeAll("\xed\xa0\x80\xc0\xaf")
	r, size := utf8.DecodeLastRuneInString("x€")
	fmt.Println(int(r))
	fmt.Println(size)
	r, size = utf8.DecodeLastRuneInString("x\x82\xac")
	fmt.Println(int(r))
	fmt.Println(size)
	fmt.Println(runes("a€\xffb"))
	fmt.Println(string(rune(0x20AC)))
	fmt.Println(len(string(rune(-1))))
	fmt.Println(len(string(rune(0xD800))))
	fmt.Println(utf8.RuneLen(0x10FFFF))
	fmt.Println(utf16.IsSurrogate(0xDBFF))
	hi, lo := utf16.EncodeRune(0x1F600)
	fmt.Println(int(hi))
	fmt.Println(int(lo))
	fmt.Println(int(utf16.DecodeRune(hi, lo)))

	parse("777", 8)
	parse("-80000000", 16)
	parse("7fffffff", 16)
	parse("80000000", 16)
	parse("12x", 10)
	parse("", 10)
	fmt.Println(strconv.FormatInt(-255, 16))
	fmt.Println(strconv.FormatInt(8, 2))
	fmt.Println(fmt.Sprintf("\\x%02x and %d%%", 10, -3))
	fmt.Println(fmt.Sprintf("[%4d|%s|%X]", 42, "ok", 255))

	var b strings.Builder
	b.WriteString("ab")
	b.WriteByte('c')
	b.WriteRune(0x00E9)
	fmt.Println(b.String())
	fmt.Println(b.Len())
	fmt.Println(strings.TrimSuffix("file.go", ".go"))

	fmt.Println(classify('a'))
	fmt.Println(classify('b'))
	fmt.Println(classify('c'))
	fmt.Println(classify('z'))
	fmt.Println(scanWords("  one two. three  four."))
	fmt.Println(findPair([]int{3, 8, -1, 5, 9}, 14))
	fmt.Println(findPair([]int{1, 2}, 99))

	m := make(map[int]int, 8)
	m[1] = 2
	m[3] = 4
	clear(m)
	fmt.Println(len(m))
	xs := make([]int, 0, 4)
	xs = append(xs, 7)
	fmt.Println(len(xs))
}
