"""
Validates a single ActionUI element node and its subtree recursively.
"""
from __future__ import annotations

from .errors import ValidationIssue
from .schema_loader import SchemaLoader
from .property_validator import validate_property
from .platform_filter import (
    ALL_PLATFORMS,
    split_platform_suffix,
    format_suffix_label,
    platform_matches,
    platforms_include,
)


# Top-level keys that are structural (never element-specific properties)
_STRUCTURAL_KEYS = {"type", "id", "properties"}

# Universal subview keys any element may carry (from View schema)
_UNIVERSAL_SUBVIEW_KEYS = {"overlay", "sheet", "popover", "fullScreenCover", "background", "backgroundView", "toolbar"}

# Annotation-only keys: intentional JSON "comments"; silently allowed everywhere
_ANNOTATION_KEYS = {"description", "note", "comment", "info"}


def _expand_suffixed_keys(
    obj: dict, path: str
) -> tuple[dict[str, list[tuple[str | None, object]]], list[ValidationIssue]]:
    """Group object keys by base, returning a `{base: [(suffix_or_None, value), ...]}`
    map plus warnings for keys with unknown platform suffixes.

    Keys with an unknown suffix are dropped from the result (matching runtime
    behavior). Their full original key is named in the warning so authors can
    locate the typo.
    """
    expanded: dict[str, list[tuple[str | None, object]]] = {}
    warnings: list[ValidationIssue] = []
    for key, value in obj.items():
        base, suffix = split_platform_suffix(key)
        if suffix is None:
            expanded.setdefault(base, []).append((None, value))
        elif suffix in ALL_PLATFORMS:
            expanded.setdefault(base, []).append((suffix, value))
        else:
            warnings.append(ValidationIssue(
                "warning", path,
                f"unknown platform suffix in key '{key}' (suffix='{suffix}'); "
                f"key will be dropped at runtime. Known platforms: "
                f"{', '.join(sorted(ALL_PLATFORMS))}"
            ))
    return expanded, warnings


