#!/bin/bash
# Make the two files that the tests on the real programs need.
#
#   scripts/make_fixtures.sh "/path/to/one file.ARW"
#
# Give it one Sony ARW of your own. Your photo is copied, never changed.
# fixtures/ is gitignored, so your photo never enters the repo.
#
# fixtures/sample.ARW is a copy of your photo. It alone is enough for the
# tests of dnglab. fixtures/sample.dng is made from it, and the other tests
# on the real programs need it:
#
# - With Adobe DNG Converter in /Applications, that program makes the DNG.
# - Without it, dnglab makes the DNG, and exiftool writes the name of the ARW
#   into it, as the app does for each DNG that dnglab makes. Every test
#   passes with this DNG too (checked with dnglab 0.8.0 and exiftool 13.55).
#   Without the name, three tests fail on a Mac that has Adobe DNG Converter.
# - With neither, the script stops before it copies a file.
#
# The tests that start Adobe DNG Converter skip on a Mac that does not have
# it, whichever program made the DNG.
#
# Any Sony ARW that dnglab and Adobe DNG Converter can read works. The tests
# of the dnglab match need a frame that the match table covers: a Sony
# A7S III, compressed raw, ISO 50 or 80 to 12800, adapted lens. With another
# frame those tests skip, and the others still run.
set -euo pipefail

src="${1:?Give the path of one ARW file}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
adobe="/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter"

# Where the app looks: the two Homebrew folders, then the PATH.
find_tool() {
  local folder
  for folder in /opt/homebrew/bin /usr/local/bin; do
    if [ -x "$folder/$1" ]; then echo "$folder/$1"; return; fi
  done
  command -v "$1" || true
}

if [ ! -f "$src" ]; then
  echo "No file at: $src" >&2
  exit 1
fi

# Before any file is copied: which program makes the DNG.
dnglab=""
exiftool=""
if [ -x "$adobe" ]; then
  maker="Adobe DNG Converter"
else
  dnglab="$(find_tool dnglab)"
  exiftool="$(find_tool exiftool)"
  if [ -z "$dnglab" ] || [ -z "$exiftool" ]; then
    echo "No program was found that can make the DNG. No file was copied." >&2
    echo "Install Adobe DNG Converter in /Applications, or install dnglab and exiftool:" >&2
    echo "  brew install dnglab exiftool" >&2
    exit 1
  fi
  maker="dnglab"
fi

mkdir -p "$root/fixtures"
cp "$src" "$root/fixtures/sample.ARW"
rm -f "$root/fixtures/sample.dng"
if [ "$maker" = "dnglab" ]; then
  # Never -f: the name is free, and dnglab must not write over a file.
  "$dnglab" convert --embed-raw false "$root/fixtures/sample.ARW" "$root/fixtures/sample.dng"
  "$exiftool" -m -overwrite_original -IFD0:OriginalRawFileName=sample.ARW "$root/fixtures/sample.dng"
else
  # Never -h: it opens a window and does not return.
  "$adobe" -c -d "$root/fixtures" "$root/fixtures/sample.ARW"
fi
# Adobe DNG Converter returns 0 for a file that it cannot read.
if [ ! -s "$root/fixtures/sample.dng" ]; then
  echo "$maker made no DNG from this file. It may not support it." >&2
  exit 1
fi
echo "fixtures ready: $(ls "$root/fixtures" | tr '\n' ' ')"
echo "The DNG was made with $maker."
