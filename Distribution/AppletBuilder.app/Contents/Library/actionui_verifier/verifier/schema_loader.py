from __future__ import annotations

import json
from pathlib import Path


class SchemaLoader:
    """Loads element schemas from one or more directories.

    The primary directory holds the built-in ActionUI element schemas. Extra
    directories (typically shipped by optional add-on libraries via the
    verifier's --schema-dir option) extend the known type set without modifying
    the core schemas. On a name collision the primary directory wins, so an
    add-on cannot silently shadow a built-in element.
    """

    def __init__(self, schemas_dir: str | Path, extra_dirs: list[str | Path] | None = None):
        # Primary directory first so its schemas take precedence on collision.
        self._dirs: list[Path] = [Path(schemas_dir)]
        for d in (extra_dirs or []):
            self._dirs.append(Path(d))
        self._cache: dict = {}

    def view_schema(self) -> dict:
        return self._load("View")

    def element_schema(self, element_type: str) -> dict | None:
        return self._load(element_type)

    def known_types(self) -> set[str]:
        types: set[str] = set()
        for d in self._dirs:
            if d.is_dir():
                types |= {p.stem for p in d.glob("*.json") if p.stem != "View"}
        return types

    def _load(self, name: str) -> dict | None:
        if name in self._cache:
            return self._cache[name]
        for d in self._dirs:
            path = d / f"{name}.json"
            if path.exists():
                with open(path, encoding="utf-8") as f:
                    schema = json.load(f)
                self._cache[name] = schema
                return schema
        return None
