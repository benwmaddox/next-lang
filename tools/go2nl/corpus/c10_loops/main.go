package main

import "fmt"

func sumOdd(n int) int {
	s := 0
	for i := 0; i < n; i++ {
		if i%2 == 0 {
			continue
		}
		s += i
	}
	return s
}

func collatz(n int) int {
	steps := 0
	for n != 1 {
		if n%2 == 0 {
			n /= 2
		} else {
			n = 3*n + 1
		}
		steps++
	}
	return steps
}

func firstSquareOver(limit int) int {
	i := 0
	for {
		if i*i > limit {
			return i
		}
		i++
	}
}

func skipEveryThird(n int) int {
	count := 0
	for i := 0; i < n; i += 1 {
		if i%3 == 2 {
			continue
		}
		count++
	}
	return count
}

func main() {
	fmt.Println(sumOdd(10))
	fmt.Println(collatz(27))
	fmt.Println(firstSquareOver(50))
	fmt.Println(skipEveryThird(10))
	for i := range 3 {
		fmt.Println(i)
	}
}
