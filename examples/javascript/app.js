// Fluoride JavaScript test file — comprehensive syntax coverage
// Covers: functions, generators, const/let/var, class, export, control flow, expressions

import { EventEmitter } from "events";

// --- Functions ---

function greet(name) {
  return "Hello, " + name;
}

function noArgs() {
  console.log("no args");
}

function multiArgs(a, b, c) {
  return a + b + c;
}

// --- Generator functions ---

function* counter() {
  let i = 0;
  while (true) {
    yield i++;
  }
}

function* fibonacci() {
  let a = 0,
    b = 1;
  while (true) {
    yield a;
    [a, b] = [b, a + b];
  }
}

// --- Variable declarations ---

const MAX_RETRIES = 3;

const PI = 3.14159;

let mutableCounter = 0;

let status = "idle";

var legacyFlag = true;

var oldConfig = { debug: false };

// Arrow function as const
const add = (a, b) => a + b;

// Arrow function single param
const double = (x) => x * 2;

// Regular function as const
const multiply = function(a, b) {
  return a * b;
};

// Generator as const
const range = function*(start, end) {
  for (let i = start; i < end; i++) {
    yield i;
  }
};

// --- Class with all member types ---

class Animal {
  // Field with initializer
  name = "unknown";

  // Static field
  static count = 0;

  // Constructor
  constructor(name) {
    this.name = name;
    Animal.count++;
  }

  // Instance method
  speak() {
    return this.name + " makes a sound";
  }

  // Method with params
  greet(other, loudly) {
    return loudly ? "HI " + other.name + "!" : "hi " + other.name;
  }

  // Getter
  get displayName() {
    return this.name.toUpperCase();
  }

  // Setter
  set displayName(value) {
    this.name = value.toLowerCase();
  }

  // Static method
  static create(name) {
    return new Animal(name);
  }

  // Static block
  static {
    console.log("Animal class loaded");
  }
}

// Inheritance
class Dog extends Animal {
  constructor(name, breed) {
    super(name);
    this.breed = breed;
  }

  speak() {
    return this.name + " barks";
  }
}

// --- Export statements ---

export function exportedFunction(x) {
  return x * 2;
}

export const EXPORTED_CONST = 42;

export let exportedLet = "mutable export";

export class ExportedClass {
  value = 0;

  getValue() {
    return this.value;
  }
}

export default {
  key: "value",
  version: 1,
};

// --- Control flow statements ---

if (mutableCounter > 0) {
  console.log("positive");
}

while (mutableCounter < 10) {
  mutableCounter++;
}

for (let i = 0; i < 10; i++) {
  console.log(i);
}

for (const key in { a: 1, b: 2 }) {
  console.log(key);
}

switch (mutableCounter) {
  case 0:
    break;
  case 1:
    break;
  default:
    break;
}

try {
  throw new Error("test");
} catch (e) {
  console.error(e);
}

do {
  mutableCounter++;
} while (mutableCounter < 5);

// --- Expression statements ---

console.log("expression statement at top level");

void 0;
