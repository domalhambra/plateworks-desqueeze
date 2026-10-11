#!/bin/bash
# Make the download: Desqueeze.app with exiftool and dnglab inside, in a
# signed and notarized disk image (design, section 15).
#
#   scripts/make_release.sh            The release. Needs the Developer ID.
#   scripts/make_release.sh --local    The app only, signed ad hoc, for checks.
#
# The script uploads nothing. A release is published by hand.
#
# The eight steps of the release. Each step stops the script when it fails.
#
#   1. Check. The work tree is clean. The version of project.yml has a dated
#      section in CHANGELOG.md. The two programs are at the pinned versions
#      and hashes. The keychain has one "Developer ID Application" identity.
#      The keychain profile for the notary service works. Every check that
#      can run does run, and each one that fails says one sentence.
#   2. Build. xcodegen writes the Xcode project, and xcodebuild makes a
#      Release build for arm64 in the output folder.
#   3. Put the programs inside, with the license texts.
#   4. Sign from the inside out: dnglab first, then the app. Each with the
#      hardened runtime and a secure time stamp. Never --deep.
#   5. Prove the bundle. The signature is valid. The two programs, started
#      from inside the bundle, give their pinned versions.
#   6. Notarize the app from a zip, and staple the ticket to the app.
#   7. Make the disk image from the stapled app, sign it, notarize it, and
#      staple it.
#   8. Prove the result. spctl accepts the app and the disk image. The last
#      lines are the path of the disk image and its SHA-256.
#
# --local does steps 2, 3 and 5, with the check of the two programs before
# them and an ad hoc signature between them. It needs no Developer ID and no
# clean tree, it asks no time stamp, and it makes no disk image. The app is
# for checks, and for the Mac that built it.
#
# Where the output goes:
#
#   build/release/local/Desqueeze.app                  --local
#   build/release/<version>/Desqueeze.app              the release
#   build/release/<version>/Desqueeze-<version>.dmg    the release
#
# The script writes into its output folder only, and build/ is gitignored.
# It puts a marker file into the folder. A later run removes the folder only
# when the marker is there, so it removes only its own earlier output.
#
# One program that the script starts writes outside that folder: xcodegen
# writes PlateworksDesqueeze.xcodeproj at the repo root, as it does for
# every build. git ignores that folder. xcodegen also writes
# App/PlateworksDesqueeze/Info.plist when project.yml gives it new content.
# The release stops when the build changed a tracked file.
#
# The script holds no name of a person, no Apple ID and no team. It finds
# the identity in the keychain by its kind. The notary credentials are in a
# keychain profile. Make the profile one time:
#
#   xcrun notarytool store-credentials desqueeze-notary
#
# Variable, optional:
#
#   DESQUEEZE_NOTARY_PROFILE  The name of the keychain profile. The default
#                             is desqueeze-notary.
#
# The programs inside are copies from Homebrew on this Mac. They are the
# files that the match table was measured with (design 13.2). The pins
# below hold them: two versions and three hashes. A new version of a program
# is a new measurement first, then a new pin: docs/changing-things.md has
# the steps.
#
# Which files of Homebrew's exiftool go into the app:
#
# - The script is libexec/bin/exiftool in the package folder. Homebrew has
#   two copies of the script. bin/exiftool is the one on the PATH, and
#   Homebrew wrote the path of its own lib folder into it, so that copy
#   works at one place only. libexec/bin/exiftool is exiftool's own script,
#   which looks for a folder named lib beside itself. To see the difference:
#     diff "$(brew --prefix exiftool)/bin/exiftool" "$(brew --prefix exiftool)/libexec/bin/exiftool"
#   Homebrew changed one line of it, the first, to the path of one Perl
#   version. The copy in the app gets "#!/usr/bin/perl" there, the Perl of
#   macOS. No other line changes.
# - The lib folder is exiftool's own Perl modules: the folder Image and the
#   two files File/RandomAccess.pm and File/RandomAccess.pod, from
#   libexec/lib/perl5. Homebrew puts them in one folder with the modules of
#   other packages, which exiftool does not need for a DNG. The list of
#   exiftool's own files is in the package:
#     find "$(brew --prefix exiftool)/libexec" -path '*Image/ExifTool/.packlist'
#   No file of lib is changed.
set -euo pipefail

