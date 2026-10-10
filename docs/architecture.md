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
| `SqueezeFactor.swift` | A factor: the range 1 to 4, four decimal places, the presets, the tag value `<factor> 1`, the read-back tolerance, the sentence for a wrong factor, and the hint for a comma | `SqueezeFactorTests.swift` |
| `FolderChoice.swift` | What counts as a folder: a link to a folder is that folder, a package is not one. The sentence that says why a path is no folder. | `FolderChoiceTests.swift` |
| `FolderScan.swift` | The lists of one folder: DNG files, ARW files, orphan backups. The rule for a pending ARW. | `FolderScanTests.swift` |
| `FolderScanner.swift` | `FolderSnapshot`: the lists, the tag of each DNG, the backup state, and whether the folder is writable | `FolderScannerTests.swift` |
| `FolderText.swift` | The sentences and counts about a folder: the counts line, the run button label, the folder messages, the advice about the converters. The words of the window about the originals: the label of the box, the line under it, and the run button label with the originals. | `FolderTextTests.swift`, `OriginalsTests.swift` |
| `ProcessRunner.swift` | The protocol that starts a program with no shell, and its real implementation. A program that a signal ended is an error, not an exit code. | `ProcessRunnerTests.swift` |
| `LoggingProcessRunner.swift` | The runner behind `--verbose`: each command line, its exit code, its output | `LoggingProcessRunnerTests.swift` |
| `ToolLocator.swift` | Where the three programs are, and the sentences for a missing exiftool and for the dnglab install | `ToolLocatorTests.swift` |
| `ScaleTag.swift` | `Scale`, and the three exiftool calls for `DefaultScale`: read a folder, write one file, read one file back. The one read of a DNG before its original moves to the Trash. | `ScaleTagTests.swift`, `OriginalsTests.swift`. With the real exiftool: `IntegrationTests.swift`, `DnglabIntegrationTests.swift` |
| `Backups.swift` | The `_original` backup: exists, to the Trash, restore with one rename. `trashFile`, the one way to the Trash for a work file, a leftover, and an original. The test variable `DESQUEEZE_TEST_BACKUP_FOLDER`. | `BackupsTests.swift`, `BackupTestFolderTests.swift` |
| `RawConverter.swift` | The converter protocol, the pair of converters, the names of the output and of the work file, and the Adobe converter. The rules that hold for every converter: a name that is too long, the checks before the start, the leftovers of an earlier run, the work file, the rename, and what counts as a partial output. | `RawConverterTests.swift`. With the real converter: `IntegrationTests.swift` |
| `DnglabConverter.swift` | The steps that only dnglab has: its command, the match write into the work file, the read-back, and dnglab's own words for a failure | `DnglabConverterTests.swift`. With the real dnglab: `DnglabIntegrationTests.swift` |
| `ExclusiveRename.swift` | A rename that fails when the name is taken, and the path for a volume that has no such call | `ExclusiveRenameTests.swift`, which also makes APFS and ExFAT disk images |
| `ARWFacts.swift` | The five facts about an ARW, the exiftool read that gets them, and how exiftool prints a file name | `ARWFactsTests.swift`. With the real exiftool: `DnglabIntegrationTests.swift` |
| `AdobeMatch.swift` | The match table, the five rules of a full match, the tags to write, and the compare of numbers at the read-back | `AdobeMatchTests.swift`. Against the real Adobe DNG Converter: the drift check in `DnglabIntegrationTests.swift` |
| `ConverterChoice.swift` | Which converter gets an ARW, in which order. The names of the converters and the sentences about who converts. | `ConverterChoiceTests.swift` |
| `RunPlan.swift` | The one decision for a DNG: skip, blocked, or write. The plan of a dry run, with its step for an original that would move. | `PlanTests.swift`, `OriginalsPlanTests.swift` |
| `Originals.swift` | The rule for one original (design 14.2): the function that decides "move" or "keep", the eight sentences of an original that the run did not move, the record of a file (size, modification date, file number) and its compare, for the ARW and for its DNG, and the check of the DNG | `OriginalsTests.swift`. On real files: `OriginalsDiskTests.swift` |
| `RunSummary.swift` | The counts of a run, the note for each file with its `kind`, the note of a volume that gives no folder lock, the counts line, the line about the two converters, the rule of the Lightroom line, the line about the originals, the progress value, and the cancel flag | `RunSummaryTests.swift`, `OriginalsTests.swift` |
| `FolderLock.swift` | One run in a folder at a time: the advisory lock on the folder, what each answer of the system means, the sentence of a run that did not start, the error of a lock call that failed, and the line of `--verbose` for a volume with no lock | `FolderLockTests.swift`. Its test on an ExFAT volume is a part of `ExclusiveRenameVolumeTests`, and `ExclusiveRenameTests.swift` makes and detaches the disk image. With two processes of the built tool: `TwoRunsTests.swift` in `Tests/DesqueezeCLITests/` |
| `DesqueezeJob.swift` | The run and the dry run, in order, on a fresh scan. The run holds the folder lock. The fifth step of a run that was asked to move the originals. | `DesqueezeJobTests.swift`, `PlanTests.swift`, `FolderLockTests.swift`, `OriginalsJobTests.swift`, `OriginalsPlanTests.swift`. With the real programs: `IntegrationTests.swift`, `DnglabIntegrationTests.swift` |
| `Reports.swift` | The report types and their JSON: `ScanReport`, `RunReport`, `ErrorReport`, and the one function that prints them | `ReportsTests.swift`, `OriginalsPlanTests.swift` |
| `Operations.swift` | `DesqueezeOperations`: scan, run, remove, each with a report that is ready to print | `OperationsTests.swift` |
| `InterruptWatcher.swift` | A flag that a signal sets, so a run stops after its current file | No unit test. `InterruptTests.swift` in `Tests/DesqueezeCLITests/` sends real signals to the built tool. |
| `Version.swift` | The version number of the tools | `VersionTests` in `BackupTestFolderTests.swift`, and the changelog test in `DocsCheckTests.swift` |

