# Architecture

Read this to learn which file owns which behavior and which test covers it.
For the rules that must not break, read `CLAUDE.md`. For the reasons behind
the shape, read `docs/decisions.md`. For step-by-step changes, read
`docs/changing-things.md`. The contract for all behavior is the design,
`docs/superpowers/specs/2026-10-05-desqueeze-design.md`.

## The shape

One core, three front ends, three external programs.

```
   a person               a person or a script         an MCP client
      │                          │                          │
      ▼                          ▼                          ▼
  the window                 desqueeze                 desqueeze-mcp
  App/PlateworksDesqueeze    Sources/desqueeze         MCPServer/Sources/desqueeze-mcp
  SwiftUI and AppKit         Sources/DesqueezeCLI      the MCP library, on standard
      │                          │                     input and standard output
      │                          │                          │
      │                          └──── DesqueezeOperations ─┘
      │                                scan, run, remove
      │                                ScanReport and RunReport, printed as JSON
      │                                       │
      ▼                                       ▼
  ┌───────────────────────── DesqueezeCore ─────────────────────────┐
  │  Sources/DesqueezeCore, Foundation only                          │
  │                                                                  │
  │  FolderScanner ── scan ──▶ FolderSnapshot                        │
  │  DesqueezeJob ─── run ───▶ RunSummary      plan ──▶ RunPlan      │
  │       │                │                        │                │
  │  ScaleTagging     RawConverters            BackupHandling        │
  │  ScaleTag         DnglabConverter          FileBackups           │
  │                   AdobeConverter                │                │
  │       │                │                        ▼                │
  │       └── ProcessRunner (no shell) ──┐       the Trash           │
  └──────────────────────────────────────┼──────────────────────────┘
                 ┌──────────────┬────────┴─────────┐
                 ▼              ▼                  ▼
             exiftool        dnglab        Adobe DNG Converter
             reads and       converts      converts the photos that
             writes tags     ARW to DNG    dnglab cannot match (optional)
```

The core holds every rule. A front end collects input, calls the core, and
shows what the core returns. The window calls `FolderScanner` and
`DesqueezeJob`. The tool and the server call `DesqueezeOperations`, which joins
the same two types to the report types. So all three front ends do the same
work on a folder.

The three external programs are not part of this repo and are not inside
the built app. The core finds them on the Mac at run time
(`Sources/DesqueezeCore/ToolLocator.swift`):

| Program | Where the core looks | When it is missing |
|---|---|---|
| exiftool | `/opt/homebrew/bin`, then `/usr/local/bin`, then each folder of `PATH` | No front end can work. Each one gives the install command. |
| dnglab | The same folders | Adobe DNG Converter converts every ARW. |
| Adobe DNG Converter | `/Applications`. The window also asks Launch Services for the app with the bundle identifier `com.adobe.DNGConverter`. | dnglab converts every ARW. A photo with no full match gets a note. |

With neither converter, the ARW files wait and the DNG files still run.

## The two packages

| Package | Manifest | Holds | Third-party code |
|---|---|---|---|
| The root package | `Package.swift` | The library `DesqueezeCore`, the library `DesqueezeCLI`, the executable `desqueeze`, and their tests | None |
| The server package | `MCPServer/Package.swift` | The executable `desqueeze-mcp` and its tests. It takes `DesqueezeCore` from the root package by path. | The MCP library for Swift, swift-sdk, and the six packages that it brings |

The server is its own package for one reason. In the root manifest, every
build of the core and every Xcode build of the app would fetch the MCP
library and its six packages. In a package of its own, the root package and
the app stay free of third-party code, at build time too. The library is
pinned to one minor version, because it is not yet at 1.0.
`THIRD_PARTY_NOTICES.md` lists each package with its version and license.

The app is not a package. XcodeGen writes the Xcode project from
`project.yml`, and the project file is not in git. The app target links
`DesqueezeCore` from the root package.

## Module map

Each row was checked against the code. A dash in the last column means that
no test covers the file.

### The core, `Sources/DesqueezeCore/`

