# Testing

The three test suites, the fixtures, what skips, and the rules that keep a test from a real photo and from the real Trash.

## Overview

Run all three suites before you say that a change is done. Run each command
from the root of the repo.

```bash
swift test
swift test --package-path MCPServer
xcodegen generate
xcodebuild -project PlateworksDesqueeze.xcodeproj -scheme PlateworksDesqueeze -derivedDataPath build test
```

| Suite | Command | Covers |
|---|---|---|
| The root package | `swift test` | The core and the command line tool: unit tests on fakes, the tests on the real programs, the end-to-end tests of the built tool, and the checks of the documents |
| The server package | `swift test --package-path MCPServer` | The MCP server: the built server over its pipes, and the parts that start no server. The first run fetches the MCP library, so it needs a network connection. |
| The window | `xcodebuild` with the `test` action, after `xcodegen generate` | The state of the window, on fakes |

The view of the window has no test. Check it by hand, with the launch
arguments that `docs/changing-things.md` in the repo lists.

## Three kinds of test

**Unit tests on fakes.** ``DesqueezeJob`` depends on protocols:
``ScaleTagging``, ``RawConverter``, ``BackupHandling`` and
``ARWFactsReading``. Each program is started through one more protocol,
``ProcessRunner``. A unit test gives the code a fake for each one. So it
needs no exiftool, no converter and no photo, and it can make each failure
happen: a write that fails, a Trash that refuses, a converter that a signal
ends. The job also takes the function that reads the ``FileRecord`` of a
file, so a test can make an ARW change during a run with no disk. The fakes
are in `Tests/DesqueezeCoreTests/Fakes.swift`.

Many unit tests pin the exact arguments of a call to exiftool or to a
converter. A change to a command line fails a test first.

**Tests on the real programs.** These run the real exiftool, dnglab and
Adobe DNG Converter on one ARW and one DNG. They prove what a fake cannot:
that the programs do what the code expects. Each test copies the fixtures to
a temporary folder first.

**End-to-end tests.** These start the built `desqueeze`, or the built
`desqueeze-mcp`, as a separate process, and read what it prints. The tests
of the server speak to it with a small client that does not use the MCP
library, so they check the bytes on the wire.

## The fixtures

The tests on the real programs need two files in `fixtures/`: `sample.ARW`
and `sample.dng`. The folder is not in the repo, because a photo is private.
Make it with one ARW of your own:

```bash
scripts/make_fixtures.sh "/path/to/one file.ARW"
```

The script copies your ARW and does not change it. It makes the DNG with
Adobe DNG Converter. When that is not in the Applications folder, it makes
the DNG with dnglab, and exiftool writes the name of the ARW into it, as
the tool does. Every test passes with either DNG. With neither program, the
script stops before it copies a file.

`.gitignore` ignores `fixtures/`, and also every ARW, every DNG and every
backup of a DNG in the tree. Never commit a photo.

Any Sony ARW that dnglab and Adobe DNG Converter can read works. A test
takes each value that it expects from the frame itself. The drift check and
the tests of the real dnglab match need a frame that the match table covers:
a Sony A7S III, compressed raw, ISO 50 or 80 to 12800, from an adapted lens.
With another frame they skip, and the other tests still run. Say in your
pull request which tests skipped.

## What skips, and why

A test that needs a fixture or a program skips when it is absent. It does
not fail. So a run with no fixtures passes, and proves less. Read which
tests skipped.

| Absent | What skips |
|---|---|
| `fixtures/` | Every test on the real programs, the end-to-end tests of the tool, and each test of the server that runs on a photo |
| dnglab | The tests of the real dnglab conversion, and the drift check |
| Adobe DNG Converter | The tests of the real Adobe conversion, the tests of the real exiftool in `Tests/DesqueezeCoreTests/IntegrationTests.swift`, the drift check, the end-to-end tests of the tool, and the end-to-end tests of the server that run on a photo |
| exiftool | All of the above, and the tests of the tool errors of the server |
| A frame in `fixtures/` that the match table covers | The drift check, and the tests of the real dnglab match |

Two more kinds of test can skip. The tests that make APFS and ExFAT disk
images, for the rename and for the folder lock, skip when `hdiutil` cannot
make or attach an image. One test of the server
skips on a Mac that is too fast for it, and says so.

To list the skipped tests of a run:

```bash
swift test 2>&1 | grep -i "skipped"
```

A suite whose tests all skipped still reads as passed, so this list is the
only place that shows a skip.

## The rules for a test

**Write the test first, and see it fail.** A behavioral test counts only
after it fails against a break. When you add a test to code that exists
already, break the code for a moment, see the test fail for the reason that
you expect, and restore the code.

**Never test on real photos.** Never run the tool, the server, a test or
exiftool on a folder of photos that you care about. Copy the folder first.

**No test reaches the real Trash.**

- In a unit test, give ``FileBackups/init(trash:)`` a function of your own.
  The parameter has no default, so no test reaches the Trash by leaving it
  out.
- A test that starts the built tool or the built server sets the
  environment variable `DESQUEEZE_TEST_BACKUP_FOLDER` to a temporary folder
  that exists. Each discarded file then goes to that folder. The value must
  be an absolute path to a folder that exists. With any other value, the
  tool stops before it reads a photo folder.
