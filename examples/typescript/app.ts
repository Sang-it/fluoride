// @ts-nocheck
// Fluoride TypeScript test file — comprehensive syntax coverage
// Covers: functions, const/let/var, class, abstract class, interface, type,
// enum, export, declare, namespace, control flow, expression statements

import { readFile } from "fs/promises";

// --- Functions ---

function greet(name: string): string {
  return `Hello, ${name}`;
}

function noArgs(): void {
  console.log("no args");
}

function multiArgs(a: number, b: string, c: boolean): void {}

// --- Variable declarations ---

const MAX_RETRIES = 3;

let counter = 0;

var legacyFlag = true;

// Arrow function as const
const add = (a: number, b: number): number => a + b;

// Arrow function single param
const double = (x: number) => x * 2;

// --- Class with all member types ---

class Animal {
  // Property with initializer
  name: string = "";

  // Static property
  static count = 0;

  // Constructor
  constructor(name: string) {
    this.name = name;
    Animal.count++;
  }

  // Instance method
  speak(): string {
    return `${this.name} makes a sound`;
  }

  // Method with params
  greet(other: Animal, loudly: boolean): string {
    return loudly ? `HI ${other.name}!` : `hi ${other.name}`;
  }

  // Getter-like method
  getName(): string {
    return this.name;
  }

  // Static block
  static {
    console.log("Animal class loaded");
  }
}

// --- Abstract class ---

abstract class Shape {
  abstract area(): number;

  abstract perimeter(): number;

  color: string = "red";

  describe(): string {
    return `A ${this.color} shape with area ${this.area()}`;
  }
}

// --- Interface with all signature types ---

interface Serializable {
  // Property signature
  id: string;

  // Optional property
  version?: number;

  // Method signature
  serialize(): string;

  // Method with params
  deserialize(data: string, strict: boolean): void;
}

interface Callable {
  (x: number, y: number): number;
}

interface Constructable {
  // Construct signature
  new (name: string): Animal;
}

interface Indexable {
  // Index signature
  [key: string]: unknown;
}

// --- Type aliases ---

type ID = string | number;

type Callback = (error: Error | null, result: string) => void;

type Point = { x: number; y: number };

type ConnectionState = "idle" | "active" | "closed";

// --- Enums ---

enum Direction {
  Up = 0,
  Down,
  Left,
  Right,
}

enum LogLevel {
  Debug = "DEBUG",
  Info = "INFO",
  Warn = "WARN",
  Error = "ERROR",
}

// --- Export statements (all variations) ---

export function exportedFunction(x: number): number {
  return x * 2;
}

export const EXPORTED_CONST = 42;

export let exportedLet = "mutable";

export class ExportedClass {
  value: number = 0;

  getValue(): number {
    return this.value;
  }
}

export interface ExportedInterface {
  name: string;
  process(): void;
}

export type ExportedType = string | number;

export enum ExportedEnum {
  A,
  B,
  C,
}

export abstract class ExportedAbstractClass {
  abstract run(): void;
}

export default {
  key: "value",
  version: 1,
};

// --- Declare statements (ambient declarations) ---

declare function declaredFunction(x: number): string;

declare const DECLARED_CONST: number;

declare let declaredLet: string;

declare class DeclaredClass {
  name: string;
  greet(): void;
}

declare abstract class DeclaredAbstractClass {
  abstract process(): void;
}

declare interface DeclaredInterface {
  id: number;
  getName(): string;
}

declare type DeclaredType = string;

declare enum DeclaredEnum {
  X,
  Y,
}

declare namespace DeclaredNamespace {
  function innerFn(): void;
  const innerConst: number;
}

// --- Namespaces ---

namespace MyLib {
  export function create(): void {}

  export const VERSION = "1.0.0";

  export class Builder {
    steps: string[] = [];

    addStep(name: string): void {
      this.steps.push(name);
    }

    build(): string {
      return this.steps.join(" -> ");
    }
  }

  export interface Config {
    debug: boolean;
    timeout: number;
  }

  export type Mode = "fast" | "safe";

  export enum Priority {
    Low,
    Medium,
    High,
  }

  // Nested namespace
  export namespace Utils {
    export function format(s: string): string {
      return s.trim();
    }
  }
}

namespace Nested {
  export class Outer {
    method(): void {}
  }

  export namespace Inner {
    export class Deep {
      value: number = 0;

      get(): number {
        return this.value;
      }
    }
  }
}

// --- Control flow statements ---

if (counter > 0) {
  console.log("positive");
}

while (counter < 10) {
  counter++;
}

for (let i = 0; i < 10; i++) {
  console.log(i);
}

for (const key in { a: 1, b: 2 }) {
  console.log(key);
}

switch (counter) {
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
  counter++;
} while (counter < 5);

// --- Expression statement ---

console.log("expression statement at top level");
