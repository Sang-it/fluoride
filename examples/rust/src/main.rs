// Fluoride Rust test file — comprehensive syntax coverage
// Covers: fn, pub fn, struct, enum, union, impl, trait, type, const, static,
// mod, macro_rules!, macro invocation, extern, expression

use std::fmt;
use std::sync::atomic::{AtomicU32, Ordering};

// --- Functions ---

fn greet(name: &str) -> String {
    format!("Hello, {}", name)
}

fn no_args() {
    println!("no args");
}

fn multi_args(a: i32, b: &str, c: bool) -> String {
    format!("{} {} {}", a, b, c)
}

pub fn public_greet(name: &str) -> String {
    greet(name)
}

pub fn public_no_args() {
    println!("public no args");
}

// --- Structs ---

struct Point {
    x: f64,
    y: f64,
}

struct Color(u8, u8, u8);

pub struct PubPoint {
    pub x: f64,
    pub y: f64,
}

pub struct Config {
    pub debug: bool,
    pub timeout: u32,
    pub host: String,
}

// --- Enums ---

enum Direction {
    Up,
    Down,
    Left,
    Right,
}

enum Shape {
    Circle(f64),
    Rectangle(f64, f64),
    Triangle { base: f64, height: f64 },
}

pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

// --- Union ---

union IntOrFloat {
    i: i32,
    f: f32,
}

// --- Impl blocks ---

impl Point {
    fn new(x: f64, y: f64) -> Self {
        Point { x, y }
    }

    fn distance(&self, other: &Point) -> f64 {
        ((self.x - other.x).powi(2) + (self.y - other.y).powi(2)).sqrt()
    }

    fn translate(&mut self, dx: f64, dy: f64) {
        self.x += dx;
        self.y += dy;
    }

    const ORIGIN: Point = Point { x: 0.0, y: 0.0 };

    type Coord = f64;
}

impl fmt::Display for Point {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "({}, {})", self.x, self.y)
    }
}

impl Shape {
    fn area(&self) -> f64 {
        match self {
            Shape::Circle(r) => std::f64::consts::PI * r * r,
            Shape::Rectangle(w, h) => w * h,
            Shape::Triangle { base, height } => 0.5 * base * height,
        }
    }

    fn describe(&self) -> &str {
        match self {
            Shape::Circle(_) => "circle",
            Shape::Rectangle(_, _) => "rectangle",
            Shape::Triangle { .. } => "triangle",
        }
    }
}

// --- Traits ---

trait Drawable {
    fn draw(&self);

    fn area(&self) -> f64;

    fn color(&self) -> &str {
        "black"
    }
}

pub trait Serializable {
    fn serialize(&self) -> String;

    fn deserialize(data: &str) -> Self;
}

// --- Type aliases ---

type Result<T> = std::result::Result<T, String>;

pub type PubResult = Result<()>;

// --- Constants ---

const MAX_SIZE: u32 = 100;

const DEFAULT_NAME: &str = "unknown";

pub const PUB_MAX: u32 = 200;

// --- Statics ---

static COUNTER: AtomicU32 = AtomicU32::new(0);

pub static PUB_COUNTER: AtomicU32 = AtomicU32::new(0);

// --- Modules ---

mod utils {
    pub fn helper() -> &'static str {
        "help"
    }

    pub struct InnerStruct {
        pub x: i32,
        pub y: i32,
    }

    pub enum InnerEnum {
        A,
        B,
    }

    pub const INNER_CONST: i32 = 42;
}

pub mod pub_utils {
    pub fn public_helper() -> bool {
        true
    }

    pub mod nested {
        pub fn deep_helper() {}
    }
}

// --- Macros ---

macro_rules! say_hello {
    () => {
        println!("Hello!");
    };
    ($name:expr) => {
        println!("Hello, {}!", $name);
    };
}

macro_rules! create_map {
    ($($key:expr => $val:expr),*) => {{
        let mut map = std::collections::HashMap::new();
        $(map.insert($key, $val);)*
        map
    }};
}

// --- Extern ---

extern "C" {
    fn abs(input: i32) -> i32;
}

// --- Main ---

fn main() {
    let p = Point::new(1.0, 2.0);
    println!("{}", p);

    let s = Shape::Circle(5.0);
    println!("{} area: {}", s.describe(), s.area());

    say_hello!();
    say_hello!("World");

    let map = create_map!("a" => 1, "b" => 2);
    println!("{:?}", map);

    println!("{}", greet("Rust"));
    COUNTER.fetch_add(1, Ordering::SeqCst);
}