- When the variable is set, the tool says so on standard error: "Test mode:
  every file that would go to the Trash goes to …." That is each backup,
  each work file, and each original that a run moves on request.

The variable is for tests only. No help text names it.

**No test moves an original to the real Trash.** An original goes through
the same function as a backup, ``BackupHandling/trashFile(_:)``, so the two
rules above hold for it too. The tests of the option are in
`Tests/DesqueezeCoreTests/OriginalsTests.swift`,
`Tests/DesqueezeCoreTests/OriginalsJobTests.swift` and
`Tests/DesqueezeCoreTests/OriginalsPlanTests.swift`, on fakes.
`Tests/DesqueezeCoreTests/OriginalsDiskTests.swift` has real files in a
temporary folder, with a fake converter and a fake tag, so it never skips.
A test on fakes gives the job paths that do not exist, and it cannot see a
delete. With the real programs,
`testARealRunWithTheOptionOnLeavesTheDNGAndMovesItsARWToTheInjectedTrash`
moves a copy of the fixture into a folder of the test. The tests of the
built tool are in `Tests/DesqueezeCLITests/EndToEndOriginalsTests.swift`.
They skip when dnglab does not get the fixture frame, so they never start
Adobe DNG Converter.

For this option, a test that passes is not enough. Break the rule in the
code, see the test fail, and restore the code. Five breaks to try first:

| Break | The test that catches it |
|---|---|
| The option is treated as on when it is off. | `testWithTheOptionOffAConversionThatPassedMovesNoARWAndAsksTheDiskNothing` |
| The compare of the ARW with its record is left out. | `testLine4AnARWThatChangedDuringTheRunStays` |
| The step runs after a cancel. | `testACancelBeforeTheFifthStepMovesNoARWAndTheRunIsStopped` |
| The compare of the DNG with its two records is left out. | `testLine6ADNGThatWasReplacedBetweenItsConversionAndItsTagStepKeepsItsOriginalAndIsStillTagged`, `testARealDNGOfAnotherFrameThatTakesTheNameAfterTheConversionKeepsTheARW` |
| A delete follows a refusal of the Trash. | `testATrashThatRefusesLeavesTheRealARWInTheFolderWithItsBytes` |

One rule has no behavioral test: the option has no default value. Every
caller in the code states the value, so a default changes no result.
`Tests/DesqueezeCoreTests/NoDefaultForTheOptionTests.swift` reads the Swift
files of the product, and fails for a default.

**No test reads or writes the saved settings of the app.** The tests of the
window give the model its own functions for the saved factor. The box for
the originals is never saved: `testTheBoxIsNeverSavedAndTheNextModelStartsWithItOff`
holds that.

**The tests of the window start no app.** They compile the model of the
window into a test bundle with no app host. A test run opens no window.

## Checks of the documents

Three checks run inside `swift test`:

- The docs check, `scripts/docs_check.py`, fails when a document quotes a
  path that does not exist, or when a Markdown file under `docs/` has no row
  in `docs/README.md`.
- The changelog test fails when the newest entry of `CHANGELOG.md` is not
  the version that the tools print.
- The site test, `DocsSiteTests`, reads the source of this site. It fails
  when the first page names an article that does not exist, when a link
  between two pages points to no page, and when a page quotes a test or a
  path of the repo that does not exist.

## The drift check

`AdobeDriftTests` is the guard of the match table. It converts the fixture
with Adobe DNG Converter and with dnglab plus the match, and compares all
nine tags. Run it after a new version of either converter, and after new
camera firmware:

```bash
swift test --filter AdobeDriftTests
```

<doc:AddingACamera> says how to read its result.

The check skips for a frame that the match table does not cover. It decides
that with no code of the tool: the helper `factsOfACoveredFrame` asks
exiftool for each fact of the frame, and reads the data file. So a reader of
the facts that breaks fails the check. It does not turn the check into a
skip.

## The folder lock

One run works in a folder at a time, and ``FolderLock`` holds that rule.
Its tests are in `Tests/DesqueezeCoreTests/FolderLockTests.swift`. The unit
tests give the lock three fake system calls, so they need no second
process, and they drive each answer of the lock call: the lock, a lock that
another run holds, a volume with no lock, a call that a signal broke, and
any other error. Other tests take the system's own lock on a temporary folder: the
lock makes no file. `Tests/DesqueezeCLITests/TwoRunsTests.swift` starts the
built tool twice on one folder, and the second run must not start.

A test of a front end holds the lock itself, and then asks the front end
for a run. That is the real case, because the lock holds between two runs
in one process as it does between two processes.

## What no test can do

The acceptance pass is by hand: a copy of a real shoot folder in the window,
each factor, a second run, Remove, and one photo opened in Lightroom at each
factor. The design lists the steps, in its section 9. The real Trash is also
checked by hand, and so is the box for the originals in the window: tick it
only on a copy of a folder, because the window uses the real Trash.

The download has no suite either. `scripts/make_release.sh --local` makes
the app with exiftool and dnglab inside, and stops when a program inside
does not give its pinned version. A run in the window of that app, on
copies, is by hand. The steps of the script that need the Developer ID run
only on the Mac that has it. `docs/changing-things.md` in the repo has the
steps.
