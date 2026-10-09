#!/bin/bash
# Make the two files the integration tests need.
#
#   scripts/make_fixtures.sh "/path/to/one A7S III file.ARW"
#
# The source file is copied, never changed. fixtures/ is gitignored: the
# photo is Dom's and this repo may become public.
set -euo pipefail

src="${1:?Give the path of one ARW file}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
converter="/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter"

mkdir -p "$root/fixtures"
cp "$src" "$root/fixtures/sample.ARW"
rm -f "$root/fixtures/sample.dng"
"$converter" -c -d "$root/fixtures" "$root/fixtures/sample.ARW"
test -f "$root/fixtures/sample.dng"
echo "fixtures ready: $(ls "$root/fixtures" | tr '\n' ' ')"
