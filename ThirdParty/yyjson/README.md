# yyjson (vendored)

The JSON reader behind `Common/ACFJSON.cpp`, which OMC uses instead of NSJSONSerialization so the same code builds on macOS and Linux. Only the reader is used; OMC's JSON writer is its own (it reproduces NSJSONSerialization's output).

- Upstream: https://github.com/ibireme/yyjson
- Version: 0.13.0 (git tag `0.13.0`), the same copy `~/git/replay` vendors
- License: MIT, `LICENSE` in this folder
- Files, unmodified from the tag (`src/yyjson.c`, `src/yyjson.h`, `LICENSE`), SHA-256:
  - `yyjson.c` `d2d58ef0a3b2267862dc363832c4f3185fd375aea933d5d3419d1a940d6ece2e`
  - `yyjson.h` `ef803cda5c06b8962face6dfa39c3284b3bcf3e73f4d7317664690cc779679ca`
  - `LICENSE` `45e384d3d52c73cba3a64d6e6c25d47cd738cd8a55c30629e3201046eda62947`

To update: download the three files of the new tag from `https://raw.githubusercontent.com/ibireme/yyjson/<tag>/`, replace them here, update this file, and run the JSON parity tests (`OMCJSONFoundationParityTests`). Do not edit the files in place; a local change would be lost at the next update.
