from __future__ import annotations

import json
from pathlib import Path


class SchemaLoader:
    """
    Loads and caches the JSON schema files describing the Command.plist key surface.

    Schemas live in schemas/:
      Root.json     — COMMAND_LIST + VERSION
      Command.json  — all top-level command keys
      <SUBDICT>.json — one per nested sub-dictionary (NIB_DIALOG, PROGRESS, …)
      _shared/*.json — reusable fragments referenced via "subschema"
    """

    def __init__(self, schemas_dir: str | Path):
        self._dir = Path(schemas_dir)
        self._cache: dict = {}

    def root_schema(self) -> dict | None:
        return self._load("Root")

    def command_schema(self) -> dict | None:
        return self._load("Command")

    def subdict_schema(self, name: str) -> dict | None:
        """Load a sub-dictionary schema by name (e.g. 'NIB_DIALOG' or '_shared/NavDialog')."""
        return self._load(name)

    def _load(self, name: str) -> dict | None:
        if name in self._cache:
            return self._cache[name]
        path = self._dir / f"{name}.json"
        if not path.exists():
            return None
        with open(path, encoding="utf-8") as f:
            schema = json.load(f)
        schema = self._resolve_extends(schema)
        self._cache[name] = schema
        return schema

    def _resolve_extends(self, schema: dict) -> dict:
        """
        Merge a parent schema's properties into a child that declares
        "extends": "<name>". Child entries win on key collisions. Used to keep
        the five near-identical file-navigation dialog schemas DRY.
        """
        parent_name = schema.get("extends")
        if not parent_name:
            return schema
        parent = self._load(parent_name) or {}
        merged = dict(parent)
        merged.update(schema)
        merged_props = dict(parent.get("properties", {}))
        merged_props.update(schema.get("properties", {}))
        merged["properties"] = merged_props
        merged.pop("extends", None)
        return merged
