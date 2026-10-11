# Contributing to Plateworks Desqueeze

Thank you for your interest. This file says how to build, how to test, and
what a change must hold to before it can merge. `README.md` says what the
tool does. `docs/architecture.md` says which file owns what.

This tool changes people's photo files. So the rules below are strict, and a
change that makes a file less safe does not merge.

## Build and test

You need a Mac with Xcode, and exiftool, dnglab and XcodeGen from Homebrew.
`README.md` lists the versions that were tested.

Run all three suites before you open a pull request:

```bash
swift test
swift test --package-path MCPServer
xcodegen generate
xcodebuild -project PlateworksDesqueeze.xcodeproj -scheme PlateworksDesqueeze -derivedDataPath build test
```

The first command tests the core and the command line tool, and runs the
docs check. The second tests the MCP server. The last two test the state of
the window. `docs/changing-things.md` has one section for each common
change, with the file to edit and the test that judges it.

## The rules that must not break

The rules are the numbered list "Invariants" in `CLAUDE.md`. Read them
before you change code. They are short, and each one has its reason. The
design, `docs/superpowers/specs/2026-10-05-desqueeze-design.md`, is the
contract for all behavior. When you change behavior, change the design in
the same pull request.

## Write the test first

1. Write the test for the new behavior.
2. Run it, and see it fail for the reason that you expect.
3. Write the code.
4. Run it again, and see it pass.

A behavioral test counts only after it fails against a break. If you add a
test to code that exists already, break the code for a moment, see the test
fail, and restore the code.

## Never test on real photos

- Never run the tool, the server, a test or exiftool on a folder of photos
  that you care about. Copy the folder first, and work on the copy.
- No test may reach the real Trash. In a unit test, give `FileBackups` a
  function of your own. For a built tool or server, set
  `DESQUEEZE_TEST_BACKUP_FOLDER` to a temporary folder that exists. Each
  discarded file then goes to that folder.
- No test may read or write the saved settings of the app.

## Make the fixtures

Some tests run the real programs on one ARW and one DNG in `fixtures/`. The
folder is gitignored, because a photo is private. Without it, those tests
skip and the other tests still run.

```bash
scripts/make_fixtures.sh "/path/to/one file.ARW"
```

The script copies your ARW and does not change it. It makes the DNG with
Adobe DNG Converter. When that is not in the Applications folder, it makes
the DNG with dnglab and exiftool. With neither, it stops before it copies a
file. Any Sony ARW that dnglab and Adobe DNG Converter can read works: a
test takes each value that it expects from the frame itself. The drift check and the tests of the real dnglab match need a
frame that the match table covers: a Sony A7S III, compressed raw, ISO 50
or 80 to 12800, adapted lens. With another frame they skip, and the other
tests still run. Say in your pull request which tests skipped on your Mac.

Never commit a photo. `.gitignore` ignores every ARW, every DNG and every
backup of a DNG in the tree, so `git add` does not take one by accident.

## One source for each sentence

Every sentence that more than one front end says is made once, in
`Sources/DesqueezeCore/`. The window, the tool and the server only show it.
Do not write such a sentence a second time in a front end.
`docs/changing-things.md` has a table that says where each sentence is made.

Text for a person is in sentence case, with no exclamation mark and no
emoji. An error is one plain sentence, with the tool's own words on a detail
line below it.

## Documents

A change is not complete until its documents are. `swift test` runs a check
of the documents. It fails when `README.md`, `CLAUDE.md`, `AGENTS.md` or a
document at the top of `docs/` quotes a path that does not exist. It also
fails when a Markdown file under `docs/` has no row in `docs/README.md`.
Write documents
in short sentences, in the active voice, with one word for one thing.
`scripts/docs_check.py` is a copy of the documentation standard's check.
Its header comment differs, and it has no skip rule for paths outside the
repo. Do not edit its checks here.

## The download

A release is made on one Mac, the maintainer's, with
`scripts/make_release.sh`. You do not need to make one, and you cannot: the
script needs the Developer ID. A pull request never carries a built app or
a disk image.

`scripts/make_release.sh --local` works on any Mac with Apple silicon that
has exiftool and dnglab from Homebrew at the versions that the script pins.
It makes the app with the two programs inside, signed ad hoc. Run it when
you change the script, the places of the programs in the bundle, or where
the window looks for a program. The design, section 15, is the contract,
and `docs/changing-things.md` has the steps.

Do not change a pinned version or a pinned hash in a pull request without
the measurement that `docs/changing-things.md` asks for.

## Commit messages

