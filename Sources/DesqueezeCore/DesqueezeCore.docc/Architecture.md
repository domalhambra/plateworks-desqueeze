# Architecture

One core, three front ends and three external programs, and the path of one run through them.

## Overview

```
  the window            desqueeze              desqueeze-mcp
  SwiftUI, AppKit       Foundation only        the MCP library
        |                    |                       |
        |                    +- DesqueezeOperations -+
        |                       ScanReport, RunReport, as JSON
        |                                |
  +-----v--------------------------------v-----------------+
  | DesqueezeCore                                          |
  |   FolderScanner -> FolderSnapshot                      |
  |   DesqueezeJob  -> RunSummary, RunPlan                 |
  |   ScaleTagging     RawConverter     BackupHandling     |
  |   ProcessRunner starts each program, with no shell     |
  +--------+------------------+-------------------+--------+
           |                  |                   |
       exiftool            dnglab        Adobe DNG Converter
```

**The core holds every rule.** `DesqueezeCore` imports Foundation only. It
decides what a folder holds, which converter gets an ARW, when a file is
skipped or blocked, and what each sentence says.

**A front end holds no rule about files.** It collects input, calls the
core, and shows what the core returns. The window calls ``FolderScanner``
and ``DesqueezeJob``. The command line tool and the MCP server call
``DesqueezeOperations``, which joins the same two types to the report types
``ScanReport`` and ``RunReport``. So the three front ends do the same work
on a folder, and the tool and the server print the same JSON.

**Three external programs do the file work.** exiftool reads and writes the
tags. dnglab converts an ARW to a DNG. Adobe DNG Converter is the optional
backup for a photo that dnglab cannot match. None of them is in the repo or
in the built app. ``ToolLocator`` finds them on the Mac at run time.

## The parts of the core

| Part | Types | Job |
|---|---|---|
| The scan | ``FolderChoice``, ``FolderScan``, ``FolderScanner``, ``FolderSnapshot`` | What counts as a folder. The DNG files, the pending ARW files and the orphan backups of its top level. The tag of each DNG. |
| The factor and the tag | ``SqueezeFactor``, ``Scale``, ``ScaleTagging``, ``ScaleTag`` | A valid factor, and the three exiftool calls for `DefaultScale`: read a folder, write one file, read one file back. |
| The backup | ``BackupHandling``, ``FileBackups`` | The `_original` file that exiftool keeps: is it there, send it to the Trash, put it back. |
| The converters | ``RawConverter``, ``DnglabConverter``, ``AdobeConverter``, ``ConverterOutput``, ``ExclusiveRename`` | One ARW to one DNG, through a hidden work file and a rename that never replaces. |
| The match | ``ARWFacts``, ``AdobeMatch``, ``ConverterChoice`` | The facts of an ARW, the tags that make a dnglab DNG render as Adobe's, and which converter gets the ARW. |
| The job | ``DesqueezeJob``, ``FolderLock``, ``TagDecision``, ``RunPlan``, ``RunSummary``, ``FileNote`` | The run and the dry run, in order, with the counts and one note for each file that has something to say. One run in a folder at a time. |
| The originals | ``OriginalDecision``, ``FileRecord``, ``OriginalState``, ``DNGCheck``, ``OriginalCheckTags`` | Whether an original ARW moves to the Trash, when the run was asked to move the originals: the function that decides, the record of a file and its compare, and the check of the DNG. |
| The reports | ``DesqueezeOperations``, ``ScanReport``, ``RunReport``, ``ReportJSON`` | Scan, run and remove, each with a report that is ready to print as JSON. |
| The text | ``FolderText``, ``ConverterText`` | Each sentence that more than one front end says, made once. |
| The programs | ``ProcessRunner``, ``LoggingProcessRunner``, ``ToolLocator`` | Start a program with no shell, show each command for `--verbose`, and find the three programs. |

Three choices shape the code:

- **File work is behind protocols.** ``DesqueezeJob`` depends on
  ``ScaleTagging``, ``RawConverter``, ``BackupHandling`` and
  ``ARWFactsReading``. The unit tests give it fakes, so they need no
  exiftool, no converter and no Trash.
- **No shell.** ``ProcessRunner`` gives a program its arguments as an array.
  A path with spaces is one argument.
- **A sentence is made once.** A front end reads the `kind` of a note, and
  never the English sentence. So a sentence can change with no break in a
  script.

## One run, step by step

``DesqueezeJob/run(folder:factor:convert:trashOriginals:remove:cancel:progress:)``
works on one file at a time, in this order. <doc:SafetyRulesForCode> has the rule
behind each step.

1. **Lock, then scan.** The run takes the ``FolderLock`` of the folder and
   holds it to its end. When another run holds it, the run throws
   ``FolderLock/Busy`` and has read nothing. On a volume that gives no lock
   for a folder, the run goes on, and its notes start with one of the kind
   `noFolderLock`. Any other error of the lock call throws
   ``FolderLock/Failed``, and the run has read nothing. Then the run makes its own
   ``FolderSnapshot`` of the folder. No front end can give it an earlier
   scan: files can change between a scan and a click. A read-only folder
   gets one note, and no file is tried. Each orphan backup gets a note
   first.
2. **Choose a converter for each pending ARW.** When dnglab is installed,
   one exiftool read gets the ``ARWFacts`` of up to 200 files.
   ``ConverterChoice`` gives each ARW its list of converters, from
   ``AdobeMatch`` and from what is installed.