`Fakes.swift` and `JobHarness.swift` in the test folder are the fakes that
the unit tests share. They are not tests.

### The command line tool, `Sources/DesqueezeCLI/` and `Sources/desqueeze/`

Test files are in `Tests/DesqueezeCLITests/`.

| File | Owns | Tests |
|---|---|---|
| `Sources/DesqueezeCLI/Arguments.swift` | The parser: the commands, the options, each usage error. `--trash-originals` is the only thing that turns the option of design 14 on. | `ArgumentsTests.swift`, `OriginalsToolTests.swift` |
| `Sources/DesqueezeCLI/Commands.swift` | `DesqueezeTool`: parse, do, print. The exit codes. `ToolEnvironment`, which holds everything the tool takes from the outside. | `CommandsTests.swift`, `ExitCodeTests.swift`, `OriginalsToolTests.swift` |
| `Sources/DesqueezeCLI/TextOutput.swift` | The layout of the text for a person | `TextOutputTests.swift`, `OriginalsToolTests.swift` |
| `Sources/DesqueezeCLI/Usage.swift` | The version line, the help, and how a usage error is shown | `CommandsTests.swift`, `OriginalsToolTests.swift` |
| `Sources/DesqueezeCLI/LiveEnvironment.swift` | The real environment: the programs, the Trash, the signals, the two standard streams | No unit test. The end-to-end tests start the built tool: `EndToEndTests.swift`, `EndToEndFailureTests.swift`, `EndToEndOriginalsTests.swift`, `InterruptTests.swift`, `TwoRunsTests.swift`. |
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
| `ToolEnvironment.swift` | One tool call from its arguments to its result, through `DesqueezeOperations`. It gives the option of design 14 as `false`, always: the server never moves an original. | `InProcessTests.swift`, `ToolErrorTests.swift`, `ServerEndToEndTests.swift` |
| `ToolHandlers.swift` | The handlers for the list of tools and for a tool call, the progress messages, and the cancel of a call | `InProcessTests.swift`, `ServerEndToEndTests.swift` |
| `CallQueue.swift` | One tool call at a time. The queue closes when the client is gone. | `InProcessTests.swift`, `AnsweringTransportTests.swift` |
| `AnsweringTransport.swift` | The transport: one message is written at a time, and the program does not end with an answer owed | `AnsweringTransportTests.swift` |
| `main.swift` | One line that starts the program | The end-to-end tests |

