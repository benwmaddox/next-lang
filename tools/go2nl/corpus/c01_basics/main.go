package main

import "fmt"

const limit = 10

func square(x int) int { return x * x }

func classify(n int) int {
	if n < 0 {
		return -1
	} else if n == 0 {
		return 0
	}
	return 1
}

func main() {
	total := 0
	for i := 0; i < limit; i++ {
		total += square(i)
	}
	fmt.Println(total)
	fmt.Println(classify(-5))
	fmt.Println(classify(0))
	fmt.Println(classify(7))
	x := 17
	x %= 5
	x *= 3
	x -= 1
	fmt.Println(x)
	fmt.Println(7/2 == 3 && -7/2 == -3)
	fmt.Println(-7 % 3)
	var flag bool
	fmt.Println(!flag)
}