Test files are in `Tests/DesqueezeCoreTests/`.

| File | Owns | Tests |
|---|---|---|
| `SqueezeFactor.swift` | A factor: the range 1 to 4, four decimal places, the presets, the tag value `<factor> 1`, the read-back tolerance, and the sentence for a wrong factor | `SqueezeFactorTests.swift` |
| `FolderChoice.swift` | What counts as a folder: a link to a folder is that folder, a package is not one. The sentence that says why a path is no folder. | `FolderChoiceTests.swift` |
| `FolderScan.swift` | The lists of one folder: DNG files, ARW files, orphan backups. The rule for a pending ARW. | `FolderScanTests.swift` |
| `FolderScanner.swift` | `FolderSnapshot`: the lists, the tag of each DNG, the backup state, and whether the folder is writable | `FolderScannerTests.swift` |
| `FolderText.swift` | The sentences and counts about a folder: the counts line, the run button label, the folder messages, the advice about the converters | `FolderTextTests.swift` |
| `ProcessRunner.swift` | The protocol that starts a program with no shell, and its real implementation. A program that a signal ended is an error, not an exit code. | `ProcessRunnerTests.swift` |
| `LoggingProcessRunner.swift` | The runner behind `--verbose`: each command line, its exit code, its output | `LoggingProcessRunnerTests.swift` |
| `ToolLocator.swift` | Where the three programs are, and the sentences for a missing exiftool and for the dnglab install | `ToolLocatorTests.swift` |
| `ScaleTag.swift` | `Scale`, and the three exiftool calls for `DefaultScale`: read a folder, write one file, read one file back | `ScaleTagTests.swift`. With the real exiftool: `IntegrationTests.swift` |
| `Backups.swift` | The `_original` backup: exists, to the Trash, restore with one rename. The test variable `DESQUEEZE_TEST_BACKUP_FOLDER`. | `BackupsTests.swift`, `BackupTestFolderTests.swift` |
| `RawConverter.swift` | The converter protocol, the pair of converters, the names of the output and of the work file, the rules that hold for every converter, and the Adobe converter | `RawConverterTests.swift`. With the real converter: `IntegrationTests.swift` |
| `DnglabConverter.swift` | The dnglab conversion: the work file, the tag write, the read-back, the rename | `DnglabConverterTests.swift`. With the real dnglab: `DnglabIntegrationTests.swift` |
| `ExclusiveRename.swift` | A rename that fails when the name is taken, and the path for a volume that has no such call | `ExclusiveRenameTests.swift`, which also makes APFS and ExFAT disk images |
| `ARWFacts.swift` | The five facts about an ARW, the exiftool read that gets them, and how exiftool prints a file name | `ARWFactsTests.swift` |
| `AdobeMatch.swift` | The match table, the five rules of a full match, the tags to write, and the compare of numbers at the read-back | `AdobeMatchTests.swift`. Against the real Adobe DNG Converter: the drift check in `DnglabIntegrationTests.swift` |
| `ConverterChoice.swift` | Which converter gets an ARW, in which order. The names of the converters and the sentences about who converts. | `ConverterChoiceTests.swift` |
| `RunPlan.swift` | The one decision for a DNG: skip, blocked, or write. The plan of a dry run. | `PlanTests.swift` |
| `RunSummary.swift` | The counts of a run, the note for each file with its `kind`, the counts line, the progress value, and the cancel flag | `RunSummaryTests.swift` |
| `DesqueezeJob.swift` | The run and the dry run, in order, on a fresh scan | `DesqueezeJobTests.swift`, `PlanTests.swift`. With the real programs: `IntegrationTests.swift`, `DnglabIntegrationTests.swift` |
| `Reports.swift` | The report types and their JSON: `ScanReport`, `RunReport`, `ErrorReport`, and the one function that prints them | `ReportsTests.swift` |
| `Operations.swift` | `DesqueezeOperations`: scan, run, remove, each with a report that is ready to print | `OperationsTests.swift` |
| `InterruptWatcher.swift` | A flag that a signal sets, so a run stops after its current file | No unit test. `InterruptTests.swift` in `Tests/DesqueezeCLITests/` sends real signals to the built tool. |
| `Version.swift` | The version number of the tools | `VersionTests` in `BackupTestFolderTests.swift`, and the changelog test in `DocsCheckTests.swift` |

