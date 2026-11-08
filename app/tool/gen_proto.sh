#!/usr/bin/env bash
# Regenerates lib/src/gen/ from the repo's proto/ghostwave.proto (the same file
# the firmware implements; there is no copy in app/).
# Needs protoc and the Dart plugin pinned below:
#   dart pub global activate protoc_plugin 25.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PATH:$HOME/.pub-cache/bin"
command -v protoc >/dev/null || { echo "protoc not found" >&2; exit 1; }
command -v protoc-gen-dart >/dev/null || { echo "protoc-gen-dart not found (dart pub global activate protoc_plugin 25.1.0)" >&2; exit 1; }
rm -rf lib/src/gen
mkdir -p lib/src/gen
protoc --dart_out=lib/src/gen -I ../proto ../proto/ghostwave.proto
echo "generated: $(ls lib/src/gen | tr '\n' ' ')"
