"""
Platform-suffix awareness for the verifier.

Mirrors the platform token set in:
  - ActionUI/Common/PlatformFilter.swift          (`PlatformFilter.allPlatforms`)
  - ActionUIAndroid/library/.../PlatformFilter.kt (`PlatformFilter.ALL_PLATFORMS`)

A key like `text:ios` is a platform-specific variant of `text`. The runtime
filter rewrites it to `text` on iOS and drops it elsewhere. The verifier
mirrors this:

  - Known suffix (in ALL_PLATFORMS): treat as a valid variant of the base key.
  - Unknown suffix: warn (key will be dropped at runtime), skip validation
    of the value. Catches typos like `tint:Android` (capital A).

Both filters must agree on this set so a JSON file's "known platform tokens"
don't depend on which platform is reading it.
"""
from __future__ import annotations

ALL_PLATFORMS: frozenset[str] = frozenset({
    "ios", "macos", "tvos", "watchos", "visionos", "apple",
    "android", "androidtv", "wear",
    "desktop", "web",
})


def split_platform_suffix(key: str) -> tuple[str, str | None]:
    """Split a key on its last colon.

    Returns (base, suffix-or-None). A key without ':' returns (key, None).
    A key with ':' always returns the split, regardless of whether the
    suffix is a known platform — callers check ALL_PLATFORMS membership
    to distinguish real platform tags from typos.
    """
    idx = key.rfind(":")
    if idx < 0:
        return key, None
    return key[:idx], key[idx + 1:]


def format_suffix_label(base: str, suffix: str | None) -> str:
    """Render `base[:suffix]` for use in error/warning messages."""
    return base if suffix is None else f"{base}:{suffix}"


# Umbrella platform tokens and the concrete platforms they cover. A schema
# `platforms` annotation or a `:suffix` may use either an umbrella ("apple") or
# a concrete token ("ios"); matching expands umbrellas to their members.
PLATFORM_FAMILIES: dict[str, frozenset[str]] = {
    "apple":   frozenset({"apple", "ios", "macos", "tvos", "watchos", "visionos"}),
    "android": frozenset({"android", "androidtv", "wear"}),
    "desktop": frozenset({"desktop"}),
    "web":     frozenset({"web"}),
}


def platform_matches(token: str, platform: str) -> bool:
    """True if `token` (from a `:suffix` or a schema `platforms` entry) applies
    to the concrete `platform`. An umbrella token matches any of its members."""
    if token == platform:
        return True
    family = PLATFORM_FAMILIES.get(token)
    return family is not None and platform in family


def platforms_include(annotation: list[str], platform: str) -> bool:
    """True if any entry in a schema `platforms` list applies to `platform`."""
    return any(platform_matches(entry, platform) for entry in annotation)
