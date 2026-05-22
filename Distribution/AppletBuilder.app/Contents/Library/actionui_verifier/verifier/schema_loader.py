from __future__ import annotations

import json
from pathlib import Path


class SchemaLoader:
    def __init__(self, schemas_dir: str | Path):
        self._dir = Path(schemas_dir)
        self._cache: dict = {}

    def view_schema(self) -> dict:
        return self._load("View")

    def element_schema(self, element_type: str) -> dict | None:
        return self._load(element_type)

    def known_types(self) -> set[str]:
        return {p.stem for p in self._dir.glob("*.json") if p.stem != "View"}

    def _load(self, name: str) -> dict | None:
        if name in self._cache:
            return self._cache[name]
        path = self._dir / f"{name}.json"
        if not path.exists():
            return None
        with open(path, encoding="utf-8") as f:
            schema = json.load(f)
        self._cache[name] = schema
        return schema