`ServerProcess.swift` and `ServerTestCase.swift` start the built server and
speak to it with a small client that does not use the MCP library. So the
tests check the bytes on the wire.

### The window, `App/PlateworksDesqueeze/`

| File | Owns | Tests |
|---|---|---|
| `AppModel.swift` | The window's state: the folder, the factor, the box for the originals, the one job in flight, Cancel, a run that another run kept out, the detail line of a lock call that failed, the quit during a run, the launch arguments | `AppModelTests.swift` and `OriginalsModelTests.swift` in `App/PlateworksDesqueezeTests/`. `Fakes.swift` beside them holds their fakes. |
| `ContentView.swift` | The one view: the drop zone, the factor row, the box for the originals, the buttons, the progress bar, the result list | - |
| `DesqueezeApp.swift` | The app and its delegate: one window, and the reply to a quit | - |
| `Info.plist` | Written by XcodeGen from `project.yml`. A hand edit is lost. | - |

The view and the delegate have no test. Check them by hand, with the launch
arguments in `docs/changing-things.md`. The window's tests compile
`AppModel.swift` into a test bundle with no app host, so a test run starts
no app and opens no window.

## One run, step by step

`DesqueezeJob.run(folder:)` does these steps in order, one file at a time.
Each step has the rule that keeps the user's files safe. Design 4.3, 13.3,
13.9 and 14.2 are the contract.

0. **Lock the folder.** Before the scan, the run takes an advisory lock on
   the folder: it opens the folder and asks for `flock`. It holds the lock
   until it returns or throws. No lock file is made. When another run holds
   the lock, in this process or in another, the run does not start. It
   throws `FolderLock.Busy`, and each front end says the core's sentence.
   On a volume that gives no such lock, the run goes on without one, and
   its notes start with one of the kind `noFolderLock`, on the name of the
   folder. Six answers of `flock` mean "no lock": `ENOTSUP`, `EOPNOTSUPP`,
   `ENOLCK`, `EISDIR`, `ENOSYS` and `EINVAL`. `EINTR` is asked again. Any
   other error throws `FolderLock.Failed` before a file is read, and each
   front end says that the folder could not be read, with the system's
   words.
   *Safety:* two runs in one folder would take each other's work file for a
   leftover. A scan and a dry run take no lock: they change no file.
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
   over a file. A leftover file of exiftool beside the photo,
   `<base>.dng_exiftool_tmp`, stops that ARW, and the note names the file.
   So does a base name of more than 222 UTF-16 units, counted in its
   decomposed form: the name of exiftool's temporary file beside the work
   file would be longer than the 255 units that a file name can have, and
   the note says that the name is too long.
4. **Convert to a work file.** Each converter writes the hidden file
   `.<base>.desqueeze-work.dng`, not `<base>.dng`. dnglab takes the path of
   the work file. Adobe DNG Converter takes its name with `-o`. A work file
   that an earlier run left goes to the Trash first, and so does exiftool's
   leftover of that work file, `<work file>_exiftool_tmp`. Only a regular
   file is taken: a folder or a link at either name stops that ARW, and the
   note names it. *Safety:* the scan, Finder and Lightroom do not see a
   hidden file. So a run that ends hard never leaves a DNG that looks
   complete. No converter gets a name that is taken.
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
   conversion sends to the Trash. The job does not take the converter's
   word: a file moves only when its path is exactly the work file of that
   ARW. A failed conversion never touches the ARW. A work file that the
   Trash refused is named in the note.
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
12. **Move the originals, only on request.** The step exists only when the
    caller gave `trashOriginals: true`, and never for Remove. It starts
    after the tag of the last DNG, and not after a cancel. For each ARW that
    this run converted, `OriginalDecision.decide` asks five things, in
    this order: the DNG has a full match, its tag step ended at the factor,
    the DNG is the file that this run made, the DNG passes its check, and
    the ARW is the file that was converted. For the third one, the run
    recorded the size, the modification date and the file number of the DNG
    directly after the conversion, and again directly after the tag step.
    The first record must hold directly before the tag step, and the second
    one here: before the check of the DNG, and again after its exiftool
    read. After a tag step that skipped, the second record is the first
    one. The name in a DNG cannot prove whose DNG it is. The check of
    the DNG is one exiftool read: the DNG is a regular file with bytes, it
    names the ARW in `OriginalRawFileName`, and its `DefaultScale` is the
    factor. The run recorded the same three facts of the ARW before the
    conversion, and it reads them again as the last thing before the move.
    Then `BackupHandling.trashFile` moves the ARW. *Safety:* an ARW that
    fails one check stays, with an `originalKept` note. A DNG that is not
    the run's own is still tagged, and only its ARW stays. A link or a
    folder never goes. An ARW that is not there gets a note that says so.
    When the Trash refuses the file, the ARW stays: the job deletes nothing
    and tries no second way. A file beside the ARW, such as `<base>.xmp`,
    is not touched.

