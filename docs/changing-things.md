# Changing things

One section for each task. Each section names the file to edit, the test
that judges the change, and the design section to read first. "Design" is
`docs/superpowers/specs/2026-10-05-desqueeze-design.md`.

Every command runs from the repo root. Three rules hold for every task:

- Write the test first. A behavioral test counts only after it fails against
  a break.
- Never test on a real photo folder. Use a copy in a temporary folder.
- Before any claim of done, run the three suites (the first section).

## Run the three suites

1. Run the root package: `swift test`. It needs no Xcode project. The docs
   check runs inside it.
2. Run the server package: `swift test --package-path MCPServer`. The first
   run fetches the MCP library, so it needs a network connection.
3. Make the Xcode project: `xcodegen generate`.
4. Run the window's tests:

   ```bash
   xcodebuild -project PlateworksDesqueeze.xcodeproj -scheme PlateworksDesqueeze -derivedDataPath build test
   ```

A test that needs `fixtures/` or a program that is not installed skips. It
does not fail. `docs/architecture.md` lists what skips. The tests on the
real programs start Adobe DNG Converter, so its icon shows in the Dock
during a run.

## Make the fixtures

The tests on the real programs need one ARW and one DNG in `fixtures/`. The
folder is gitignored: the photo is yours and stays on your Mac.

1. Install the programs that make the DNG. With Adobe DNG Converter in
   `/Applications`, the script uses it. Without it, the script uses dnglab,
   and exiftool then writes the name of the ARW into the DNG, as the app
   does. With neither, the script stops before it copies a file.
2. Run the script with one ARW file. The script copies the file and does not
   change it.

   ```bash
   scripts/make_fixtures.sh "/path/to/one file.ARW"
   ```

Every test passes with either DNG. The tests that start Adobe DNG Converter
skip on a Mac that does not have it. `.gitignore` also ignores every ARW,
every DNG and every backup of a DNG, wherever it is in the tree.

Any Sony ARW that dnglab and Adobe DNG Converter can read works. A test
takes each value that it expects from the frame itself. The drift check and
the tests of the real dnglab match need a frame that the match table
covers: a Sony A7S III, compressed raw, ISO 50 or 80 to 12800, adapted lens.
With another frame they skip, and the other tests still run. They are in
`Tests/DesqueezeCoreTests/DnglabIntegrationTests.swift`.

## Change a sentence that a front end says

Read design 8 and 13.5 first. A sentence is in sentence case, with no
exclamation mark and no emoji. An error is one plain sentence, with the
tool's own words on a detail line below it.

