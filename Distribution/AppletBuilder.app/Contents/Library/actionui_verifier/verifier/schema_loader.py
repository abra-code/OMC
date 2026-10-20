from __future__ import annotations

import json
from pathlib import Path


class SchemaReferenceError(ValueError):
    """A schema's $ref names nothing, or refers back to itself."""


def expand_references(schema, name: str):
    """Expand `$ref` within one schema file.

    An object holding `"$ref": "name"` becomes the schema's `definitions[name]`,
    expanded too, merged with the object's other keys (which win). The
    `definitions` key itself is removed. Mirrors SchemaSet.expandReferences in
    the Swift verifier.
    """
    if not isinstance(schema, dict):
        return schema
    top = dict(schema)
    definitions = top.pop("definitions", None)
    if not isinstance(definitions, dict):
        definitions = {}

    def expand(value, trail: tuple[str, ...]):
        if isinstance(value, list):
            return [expand(item, trail) for item in value]
        if not isinstance(value, dict):
            return value
        if "$ref" not in value:
            return {key: expand(item, trail) for key, item in value.items()}
        reference = value["$ref"]
        if not isinstance(reference, str):
            raise SchemaReferenceError(f"schema {name}: $ref must name a definition")
        if reference in trail:
            raise SchemaReferenceError(f"schema {name}: $ref '{reference}' refers back to itself")
        definition = definitions.get(reference)
        if not isinstance(definition, dict):
            raise SchemaReferenceError(f"schema {name}: $ref '{reference}' names no object in 'definitions'")
        merged = expand(definition, trail + (reference,))
        for key, sibling in value.items():
            if key != "$ref":
                merged[key] = expand(sibling, trail)
        return merged

    return expand(top, ())


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
                    schema = expand_references(json.load(f), name)
                self._cache[name] = schema
                return schema
        return None