A cancel is honored between files, never in the middle of one. The result
has the counts and one note for each file that has something to say.

`DesqueezeJob.plan(folder:)` is the dry run. It makes the same scan, asks the
same three functions (`ConverterChoice`, `TagDecision` and
`OriginalDecision`), and changes no file. So a dry run shows what the run
that follows does when every step passes. The two differ only where a step
of the real run fails. It takes no lock, so it can read a folder in which
a run works, and it never has the `noFolderLock` note of a run. It can then
show a file in change, for example a DNG as blocked by a backup that the
run is about to clear. For the originals it reads no ARW and no DNG: it plans a run in
which every check passes.

The option has no default value in `DesqueezeJob.run`, in
`DesqueezeJob.plan` and in `DesqueezeOperations.run`. So each front end
states it. The window gives the state of its box. The tool gives its flag,
`--trash-originals`. The server gives `false`, always.

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
- **One run in a folder at a time.** The lock is on the folder, not in the
  app, so it holds between the window, the tool and the server, and between
  two runs in one process. It goes when the run ends, and when the process
  ends for any reason. A scan and a dry run are allowed while a run works,
  and their result can be of a folder in change.
- **The moment after a hard end.** After a hard end of a run, the lock is
  free at once, and a converter that the dead run started can still work
  for a moment. A run that starts in that moment can meet its work file.
  Both converters end in under half a second on the Mac of the measurement,
  and two trials showed no collision (design 13.9).
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
  settings. The first time, it starts at 1.5. It saves the factor when the
  job gives a result, so a run that did not start saves nothing: a run that
  was refused because another run works in the folder, and a run whose
  folder could not be read. A quit during a run saves the factor before the
  app ends. The launch arguments are read from the command line only.
- **One state, one message in the window.** The sentence of a run that was
  refused goes at the next click that starts a run, when another folder
  loads, and when a scan of the folder fails. A folder that could not be
  read is the newer event, so the window shows that alone, and VoiceOver
  hears the same.
- **A lock call that failed has a detail line in the window.** The run did
  not start, and the window shows "This folder could not be read." with the
  system's words below it, as the tool and the server do (design 13.9). The
  words are the core's, from `FolderLock.Failed`. The line goes when a scan
  of the folder lands, and when another folder loads. A scan that failed
  has no such line. The model gets its lock from outside, so a test gives
  one whose call fails.
- **The window never remembers the box for the originals.** It is off at
  every launch, when a folder loads, and after every run, also a run that
  was cancelled or that failed. No launch argument turns it on. A scan of
  the loaded folder does not change it.
- **The Lightroom line and the line about the two converters** are decided
  in the core (`RunSummary`). The window and the tool show them for the
  same runs, and the description of the server's tools gives a model the
  same rule. The line about the originals is made there too. It shows only
  after a run that was asked to move them.

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
| The root package | `swift test` | The core and the tool: unit tests on fakes, the docs check, the site test, the changelog test, and the tests on the real programs |
| The server package | `swift test --package-path MCPServer` | The server: the built server over its pipes, and the parts that start no server |
| The window | `xcodebuild` with the `test` action, after `xcodegen generate` | The window's state, on fakes |

