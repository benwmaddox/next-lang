package main

import "fmt"

func at(xs []int, i int) int { return xs[i] }

func main() {
	xs := []int{1, 2, 3}
	fmt.Println(at(xs, 1))
	fmt.Println(at(xs, 5))
}
