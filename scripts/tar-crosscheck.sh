#!/usr/bin/env bash
# GNU tar cross-check for the .agnos-agent bundle format (ADR-0008).
#
# mela writes and reads gzipped ustar with its own code, so a self-consistent
# round trip proves nothing about the format. GNU tar is the independent oracle
# (rust-old/ cannot be built, and is being retired):
#   1. mela packs a Flutter build dir; GNU tar lists and extracts the bundle, and
#      every entry matches the source and mela's own reader byte for byte.
#   2. GNU tar builds gnu, ustar and pax archives; mela lists and reads them, and
#      every regular file matches the source byte for byte.
#
# Run from anywhere: scripts/tar-crosscheck.sh. Needs GNU tar and gzip.
# The fixture's flutter_assets/ is one level deep: nested assets are defect D11
# (docs/development/rust-parity.md); add a nested file here when it is fixed.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "tar-crosscheck: FAIL: $*" >&2; exit 1; }

tar --version | head -1 | grep -q 'GNU tar' || fail "GNU tar is required"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

mkdir -p build
cyrius build scripts/tar-crosscheck.cyr build/tar-crosscheck > "$T/build.log" 2>&1 \
  || { cat "$T/build.log" >&2; fail "helper did not build"; }
H=build/tar-crosscheck

# --- fixture: a Flutter build dir (engine, AOT binary, assets) --------------
B="$T/flutter-build"
mkdir -p "$B/lib" "$B/flutter_assets"
head -c 300000 /dev/urandom > "$B/lib/libflutter_linux_gtk.so"
head -c 50000  /dev/urandom > "$B/lib/libapp.so"
printf '{"assets":["NOTICES.Z"]}' > "$B/flutter_assets/AssetManifest.json"
head -c 1000   /dev/urandom > "$B/flutter_assets/NOTICES.Z"

# --- 1. mela writes, GNU tar reads ------------------------------------------
bundle="$("$H" pack "$B" "$T/out")" || fail "mela could not pack the fixture"
gzip -t "$bundle" || fail "gzip -t rejects mela's bundle"

expected="$T/expected"
printf '%s\n' \
  assets/flutter_assets/AssetManifest.json \
  assets/flutter_assets/NOTICES.Z \
  bin/flutter_engine.so \
  bin/xcheck-app \
  manifest.json \
  sandbox.json > "$expected"

tar -tzf "$bundle" | sort > "$T/gnu-list" || fail "GNU tar cannot list mela's bundle"
"$H" list "$bundle" | sort > "$T/mela-list" || fail "mela cannot list its own bundle"
diff -u "$expected" "$T/gnu-list" || fail "GNU tar lists different entries than expected"
diff -u "$T/gnu-list" "$T/mela-list" || fail "GNU tar and mela list different entries"

if tar -tvzf "$bundle" | grep -v '^-' ; then
  fail "mela's bundle has a non-regular entry"
fi

X="$T/extract"
mkdir -p "$X"
tar -xzf "$bundle" -C "$X" || fail "GNU tar cannot extract mela's bundle"
cmp "$B/lib/libflutter_linux_gtk.so" "$X/bin/flutter_engine.so" || fail "engine differs after GNU extract"
cmp "$B/lib/libapp.so" "$X/bin/xcheck-app" || fail "AOT binary differs after GNU extract"
cmp "$B/flutter_assets/AssetManifest.json" "$X/assets/flutter_assets/AssetManifest.json" \
  || fail "AssetManifest.json differs after GNU extract"
cmp "$B/flutter_assets/NOTICES.Z" "$X/assets/flutter_assets/NOTICES.Z" || fail "NOTICES.Z differs after GNU extract"

while read -r e; do
  "$H" get "$bundle" "$e" "$T/entry" || fail "mela cannot read its own entry $e"
  cmp "$X/$e" "$T/entry" || fail "mela and GNU tar disagree on $e"
done < "$T/gnu-list"

# --- 2. GNU tar writes, mela reads ------------------------------------------
S="$T/src"
mkdir -p "$S/bin" "$S/assets/flutter_assets"
cp "$B/lib/libflutter_linux_gtk.so" "$S/bin/flutter_engine.so"
cp "$X/manifest.json" "$X/sandbox.json" "$S/"
cp "$B/flutter_assets/AssetManifest.json" "$B/flutter_assets/NOTICES.Z" "$S/assets/flutter_assets/"

for fmt in gnu ustar pax; do
  a="$T/gnu-$fmt.tgz"
  tar --format="$fmt" -czf "$a" -C "$S" manifest.json sandbox.json bin assets
  tar -tzf "$a" | grep -v '/$' | sort > "$T/gnu-list"     # regular files; dirs end in /
  "$H" list "$a" | sort > "$T/mela-list" || fail "mela cannot list a GNU $fmt archive"
  diff -u "$T/gnu-list" "$T/mela-list" || fail "mela lists different entries for GNU $fmt"
  while read -r e; do
    "$H" get "$a" "$e" "$T/entry" || fail "mela cannot read $e from GNU $fmt"
    cmp "$S/$e" "$T/entry" || fail "$e differs reading GNU $fmt"
  done < "$T/gnu-list"
done

echo "tar-crosscheck: ok (mela -> GNU tar: 6 entries byte-exact; GNU tar gnu/ustar/pax -> mela: byte-exact)"