1. Find where the sentence is made. A sentence that more than one front end
   says is made once, in the core. Never write it a second time in a front
   end.

   | The sentence is about | File | Test |
   |---|---|---|
   | A folder: the counts, the run button, read-only, the advice about the converters | `Sources/DesqueezeCore/FolderText.swift` | `Tests/DesqueezeCoreTests/FolderTextTests.swift` |
   | The box for the originals in the window: its label, the line under it, the run button with the originals | `Sources/DesqueezeCore/FolderText.swift` | `Tests/DesqueezeCoreTests/OriginalsTests.swift` |
   | One file of a run: most notes, the counts line, the Lightroom line and when it shows, the line about the two converters, the line about the originals | `Sources/DesqueezeCore/RunSummary.swift` | `Tests/DesqueezeCoreTests/RunSummaryTests.swift`, `Tests/DesqueezeCoreTests/OriginalsTests.swift` |
   | An original that the run did not move: the eight sentences, and the detail line of a DNG that did not pass its check | `Sources/DesqueezeCore/Originals.swift` | `Tests/DesqueezeCoreTests/OriginalsTests.swift` |
   | A run that did not start, because another run works in the folder. The line of `--verbose` for a volume that gave no folder lock. | `Sources/DesqueezeCore/FolderLock.swift` | `Tests/DesqueezeCoreTests/FolderLockTests.swift` |
   | The note of a run on a volume that gives no folder lock | `Sources/DesqueezeCore/RunSummary.swift` | `Tests/DesqueezeCoreTests/FolderLockTests.swift` |
   | A write that failed, a backup that was restored, a partial DNG | `Sources/DesqueezeCore/DesqueezeJob.swift` | `Tests/DesqueezeCoreTests/DesqueezeJobTests.swift` |
   | Who converts | `Sources/DesqueezeCore/ConverterChoice.swift` | `Tests/DesqueezeCoreTests/ConverterChoiceTests.swift` |
   | A failed conversion, a leftover file, a file name that is too long | `Sources/DesqueezeCore/RawConverter.swift` | `Tests/DesqueezeCoreTests/RawConverterTests.swift` |
   | A missing exiftool, the dnglab install | `Sources/DesqueezeCore/ToolLocator.swift` | `Tests/DesqueezeCoreTests/ToolLocatorTests.swift` |
   | A wrong factor, and the hint for a factor with a comma | `Sources/DesqueezeCore/SqueezeFactor.swift` | `Tests/DesqueezeCoreTests/SqueezeFactorTests.swift` |
   | A path that is no folder | `Sources/DesqueezeCore/FolderChoice.swift` | `Tests/DesqueezeCoreTests/FolderChoiceTests.swift` |
   | The help and the usage errors of the tool | `Sources/DesqueezeCLI/Usage.swift`, `Sources/DesqueezeCLI/Arguments.swift` | `Tests/DesqueezeCLITests/CommandsTests.swift`, `Tests/DesqueezeCLITests/ArgumentsTests.swift`, `Tests/DesqueezeCLITests/OriginalsToolTests.swift` |
   | The layout of the tool's text | `Sources/DesqueezeCLI/TextOutput.swift` | `Tests/DesqueezeCLITests/TextOutputTests.swift` |
   | What a model reads about a tool | `MCPServer/Sources/desqueeze-mcp/Tools.swift` | `MCPServer/Tests/DesqueezeMCPTests/ServerEndToEndTests.swift` |
   | The window alone | `App/PlateworksDesqueeze/AppModel.swift` | `App/PlateworksDesqueezeTests/AppModelTests.swift`, `App/PlateworksDesqueezeTests/OriginalsModelTests.swift` |
   | The window alone, in the view | `App/PlateworksDesqueeze/ContentView.swift` | None. Check it by hand. |

2. Change the test to the new words, and see it fail.
3. Change the sentence.
4. Run the three suites. The end-to-end tests of the tool and of the server
   also read some sentences.

When you write about the converters, say it the long way: dnglab converts
each photo that it can match, and Adobe DNG Converter converts the others.
"dnglab converts first" is not the rule.

## Add a preset factor

Read design 4.2 and 5 first.

1. Change the expected list in
   `Tests/DesqueezeCoreTests/SqueezeFactorTests.swift`, and see the test
   fail.
2. Add the number to `presets` in `Sources/DesqueezeCore/SqueezeFactor.swift`.
   The window draws one button for each preset.
3. Change the description of the `factor` argument in
   `MCPServer/Sources/desqueeze-mcp/Tools.swift`. It names the common
   factors by hand.
4. Check the window by hand: the row must fit in the fixed width.

## Add a note kind

Read design 12.1, 13.6 and 14.3 first. A front end reads the `kind` of a
note, never the English sentence.

1. Add the kind to the list in design 12.1, and to the two tests that pin
   every kind: `testEachKindIsWrittenAsItsName` in
   `Tests/DesqueezeCoreTests/ReportsTests.swift`, and the first test of
   `Tests/DesqueezeCoreTests/RunSummaryTests.swift`. See them fail.
2. Add the case to `FileNote.Kind` in
   `Sources/DesqueezeCore/RunSummary.swift`. Add the function that makes the
   note in the same file, with its sentence.
3. Add the note where the run decides it:
   `Sources/DesqueezeCore/DesqueezeJob.swift`, or
   `Sources/DesqueezeCore/RunPlan.swift` for a file that is not written. The
   dry run must give the same note. `Tests/DesqueezeCoreTests/RunSummaryTests.swift`
   and `Tests/DesqueezeCoreTests/PlanTests.swift` judge it.