# The pins. Each program must be at this version, and each file must have
# this SHA-256. Read a version with `dnglab --version` and `exiftool -ver`.
dnglab_version="0.8.0"
dnglab_sha256="ba7266d2f64a10f3f24198ccf5d4efac1c2a93ba6520d5d3578f4ef94bf235b4"
exiftool_version="13.55"
exiftool_script_sha256="cd9742cc0460b92ea6233f3125bc09d06c46e531ff3798fb77c480d2dd1bd360"
# One hash for the lib folder: the SHA-256 of the list that `lib_digest`
# makes, which has the SHA-256 and the path of each file.
exiftool_lib_sha256="65152ba49a9d8af78967034f16cd38d4251da7f4b44db1666a2573dc72ff6375"

# The places in the bundle. App/PlateworksDesqueeze/BundledTools.swift holds
# the same two, and a test of the window reads them here.
dnglab_place="Contents/Helpers/dnglab"
exiftool_place="Contents/Resources/exiftool/exiftool"
licenses_place="Contents/Resources/licenses"
system_perl="/usr/bin/perl"

usage() {
  echo "usage: scripts/make_release.sh [--local]"
  echo "  no argument  Make the signed, notarized disk image. Needs the Developer ID."
  echo "  --local      Make the app only, signed ad hoc, at build/release/local/Desqueeze.app."
}

mode="release"
case "${1-}" in
  "") ;;
  --local) mode="local" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then usage >&2; exit 2; fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${DESQUEEZE_NOTARY_PROFILE:-desqueeze-notary}"
marker=".made-by-make_release"

# One sentence for each check that fails. The script stops after the last
# check, so one run shows everything that is missing.
failures=0
fail() {
  echo "make_release.sh: $1" >&2
  failures=$((failures + 1))
}
stop() {
  echo "make_release.sh: $1" >&2
  exit 1
}

sha256_of() { shasum -a 256 "$1" | cut -d ' ' -f 1; }

# The SHA-256 and the path of each file of exiftool's lib, in a fixed order,
# as one hash. $1 is the folder that holds Image and File.
lib_digest() {
  (cd "$1" && find Image File/RandomAccess.pm File/RandomAccess.pod -type f -print0 \
    | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d ' ' -f 1)
}

# The version of project.yml, for example 0.1.0.
version="$(sed -n 's/^ *MARKETING_VERSION: *"\([0-9][0-9.]*\)" *$/\1/p' "$root/project.yml")"
if [ -z "$version" ]; then stop "project.yml has no MARKETING_VERSION."; fi

# ---------------------------------------------------------------- 1. Check

echo "1/8 Check"

if [ "$mode" = "release" ]; then
  if [ -n "$(git -C "$root" status --porcelain)" ]; then
    fail "The work tree is not clean. Commit or remove each change first."
  fi
  if ! grep -q "^## \[$version\] - [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\$" "$root/CHANGELOG.md"; then
    fail "CHANGELOG.md has no dated section for version $version. Give its heading the date: ## [$version] - YYYY-MM-DD"
  fi
fi

if [ "$(uname -m)" != "arm64" ]; then
  fail "This Mac does not have Apple silicon. The download is for Apple silicon, and its programs come from this Mac."
fi
for tool in xcodegen xcodebuild; do
  if ! command -v "$tool" >/dev/null; then fail "$tool was not found. The build needs it."; fi
done
if [ ! -x "$system_perl" ]; then
  fail "$system_perl cannot be run. The exiftool inside the app needs the Perl of macOS."
fi

# Homebrew's folder: `brew --prefix`, or one of its two fixed folders.
brew_prefix=""
if command -v brew >/dev/null; then
  brew_prefix="$(brew --prefix)"
else
  for folder in /opt/homebrew /usr/local; do
    if [ -x "$folder/bin/brew" ]; then brew_prefix="$folder"; break; fi
  done
fi

# The folder of one Homebrew package, with links resolved. Empty when the
# package is not installed.
package_folder() {
  if [ -n "$brew_prefix" ] && [ -d "$brew_prefix/opt/$1" ]; then (cd "$brew_prefix/opt/$1" && pwd -P); fi
}

dnglab_package=""
exiftool_package=""
if [ -z "$brew_prefix" ]; then
  fail "Homebrew was not found. The programs inside the app are copies from Homebrew."
else
  dnglab_package="$(package_folder dnglab)"
  exiftool_package="$(package_folder exiftool)"
fi

dnglab_source="$dnglab_package/bin/dnglab"
exiftool_source="$exiftool_package/libexec/bin/exiftool"
exiftool_lib_source="$exiftool_package/libexec/lib/perl5"

