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
# Both directions include names over 100 bytes (the ustar prefix, GNU L and PAX
# path records) and check file modes: 0755 for an executable, else 0644
# (ADR-0014).
#
# Run from anywhere: scripts/tar-crosscheck.sh. Needs GNU tar and gzip.
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
mkdir -p "$B/lib" "$B/flutter_assets/fonts"
head -c 300000 /dev/urandom > "$B/lib/libflutter_linux_gtk.so"
head -c 50000  /dev/urandom > "$B/lib/libapp.so"
printf '{"assets":["NOTICES.Z"]}' > "$B/flutter_assets/AssetManifest.json"
head -c 1000   /dev/urandom > "$B/flutter_assets/NOTICES.Z"
head -c 4000   /dev/urandom > "$B/flutter_assets/fonts/M.otf"   # nested (D11, v1.1.3)
# a 162-byte entry name: mela writes it with the ustar prefix (ADR-0014)
LONGDIR="packages/$(printf 'p%.0s' $(seq 60))/assets"
LONGFILE="$(printf 'f%.0s' $(seq 56)).png"
mkdir -p "$B/flutter_assets/$LONGDIR"
head -c 2000   /dev/urandom > "$B/flutter_assets/$LONGDIR/$LONGFILE"
chmod 0755 "$B/lib/libflutter_linux_gtk.so"
chmod 0644 "$B/lib/libapp.so"

# --- 1. mela writes, GNU tar reads ------------------------------------------
bundle="$("$H" pack "$B" "$T/out")" || fail "mela could not pack the fixture"
gzip -t "$bundle" || fail "gzip -t rejects mela's bundle"

expected="$T/expected"
printf '%s\n' \
  assets/flutter_assets/AssetManifest.json \
  assets/flutter_assets/NOTICES.Z \
  assets/flutter_assets/fonts/M.otf \
  "assets/flutter_assets/$LONGDIR/$LONGFILE" \
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
[ "$(printf 'assets/flutter_assets/%s/%s' "$LONGDIR" "$LONGFILE" | wc -c)" -gt 100 ] \
  || fail "the long-name fixture is not over 100 bytes"
tar -tvzf "$bundle" > "$T/gnu-verbose"    # to a file: grep -q on a pipe SIGPIPEs tar under pipefail
grep -q '^-rwxr-xr-x .* bin/flutter_engine.so$' "$T/gnu-verbose" || fail "GNU tar does not see the engine as 0755"
grep -q '^-rw-r--r-- .* bin/xcheck-app$' "$T/gnu-verbose" || fail "GNU tar does not see the AOT binary as 0644"
grep -q '^-rw-r--r-- .* manifest.json$' "$T/gnu-verbose" || fail "GNU tar does not see manifest.json as 0644"

X="$T/extract"
mkdir -p "$X"
tar -xzf "$bundle" -C "$X" || fail "GNU tar cannot extract mela's bundle"
cmp "$B/lib/libflutter_linux_gtk.so" "$X/bin/flutter_engine.so" || fail "engine differs after GNU extract"
cmp "$B/lib/libapp.so" "$X/bin/xcheck-app" || fail "AOT binary differs after GNU extract"
cmp "$B/flutter_assets/AssetManifest.json" "$X/assets/flutter_assets/AssetManifest.json" \
  || fail "AssetManifest.json differs after GNU extract"
cmp "$B/flutter_assets/NOTICES.Z" "$X/assets/flutter_assets/NOTICES.Z" || fail "NOTICES.Z differs after GNU extract"
cmp "$B/flutter_assets/fonts/M.otf" "$X/assets/flutter_assets/fonts/M.otf" || fail "fonts/M.otf differs after GNU extract"
cmp "$B/flutter_assets/$LONGDIR/$LONGFILE" "$X/assets/flutter_assets/$LONGDIR/$LONGFILE" \
  || fail "the long-named asset differs after GNU extract"

