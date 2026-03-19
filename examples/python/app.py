# Fluoride Python test file — comprehensive syntax coverage
# Covers: def, async def, class, decorated, assignment, augmented assignment,
# type alias, expression, control flow, with, assert

from dataclasses import dataclass
from typing import Optional
import asyncio

# --- Functions ---


def greet(name: str) -> str:
    return f"Hello, {name}"


def no_args() -> None:
    print("no args")


def multi_args(a: int, b: str, c: bool) -> None:
    pass


def default_args(x: int = 0, y: int = 0) -> int:
    return x + y


# --- Async functions ---


async def fetch(url: str) -> str:
    await asyncio.sleep(1)
    return f"response from {url}"


async def process_batch(items: list[str]) -> list[str]:
    results = []
    for item in items:
        results.append(await fetch(item))
    return results


# --- Class with all member types ---


class Animal:
    # Class variable
    species = "Unknown"

    # Another class variable
    count = 0

    def __init__(self, name: str, age: int) -> None:
        self.name = name
        self.age = age
        Animal.count += 1

    def speak(self) -> str:
        return f"{self.name} makes a sound"

    def greet(self, other: "Animal", loudly: bool = False) -> str:
        if loudly:
            return f"HI {other.name}!"
        return f"hi {other.name}"

    async def fetch_data(self) -> str:
        await asyncio.sleep(0.1)
        return "data"

    @property
    def display_name(self) -> str:
        return self.name.upper()

    @staticmethod
    def create(name: str) -> "Animal":
        return Animal(name, 0)

    @classmethod
    def from_dict(cls, data: dict) -> "Animal":
        return cls(data["name"], data.get("age", 0))


# Inheritance
class Dog(Animal):
    breed: str = "mixed"

    def __init__(self, name: str, age: int, breed: str) -> None:
        super().__init__(name, age)
        self.breed = breed

    def speak(self) -> str:
        return f"{self.name} barks"

    def fetch(self, item: str) -> str:
        return f"{self.name} fetches {item}"


# --- Decorated class ---


@dataclass
class Point:
    x: float
    y: float

    def distance(self, other: "Point") -> float:
        return ((self.x - other.x) ** 2 + (self.y - other.y) ** 2) ** 0.5


@dataclass(frozen=True)
class Config:
    debug: bool = False

    timeout: int = 30

    host: str = "localhost"


# --- Assignments ---

MAX_RETRIES = 3

PI = 3.14159

DEFAULT_CONFIG = {"debug": False, "timeout": 30}

# --- Augmented assignments ---

counter = 0
counter += 1


total = 100

total -= 10

# --- Type alias (Python 3.12) ---

type Matrix = list[list[float]]

type Vector = list[float]

type Callback = callable[[str], None]

# --- Expression statements ---

print("expression statement at top level")

# --- Control flow ---

if counter > 0:
    print("positive")

while counter < 10:
    counter += 1

for i in range(10):
    print(i)

try:
    raise ValueError("test")
except ValueError as e:
    print(e)
finally:
    print("done")

with open("/dev/null") as f:
    pass

# --- Assert ---

assert MAX_RETRIES == 3

assert counter > 0, "counter must be positive"