`Fakes.swift` and `JobHarness.swift` in the test folder are the fakes that
the unit tests share. They are not tests.

### The command line tool, `Sources/DesqueezeCLI/` and `Sources/desqueeze/`

Test files are in `Tests/DesqueezeCLITests/`.

| File | Owns | Tests |
|---|---|---|
| `Sources/DesqueezeCLI/Arguments.swift` | The parser: the commands, the options, each usage error | `ArgumentsTests.swift` |
| `Sources/DesqueezeCLI/Commands.swift` | `DesqueezeTool`: parse, do, print. The exit codes. `ToolEnvironment`, which holds everything the tool takes from the outside. | `CommandsTests.swift`, `ExitCodeTests.swift` |
| `Sources/DesqueezeCLI/TextOutput.swift` | The layout of the text for a person | `TextOutputTests.swift` |
| `Sources/DesqueezeCLI/Usage.swift` | The version line, the help, and how a usage error is shown | `CommandsTests.swift` |
| `Sources/DesqueezeCLI/LiveEnvironment.swift` | The real environment: the programs, the Trash, the signals, the two standard streams | No unit test. The end-to-end tests start the built tool: `EndToEndTests.swift`, `EndToEndFailureTests.swift`, `InterruptTests.swift`. |
| `Sources/desqueeze/main.swift` | One line that starts the tool | The same end-to-end tests |

`BuiltTool.swift` starts the built tool for the end-to-end tests, and
`ToolHarness.swift` holds the fake programs for the others.

### The MCP server, `MCPServer/Sources/desqueeze-mcp/`

Test files are in `MCPServer/Tests/DesqueezeMCPTests/`.

| File | Owns | Tests |
|---|---|---|
| `Program.swift` | The program: its two flags, the test variable, the start of the server, the signals | `InProcessTests.swift`, `CommandLineTests.swift` |
| `Tools.swift` | The three tools as a client sees them: names, descriptions, argument schemas, annotations | `ServerEndToEndTests.swift`, through the built server |
| `ToolCall.swift` | The check of the arguments of one call | `ToolErrorTests.swift`, through the built server |
| `ToolEnvironment.swift` | One tool call from its arguments to its result, through `DesqueezeOperations` | `InProcessTests.swift`, `ToolErrorTests.swift`, `ServerEndToEndTests.swift` |
| `ToolHandlers.swift` | The handlers for the list of tools and for a tool call, the progress messages, and the cancel of a call | `InProcessTests.swift`, `ServerEndToEndTests.swift` |
| `CallQueue.swift` | One tool call at a time. The queue closes when the client is gone. | `InProcessTests.swift` |
| `AnsweringTransport.swift` | The transport: one message is written at a time, and the program does not end with an answer owed | `AnsweringTransportTests.swift` |
| `main.swift` | One line that starts the program | The end-to-end tests |

`ServerProcess.swift` and `ServerTestCase.swift` start the built server and
speak to it with a small client that does not use the MCP library. So the
tests check the bytes on the wire.

### The window, `App/PlateworksDesqueeze/`

| File | Owns | Tests |
|---|---|---|
| `AppModel.swift` | The window's state: the folder, the factor, the one job in flight, Cancel, the quit during a run, the launch arguments | `AppModelTests.swift` in `App/PlateworksDesqueezeTests/` |
| `ContentView.swift` | The one view: the drop zone, the factor row, the buttons, the progress bar, the result list | - |
| `DesqueezeApp.swift` | The app and its delegate: one window, and the reply to a quit | - |
| `Info.plist` | Written by XcodeGen from `project.yml`. A hand edit is lost. | - |

The view and the delegate have no test. Check them by hand, with the launch
arguments in `docs/changing-things.md`. The window's tests compile
`AppModel.swift` into a test bundle with no app host, so a test run starts
no app and opens no window.