4. Decide if the kind needs attention. `needsAttention` in
   `Sources/DesqueezeCore/RunSummary.swift` is true only for a failed or a
   blocked file. The exit code in `Sources/DesqueezeCLI/Commands.swift` is 1
   for those, for a stopped run, and for a read-only folder.
   `Tests/DesqueezeCLITests/ExitCodeTests.swift` judges the exit code. A
   kind that only informs, as `convertedUnmatched`, `originalKept` and
   `noFolderLock` do, also goes into `isInformation` in `App/PlateworksDesqueeze/AppModel.swift`,
   so the window gives its note the information symbol.
5. Tell the model about the kind in the description of `desqueeze_run`, in
   `MCPServer/Sources/desqueeze-mcp/Tools.swift`, and in the description of
   `desqueeze_remove` when Remove can give the note.
6. Add the kind to the table "The kinds of note" in
   `Sources/DesqueezeCore/DesqueezeCore.docc/TheJSONReports.md`, and its
   sentence to `Sources/DesqueezeCore/DesqueezeCore.docc/Troubleshooting.md`.

## Add a field to the JSON

Read design 12.1, 13.6 and 14.3 first. The tool and the server print the
same report types, so one change reaches both.

1. Add the key to the test of the shape in
   `Tests/DesqueezeCoreTests/ReportsTests.swift`, and see it fail.
2. Add the property to `ScanReport` or `RunReport` in
   `Sources/DesqueezeCore/Reports.swift`. `ScanReport` writes its keys by
   hand in `encode(to:)`, so add the key there. `RunReport` lists its keys in
   `CodingKeys`, so add it there. Write a value that is not known as `null`,
   and do not leave its key out. Two keys are left out on purpose: `steps`
   of a real run, and `converter` of a step that is no conversion.
3. Add the key to the JSON shape in design 12.1.
4. Name the key in the tool description in
   `MCPServer/Sources/desqueeze-mcp/Tools.swift`. A model reads the keys
   there.
5. Run the three suites. `Tests/DesqueezeCLITests/EndToEndTests.swift` and
   `MCPServer/Tests/DesqueezeMCPTests/ServerEndToEndTests.swift` read the
   JSON that the built tool and the built server print.

Never rename or remove a key without a decision row: a script can depend on
it.

## Add an MCP tool

Read design 12.2 first.

1. Put the file work in the core. Add the operation to
   `Sources/DesqueezeCore/Operations.swift`, with its test in
   `Tests/DesqueezeCoreTests/OperationsTests.swift`. The server holds no rule
   about files.
2. Add the name to `toolNames` in
   `MCPServer/Tests/DesqueezeMCPTests/ServerTestCase.swift`, and write the
   test of its schema in
   `MCPServer/Tests/DesqueezeMCPTests/ServerEndToEndTests.swift`. See the
   test of the tool list fail. One test in
   `MCPServer/Tests/DesqueezeMCPTests/ToolErrorTests.swift` pins the count of
   tools: change it too.
3. Add a `ToolDefinition` in `MCPServer/Sources/desqueeze-mcp/Tools.swift`,
   and add it to `ToolCatalog.all`. The description says what the tool
   changes, that `desqueeze_remove` reverses a run, and to call
   `desqueeze_scan` first. Set the annotations: a tool that changes no file
   is marked read-only.
4. Add the case and its argument checks to
   `MCPServer/Sources/desqueeze-mcp/ToolCall.swift`.
   `MCPServer/Tests/DesqueezeMCPTests/ToolErrorTests.swift` judges each
   refusal.
5. Call the operation in
   `MCPServer/Sources/desqueeze-mcp/ToolEnvironment.swift`.
6. Add the tool to the help text in
   `MCPServer/Sources/desqueeze-mcp/Program.swift`, and to the table in
   design 12.2.

Never give a tool an argument that moves an original ARW (design 14.1). The
server gives the core `trashOriginals: false`, always, in
`MCPServer/Sources/desqueeze-mcp/ToolEnvironment.swift`.
`testACallThatAsksToMoveTheOriginalsIsRefusedAndMovesNoARW` in
`MCPServer/Tests/DesqueezeMCPTests/ServerEndToEndTests.swift` holds that
rule.

## Add a camera to the match table