if [ -n "$brew_prefix" ]; then
  if [ -z "$dnglab_package" ] || [ ! -x "$dnglab_source" ]; then
    fail "dnglab is not installed with Homebrew. Install it with: brew install dnglab"
  else
    found="$("$dnglab_source" --version || true)"
    if [ "$found" != "dnglab $dnglab_version" ]; then
      fail "dnglab is not at the pinned version. Pinned: dnglab $dnglab_version. Found: $found."
    fi
    found="$(sha256_of "$dnglab_source")"
    if [ "$found" != "$dnglab_sha256" ]; then
      fail "The dnglab binary is not the pinned file. Pinned SHA-256: $dnglab_sha256. Found: $found."
    fi
    for file in LICENSE AUTHORS; do
      if [ ! -f "$dnglab_package/$file" ]; then fail "Homebrew's dnglab has no file $file."; fi
    done
  fi

  if [ -z "$exiftool_package" ] || [ ! -x "$exiftool_package/bin/exiftool" ]; then
    fail "exiftool is not installed with Homebrew. Install it with: brew install exiftool"
  elif [ ! -f "$exiftool_source" ] || [ ! -f "$exiftool_lib_source/Image/ExifTool.pm" ] \
    || [ ! -f "$exiftool_lib_source/File/RandomAccess.pm" ] || [ ! -f "$exiftool_lib_source/File/RandomAccess.pod" ]; then
    fail "Homebrew's exiftool does not have its script and its modules where this script looks. Read the header of this script."
  else
    found="$("$exiftool_package/bin/exiftool" -ver || true)"
    if [ "$found" != "$exiftool_version" ]; then
      fail "exiftool is not at the pinned version. Pinned: $exiftool_version. Found: $found."
    fi
    found="$(sha256_of "$exiftool_source")"
    if [ "$found" != "$exiftool_script_sha256" ]; then
      fail "The exiftool script is not the pinned file. Pinned SHA-256: $exiftool_script_sha256. Found: $found."
    fi
    found="$(lib_digest "$exiftool_lib_source")"
    if [ "$found" != "$exiftool_lib_sha256" ]; then
      fail "The lib folder of exiftool is not the pinned one. Pinned SHA-256: $exiftool_lib_sha256. Found: $found."
    fi
    if [ ! -f "$exiftool_package/README" ]; then fail "Homebrew's exiftool has no file README."; fi
  fi
fi

identity=""
if [ "$mode" = "release" ]; then
  # The identity is found by its kind. Its name and its hash are not shown.
  # One identity in two keychains is listed two times, and counts as one.
  identity="$(security find-identity -v -p codesigning \
    | awk '/"Developer ID Application: / { print $2 }' | sort -u)"
  count="$(printf '%s' "$identity" | grep -c . || true)"
  if [ "$count" -eq 0 ]; then
    fail "No Developer ID Application identity was found in the keychain."
  elif [ "$count" -gt 1 ]; then
    fail "The keychain has $count Developer ID Application identities. The script needs exactly one."
  fi

  # The last check, and only after every other check passed: it is the one
  # check that asks Apple's notary service, so it needs a network
  # connection.
  if [ "$failures" -eq 0 ]; then
    if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
      fail "The keychain profile $profile does not work with the notary service. Make it with: xcrun notarytool store-credentials $profile"
    fi
  fi
fi

if [ "$failures" -gt 0 ]; then
  echo "make_release.sh: stopped at step 1, the check. Nothing was built." >&2
  exit 1
fi

# The output folder. Only a folder with the marker of this script is removed.
if [ "$mode" = "local" ]; then
  out="$root/build/release/local"
else
  out="$root/build/release/$version"
fi
if [ -e "$out" ] || [ -L "$out" ]; then
  if [ -L "$out" ] || [ ! -f "$out/$marker" ]; then
    stop "build/release/$(basename "$out") is not a folder that this script made. Move it away first."
  fi
  # The copies from Homebrew are read-only files.
  chmod -R u+w "$out"
  rm -rf "$out"
fi
mkdir -p "$out"
: > "$out/$marker"

app="$out/Desqueeze.app"
dmg="$out/Desqueeze-$version.dmg"

# ---------------------------------------------------------------- 2. Build