## One run, step by step

`DesqueezeJob.run(folder:)` does these steps in order, one file at a time.
Each step has the rule that keeps the user's files safe. Design 4.3 and
13.3 are the contract.

1. **Scan.** The run reads the top level of the folder itself. It never takes
   an earlier scan from a front end. Subfolders and hidden files are not
   read. *Safety:* a read-only folder gets one note, and no file is tried.
   Each orphan backup is named first and is never touched.
2. **Choose a converter for each pending ARW.** When dnglab is installed, one
   exiftool read gets the five facts of up to 200 files. `ConverterChoice`
   gives each ARW its list of converters. *Safety:* the read changes no
   file. An ARW with no facts has no full match.
3. **Check before the converter starts.** *Safety:* when anything has the name
   `<base>.dng`, the converter does not start. Neither converter may write
   over a file. A leftover file of exiftool beside the photo stops that ARW,
   and the note names the file.
4. **Convert to a work file.** The converter writes the hidden file
   `.<base>.desqueeze-work.dng`, not `<base>.dng`. A work file that an
   earlier run left goes to the Trash first, and so does exiftool's leftover
   of that work file. *Safety:* the scan, Finder and
   Lightroom do not see a hidden file. So a run that ends hard never leaves a
   DNG that looks complete.
5. **Match, for dnglab only.** One exiftool call writes Adobe's values and
   `OriginalRawFileName` into the work file. A second call reads them back.
   *Safety:* the conversion passes only when every value reads back.
6. **Give the DNG its name.** A rename moves the work file to `<base>.dng`
   and fails when anything has that name. *Safety:* a DNG that another
   program made in the meantime is never replaced. On a volume with no such
   rename, such as ExFAT, the app checks the name and then renames. That is
   a known limit (design 13.9).
7. **When a conversion fails.** The work file goes to the Trash, and the next
   converter in the list gets the ARW. The next converter is not tried when
   the failure holds for every converter: the name is taken, a leftover file
   is in the way, or the Trash refused the work file. It is also not tried
   after a cancel. *Safety:* the work file is the only file that a failed
   conversion sends to the Trash. The ARW is never changed, moved or
   deleted. A work file that the Trash refused is named in the note.
8. **Decide for each DNG.** The found DNG files come first, then the new
   ones. A DNG at the factor is skipped. A DNG with an older backup beside
   it is blocked. Any other DNG is written. *Safety:* the run asks for the
   backup again at the moment of each file. An unknown scale is never
   skipped.
9. **Write the tag.** exiftool writes `DefaultScale` and keeps the earlier file
   as `<name>.dng_original`. *Safety:* the backup is the photo as it was.
10. **Read the tag back.** *Safety:* the write counts only when the value that
    is read back is within 0.00005 of the factor.
11. **Clear the backup.** After a good read-back, the backup goes to the
    Trash. After a failed write or check, one rename restores the backup.
    *Safety:* nothing is deleted. When the Trash refuses a backup, it stays
    beside the file and a note says so.

A cancel is honored between files, never in the middle of one. The result
has the counts and one note for each file that has something to say.

`DesqueezeJob.plan(folder:)` is the dry run. It makes the same scan, asks the
same two functions (`ConverterChoice` and `TagDecision`), and changes no
file. So a dry run and the run that follows cannot disagree.

## Runtime behavior worth knowing

- **No shell.** Each program gets its arguments as an array. A path with
  spaces is one argument.
- **Signals.** Control-C, a plain `kill` and a closed Terminal window set the
  cancel flag of the tool. The run stops after its current file and prints
  the result so far. The server does the same for the call in work, then
  exits 0. Both ignore a closed pipe.
- **A program in work does not get the Control-C.** Each program starts in a
  process group of its own. A program that is only just starting can still
  get it. That file is then reported as failed and is left as it was.
- **The server runs one tool call at a time,** on a queue with a thread of
  its own. When standard input closes, the call in work completes and is
  answered. A call that waits does not start.