Read design 13.2, 13.4 and 13.9 first. The steps are in `CONTRIBUTING.md`,
under "Add a camera to the match table". This task needs Adobe DNG Converter
and one frame from that camera at each ISO setting.

The files to change:

- A new data file beside
  `docs/superpowers/specs/2026-10-09-ilce-7sm3-adobe-values.json`, in the
  same shape.
- `Sources/DesqueezeCore/AdobeMatch.swift`: a new `Camera` value, added to
  `cameras`.
- `Tests/DesqueezeCoreTests/AdobeMatchTests.swift`:
  `testTheTableIsTheDataFile` pins one camera today. Extend it to the new
  data file first, and see it fail.
- `Tests/DesqueezeCoreTests/DnglabIntegrationTests.swift`: the helper
  `factsOfACoveredFrame` decides which fixture frames the table covers. It
  reads the data file of the A7S III, and no other. Make it read the new
  data file too. Until it does, the drift check and the tests of the real
  dnglab match skip for a frame of the new camera, and a skip proves
  nothing.
- The design, 13.4 and 13.9, and `README.md`: both say that the table has one
  camera.

The drift check judges the row against the real Adobe DNG Converter:
`swift test --filter AdobeDriftTests`.

## Change a converter rule

Read design 4.3 step 1, 13.3 and 13.4 first. Then read the rules in
`CLAUDE.md`. These rules protect the user's files.

| Rule | File | Test |
|---|---|---|
| A rule for every converter: the checks before the start, the leftovers of an earlier run, the work file, what counts as a partial output | `ConverterRules` in `Sources/DesqueezeCore/RawConverter.swift` | `Tests/DesqueezeCoreTests/RawConverterTests.swift` |
| The command line of Adobe DNG Converter | `AdobeConverter` in `Sources/DesqueezeCore/RawConverter.swift` | `Tests/DesqueezeCoreTests/RawConverterTests.swift` |
| The dnglab steps: its command, the tags, the read-back | `Sources/DesqueezeCore/DnglabConverter.swift` | `Tests/DesqueezeCoreTests/DnglabConverterTests.swift` |
| The rename that never replaces | `Sources/DesqueezeCore/ExclusiveRename.swift` | `Tests/DesqueezeCoreTests/ExclusiveRenameTests.swift` |
| Which converter gets an ARW | `Sources/DesqueezeCore/ConverterChoice.swift` | `Tests/DesqueezeCoreTests/ConverterChoiceTests.swift` |
| What the run does after a failed conversion | `Sources/DesqueezeCore/DesqueezeJob.swift` | `Tests/DesqueezeCoreTests/DesqueezeJobTests.swift` |
| One run in a folder at a time: the lock, and what each answer of the system means | `Sources/DesqueezeCore/FolderLock.swift` | `Tests/DesqueezeCoreTests/FolderLockTests.swift`, and `Tests/DesqueezeCLITests/TwoRunsTests.swift` with two processes |

1. Change the design first. The design is the contract.
2. Write the test on fakes, and see it fail.
3. Change the code.
4. Run `swift test` with the fixtures and both converters installed, so the
   tests on the real programs and the drift check run.

Never pass `-f` to dnglab. Never pass `-h` to Adobe DNG Converter.

## Change the rule for the originals

Read design 14 first, all of it. This is the one feature that removes a file
of the user from the folder. Change the design first: it is the contract.

