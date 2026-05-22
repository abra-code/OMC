"""
Validates a single ActionUI element node and its subtree recursively.
"""
from __future__ import annotations

from .errors import ValidationIssue
from .schema_loader import SchemaLoader
from .property_validator import validate_property


# Top-level keys that are structural (never element-specific properties)
_STRUCTURAL_KEYS = {"type", "id", "properties"}

# Universal subview keys any element may carry (from View schema)
_UNIVERSAL_SUBVIEW_KEYS = {"overlay", "sheet", "popover", "fullScreenCover", "background", "backgroundView", "toolbar"}

# Annotation-only keys: intentional JSON "comments"; silently allowed everywhere
_ANNOTATION_KEYS = {"description", "note", "comment", "info"}


class ElementValidator:
    def __init__(self, loader: SchemaLoader):
        self._loader = loader
        self._known_types = loader.known_types()
        self._view_props = loader.view_schema().get("properties", {})

    def validate(self, node: dict, path: str, seen_ids: set, _is_root: bool = True) -> list[ValidationIssue]:
        issues = []
        sep = ": " if _is_root else "."

        # ── type ──────────────────────────────────────────────────────────────
        element_type = node.get("type")
        if not isinstance(element_type, str) or not element_type:
            issues.append(ValidationIssue("error", path, "missing or invalid 'type' field"))
            return issues  # can't continue without a type

        if element_type not in self._known_types:
            issues.append(ValidationIssue(
                "error", path,
                f"unknown element type '{element_type}'; no schema found"
            ))
            # Continue to check id and children even for unknown types

        schema = self._loader.element_schema(element_type)

        # ── id ────────────────────────────────────────────────────────────────
        el_id = node.get("id")
        # id is always optional — a negative id is auto-generated when absent.
        # When explicitly set it must be a positive non-zero integer, unique in the tree.
        if el_id is not None:
            if isinstance(el_id, bool) or not isinstance(el_id, int):
                issues.append(ValidationIssue("error", path, f"'id' must be an integer, got {type(el_id).__name__}"))
            elif el_id == 0:
                issues.append(ValidationIssue("error", path, "'id' 0 is invalid — must be a positive non-zero integer"))
            elif el_id < 0:
                issues.append(ValidationIssue("error", path, f"'id' {el_id} is negative — negative IDs are auto-generated; do not set them manually"))
            elif el_id in seen_ids:
                issues.append(ValidationIssue("error", path, f"duplicate 'id' {el_id} — IDs must be unique across the entire view tree"))
            else:
                seen_ids.add(el_id)

        # ── top-level keys ────────────────────────────────────────────────────
        allowed_top = _STRUCTURAL_KEYS | _UNIVERSAL_SUBVIEW_KEYS
        element_top_keys: set = set()
        if schema:
            element_top_keys = set(schema.get("topLevelKeys", []))
            allowed_top |= element_top_keys

        for key in node:
            if key not in allowed_top:
                issues.append(ValidationIssue(
                    "warning", path,
                    f"unexpected top-level key '{key}' for {element_type}"
                ))

        if schema is None:
            # Unknown type — skip property and children validation
            return issues

        # ── properties ────────────────────────────────────────────────────────
        properties = node.get("properties", {})
        if not isinstance(properties, dict):
            issues.append(ValidationIssue("error", path, "'properties' must be an object"))
        else:
            own_props = schema.get("ownProperties", {})
            issues += self._validate_properties(
                properties, own_props, element_type, f"{path}{sep}properties"
            )

        # ── recursive children / subviews ─────────────────────────────────────
        child_path_info = self._collect_children(node, schema)
        for child_key, children in child_path_info:
            if isinstance(children, list):
                for i, child in enumerate(children):
                    child_path = f"{path}{sep}{child_key}[{i}]"
                    if isinstance(child, dict):
                        issues += self.validate(child, child_path, seen_ids, _is_root=False)
                    elif isinstance(child, list):
                        # 2D array (e.g. Grid rows): each inner list is a row of cell elements
                        for j, cell in enumerate(child):
                            cell_path = f"{child_path}[{j}]"
                            if isinstance(cell, dict):
                                issues += self.validate(cell, cell_path, seen_ids, _is_root=False)
                            else:
                                issues.append(ValidationIssue("error", cell_path, "cell must be an object"))
                    else:
                        issues.append(ValidationIssue("error", child_path, "child must be an object"))
            elif isinstance(children, dict):
                issues += self.validate(children, f"{path}{sep}{child_key}", seen_ids, _is_root=False)

        return issues

    def _validate_properties(
        self,
        properties: dict,
        own_props: dict,
        element_type: str,
        path: str,
    ) -> list[ValidationIssue]:
        issues = []
        all_known = set(own_props) | set(self._view_props)

        for key, value in properties.items():
            if key in own_props:
                issues += validate_property(key, value, own_props[key], path)
            elif key in self._view_props:
                issues += validate_property(key, value, self._view_props[key], path)
            elif key in _ANNOTATION_KEYS:
                issues.append(ValidationIssue(
                    "info",
                    f"{path}.{key}",
                    f"'{key}' is an annotation key used as a JSON comment; ignored at runtime"
                ))
            else:
                issues.append(ValidationIssue(
                    "warning",
                    f"{path}.{key}",
                    f"'{key}' is not a known property for {element_type} or View base; possible typo"
                ))

        # Check required own properties
        for key, spec in own_props.items():
            if spec.get("required") and key not in properties:
                issues.append(ValidationIssue(
                    "error", f"{path}.{key}",
                    f"required property '{key}' is missing"
                ))

        return issues

    def _collect_children(self, node: dict, schema: dict) -> list[tuple[str, object]]:
        """
        Returns (path, value) pairs for all child elements that should be recursively validated.
        Covers declared topLevelKeys and universal subview keys present in the node.
        """
        result = []
        base_path = f"{node.get('type', '?')}(id={node.get('id', '-')})"

        all_subview_keys = set(schema.get("topLevelKeys", [])) | _UNIVERSAL_SUBVIEW_KEYS
        for key in all_subview_keys:
            val = node.get(key)
            if val is not None:
                result.append((f"{key}", val))

        return result
