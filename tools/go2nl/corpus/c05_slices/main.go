package main

import "fmt"

type Item struct {
	id    int
	price int
}

func total(items []Item) int {
	sum := 0
	for _, it := range items {
		sum += it.price
	}
	return sum
}

func double(xs []int) {
	for i := range xs {
		xs[i] *= 2
	}
}

func main() {
	var xs []int
	for i := 1; i <= 5; i++ {
		xs = append(xs, i*i)
	}
	fmt.Println(len(xs))
	double(xs)
	for i, x := range xs {
		if i%2 == 0 {
			fmt.Println(x)
		}
	}
	var items []Item
	items = append(items, Item{id: 1, price: 30}, Item{id: 2, price: 12})
	fmt.Println(total(items))
	nums := []int{4, 5, 6}
	fmt.Println(nums[1] + len(nums))
}
