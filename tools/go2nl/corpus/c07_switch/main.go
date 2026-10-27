package main

import "fmt"

func kind(c byte) int {
	switch c {
	case ' ', '\t':
		return 1
	case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
		return 2
	default:
		return 0
	case '+', '-':
		return 3
	}
}

func sign(n int) int {
	switch {
	case n < 0:
		return -1
	case n > 0:
		return 1
	}
	return 0
}

func firstDigit(s string) int {
	for i := 0; i < len(s); i++ {
		switch kind(s[i]) {
		case 2:
			return i
		case 1:
			continue
		}
	}
	return -1
}

func countUntilPlus(s string) int {
	n := 0
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '+':
			break
		default:
			n++
		}
	}
	return n
}

func main() {
	fmt.Println(kind(' '))
	fmt.Println(kind('7'))
	fmt.Println(kind('-'))
	fmt.Println(kind('x'))
	fmt.Println(sign(-3))
	fmt.Println(sign(0))
	fmt.Println(firstDigit("  ab4c"))
	fmt.Println(countUntilPlus("a+b+c"))
}
