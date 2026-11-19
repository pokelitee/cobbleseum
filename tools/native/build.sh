#!/usr/bin/env bash
# Builds the native move-effect runtime (a GDExtension, concepts_brief.md §12.5) for this
# platform into game/native/bin/. Fetches godot-cpp at a pinned commit into the git-ignored
# cache first. Needs Python with SCons (pip install scons==4.9.1) and a C++ compiler (MSVC on
# Windows, Xcode Command Line Tools on macOS, GCC or Clang on Linux).
# Usage: tools/native/build.sh [target=template_debug|template_release] [other SCons options]
set -euo pipefail

GODOT_CPP_URL="https://github.com/godotengine/godot-cpp"
# godot-4.5-stable; GDExtensions built against it load in later Godot 4 releases.
GODOT_CPP_COMMIT="e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77"

root="$(cd "$(dirname "$0")/../.." && pwd)"
cpp="$root/cache/native/godot-cpp"
if [ ! -d "$cpp/.git" ]; then
	mkdir -p "$(dirname "$cpp")"
	git clone --quiet --filter=blob:none --no-checkout "$GODOT_CPP_URL" "$cpp"
fi
if [ "$(git -C "$cpp" rev-parse HEAD 2>/dev/null)" != "$GODOT_CPP_COMMIT" ]; then
	git -C "$cpp" fetch --quiet origin "$GODOT_CPP_COMMIT"
	git -C "$cpp" checkout --quiet "$GODOT_CPP_COMMIT"
fi
python=python3
command -v "$python" >/dev/null 2>&1 && "$python" -c "import SCons" 2>/dev/null || python=python
cd "$root/native"
GODOT_CPP="$cpp" "$python" -m SCons -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)" target=template_debug build_profile="$root/native/build_profile.json" "$@"
