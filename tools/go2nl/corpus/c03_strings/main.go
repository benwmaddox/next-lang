package main

import (
	"fmt"
	"strings"
)

func countByte(s string, c byte) int {
	n := 0
	for i := 0; i < len(s); i++ {
		if s[i] == c {
			n++
		}
	}
	return n
}

func greet(name string) string {
	return "hello, " + name + "!"
}

func main() {
	s := "banana split"
	fmt.Println(len(s))
	fmt.Println(countByte(s, 'a'))
	fmt.Println(s[0:6])
	fmt.Println(s[7:])
	fmt.Println(greet("next-lang"))
	fmt.Println(strings.HasPrefix(s, "ban"))
	fmt.Println(strings.HasPrefix(s, "split"))
	fmt.Println(strings.IndexByte(s, 's'))
	acc := ""
	for i := 0; i < 3; i++ {
		acc += "ab"
	}
	fmt.Println(acc)
	fmt.Println("abc" < "abd")
	fmt.Println(s[1])
}
