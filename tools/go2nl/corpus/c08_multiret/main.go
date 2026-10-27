package main

import "fmt"

func divmod(a, b int) (int, int) {
	return a / b, a % b
}

func parseDigit(c byte) (value int, ok bool) {
	if c < '0' || c > '9' {
		return
	}
	value = int(c - '0')
	ok = true
	return
}

func minmax(xs []int) (int, int) {
	lo, hi := xs[0], xs[0]
	for _, x := range xs {
		lo = min(lo, x)
		hi = max(hi, x)
	}
	return lo, hi
}

func main() {
	q, r := divmod(17, 5)
	fmt.Println(q)
	fmt.Println(r)
	v, ok := parseDigit('7')
	fmt.Println(v)
	fmt.Println(ok)
	_, ok = parseDigit('x')
	fmt.Println(ok)
	lo, hi := minmax([]int{5, -2, 9, 3})
	fmt.Println(lo)
	fmt.Println(hi)
}