3. **Convert.** Both converters follow the same steps. The converter checks
   that the name of the ARW is not too long for the files that the
   conversion makes, and that nothing has the name `<base>.dng`. It sends to the Trash a work file
   that an earlier run left, and the `_exiftool_tmp` file of exiftool beside
   it, when each is a regular file. It writes the hidden work file from
   ``ConverterOutput/workURL(for:)``. ``DnglabConverter`` then writes the
   match into the work file and reads it back. ``AdobeConverter`` has no
   match to write. Last, ``ExclusiveRename`` gives the work file the name
   `<base>.dng`, and fails when anything has that name.
4. **When a conversion fails.** The job sends the work file to the Trash
   and gives the ARW to the next converter in its list. It does not try the
   next one when the failure holds for every converter
   (``ConvertError/failedForAll(_:partial:)``), and not after a cancel.
5. **Decide for each DNG.** The DNG files that the scan found come first,
   then the new ones. ``TagDecision`` gives skip, blocked or write. The job
   asks for the backup again at the moment of each file.
6. **Write, and read back.** exiftool writes `DefaultScale` and keeps the
   earlier file as `<name>.dng_original`. The write counts only when the
   value that is read back is within ``SqueezeFactor/tolerance`` of the
   factor.
7. **Clear the backup, or put it back.** After a good read-back, the backup
   goes to the Trash. After a failed check, one rename puts the backup back.
8. **Move the originals, only on request.** This step exists only when the
   caller gave `trashOriginals` as true, and never for Remove. It starts
   after the tag of the last DNG, and not after a cancel. For each ARW that
   this run converted, ``OriginalDecision/decide(hasFullMatch:dngIsAtTheFactor:dngIsThisRuns:dng:dngIsStillThisRuns:original:)``
   says "move" or "keep". The DNG must be the file that this run made: the
   run takes its ``FileRecord`` after the conversion and after the tag step,
   and compares the first before the tag step and the second here, before
   the check of the DNG and again after it
   (``FileRecord/isTheSameFile(recorded:now:)``). The check of the DNG is
   ``DNGCheck``, with one exiftool read
   (``ScaleTagging/readOriginalCheck(_:)``). The ARW is compared with its
   ``FileRecord`` from before the conversion, as the last thing before the
   move. The move is ``BackupHandling/trashFile(_:)``, once. An ARW that
   stays gets a note of the kind `originalKept`.

A cancel is honored between files, never in the middle of one. The result
is a ``RunSummary``: the counts, and the notes.

``DesqueezeJob/plan(folder:factor:convert:trashOriginals:remove:)`` is the
dry run. It makes the same scan and asks the same three functions,
``ConverterChoice``, ``TagDecision`` and ``OriginalDecision``, and it
changes no file. So a dry run shows what the run that follows does when
every step passes. The two differ only where a step of the real run fails.
It takes no lock, so it never has the `noFolderLock` note of a run.

`trashOriginals` has no default value, in the job and in
``DesqueezeOperations``. So each front end states it: the window gives the
state of its box, the command line tool gives its flag, and the MCP server
gives false, always.

## The two packages

| Package | Manifest | Holds | Third-party code |
|---|---|---|---|
| The root package | `Package.swift` | The library `DesqueezeCore`, the library `DesqueezeCLI`, the executable `desqueeze`, and their tests | None |
| The server package | `MCPServer/Package.swift` | The executable `desqueeze-mcp` and its tests. It takes `DesqueezeCore` from the root package by path. | The MCP library for Swift, and the packages that it brings |

The server is a package of its own for one reason. In the root manifest,
every build of the core, and every Xcode build of the app, would fetch the
MCP library and the packages that it needs. With the server apart, the root
package and the app have no third-party code, also at build time. The MCP
library is pinned to one minor version, because it is not yet at 1.0.

The app is not a package. XcodeGen writes the Xcode project from
`project.yml`, and the project file is not in git. The app target links
`DesqueezeCore` from the root package.

## The front ends

| Front end | Source | What it adds to the core |
|---|---|---|
| The window | `App/PlateworksDesqueeze/` | The state of one window: the folder, the factor, the one job in flight, Cancel, and a quit during a run. It also asks Launch Services where Adobe DNG Converter is. |
| `desqueeze` | `Sources/DesqueezeCLI/`, `Sources/desqueeze/` | A hand-written parser, the layout of the text for a person, and the exit codes. |
| `desqueeze-mcp` | `MCPServer/Sources/desqueeze-mcp/` | The three tools as a client sees them, the check of the arguments of a call, one call at a time, and an answer for every call before the program ends. |

## Signals and standard output

- Control-C, a plain `kill` and a closed Terminal window set the
  ``CancelFlag`` of the tool, through an ``InterruptWatcher``. The run stops
  after its current file and prints the result so far. The server does the
  same for the call in work, and then ends with 0.
- A program in work does not get the Control-C: each one starts in a process
  group of its own. A program that is only just starting can still get it.
  That file is then listed as failed and is left as it was.
- Standard output holds the result only. The tool prints text for a person,
  or exactly one JSON object with `--json`. Progress and messages go to
  standard error. For the server, standard output is the protocol.

## Where to read more

The repo has the details that change with the code. `docs/architecture.md`
has the module map: each source file, what it owns, and the test file that
covers it. `docs/decisions.md` has the reason for each choice. The design,
in `docs/superpowers/specs/`, is the contract for all behavior.
