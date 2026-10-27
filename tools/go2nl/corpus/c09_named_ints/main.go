package main

import "fmt"

type Kind int16

const (
	KindUnknown Kind = iota
	KindIdentifier
	KindNumber
	KindPlus
	KindCount
)

type Flags uint32

const (
	FlagNone    Flags = 0
	FlagNewline Flags = 1 << 0
	FlagEscape  Flags = 1 << 1
	FlagOctal   Flags = 1 << 2
)

func isOperator(k Kind) bool { return k >= KindPlus && k < KindCount }

func main() {
	k := KindNumber
	fmt.Println(int(k))
	fmt.Println(isOperator(k))
	fmt.Println(isOperator(KindPlus))
	f := FlagNewline | FlagOctal
	fmt.Println(f&FlagEscape != 0)
	fmt.Println(f&FlagOctal != 0)
	f &^= FlagNewline
	fmt.Println(int(f))
	var ch int32 = 'A'
	b := byte(ch + 1)
	fmt.Println(b)
	fmt.Println(int(b) << 3)
	fmt.Println(1000 >> 2)
	x := 0x5A
	fmt.Println(x ^ 0xFF)
	fmt.Println(^x)
}