class ElementValidator:
    def __init__(self, loader: SchemaLoader, target_platform: str | None = None):
        self._loader = loader
        self._known_types = loader.known_types()
        self._view_props = loader.view_schema().get("properties", {})
        # When set, validate as if the document were deployed to this single
        # platform: variants suffixed for other platforms are dropped (as they
        # are at runtime) and platform-restricted properties used here are
        # flagged. When None, validate as a cross-platform authoring document.
        self._target_platform = target_platform

    def validate(self, node: dict, path: str, seen_ids: set, _is_root: bool = True) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        sep = ": " if _is_root else "."

        expanded, suffix_warnings = _expand_suffixed_keys(node, path)
        issues += suffix_warnings

        # ── type ──────────────────────────────────────────────────────────────
        # `type` may appear unsuffixed or as `type:<platform>`. Each variant
        # must be a known element type. For schema selection, prefer the
        # unsuffixed variant, then any other valid one.
        type_variants = expanded.get("type", [])
        if not type_variants:
            issues.append(ValidationIssue("error", path, "missing or invalid 'type' field"))
            return issues

        # suffix -> validated type name (only types that exist as schemas)
        type_by_suffix: dict[str | None, str] = {}
        for suffix, value in type_variants:
            label = format_suffix_label("type", suffix)
            if not isinstance(value, str) or not value:
                issues.append(ValidationIssue(
                    "error", path, f"'{label}' must be a non-empty string"
                ))
                continue
            if value not in self._known_types:
                issues.append(ValidationIssue(
                    "error", path,
                    f"unknown element type '{value}' for '{label}'; no schema found"
                ))
                continue
            type_by_suffix[suffix] = value

        primary_type = type_by_suffix.get(None)
        if primary_type is None and type_by_suffix:
            primary_type = next(iter(type_by_suffix.values()))

        if primary_type is None:
            # No variant resolved to a known type — can't validate further.
            return issues

        # ── id ────────────────────────────────────────────────────────────────
        # id is always optional. When present it must be a positive non-zero
        # integer, unique in the tree. Multiple platform variants of the same
        # id value on a single node are de-duped (only counted once against
        # seen_ids) since at runtime only one variant survives the filter.
        seen_in_node: set = set()
        for suffix, el_id in expanded.get("id", []):
            label = format_suffix_label("id", suffix)
            if el_id is None:
                continue
            if isinstance(el_id, bool) or not isinstance(el_id, int):
                issues.append(ValidationIssue(
                    "error", path,
                    f"'{label}' must be an integer, got {type(el_id).__name__}"
                ))
            elif el_id == 0:
                issues.append(ValidationIssue(
                    "error", path, f"'{label}' 0 is invalid — must be a positive non-zero integer"
                ))
            elif el_id < 0:
                issues.append(ValidationIssue(
                    "error", path,
                    f"'{label}' {el_id} is negative — negative IDs are auto-generated; do not set them manually"
                ))
            elif el_id in seen_in_node:
                continue  # same id repeated across platform variants on this node — fine
            elif el_id in seen_ids:
                issues.append(ValidationIssue(
                    "error", path,
                    f"duplicate '{label}' {el_id} — IDs must be unique across the entire view tree"
                ))
            else:
                seen_ids.add(el_id)
                seen_in_node.add(el_id)

        # Collect schemas for every type variant so topLevelKeys / subviewKeys
        # accept keys that are valid under any platform's chosen type.
        type_schemas: list[dict] = []
        seen_type_names: set[str] = set()
        for t in type_by_suffix.values():
            if t in seen_type_names:
                continue
            seen_type_names.add(t)
            s = self._loader.element_schema(t)
            if s:
                type_schemas.append(s)

        # ── top-level keys ────────────────────────────────────────────────────
        allowed_top = set(_STRUCTURAL_KEYS) | set(_UNIVERSAL_SUBVIEW_KEYS)
        for s in type_schemas:
            allowed_top |= set(s.get("topLevelKeys", []))

        for base in expanded:
            if base not in allowed_top:
                issues.append(ValidationIssue(
                    "warning", path,
                    f"unexpected top-level key '{base}' for {primary_type}"
                ))

        primary_schema = self._loader.element_schema(primary_type)
        if primary_schema is None:
            return issues

        # ── properties ────────────────────────────────────────────────────────
        # Each `properties:X` variant pairs with the matching `type:X` schema.
        # `properties` (unsuffixed) pairs with `type` (unsuffixed) when present,
        # otherwise the primary type's schema.
        for suffix, props in expanded.get("properties", []):
            label_path = f"{path}{sep}{format_suffix_label('properties', suffix)}"
            if not isinstance(props, dict):
                issues.append(ValidationIssue("error", label_path, "must be an object"))
                continue
            paired_type = type_by_suffix.get(suffix) or primary_type
            paired_schema = self._loader.element_schema(paired_type)
            paired_own_props = paired_schema.get("ownProperties", {}) if paired_schema else {}
            issues += self._validate_properties(
                props, paired_own_props, paired_type, label_path
            )

        # ── recursive children / subviews ─────────────────────────────────────
        # Subview keys allowed: union of every type variant's topLevelKeys plus
        # the universal subview set.
        all_subview_keys: set[str] = set(_UNIVERSAL_SUBVIEW_KEYS)
        for s in type_schemas:
            all_subview_keys |= set(s.get("topLevelKeys", []))

        for child_key in all_subview_keys:
            for suffix, children in expanded.get(child_key, []):
                child_label = f"{path}{sep}{format_suffix_label(child_key, suffix)}"
                issues += self._validate_subview_value(children, child_label, seen_ids)

        return issues

    def _validate_subview_value(self, val, child_path: str, seen_ids: set) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        if isinstance(val, list):
            for i, child in enumerate(val):
                ipath = f"{child_path}[{i}]"
                if isinstance(child, dict):
                    issues += self.validate(child, ipath, seen_ids, _is_root=False)
                elif isinstance(child, list):
                    # 2D array (e.g., Grid rows)
                    for j, cell in enumerate(child):
                        cpath = f"{ipath}[{j}]"
                        if isinstance(cell, dict):
                            issues += self.validate(cell, cpath, seen_ids, _is_root=False)
                        else:
                            issues.append(ValidationIssue("error", cpath, "cell must be an object"))
                else:
                    issues.append(ValidationIssue("error", ipath, "child must be an object"))
        elif isinstance(val, dict):
            issues += self.validate(val, child_path, seen_ids, _is_root=False)
        return issues

    def _validate_properties(
        self,
        properties: dict,
        own_props: dict,
        element_type: str,
        path: str,
    ) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        expanded, suffix_warnings = _expand_suffixed_keys(properties, path)
        issues += suffix_warnings

        for base, variants in expanded.items():
            if base in own_props:
                spec = own_props[base]
            elif base in self._view_props:
                spec = self._view_props[base]
            else:
                spec = None

            for suffix, value in variants:
                label = format_suffix_label(base, suffix)

                # In deployment mode, a variant suffixed for a different platform
                # is dropped at runtime — skip it entirely (no schema or typo check).
                if (self._target_platform is not None and suffix is not None
                        and suffix in ALL_PLATFORMS
                        and not platform_matches(suffix, self._target_platform)):
                    continue

                if spec is not None:
                    issues += self._check_property_platform(base, suffix, spec, label, path)
                    issues += validate_property(label, value, spec, path)
                elif base in _ANNOTATION_KEYS:
                    issues.append(ValidationIssue(
                        "info",
                        f"{path}.{label}",
                        f"'{label}' is an annotation key used as a JSON comment; ignored at runtime"
                    ))
                else:
                    issues.append(ValidationIssue(
                        "warning",
                        f"{path}.{label}",
                        f"'{label}' is not a known property for {element_type} or View base; possible typo"
                    ))

        # Required own properties — satisfied if ANY variant (suffixed or not) is present.
        for key, spec in own_props.items():
            if spec.get("required") and key not in expanded:
                issues.append(ValidationIssue(
                    "error", f"{path}.{key}",
                    f"required property '{key}' is missing"
                ))

        return issues

    def _check_property_platform(
        self, base: str, suffix: str | None, spec: dict, label: str, path: str
    ) -> list[ValidationIssue]:
        """Warn when a platform-restricted property is used outside its platforms.

        A property whose schema has no `platforms` key is common (valid
        everywhere) and never warns. For a restricted property:

          - Deployment mode (target set): the variant is active for the target
            (base key, or a suffix matching it). Warn if the property isn't
            available there.
          - Cross-platform mode (no target): warn if used as a base key (it will
            be silently ignored on platforms that lack it — suffix it instead),
            or if suffixed for a platform the property doesn't support.
        """
        plats = spec.get("platforms")
        if plats is None:
            return []

        if self._target_platform is not None:
            if not platforms_include(plats, self._target_platform):
                return [ValidationIssue(
                    "warning", f"{path}.{label}",
                    f"'{label}': property '{base}' is not available on target "
                    f"platform '{self._target_platform}' (available on: {plats})"
                )]
            return []

        if suffix is None:
            return [ValidationIssue(
                "warning", f"{path}.{label}",
                f"'{base}' is platform-specific (available on: {plats}); in a "
                f"cross-platform document suffix it (e.g. '{base}:{plats[0]}') so it "
                f"is applied only where supported"
            )]
        if suffix in ALL_PLATFORMS and not platforms_include(plats, suffix):
            return [ValidationIssue(
                "warning", f"{path}.{label}",
                f"'{label}': property '{base}' is not available on '{suffix}' "
                f"(available on: {plats})"
            )]
        return []
