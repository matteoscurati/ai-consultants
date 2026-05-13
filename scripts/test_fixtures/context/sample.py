"""Sample Python module used by test_context_optimization.sh.

This file is deliberately verbose so AST extraction has something to strip:
the goal is for the optimized output to keep signatures + class shapes
and discard most of the docstrings and method bodies.
"""

import json
import os
import sys
from dataclasses import dataclass
from typing import Optional, List, Dict


@dataclass
class UserRecord:
    """A user record loaded from disk. Carries identity + permissions."""

    user_id: int
    name: str
    email: str
    roles: List[str]

    def is_admin(self) -> bool:
        """Return True if the user holds the admin role."""
        return "admin" in self.roles

    def display_name(self) -> str:
        """Render the human-readable display string for this record."""
        if self.is_admin():
            return f"{self.name} (admin)"
        return self.name


class UserStore:
    """In-memory store backed by a JSON file on disk."""

    def __init__(self, path: str):
        self.path = path
        self._records: Dict[int, UserRecord] = {}
        self._loaded = False

    def load(self) -> None:
        """Load records from the JSON file, replacing in-memory state."""
        if not os.path.exists(self.path):
            self._records = {}
            self._loaded = True
            return
        with open(self.path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        self._records = {
            int(k): UserRecord(**v)
            for k, v in data.items()
        }
        self._loaded = True

    def get(self, user_id: int) -> Optional[UserRecord]:
        """Look up a record by user_id. Returns None if missing."""
        if not self._loaded:
            self.load()
        return self._records.get(user_id)

    def add(self, record: UserRecord) -> None:
        """Insert or replace a record. Caller is responsible for save()."""
        self._records[record.user_id] = record

    def save(self) -> None:
        """Persist the in-memory state back to the JSON file."""
        serializable = {
            str(rec.user_id): rec.__dict__
            for rec in self._records.values()
        }
        with open(self.path, "w", encoding="utf-8") as fh:
            json.dump(serializable, fh, indent=2)


def main(argv: List[str]) -> int:
    """CLI entry point. Loads a store, prints all display names."""
    if len(argv) < 2:
        print("usage: sample.py <users.json>", file=sys.stderr)
        return 2
    store = UserStore(argv[1])
    store.load()
    for record in store._records.values():
        print(record.display_name())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
