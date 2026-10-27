package main

import "fmt"

var keywords = map[string]int{
	"if":     1,
	"else":   2,
	"return": 3,
}

func lookup(word string) int {
	if k, ok := keywords[word]; ok {
		return k
	}
	return 0
}

func main() {
	fmt.Println(lookup("else"))
	fmt.Println(lookup("while"))
	counts := map[int]int{}
	for i := 0; i < 20; i++ {
		counts[i%3]++
	}
	fmt.Println(counts[0])
	fmt.Println(counts[2])
	fmt.Println(len(counts))
	delete(counts, 1)
	fmt.Println(len(counts))
	_, ok := counts[1]
	fmt.Println(ok)
	fmt.Println(keywords["return"])
}
