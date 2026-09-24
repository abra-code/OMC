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
    select_variant,
)


# Top-level keys that are structural (never element-specific properties).
_STRUCTURAL_KEYS = {"type", "id", "properties"}

# Universal subview keys any element may carry (from View schema). contextMenu (the
# menu's action-item array) and contextMenuPreview (the optional preview view) mirror
# SwiftUI's `.contextMenu(menuItems:preview:)` two-builder shape; swipeActions (the
# leading/trailing swipe action-Button array) mirrors `.swipeActions(edge:allowsFullSwipe:)`;
# safeAreaInset (a single view placed in the safe area on an edge) mirrors `.safeAreaInset(edge:...)`.
# All are element subtrees, not properties, so they are validated recursively here.
_UNIVERSAL_SUBVIEW_KEYS = {"overlay", "sheet", "popover", "fullScreenCover", "background", "backgroundView", "toolbar", "contextMenu", "contextMenuPreview", "swipeActions", "safeAreaInset"}

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

        # In deployment mode, resolve the node's keys as the runtime filter does:
        # only the winning variant of `type`, `id`, `properties` and each subview
        # key survives on the target platform, so only that variant is checked.
        # (Variants of keys inside `properties` are handled in _validate_properties.)
        had_type = "type" in expanded
        if self._target_platform is not None:
            selected: dict[str, list[tuple[str | None, object]]] = {}
            for base, variants in expanded.items():
                winner = select_variant(variants, self._target_platform)
                if winner is not None:
                    selected[base] = [winner]
            expanded = selected

        # ── type ──────────────────────────────────────────────────────────────
        # `type` may appear unsuffixed or as `type:<platform>`. Each variant
        # must be a known element type.
        type_variants = expanded.get("type", [])
        if not type_variants:
            if had_type:
                issues.append(ValidationIssue(
                    "error", path,
                    f"no 'type' variant applies to target platform '{self._target_platform}'"
                ))
            else:
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

        variant_types = sorted(set(type_by_suffix.values()))
        if not variant_types:
            # No variant resolved to a known type — can't validate further.
            return issues

        # The primary type pairs with the unsuffixed `properties` block. It is
        # the unsuffixed `type`, or the only type left (always the case in
        # deployment mode). An element whose platform variants name different
        # types and that has no unsuffixed `type` has no primary type: its
        # unsuffixed `properties` apply under every variant, so they are
        # checked against all of them, whatever the key order in the file.
        primary_type = type_by_suffix.get(None)
        if primary_type is None and len(variant_types) == 1:
            primary_type = variant_types[0]
        type_label = primary_type or " or ".join(variant_types)

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
        for t in variant_types:
            s = self._loader.element_schema(t)
            if s:
                type_schemas.append(s)
        if not type_schemas:
            return issues

        # ── top-level keys ────────────────────────────────────────────────────
        allowed_top = set(_STRUCTURAL_KEYS) | set(_UNIVERSAL_SUBVIEW_KEYS)
        for s in type_schemas:
            allowed_top |= set(s.get("topLevelKeys", []))

        for base in expanded:
            if base not in allowed_top:
                issues.append(ValidationIssue(
                    "warning", path,
                    f"unexpected top-level key '{base}' for {type_label}"
                ))

        # ── properties ────────────────────────────────────────────────────────
        # Each `properties:X` variant pairs with the matching `type:X` schema.
        # Any other `properties` block pairs with the primary type, or with
        # every type variant when there is no primary type.
        for suffix, props in expanded.get("properties", []):
            label_path = f"{path}{sep}{format_suffix_label('properties', suffix)}"
            if not isinstance(props, dict):
                issues.append(ValidationIssue("error", label_path, "must be an object"))
                continue
            paired_type = type_by_suffix.get(suffix) or primary_type
            if paired_type is not None:
                paired_schema = self._loader.element_schema(paired_type)
                paired_own_props = paired_schema.get("ownProperties", {}) if paired_schema else {}
                paired_label = paired_type
            else:
                paired_own_props = self._merged_own_props(variant_types)
                paired_label = type_label
            issues += self._validate_properties(
                props, paired_own_props, paired_label, label_path
            )

        # ── recursive children / subviews ─────────────────────────────────────
        # Subview keys allowed: union of every type variant's topLevelKeys plus
        # the universal subview set. Sorted so that which of two subtrees reports
        # a duplicate id does not vary between runs.
        all_subview_keys: set[str] = set(_UNIVERSAL_SUBVIEW_KEYS)
        for s in type_schemas:
            all_subview_keys |= set(s.get("topLevelKeys", []))

        for child_key in sorted(all_subview_keys):
            variants = expanded.get(child_key, [])
            if len(variants) <= 1:
                for suffix, children in variants:
                    child_label = f"{path}{sep}{format_suffix_label(child_key, suffix)}"
                    issues += self._validate_subview_value(children, child_label, seen_ids)
                continue
            # Platform variants of one subview key (`children`, `children:ios`)
            # never survive together at runtime, so the same id may appear in
            # each of them. Check every variant against the ids seen so far,
            # but not against its sibling variants; then record all their ids.
            ids_before = set(seen_ids)
            for suffix, children in variants:
                child_label = f"{path}{sep}{format_suffix_label(child_key, suffix)}"
                variant_ids = set(ids_before)
                issues += self._validate_subview_value(children, child_label, variant_ids)
                seen_ids |= variant_ids

        return issues

    def _merged_own_props(self, type_names: list[str]) -> dict:
        """Union of the ownProperties of `type_names`, for a `properties` block
        that applies under several element types. On a key known to more than
        one type, the spec of the first type in `type_names` is used. A property
        is required only when every type requires it."""
        own_props_list = []
        for t in type_names:
            s = self._loader.element_schema(t)
            own_props_list.append(s.get("ownProperties", {}) if s else {})
        merged: dict = {}
        for own_props in own_props_list:
            for key, spec in own_props.items():
                merged.setdefault(key, spec)
        for key, spec in merged.items():
            if spec.get("required") and not all(
                p.get(key, {}).get("required") for p in own_props_list
            ):
                merged[key] = {**spec, "required": False}
        return merged

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
        base_props: dict | None = None,
        kind: str = "property",
    ) -> list[ValidationIssue]:
        # Validates one key/value block against `own_props` specs, falling back
        # to `base_props` (the View base schema) for keys not in `own_props`.
        # `kind` names the block in warning/error messages (e.g. "property").
        issues: list[ValidationIssue] = []
        if base_props is None:
            base_props = self._view_props
        expanded, suffix_warnings = _expand_suffixed_keys(properties, path)
        issues += suffix_warnings

        for base, variants in expanded.items():
            if base in own_props:
                spec = own_props[base]
            elif base in base_props:
                spec = base_props[base]
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
                    known_in = f"{element_type} or View base" if base_props else element_type
                    issues.append(ValidationIssue(
                        "warning",
                        f"{path}.{label}",
                        f"'{label}' is not a known {kind} for {known_in}; possible typo"
                    ))

        # Required own properties — satisfied if ANY variant (suffixed or not) is present.
        for key, spec in own_props.items():
            if spec.get("required") and key not in expanded:
                issues.append(ValidationIssue(
                    "error", f"{path}.{key}",
                    f"required {kind} '{key}' is missing"
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