One line: `area: what changed`. It starts in lower case and has no period at
the end. The area is the part of the repo: `core`, `cli`, `mcp`, `app`,
`tests`, `scripts`, `spec`, `plan`, `docs`.

```
core: a leftover file of exiftool beside a photo stops its conversion, and the note names it
cli: the line for a missing exiftool is the core's
```

## Add a camera to the match table

The match table lets dnglab make a DNG that Lightroom shows as Adobe DNG
Converter's. It has one camera today, the Sony A7S III. Every number in it
was measured. No number is estimated.

To add a camera, you need two things. **You need Adobe DNG Converter. You
need frames from that camera**, one at each ISO setting, as compressed raw.
The app converts Sony ARW files only, and the match reads Sony tags, so the
camera must be a Sony camera that writes ARW.

The method is in the design, section 13.2. The steps:

1. **Make the frames.** Make one ARW at each ISO setting of the camera, with
   a lens that does not report itself to the camera. Make a second set, or a
   part of one, with another lens. Use copies. Write down the firmware
   version of the camera.
2. **Convert each ARW with Adobe DNG Converter**, into a folder of its own.
   Never pass `-h`.

   ```bash
   "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter" -c -d "/path/to/adobe" "/path/to/frames/one file.ARW"
   ```

3. **Read the facts of each ARW.**

   ```bash
   exiftool -n -T -filename -IFD0:Model -ExifIFD:ISO -SR2SubIFD:WB_RGBLevelsDaylight -SubIFD:DistortionCorrection -SubIFD:SonyRawFileType "/path/to/frames"
   ```

   The columns are the model, the ISO, the three daylight levels, 255 for
   "no lens-correction data", and 2 for compressed raw.
4. **Read Adobe's values from each DNG.**

   ```bash
   exiftool -n -T -filename -SubIFD:WhiteLevel -IFD0:BaselineExposure -IFD0:CameraCalibration1 -IFD0:CameraCalibration2 -IFD0:NoiseProfile -IFD0:BaselineNoise -IFD0:BaselineSharpness -SubIFD:AntiAliasStrength -SubIFD:BayerGreenSplit "/path/to/adobe"
   ```

5. **Check what varies.** For the A7S III, the white level and the four
   last values are the same in every file. The baseline exposure and the
   six noise values vary with the ISO only. If your camera differs, stop
   and open an issue with the numbers.
6. **Check the calibration rule.** Adobe's calibration is the diagonal
   `r 0 0 0 1 0 0 0 b`. For the A7S III, r is 2568 divided by the red
   daylight level of the ARW. b is 1549 divided by its blue level. Each is
   rounded to 4 decimal places. The green level is 1024. Find the two
   reference numbers of your camera: r times the red level, and b times the
   blue level. The rule must give Adobe's exact numbers for every file, with
   both lenses. If it does not, the camera cannot be added by this method.
7. **Write the data file.** Put it beside
   `docs/superpowers/specs/2026-10-09-ilce-7sm3-adobe-values.json`, in the
   same shape. Keep each noise value as text, with the digits that exiftool
   printed.
8. **Write the test first.** `testTheTableIsTheDataFile` in
   `Tests/DesqueezeCoreTests/AdobeMatchTests.swift` pins one camera. Extend
   it to your data file, and see it fail.
9. **Add the row.** Add a `Camera` value to
   `Sources/DesqueezeCore/AdobeMatch.swift`, and add it to `cameras`. Copy
   the digits from the data file.
10. **Teach the test helper your camera.** `factsOfACoveredFrame` in
    `Tests/DesqueezeCoreTests/DnglabIntegrationTests.swift` decides which
    fixture frames the table covers. It reads the data file of the A7S III,
    and no other. Make it read your data file too. Until it does, the drift
    check skips for a frame of your camera, and a skip proves nothing.
11. **Run the drift check.** It converts the frame in `fixtures/` with Adobe
    DNG Converter and with dnglab plus your row, and compares every tag. Make
    the fixtures from one of your frames that the new row covers, then run
    it. The check skips for a frame that the table does not cover, so see
    that it ran:

    ```bash
    swift test --filter AdobeDriftTests
    ```

12. **Update the documents.** The design, sections 13.4 and 13.9, and
    `README.md` say that the table has one camera. Add a row to
    `docs/decisions.md`. Give the firmware version and the ISO settings that
    you measured.

The design also compared the two renders in Camera Raw, pixel by pixel. If
you can do that for your camera, put the numbers in the pull request.

Do not attach a photo that you do not want public. The numbers are enough.

## Security

Read `SECURITY.md` before you report a problem that can harm a person's
files.
