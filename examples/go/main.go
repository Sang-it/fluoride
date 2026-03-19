package main

import (
	"fmt"
	"io"
	"sync"
)

// Fluoride Go test file — comprehensive syntax coverage
// Covers: func, method, type (struct/interface), var, const, short_var,
// go, defer, select

// --- Functions ---

func greet(name string) string {
	return "Hello, " + name
}

func noArgs() {
	fmt.Println("no args")
}

func multiReturn(x int) (int, error) {
	return x * 2, nil
}

func variadic(items ...string) int {
	return len(items)
}

// --- Methods ---

func multiArgs(a int, b string, c bool) {
}

func (a *Animal) Speak() string {
	return a.Name + " makes a sound"
}

func (a *Animal) Greet(other *Animal, loudly bool) string {
	if loudly {
		return "HI " + other.Name + "!"
	}
	return "hi " + other.Name
}

func (a Animal) Age() int {
	return a.AgeYears
}

// --- Struct types ---

type Animal struct {
	AgeYears int
	Name     string
	Active   bool
}

type Point struct {
	X float64
	Y float64
}

type Config struct {
	Debug   bool
	Timeout int
	Host    string
	Port    int
}

// --- Interface types ---

type Speaker interface {
	Speak() string
}

type ReadWriter interface {
	io.Reader
	io.Writer
	Flush() error
}

type Stringer interface {
	String() string
}

// --- Var declarations ---

var globalCounter int = 0

var (
	appName    string = "fluoride"
	appVersion string = "1.0.0"
	debug      bool   = false
)

// --- Const declarations ---

const Pi = 3.14159

const MaxRetries = 3

const (
	StatusIdle   = 0
	StatusActive = 1
	StatusClosed = 2
)

// --- Go statement ---

func startWorker() {
	go func() {
		fmt.Println("worker started")
	}()
}

// --- Defer statement ---

func cleanup() {
	defer fmt.Println("cleanup done")
	fmt.Println("doing work")
}

// --- Select statement ---

func waitForSignal(ch chan string, done chan bool) {
	select {
	case msg := <-ch:
		fmt.Println(msg)
	case <-done:
		fmt.Println("done")
	}
}

// --- Main ---

func main() {
	animal := Animal{Name: "Buddy", AgeYears: 3, Active: true}
	fmt.Println(animal.Speak())

	p := Point{X: 1.0, Y: 2.0}
	fmt.Println(p)

	startWorker()
	cleanup()

	var wg sync.WaitGroup
	_ = wg

	fmt.Println(greet("World"))
}
