#!/bin/bash
# Make the two files that the tests on the real programs need.
#
#   scripts/make_fixtures.sh "/path/to/one file.ARW"
#
# Give it one Sony ARW of your own. Your photo is copied, never changed.
# fixtures/ is gitignored, so your photo never enters the repo.
#
# The script needs Adobe DNG Converter in /Applications: it makes the DNG.
#
# Any Sony ARW that dnglab and Adobe DNG Converter can read works. The tests
# of the dnglab match need a frame that the match table covers: a Sony
# A7S III, compressed raw, ISO 50 or 80 to 12800, adapted lens. With another
# frame those tests skip, and the others still run.
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