echo "2/8 Build version $version for arm64"
# The project goes to the repo root, as in every build: a project that
# xcodegen writes into another folder does not find the package of the core.
xcodegen generate --quiet --spec "$root/project.yml" --project "$root"
if ! xcodebuild -project "$root/PlateworksDesqueeze.xcodeproj" -scheme PlateworksDesqueeze \
  -configuration Release -derivedDataPath "$out/derived" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build \
  > "$out/xcodebuild.log" 2>&1; then
  tail -n 40 "$out/xcodebuild.log" >&2
  stop "The build failed. The full output is in build/release/$(basename "$out")/xcodebuild.log"
fi
if [ "$mode" = "release" ] && [ -n "$(git -C "$root" status --porcelain)" ]; then
  stop "The build changed a tracked file. Run xcodegen generate, commit the change, and start again."
fi
ditto "$out/derived/Build/Products/Release/Desqueeze.app" "$app"

found="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
if [ "$found" != "$version" ]; then
  stop "The built app has version $found, and project.yml has $version."
fi

# ------------------------------------------- 3. Put the programs inside

echo "3/8 Put dnglab $dnglab_version and exiftool $exiftool_version inside"
dnglab_inside="$app/$dnglab_place"
exiftool_inside="$app/$exiftool_place"
exiftool_folder="$(dirname "$exiftool_inside")"
licenses="$app/$licenses_place"
mkdir -p "$(dirname "$dnglab_inside")" "$exiftool_folder/lib/File" "$licenses"

# dnglab: the file as it is.
cp "$dnglab_source" "$dnglab_inside"
chmod 755 "$dnglab_inside"
if [ "$(sha256_of "$dnglab_inside")" != "$dnglab_sha256" ]; then
  stop "The copy of dnglab in the app is not the pinned file."
fi

# exiftool: the first line becomes the Perl of macOS, and nothing else
# changes.
homebrew_first_line="$(head -n 1 "$exiftool_source")"
case "$homebrew_first_line" in
  "#!/usr/bin/perl"*) ;;
  *) stop "The first line of Homebrew's exiftool script is not a line for the Perl of macOS: $homebrew_first_line" ;;
esac
{ printf '%s\n' "#!$system_perl"; tail -n +2 "$exiftool_source"; } > "$exiftool_inside"
chmod 755 "$exiftool_inside"
if [ "$(head -n 1 "$exiftool_inside")" != "#!$system_perl" ] \
  || ! diff -q <(tail -n +2 "$exiftool_source") <(tail -n +2 "$exiftool_inside") >/dev/null \
  || [ "$(wc -l < "$exiftool_source")" -ne "$(wc -l < "$exiftool_inside")" ]; then
  stop "The copy of the exiftool script differs from Homebrew's in more than its first line."
fi

# The lib folder beside the script: exiftool's own modules, not changed.
ditto "$exiftool_lib_source/Image" "$exiftool_folder/lib/Image"
cp "$exiftool_lib_source/File/RandomAccess.pm" "$exiftool_lib_source/File/RandomAccess.pod" "$exiftool_folder/lib/File/"
if [ "$(lib_digest "$exiftool_folder/lib")" != "$exiftool_lib_sha256" ]; then
  stop "The copy of exiftool's lib folder in the app is not the pinned one."
fi

# The license texts (design 15.6).
cp "$dnglab_package/LICENSE" "$licenses/dnglab-LICENSE.txt"
cp "$dnglab_package/AUTHORS" "$licenses/dnglab-AUTHORS.txt"
cp "$exiftool_package/README" "$licenses/exiftool-README.txt"
cp "$root/THIRD_PARTY_NOTICES.md" "$licenses/THIRD_PARTY_NOTICES.md"
cat > "$licenses/exiftool-CHANGED-LINE.txt" <<EOF
exiftool $exiftool_version inside Plateworks Desqueeze $version

The file $exiftool_place in this app is the exiftool
script of the Homebrew package of exiftool $exiftool_version. One line of it is
changed: the first.

  Homebrew's copy:  $homebrew_first_line
  The copy here:    #!$system_perl

No other line of the script is changed. The folder lib beside the script
holds exiftool's own Perl modules, Image::ExifTool and File::RandomAccess,
from the same package. No file of lib is changed.