| Rule | File | Test |
|---|---|---|
| When an ARW moves: the function that decides, and the order of its questions | `OriginalDecision` in `Sources/DesqueezeCore/Originals.swift` | `Tests/DesqueezeCoreTests/OriginalsTests.swift` |
| The record of an ARW and its compare (size, modification date, file number, regular file) | `FileRecord` and `OriginalState` in `Sources/DesqueezeCore/Originals.swift` | `Tests/DesqueezeCoreTests/OriginalsTests.swift` |
| The two records of a DNG and when each one must hold: the DNG is the file that this run made | `FileRecord.isTheSameFile` in `Sources/DesqueezeCore/Originals.swift`, and the conversion loop, the tag loop and `moveOne` in `Sources/DesqueezeCore/DesqueezeJob.swift` | `Tests/DesqueezeCoreTests/OriginalsJobTests.swift`. On real files: `Tests/DesqueezeCoreTests/OriginalsDiskTests.swift`. With the real programs: `Tests/DesqueezeCoreTests/DnglabIntegrationTests.swift` |
| The check of the DNG, and its one exiftool read | `DNGCheck` in `Sources/DesqueezeCore/Originals.swift`, `readOriginalCheck` in `Sources/DesqueezeCore/ScaleTag.swift` | `Tests/DesqueezeCoreTests/OriginalsTests.swift` |
| The fifth step of the run: after every tag step, not after a cancel, one try of the Trash, and no delete after a refusal | `Sources/DesqueezeCore/DesqueezeJob.swift` | `Tests/DesqueezeCoreTests/OriginalsJobTests.swift`. On real files, where a delete shows: `Tests/DesqueezeCoreTests/OriginalsDiskTests.swift`. With the real programs: `Tests/DesqueezeCoreTests/DnglabIntegrationTests.swift` |
| The steps of the dry run | `Sources/DesqueezeCore/DesqueezeJob.swift` | `Tests/DesqueezeCoreTests/OriginalsPlanTests.swift`, `Tests/DesqueezeCoreTests/PlanTests.swift` |
| The flag of the tool and its two usage errors | `Sources/DesqueezeCLI/Arguments.swift` | `Tests/DesqueezeCLITests/OriginalsToolTests.swift`, `Tests/DesqueezeCLITests/EndToEndOriginalsTests.swift` |
| The box of the window: when it shows, and when it is off | `App/PlateworksDesqueeze/AppModel.swift` | `App/PlateworksDesqueezeTests/OriginalsModelTests.swift` |
| The count of the originals that a run can move, for the box and its line | `FolderSnapshot.convertibleARWs` in `Sources/DesqueezeCore/FolderText.swift` | `Tests/DesqueezeCoreTests/OriginalsTests.swift`, `App/PlateworksDesqueezeTests/OriginalsModelTests.swift` |
| The option has no default value | Each declaration of `trashOriginals` | `Tests/DesqueezeCoreTests/NoDefaultForTheOptionTests.swift`, which reads the Swift files |

1. Write the test on fakes, and see it fail. For a rule that keeps an ARW in
   the folder, also break the rule in the code and see the test fail. The
   first break to try: the option is treated as on when it is off.
2. Change the code. Keep these four rules:
   - The option has no default value in `DesqueezeJob.run`,
     `DesqueezeJob.plan` and `DesqueezeOperations.run`. No behavioral test
     can hold this, so one test reads the source.
   - The ARW moves through `BackupHandling.trashFile`, once. Never add a
     delete, and never add a second way to the Trash.
   - Nothing saves the option, and nothing but the box of the window and
     the flag `--trash-originals` turns it on.
   - The MCP server gives `false`.
3. Run the three suites with the fixtures and dnglab installed. No test
   reaches the real Trash: each one injects the trash function, or sets
   `DESQUEEZE_TEST_BACKUP_FOLDER`.
