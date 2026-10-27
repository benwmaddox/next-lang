package main

import "fmt"

type Counter struct {
	name  string
	count int
	limit int
}

func NewCounter(name string, limit int) *Counter {
	return &Counter{name: name, limit: limit}
}

func (c *Counter) Inc() bool {
	if c.count >= c.limit {
		return false
	}
	c.count++
	return true
}

func (c *Counter) Remaining() int { return c.limit - c.count }

func (c Counter) Label() string { return c.name }

func fill(c *Counter) int {
	n := 0
	for c.Inc() {
		n++
	}
	return n
}

type Pair struct{ a, b int }

func swap(p Pair) Pair {
	p.a, p.b = p.b, p.a
	return p
}

func main() {
	c := NewCounter("clicks", 3)
	fmt.Println(c.Inc())
	fmt.Println(c.Remaining())
	fmt.Println(fill(c))
	fmt.Println(c.Inc())
	fmt.Println(c.Label())
	p := Pair{1, 2}
	q := swap(p)
	fmt.Println(p.a)
	fmt.Println(q.a)
}