exiftool is by Phil Harvey, https://exiftool.org. Its terms are in
exiftool-README.txt, under "COPYRIGHT AND LICENSE".
EOF
chmod 644 "$licenses"/*

# -------------------------------------------------------------- 4. Sign

# From the inside out: dnglab first, then the app. Never --deep: it would
# sign dnglab a second time, with the options of the app.
# codesign says "replacing existing signature" for each file, with its full
# path. Its words show only when it fails.
sign() {
  local words
  if ! words="$(codesign --force "$@" 2>&1)"; then
    printf '%s\n' "$words" >&2
    stop "codesign could not sign $(basename "${!#}")."
  fi
}
if [ "$mode" = "local" ]; then
  echo "4/8 Sign ad hoc, with the hardened runtime and no time stamp"
  sign --options runtime --timestamp=none --sign - "$dnglab_inside"
  sign --options runtime --timestamp=none --sign - "$app"
else
  echo "4/8 Sign with the Developer ID, the hardened runtime and a time stamp"
  sign --options runtime --timestamp --sign "$identity" "$dnglab_inside"
  sign --options runtime --timestamp --sign "$identity" "$app"
fi

# ---------------------------------------------------- 5. Prove the bundle

echo "5/8 Prove the bundle"
# --deep is for this check only: it makes the check read dnglab in full.
codesign --verify --deep --strict "$app"
codesign --verify --strict "$dnglab_inside"
# Each answer of a program is read in full before it is searched. A search
# that stops at its first match would end the program early, and with
# `pipefail` that is a failure.
for code in "$app" "$dnglab_inside"; do
  found="$(codesign --display --verbose=2 "$code" 2>&1)"
  if ! grep -q '^CodeDirectory .*flags=.*runtime' <<< "$found"; then
    stop "$(basename "$code") is not signed with the hardened runtime."
  fi
done
# Neither has an entitlement (design 15.2).
for code in "$app" "$dnglab_inside"; do
  found="$(codesign --display --entitlements - --xml "$code" 2>/dev/null)"
  if [ -n "$found" ]; then
    stop "The signature of $(basename "$code") has an entitlement. It must have none."
  fi
done
for code in "$app/Contents/MacOS/Desqueeze" "$dnglab_inside"; do
  found="$(lipo -archs "$code")"
  if [ "$found" != "arm64" ]; then stop "$(basename "$code") is not for arm64 only. Found: $found."; fi
done

found="$("$dnglab_inside" --version)"
if [ "$found" != "dnglab $dnglab_version" ]; then
  stop "The dnglab inside the app gives: $found. Pinned: dnglab $dnglab_version."
fi
found="$("$exiftool_inside" -ver)"
if [ "$found" != "$exiftool_version" ]; then
  stop "The exiftool inside the app gives: $found. Pinned: $exiftool_version."
fi
# -v2 with -ver lists the folders that Perl loads from, in order. The first
# one must be the lib folder inside the app.
found="$("$exiftool_inside" -ver -v2 | sed -n '/^Include directories:/{n;s/^ *//;p;}')"
if [ "$found" != "$exiftool_folder/lib" ]; then
  stop "The exiftool inside the app does not load its modules from the lib folder inside the app. It looks first in: $found"
fi
echo "    $(basename "$app"): the signature is valid, arm64"
echo "    $dnglab_place: dnglab $dnglab_version"
echo "    $exiftool_place: exiftool $exiftool_version, with its own lib"

if [ "$mode" = "local" ]; then
  echo "The app is at build/release/local/Desqueeze.app"
  echo "It is signed ad hoc: it is for checks, and for this Mac."
  exit 0
fi

# ---------------------------------------------------- 6. Notarize the app

# Sends one file to the notary service and waits for the answer.
notarize() {
  local log
  log="$out/notary-$(basename "$1").log"
  xcrun notarytool submit "$1" --keychain-profile "$profile" --wait 2>&1 | tee "$log"
  if ! grep -q 'status: Accepted' "$log"; then
    stop "The notary service did not accept $(basename "$1"). Read why with: xcrun notarytool log <id> --keychain-profile $profile"
  fi
}

echo "6/8 Notarize the app"
ditto -c -k --keepParent "$app" "$out/Desqueeze-$version.zip"
notarize "$out/Desqueeze-$version.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"

# ------------------------------------------------ 7. Make the disk image

echo "7/8 Make the disk image"
stage="$out/disk-image"
mkdir "$stage"
ditto "$app" "$stage/Desqueeze.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Desqueeze $version" -srcfolder "$stage" -format UDZO "$dmg"
sign --timestamp --sign "$identity" "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"

# ---------------------------------------------------- 8. Prove the result

echo "8/8 Prove the result"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

echo "Built from commit $(git -C "$root" rev-parse --short HEAD)."
echo "$dmg"
echo "SHA-256: $(sha256_of "$dmg")"