4. Check the window by hand, on a copy of a folder (the section "Check the
   window by hand"). The window uses the real Trash. Do not tick the box
   and click Run on a folder that you want to keep.

## Update the MCP library pin

Read design 12.2 first. The library is not yet at 1.0, and its API changes
between minor versions.

1. Change the version in `MCPServer/Package.swift`. Keep `.upToNextMinor`.
2. Resolve the packages: `swift package resolve --package-path MCPServer`.
   This writes `MCPServer/Package.resolved`. Commit that file.
3. Run `swift test --package-path MCPServer`. The end-to-end tests check the
   bytes on the wire, so they find a change in the protocol.
4. Read the header of
   `MCPServer/Sources/desqueeze-mcp/AnsweringTransport.swift`. It says what
   the library does not do at the pinned version, and what a later version
   can make simpler.
5. Update `THIRD_PARTY_NOTICES.md`: each version from
   `MCPServer/Package.resolved`, and each license from the package's own
   license file.

## Cut a version

The version is in three places: the core, `project.yml`, and the changelog.
Tests keep them equal.

1. Change the number in the three tests that pin it, and see them fail:
   `VersionTests` in `Tests/DesqueezeCoreTests/BackupTestFolderTests.swift`,
   `testVersionPrintsTheNameAndTheNumber` in
   `Tests/DesqueezeCLITests/CommandsTests.swift`, and `testVersionAndHelp`
   in `Tests/DesqueezeCLITests/EndToEndTests.swift`.
2. Change `current` in `Sources/DesqueezeCore/Version.swift`. The tool and
   the server print this number.
3. Change `MARKETING_VERSION` in `project.yml` to the same number, and
   increase `CURRENT_PROJECT_VERSION`. `VersionTests` fails when the two
   numbers differ.
4. Add the entry to `CHANGELOG.md`, as the newest one:
   `## [1.2.3] - 2027-01-31`. The changelog test in
   `Tests/DesqueezeCoreTests/DocsCheckTests.swift` fails when the newest
   entry is not the current version.
5. Run `xcodegen generate`, then the three suites.

## Make a release

Read design 15 first, all of it. A release is the disk image that
`scripts/make_release.sh` makes. Only the Mac that has the Developer ID can
make one. GitHub Actions makes none. The header of the script says what each
step does.

One time, on that Mac:

- Put the "Developer ID Application" certificate in the keychain. The script
  finds it by its kind, and it needs exactly one.
- Make the keychain profile for the notary service. The command asks for
  the credentials, and the script never sees them:

  ```bash
  xcrun notarytool store-credentials desqueeze-notary
  ```

  For a profile with another name, set `DESQUEEZE_NOTARY_PROFILE`.
- Install exiftool, dnglab and XcodeGen with Homebrew, at the versions that
  the script pins.

For each release:

1. Cut the version (the section "Cut a version"). Give the heading in
   `CHANGELOG.md` its date. The script stops for "Unreleased".
2. Run the three suites with the fixtures and both converters, so the tests
   on the real programs and the drift check run.
3. Make the app with no Developer ID first:

   ```bash
   scripts/make_release.sh --local
   ```

   It builds for arm64, puts the two programs inside, signs ad hoc, and
   proves the bundle. The app is in the folder release/local inside build.
4. Make a trial in the window of that app, on copies. The window uses the
   real Trash, so use a folder on a scratch disk image: a file that goes to
   the Trash there goes to the Trash of that image, and leaves with it.
   Prove that on one file first. Start the app with `-openFolder` and the
   folder on the image (the section "Check the window by hand"). Run with a
   factor, then Remove. While the run works, look at the process list: the
   exiftool and the dnglab must be the two inside the app, and not the ones
   of Homebrew.
5. Commit everything. The script stops when the work tree is not clean.
6. Make the release:

   ```bash
   scripts/make_release.sh
   ```

   The first step is the check. Each thing that is missing gets one
   sentence, and nothing is built. The last lines of a good run are the
   path of the disk image and its SHA-256. The script never removes a disk
   image: when one for this version is there already, it stops at the
   check. Move the disk image away, or cut a new version. When a staple
   fails six times, the notary service has accepted the file and its
   ticket is late: start the script again later.
7. Get the source archive of the dnglab version that is inside (design
   15.6). The formula file in Homebrew's dnglab package, `dnglab.rb` in its
   folder `.brew`, names the archive and its SHA-256. Check the hash of the
   file that you got.
8. Publish by hand, on the maintainer's yes: `gh release create`, with the
   disk image and the source archive of dnglab as files. Put the SHA-256 of
   the disk image in the text of the release.
9. Change the documents that say "no release is published yet":
   `README.md`, `docs/architecture.md`, `SECURITY.md`, `CHANGELOG.md`,
   `THIRD_PARTY_NOTICES.md`, `PROJECT_CHARTER.md`, and the articles `GettingStarted.md`,
   `DesqueezeCore.md` and `Troubleshooting.md` of the documentation site.
   Put what the first release proved into "Built and tested on" in
   `README.md`.

Never put a name, an Apple ID, a team or a certificate hash into a file of
the repo.

## Change a program inside the download

Read design 13.2 and 15.3 first. The app of the download holds dnglab and
exiftool at the versions that the match table was measured with. So the
order is: measure first, then pin.

1. Install the new version with Homebrew on the Mac that makes the release.
2. **Measure.** Run `swift test` with the fixtures and both converters. The
   drift check must run, not skip: `swift test --filter AdobeDriftTests`.
   It compares every matched tag of a dnglab DNG with Adobe's. When it
   fails, the match table needs a new measurement (design 13.2) before
   anything else changes.
3. **Look at the files of the new package.** The header of
   `scripts/make_release.sh` says which files of Homebrew's exiftool go
   into the app, and how to find them again. See that this is still true:
   the script in the folder libexec differs from the one on the `PATH` only
   where Homebrew wrote its own path, its first line names a Perl of macOS,
   and exiftool's own modules are the folder Image and the two files of
   `File::RandomAccess`. See that dnglab still links only libraries of
   macOS: `otool -L "$(brew --prefix dnglab)/bin/dnglab"`. See that it
   starts on the oldest macOS of the app:
   `xcrun vtool -show-build "$(brew --prefix dnglab)/bin/dnglab"`. The line
   `minos` must be 14.0 or lower, the deployment target in `project.yml`.
   The script makes this check too, in its step 1.
4. **Pin.** Change the versions in `scripts/make_release.sh`. Read them with
   `dnglab --version` and `exiftool -ver`. Then run
   `scripts/make_release.sh --local`: it stops at the check, and gives each
   hash that it found. Put the three hashes into the script.
5. Run `scripts/make_release.sh --local` again. It must pass its step 5:
   each program gives its pinned version from inside the app.
6. Make the trial in the window, as in "Make a release".
7. Change the documents in the same change: the table in design 15.3, the
   versions in `README.md`, `THIRD_PARTY_NOTICES.md`, `docs/architecture.md`
   and the header of `.github/workflows/tests.yml`. Add a row to
   `docs/decisions.md` and an entry to `CHANGELOG.md`.

To change where a program is inside the app, change two files in one
change: `App/PlateworksDesqueeze/BundledTools.swift` and
`scripts/make_release.sh`.
`testTheReleaseScriptPutsTheProgramsAtTheSameTwoPlaces` in
`App/PlateworksDesqueezeTests/BundledToolsTests.swift` fails when they
differ. To change the order in which the window looks, change the design
first (15.4), then `Tests/DesqueezeCoreTests/ToolLocatorTests.swift`, then
`Sources/DesqueezeCore/ToolLocator.swift`. The window gets its three
programs from one function, `WindowTools.find`, and `AppModel.live` only
calls it. Keep it so: a rule that is in `AppModel.live` has no test.

## Check the window by hand

The view has no test. Build the app (`README.md`), then start it with launch
arguments. Each argument is read from the command line only, never from the
saved settings.

| Argument | Shows |
|---|---|
| `-openFolder <path>` | The folder, loaded at launch. Use a copy of a shoot folder. |
| `-simulateMissingTools YES` | The window on a Mac with no exiftool and no converter |
| `-simulateMissingDnglab YES` | The window with no dnglab |
| `-simulateMissingAdobe YES` | The window with no Adobe DNG Converter |
| The last two together | The window with exiftool and with neither converter |

The arguments are in `LaunchOptions`, at the end of
`App/PlateworksDesqueeze/AppModel.swift`. An argument that hides a program
hides it wherever it is, also the copy inside the app of the download:
`WindowTools.find` in `App/PlateworksDesqueeze/BundledTools.swift` does
that, and `App/PlateworksDesqueezeTests/BundledToolsTests.swift` holds it.
Design 9 has the full acceptance pass. The window uses the real Trash, so the backups of a hand check go
there. No argument ticks the box "Move the original ARW files to the Trash"
(design 14.4): tick it by hand, and only on a copy of a folder. With the
box on, a run moves the ARW files of that copy to the real Trash.

## Take the screenshots again

The site has five screenshots of the window, each in a light and a dark
variant. They are in `Sources/DesqueezeCore/DesqueezeCore.docc/Resources/`.
Take all of them again when the window changes, so that they stay one set.

1. Make a scratch disk image and attach it. A file that goes to the Trash
   from a folder on it goes to the Trash of that image, and leaves with it.
   Prove that on one file first.

   ```bash
   hdiutil create -size 700m -fs APFS -volname Card card.dmg
   hdiutil attach -nobrowse card.dmg
   ```

2. Make a folder named "Shoot 1" on it. Put 8 DNG files and 4 ARW files
   in it, under plain names such as `DSC04093.dng`. Copies of one photo are
   enough: the window shows names and counts, never a picture.
3. Start the app with `-openFolder "/Volumes/Card/Shoot 1"` (see "Check the
   window by hand"). For the fifth screenshot, add
   `-simulateMissingTools YES`.
4. Capture the window alone, with its shadow. `<id>` is the number of the
   window.

   ```bash
   screencapture -x -l <id> window-folder@2x.png
   ```

5. Take the five states: the folder loaded (`window-folder`), the box for
   the originals on (`window-originals`), a run in progress (`window-run`),
   the result (`window-result`), and no exiftool (`window-no-exiftool`). A
   run of 12 photos takes some seconds, so capture in a loop and keep one
   frame.
6. Do the same in the other appearance of macOS. A dark file has `~dark`
   before `@2x`, for example `window-folder~dark@2x.png`.
7. When a screenshot shows other words or counts than before, change its
   text alternative in the article. `README.md` shows `window-result` too.
8. Run `scripts/build_docs.sh`, and look at "Using the window" on the site.
9. Detach the disk image, and delete it.

## Add or change a document

1. Put a new document under `docs/`, and add its row to `docs/README.md`.
   The docs check fails for a Markdown file with no row.
2. Quote a repo path in backticks, from the repo root. The docs check reads
   `README.md`, `CLAUDE.md`, `AGENTS.md` and each document at the top of
   `docs/`. It fails for a quoted path that does not exist. It does not read
   the other documents at the repo root, so check their paths yourself.
3. When a document governs a kind of change, add a row to the table in
   `CLAUDE.md`. That file must stay under 2,000 tokens, so trim it when you
   add to it.
4. When you add a source file, add its row to the module map in
   `docs/architecture.md`.
5. Run the check alone:

   ```bash
   python3 scripts/docs_check.py . --require docs/decisions.md --require docs/architecture.md --require docs/changing-things.md --known-absent fixtures/
   ```

`scripts/docs_check.py` is a copy of the check that the documentation
standard defines. Its header comment differs, and it has no skip rule for
paths outside the repo. Do not edit its checks here.

## Change the documentation site

The site is a DocC catalog, `Sources/DesqueezeCore/DesqueezeCore.docc`. It
has a first page, `DesqueezeCore.md`, and one Markdown file for each
article. The API reference comes from the documentation comments in
`Sources/DesqueezeCore/`. The package has no dependency for the site: the
build uses the `docc` of Xcode.

1. Change the article, or the documentation comment. For a new article, add
   its file to the catalog, and add its `<doc:Name>` line under "Topics" on
   the first page. For a new public type, add it to a group under "Topics"
   too.
2. Hold to the rules of the site. It is for a public reader: no path on one
   Mac, and no private repo. Every command in an article was run. A fact
   that a repo document also states must agree with it. Numbers that change,
   such as test counts and timings, stay out.
3. Run the site test: `swift test --filter DocsSiteTests`. It fails when the
   first page names an article that does not exist, when an article is not
   on the first page, when a `<doc:…>` link points to no article, and when
   an article quotes a test or a repo path that does not exist.
4. Build the site: `scripts/build_docs.sh`. It writes the site to the folder
   docs inside build, which git ignores. A warning of docc is an error
   there: an unresolved link or symbol stops the build. Fix it.
5. Look at the site. The script prints the command for a web server on this
   Mac, and the command for a preview that follows each change to an
   article.

When you change a sentence, an option, a note kind, a JSON key or the match
table, change the article that describes it in the same change.

`.github/workflows/docs.yml` publishes the site to GitHub Pages on a push to
the main branch. Its header says what it needs. The runner's Xcode can be
older than yours: a warning of its `docc` fails the build there.

## Record a decision

Add a row to `docs/decisions.md` under the date of the decision: what was
decided, why, and the design section or the file that carries it. Never
delete a row. When a decision is reversed, mark the old row superseded and
add the new one.