- **Standard output is the result only.** The tool prints text for a person,
  or exactly one JSON object with `--json`. Progress and messages go to
  standard error. For the server, standard output is the protocol.
- **exiftool prints a control character in a file name as a period.** The
  core finds a row by the printed name. Two files whose names print the same
  get no row: an unknown scale for a DNG, and no full match for an ARW.
- **The window scans again** when the app becomes active, and after every
  run. A scan that lands late is discarded.
- **The window remembers the factor** of the last run in the app's saved
  settings. The launch arguments are read from the command line only.

## Delivery

Nothing is hosted, and there is no release yet. Each of the three is built
from source on the Mac that uses it (design 12.3). The commands are in
`README.md`.

| Built thing | Build | Where it goes |
|---|---|---|
| The app, `Desqueeze.app` | `xcodegen generate`, then `xcodebuild` with the Release configuration | The Applications folder |
| `desqueeze` | `swift build -c release` | A folder on the `PATH`. The maintainer uses `~/.local/bin/`. |
| `desqueeze-mcp` | `swift build -c release --package-path MCPServer` | The same folder. The MCP client is given the absolute path. |

The build signs the app ad hoc, so it runs on the Mac that built it. It is
not signed with a Developer ID and is not notarized. The app is not
sandboxed, because a sandboxed app cannot start the three programs.
`project.yml` has no entitlements file, on purpose.

There are no environment variables for normal use. The tools read `PATH` to
find exiftool and dnglab. `DESQUEEZE_TEST_BACKUP_FOLDER` is for tests only:
it sends each discarded file to a folder in place of the Trash.

## The verification harness

| Suite | Command | Covers |
|---|---|---|
| The root package | `swift test` | The core and the tool: unit tests on fakes, the docs check, the changelog test, and the tests on the real programs |
| The server package | `swift test --package-path MCPServer` | The server: the built server over its pipes, and the parts that start no server |
| The window | `xcodebuild` with the `test` action, after `xcodegen generate` | The window's state, on fakes |

The tests on the real programs copy `fixtures/sample.ARW` and
`fixtures/sample.dng` to a temporary folder first. `fixtures/` is gitignored
and is made with `scripts/make_fixtures.sh`. A test that needs a fixture or a
program skips when it is absent. It does not fail.

- **No fixtures:** the tests on the real programs skip. So do the end-to-end
  tests of the tool, and each server test that runs on a photo.
  `XCTSkip` in the test files is the full list.
- **No dnglab:** the tests in `DnglabIntegrationTests.swift` skip.
- **No Adobe DNG Converter:** `IntegrationTests.swift` and the drift check
  skip. So do the end-to-end tests of the tool, and the end-to-end tests of
  the server that run on a photo.
- **No exiftool:** all of these skip, and the server's tool-error tests too.
- **Two more skips:** the disk-image tests in `ExclusiveRenameTests.swift`
  skip when `hdiutil` cannot make or attach an image. One server test skips
  on a Mac that is too fast for it, and says so.

**The drift check** is `AdobeDriftTests` in `DnglabIntegrationTests.swift`. It
converts the fixture with Adobe DNG Converter and with the app's dnglab
path, and compares every matched tag. It fails when a new version of either
converter, or new camera firmware, changes a value.

**The docs check** is `DocsCheckTests.swift`. It runs
`scripts/docs_check.py`. So `swift test` fails when `README.md`, `CLAUDE.md`,
`AGENTS.md` or a document at the top of `docs/` quotes a path that does not
exist.

**No test reaches the real Trash.** A unit test gives `FileBackups` its own
function. A test that starts a built tool sets
`DESQUEEZE_TEST_BACKUP_FOLDER`. The window's tests use fakes, and they do
not read or write the saved settings.

**By hand:** the acceptance pass of design 9, on a copy of a shoot folder,
and one photo opened in Lightroom at each factor. No test can do those.

## Cross-repo dependencies

None in code. The documentation standard and the writing standard that this
repo follows are kept outside it. `docs/README.md` names them.
