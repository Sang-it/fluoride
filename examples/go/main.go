package main

import (
	"fmt"
	"strings"
	"sync"
)

const MaxWorkers = 10

var defaultTimeout = 30

type Task struct {
	ID      int
	Payload string
}

type Result struct {
	TaskID int
	Output string
	Err    error
}

type WorkerPool struct {
	mu      sync.Mutex
	workers int
	tasks   chan Task
	results chan Result
}

func NewWorkerPool(size int) *WorkerPool {
	return &WorkerPool{
		workers: size,
		tasks:   make(chan Task, size*2),
		results: make(chan Result, size*2),
	}
}

func (wp *WorkerPool) Submit(task Task) {
	wp.mu.Lock()
	defer wp.mu.Unlock()
	wp.tasks <- task
}

func (wp *WorkerPool) Start() {
	for i := 0; i < wp.workers; i++ {
		go wp.worker(i)
	}
}

func (wp *WorkerPool) worker(id int) {
	for task := range wp.tasks {
		output := processTask(task)
		wp.results <- Result{TaskID: task.ID, Output: output}
	}
}

func processTask(t Task) string {
	return strings.ToUpper(t.Payload)
}

func formatResult(r Result) string {
	if r.Err != nil {
		return fmt.Sprintf("Task %d: ERROR - %v", r.TaskID, r.Err)
	}
	return fmt.Sprintf("Task %d: %s", r.TaskID, r.Output)
}

func main() {
	pool := NewWorkerPool(MaxWorkers)
	pool.Start()

	pool.Submit(Task{ID: 1, Payload: "hello world"})

	result := <-pool.results
	fmt.Println(formatResult(result))
}
