from dataclasses import dataclass
from typing import Optional
import asyncio
import json

MAX_RETRIES = 3


TIMEOUT_SECONDS = 30.0


@dataclass
class User:
    name: str
    age: Optional[int] = None
    email: str


class UserRepository:
    def __init__(self):
        self._users: list[User] = []

    def all(self) -> list[User]:
        return list(self._users)

    def find_by_email(self, email: str) -> Optional[User]:
        return next((u for u in self._users if u.email == email), None)

    def add(self, user: User) -> None:
        self._users.append(user)


async def fetch_user(user_id: int) -> dict:
    await asyncio.sleep(0.1)
    return {"id": user_id, "name": f"User {user_id}"}


def validate_email(email: str) -> bool:
    return "@" in email and "." in email.split("@")[-1]


def serialize_user(user: User) -> str:
    return json.dumps({"name": user.name, "email": user.email, "age": user.age})


def parse_config(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def main() -> None:
    repo = UserRepository()
    user = User(name="Alice", email="alice@example.com", age=30)
    repo.add(user)
    print(serialize_user(user))


if __name__ == "__main__":
    main()