# mela extracts its own bundle with the modes GNU tar reports
MX="$T/mela-extract"
[ "$("$H" extract "$bundle" "$MX")" = 8 ] || fail "mela did not extract its 8 entries"
[ "$(stat -c %a "$MX/bin/flutter_engine.so")" = 755 ] || fail "mela extracted the engine without 0755"
[ "$(stat -c %a "$MX/bin/xcheck-app")" = 644 ] || fail "mela extracted the AOT binary without 0644"
cmp "$X/assets/flutter_assets/$LONGDIR/$LONGFILE" "$MX/assets/flutter_assets/$LONGDIR/$LONGFILE" \
  || fail "mela and GNU tar extract the long-named asset differently"

while read -r e; do
  "$H" get "$bundle" "$e" "$T/entry" || fail "mela cannot read its own entry $e"
  cmp "$X/$e" "$T/entry" || fail "mela and GNU tar disagree on $e"
done < "$T/gnu-list"

# --- 2. GNU tar writes, mela reads ------------------------------------------
S="$T/src"
mkdir -p "$S/bin" "$S/assets/flutter_assets/fonts"
cp "$B/lib/libflutter_linux_gtk.so" "$S/bin/flutter_engine.so"
cp "$X/manifest.json" "$X/sandbox.json" "$S/"
cp "$B/flutter_assets/AssetManifest.json" "$B/flutter_assets/NOTICES.Z" "$S/assets/flutter_assets/"
cp "$B/flutter_assets/fonts/M.otf" "$S/assets/flutter_assets/fonts/"
# names past 100 bytes: 150 bytes for all three formats (ustar uses its prefix),
# 300 bytes for gnu (an L entry) and pax (a path record) only
mkdir -p "$S/long150/$(printf 'a%.0s' $(seq 80))"
head -c 3000 /dev/urandom > "$S/long150/$(printf 'a%.0s' $(seq 80))/$(printf 'b%.0s' $(seq 60)).bin"
L300="long300/$(printf 'c%.0s' $(seq 95))/$(printf 'd%.0s' $(seq 95))"
mkdir -p "$S/$L300"
head -c 3000 /dev/urandom > "$S/$L300/$(printf 'e%.0s' $(seq 95)).bin"
# modes: an owner-executable script and a private file
printf '#!/bin/sh\n' > "$S/bin/run.sh"; chmod 0750 "$S/bin/run.sh"
printf 'secret' > "$S/bin/private.txt"; chmod 0600 "$S/bin/private.txt"

for fmt in gnu ustar pax; do
  a="$T/gnu-$fmt.tgz"
  if [ "$fmt" = ustar ]; then
    tar --format="$fmt" -czf "$a" -C "$S" manifest.json sandbox.json bin assets long150
  else
    tar --format="$fmt" -czf "$a" -C "$S" manifest.json sandbox.json bin assets long150 long300
  fi
  tar -tzf "$a" | grep -v '/$' | sort > "$T/gnu-list"     # regular files; dirs end in /
  "$H" list "$a" | sort > "$T/mela-list" || fail "mela cannot list a GNU $fmt archive"
  diff -u "$T/gnu-list" "$T/mela-list" || fail "mela lists different entries for GNU $fmt"
  while read -r e; do
    "$H" get "$a" "$e" "$T/entry" || fail "mela cannot read $e from GNU $fmt"
    cmp "$S/$e" "$T/entry" || fail "$e differs reading GNU $fmt"
  done < "$T/gnu-list"
  grep -q '^long150/' "$T/mela-list" || fail "mela lost the 150-byte name in GNU $fmt"
  if [ "$fmt" != ustar ]; then
    grep -q '^long300/' "$T/mela-list" || fail "mela lost the 300-byte name in GNU $fmt"
  fi
  GX="$T/gnu-$fmt-x"
  "$H" extract "$a" "$GX" > /dev/null || fail "mela cannot extract GNU $fmt"
  [ "$(stat -c %a "$GX/bin/run.sh")" = 755 ] || fail "GNU $fmt: 0750 did not extract as 0755"
  [ "$(stat -c %a "$GX/bin/private.txt")" = 644 ] || fail "GNU $fmt: 0600 did not extract as 0644"
  [ "$(stat -c %a "$GX/manifest.json")" = 644 ] || fail "GNU $fmt: manifest.json did not extract as 0644"
done

echo "tar-crosscheck: ok (mela -> GNU tar: 8 entries byte-exact, a 162-byte name, modes; GNU tar gnu/ustar/pax -> mela: byte-exact, names to 300 bytes, modes)"