The tests on the real programs copy `fixtures/sample.ARW` and
`fixtures/sample.dng` to a temporary folder first. `fixtures/` is gitignored
and is made with `scripts/make_fixtures.sh`. The script makes the DNG with
Adobe DNG Converter, or with dnglab and exiftool when that is not installed.
A test that needs a fixture or a program skips when it is absent. It does
not fail. The ARW can be any Sony ARW that dnglab and Adobe DNG Converter can
read: a test takes each value that it expects from the frame itself.

- **No fixtures:** the tests on the real programs skip. So do the end-to-end
  tests of the tool, and each server test that runs on a photo.
  `XCTSkip` in the test files is the full list.
- **No dnglab:** the tests in `DnglabIntegrationTests.swift` skip.
- **No Adobe DNG Converter:** `IntegrationTests.swift` and the drift check
  skip. So do the end-to-end tests of the tool, and the end-to-end tests of
  the server that run on a photo.
- **No exiftool:** all of these skip, and the server's tool-error tests too.
- **A frame that the match table does not cover:** the drift check and the
  tests of the real dnglab match skip. Each one says: "This test needs a
  frame that the match table covers: a Sony A7S III, compressed raw, ISO 50
  or 80 to 12800, adapted lens." The other tests on the real programs still
  run. With both converters installed, Adobe DNG Converter converts such a
  frame, and the end-to-end tests expect that.
- **Two more skips:** the disk-image tests in `ExclusiveRenameTests.swift`
  and `FolderLockTests.swift` skip when `hdiutil` cannot make or attach an
  image. One server test skips on a Mac that is too fast for it, and says
  so.

**The drift check** is `AdobeDriftTests` in `DnglabIntegrationTests.swift`. It
converts the fixture with Adobe DNG Converter and with the app's dnglab
path, and compares every matched tag. It fails when a new version of either
converter, or new camera firmware, changes a value. It needs a fixture frame
that the match table covers. The helper `factsOfACoveredFrame` decides that
with no code of the product: it asks exiftool for each fact, and reads the
data file of the A7S III. So a broken facts reader fails the check, and does
not skip it. A new camera must be added to that helper.

**The docs check** is `DocsCheckTests.swift`. It runs
`scripts/docs_check.py`. So `swift test` fails when `README.md`, `CLAUDE.md`,
`AGENTS.md` or a document at the top of `docs/` quotes a path that does not
exist.

**The site test** is `Tests/DesqueezeCoreTests/DocsSiteTests.swift`. It reads
the source of the documentation site, the DocC catalog
`Sources/DesqueezeCore/DesqueezeCore.docc`. It fails when the first page
names an article that does not exist, when a link between two pages points
to no page, and when a page quotes a test or a path of the repo that does
not exist. It does not build the site.

**The site build** is `scripts/build_docs.sh`. It builds the site with the
`docc` of Xcode, and it must end with no warning. No suite runs it: run it
after a change to an article or to a documentation comment.

**Two workflows** are in `.github/workflows/`. `tests.yml` runs the three
suites on every push and on every pull request. `docs.yml` builds the site
with `scripts/build_docs.sh` and publishes it to GitHub Pages. Both first
passed on 2026-10-10. The runner has no sample photo and no Adobe DNG
Converter, so the tests on the real programs skip there: the header of
`tests.yml` says what a green run proves.

**No test reaches the real Trash.** A unit test gives `FileBackups` its own
function. A test that starts a built tool sets
`DESQUEEZE_TEST_BACKUP_FOLDER`. The window's tests use fakes, and they do
not read or write the saved settings. A test of the folder lock takes the
system's lock on a temporary folder: the lock makes no file.

**By hand:** the acceptance pass of design 9, on a copy of a shoot folder,
and one photo opened in Lightroom at each factor. No test can do those.

## Cross-repo dependencies

None in code. The documentation standard and the writing standard that this
repo follows are kept outside it. `docs/README.md` names them.
