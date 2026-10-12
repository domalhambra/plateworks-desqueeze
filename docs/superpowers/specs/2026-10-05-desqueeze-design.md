# Desqueeze design

Date: 2026-10-05. Red-teamed 2026-10-09; section 2.1 holds the findings and
each one's fix is in the body. Revised 2026-10-09 after the code reviews of
the job and the window, and extended with section 12 (command line and MCP)
and section 13 (dnglab first). Extended 2026-10-10 with section 14 (the
originals to the Trash, on request) and section 15 (the download). Extended
2026-10-12 with section 16 (the privacy page) and section 17 (the accent
and the icon). Status: approved by Dom, and built.

**How to read this document.** It grew in one week, and the later sections
changed earlier decisions. Sections 12 to 17 are the newest. Where they
differ from any earlier section, they win. The earlier text was corrected
where it would mislead, and it still tells the story in the order it
happened: Adobe DNG Converter was the only converter until section 13.

## 1. Purpose

Dom shoots stills on a Sony A7S III with anamorphic lenses of different squeeze
factors. The photos are squeezed. A DNG file can carry a `DefaultScale`
tag, and Lightroom and Camera Raw stretch the image by that tag when they render
it. No pixels change, and the tag is reversible.

Until now Dom wrote the tag with six terminal steps, from a guide of his own.
Desqueeze does the same job: drop a folder on its window, pick a factor, run.
Section 12 added a command line tool and an MCP server on the same core.

**Done for version 1:** Dom drops a shoot folder on the window, picks a factor,
and each DNG in the folder opens in Lightroom at the correct shape. ARW files in
the folder are converted to DNG first.

## 2. What was proven before the design

Tested on 2026-10-05 on scratch copies, with exiftool 13.55 and Adobe DNG
Converter 18.7.

| Test | Result |
|---|---|
| Write `DefaultScale` of `1.33 1`, `1.5 1`, `1.8 1`, `2 1` to a DNG | Each value wrote and read back. |
| Write `DefaultScale="1.5 1"` to an A7S III ARW | Exiftool wrote it. The sensor data stayed byte-identical. |
| Convert that tagged ARW with Adobe DNG Converter | The DNG carried `DefaultScale: 1 1`. Adobe discards the tag in an ARW. |
| Run Adobe DNG Converter from the command line with `-c -d <folder> <file>` | Exit code 0. One DNG beside the source, same base name, extension `.dng`. |

Conclusion: the tag works only in a DNG. An ARW must be converted first.

Not tested: Lightroom or Camera Raw opening a tagged ARW directly. Capture One
is out of scope: Dom's workflow is moving to Lightroom (2026-10-09).

### 2.1 Red team, 2026-10-09

Each claim below was tested on scratch copies. The fix for each is in the
section named.

| Finding | Where it lands |
|---|---|
| Adobe DNG Converter returns exit code 0 on a junk file and makes no DNG. | 4.3 step 1: the two-part pass rule. |
| When `one.dng` exists, the converter writes `one_1.dng`. It never overwrites. | 4.1 pending rule, and a test in 9. |
| `exiftool -ext dng` includes files whose names start with a period. | 4.1: the app filters them. |
| A failed write (read-only folder) exits 1, leaves the file unchanged, and makes no backup. | 4.3 step 4: restore only when a backup exists. |
| exiftool never replaces an existing `_original`. A second write keeps the old backup. | 4.1 and 4.3 step 2: the skip rule. |
| The converter's command line ignores its window preferences. `-h` opens a window and never returns. | 4.3 step 1: the output format, and never call `-h`. |
| Adobe DNG Converter writes `OriginalRawFileName` into the DNG. dnglab does when it embeds the raw file, and the app does not let it (13.2), so the app writes the tag itself. | 4.1: the pending rule reads it. |
| Finder and Quick Look ignore `DefaultScale`. Previews stay squeezed. | 4.4: a known limitation. |
| Camera Raw honors the tag: a 4240-wide DNG opened at 6360 wide at 1.5, from both converters. | Confirms section 1. |
| One tag write takes 0.10 s. One conversion takes 0.37 s, or 0.52 s with the converter's window open. A 228-file folder takes about 30 s. | 3: parallel writes are not needed. |
| The Trash works on exFAT, HFS+ and APFS disk images, and a second file of the same name gets a time suffix. A physical card and a network share are untested. | 4.3 step 4 and 8: keep the backup and report. |
| exiftool writes a new file. The tagged DNG has a creation date of now and no Finder tags. The file that carried them is the backup, which goes to the Trash. | 4.4: a known limitation. |

**dnglab against Adobe DNG Converter.** dnglab 0.8.0 is an open-source
converter (`brew install dnglab`). It read the A7S III file. Both outputs went
through Camera Raw with default settings and were compared pixel by pixel.

| | dnglab | Adobe |
|---|---|---|
| Time for one file | 0.07 s (0.09 s with `--embed-raw false`, as the app calls it) | 0.37 s |
| `exiftool -validate` | OK | 5 warnings |
| DNG version, raw compression | 1.6, lossless | 1.4, lossless |
| Size, no embedded raw | 12.1 MB | 11.5 MB |
| Render, mean luminance | 0.055 stops darker, slightly cooler | reference |
| Pixels that differ by more than 1/255 | 66%, as a uniform offset | |
| Embedded camera profile, BaselineExposure | none | Adobe Standard, 0.15 |
| WhiteLevel | 15360 | 16383 |

The two renders look the same to the eye. Two facts decide the choice. The raw
data of the test frame holds 89 samples above 15360, so dnglab's white point
clips about 0.09 stops of highlight headroom that Adobe keeps. And Adobe's
converter is the same engine as Lightroom's "Copy as DNG", so its output is the
file Dom gets today. Adding `BaselineExposure 0.15` to a dnglab file overshoots
by 0.077 stops, so no tag fix closes the gap. Decision: section 11.

## 3. Scope

**In version 1**

- One window. Drag a folder in, or choose one.
- Four preset factors (1.33, 1.5, 1.8, 2) and a custom factor.
- Convert each ARW that has no DNG, then tag every DNG.
- Remove the tag (write `1 1`).
- Progress, a result count, and a list of failed files.
- Cancel between files.

**Not in version 1.** Each item waits until the app ships to other people, or
until Dom asks for it.

| Item | Why it waits |
|---|---|
| Bundled exiftool | Dom's Mac has exiftool. A shipped app must carry its own. |
| A bundled dnglab | dnglab converts since 2026-10-09 (section 13). Version 1 finds the one Homebrew installed. A shipped app must carry its own. |
| A match table for cameras other than the A7S III | Section 13 has one measured row. Each other camera needs its own. |
| Code signing and notarization | Needed only for other people's Macs. |
| Brand marks, accent color, app icon art | The Plateworks brand standards, kept outside this repo, govern them. Version 1 uses system colors and the system font. Since version 0.1.1 the app has its accent and its icon (section 17). |
| A register row in the Plateworks principles | A register belongs to a published property. |
| Privacy page | Same reason. |
| Subfolder scan | Shoot folders hold `Exports` and `CaptureOne` subfolders that must stay untouched. |
| Folder drop on the Dock icon | The window drop does the job. |
| Parallel writes | A 228-file folder takes about 30 s one file at a time (2.1). |
| Vertical squeeze | No lens Dom owns needs it. |
| Capture One support | Dom's workflow is moving to Lightroom. |

## 4. Behavior

### 4.1 Scan

The app reads the top level of the folder only. It does not enter subfolders.

- A **DNG** is a file whose extension is `dng`, in any letter case.
- An **ARW** is a file whose extension is `arw`, in any letter case.
- The app ignores names that start with a period, and every other file type.
  exiftool does not skip hidden files, so the app drops them from the scan
  output itself.
- A DNG **claims** an ARW when the two have the same base name, or when the
  DNG's `OriginalRawFileName` tag equals the ARW's file name. Both comparisons
  ignore letter case. Every DNG this app makes has that tag (Adobe's converter
  writes it, and the app writes it into a dnglab DNG), so a DNG that was
  renamed on import still claims its ARW.
- An ARW is **pending** when no DNG in the folder claims it. An orphan backup
  (below) claims an ARW the same way its DNG would, by base name, so the run
  never converts a photo whose DNG is waiting to be renamed back.
- A DNG has an **existing backup** when a file named `<name>.dng_original` is
  beside it. exiftool never replaces an existing `_original`, so a write over
  one would leave a backup of the wrong state. The run checks for the backup
  again at the moment it tags each file.
- An **orphan backup** is a file named `<name>.dng_original` with no
  `<name>.dng` beside it. It can exist only if exiftool stopped between its two
  renames. In a folder with no ARW files it is the only copy of that photo. The
  app never touches it, and always reports it.

The app then reads the current `DefaultScale` and `OriginalRawFileName` of
every DNG with one exiftool call:

```
exiftool -m -T -filename -SubIFD:DefaultScale -OriginalRawFileName -ext dng <folder>
```

When exiftool prints no value for a DNG (`-` in the output), or no row at all,
the scale is **unknown**. Unknown is not `1 1`. exiftool prints `-` both for a
DNG that has no tag and for a file it cannot read, so the app never skips such
a file: it tries the write, and the write tells the two cases apart.

The group `SubIFD` is named on every read and write, because that is the IFD
Camera Raw reads.

The window shows the folder name and the counts, for example
`216 DNG · 12 ARW to convert`.

### 4.2 Factor

- A factor is a decimal number from 1 to 4, with at most four decimal places.
- The tag value is `<factor> 1`: horizontal stretch, then vertical stretch.
- The app remembers the last factor between launches.
- An invalid custom value shows a message beside the field, and the run does
  not start.

### 4.3 Run

A run starts with its own fresh scan of the folder. No front end can hand the
run an earlier scan: files and tag values can change between a scan and a
click, and a run on old values reports "skipped" for a file it never looked at.

Then the run does these steps in order. One file at a time.

1. **Convert.** For each pending ARW, call Adobe DNG Converter:

   ```
   "<Adobe DNG Converter>" -c -d <folder> -o <work file name> <file.ARW>
   ```

   The converter writes a hidden work file, not `<base>.dng` (13.3). The
   conversion passes when the exit code is 0, the work file exists and has
   bytes, and the rename to `<base>.dng` passed. The exit code alone is not
   enough: Adobe's converter returns 0 on a file it cannot read, and makes no
   DNG.
   The app never changes or deletes an ARW, and it moves one only on the
   user's request for that run (section 14). If `<base>.dng` appeared
   after the scan, the app does not start the converter for that ARW, and
   reports it.

   (Until 13.3, the converter wrote `<base>.dng` itself, and this was the
   rule. Read "the work file" for `<base>.dng` below.) A converter that is
   ended before it completes can leave a `<base>.dng` with no bytes (tested 2026-10-09: the terminate and kill signals at 0.30 s
   of a 0.37 s conversion). Left there, that file would claim the ARW in every
   later scan, and the photo would never convert. So when a conversion fails
   after the converter started, and `<base>.dng` is there, the app moves that
   file to the Trash and says so on the note's detail line. The app made the
   file in this run: the check before the start proved that no DNG had that
   name. If the Trash refuses, the note names the file to delete by hand.

   The command line ignores the converter's window preferences. With `-c` it
   writes DNG 1.4, lossless raw, JPEG previews. A DNG that dnglab makes is DNG
   1.6, lossless raw (13.2). Never pass `-h`: it opens a window and the process never
   returns.

2. **Tag.** For each DNG, including the new ones:
   - Skip it when its current value is known and equals the chosen factor. If
     a backup is beside such a file, report that too: "Already at this value.
     A backup, `<name>_original`, is beside this file."
   - Hold it back and report it when it has an existing backup. The app does
     not touch a backup that it did not make. Such a file counts as
     **blocked**, not as skipped: "skipped" means only "already at this
     value".
   - Otherwise write the tag. Exiftool keeps the previous file as
     `<name>.dng_original`.

     ```
     exiftool -m -SubIFD:DefaultScale=<factor> 1 <file.dng>
     ```

     The app passes each argument as its own array element, with no shell. The
     write passes when the exit code is 0 and the output contains
     `1 image files updated`. The warning `Error copying hidden data` is
     expected from Adobe DNG Converter files and is ignored.

3. **Check.** Read the tag back from the file:

   ```
   exiftool -s3 -SubIFD:DefaultScale <file.dng>
   ```

   The check passes when the first number is within 0.00005 of the factor (half
   of the smallest step between two factors, so neighbors never match) and
   the second number is 1.

4. **Clear the backup.**
   - Check passed: move `<name>.dng_original` to the Trash. If the Trash
     refuses the file, which can happen on an external volume, keep the backup
     and report the file with the reason.
   - Write or check failed, and a backup exists: restore `<name>.dng_original`
     as `<name>.dng` with one atomic rename, and report the file as failed.
   - Write failed with no backup: the file is unchanged. A failed write makes
     no backup. Report the file as failed.
   - The restore itself failed: report "The change failed, and the backup
     could not be restored. The backup is `<name>_original`." with both error
     texts in the detail.

Each orphan backup in the folder is reported at the start of the result, with
the name to give it: "A backup with no DNG beside it. Rename it to `<name>.dng`
to get the photo back."

**Remove** runs steps 2 to 4 with factor 1. It does not convert ARW files.

**Cancel** stops the run after the current file completes. Completed files stay
tagged.

### 4.4 Result

The window shows one line of counts: converted (when it is not zero), set,
skipped, blocked (when it is not zero), failed, and "stopped" after a Cancel. Below it, each failed or
reported file has its name, one plain sentence, and the tool's own words on a
detail line.

When a run left ARW files unconverted because no converter is installed, the
result says so, with the count (13.5).

The result line and each error message carry a symbol, and the counts stay in
the primary text colour. Colour is never the only signal. When this was written,
the app took the accent of each Mac, which can be the same red as an error.
Since version 0.1.1 the accent is one blue on each Mac (section 17), and the
rule holds: a person who does not see a colour still gets the meaning. A result with a failed or blocked file
gets the "needs attention" symbol.

Under the counts, when the run set the tag on at least one photo, one line:
"Photos already in Lightroom: Metadata › Read Metadata from File." Lightroom
caches the tag at import. A run that set nothing, and a dry run, do not show
it. Every front end follows this one rule, from the core.

When both converters did work in one run, a line says how many photos each
converted. Every front end shows it.

Known limitations:

- Finder and Quick Look ignore the tag, so their previews stay squeezed.
  Lightroom and Camera Raw render the correct shape.
- A tagged DNG is a new file. Finder shows its Date Created as the time of the
  run, and Finder tags on the old file are gone. The capture date inside the
  photo does not change, and Lightroom reads that one.

## 5. The window

One fixed-width window, about 440 points wide.

| Part | Behavior |
|---|---|
| Drop zone | Accepts one folder. A symbolic link to a folder counts as that folder. A package, such as an app or a Lightroom library, is not a folder here. A dropped file that is not a folder shows "Drop a folder" until the next folder loads. That message never replaces a message about the loaded folder. Holds the "Choose folder" button, which opens the standard folder panel. |
| Folder summary | Folder name and the counts from the scan. While a scan runs, the previous folder's counts are gone and Run and Remove are off. A read-only folder gets a message here. Each orphan backup is named here with the name to rename it to: up to five by name, then a count of the others. |
| Factor row | Four preset buttons and one custom field. One factor is selected at a time. A click in the custom field selects it. VoiceOver hears which factor is selected. |
| Run button | Label: `Desqueeze N photos`, `Desqueeze 1 photo`, or `Desqueeze` when there is nothing to run. N is the count of DNG files plus the pending ARW files that can convert. When no converter is installed, the ARW files are not in N (13.5). |
| Originals checkbox | Section 14.4. Off at every launch. |
| Remove button | Writes `1 1`. On only when the folder has a DNG. It asks nothing and runs at once: the change is reversible. |
| Progress bar | One step for each conversion and one for each tag write. Before the first step completes, the bar is indeterminate. During a run, the Run button becomes Cancel, and Escape presses it. After a Cancel the button reads "Finishing…" and is off until the run has ended, so a second click cannot start a new run. The run stays "running" until the scan after it has landed, so no click can act on old counts. |
| Quit during a run | The app cancels the run, lets the current file complete, then quits. |
| Result line and list | Section 4.4. |

Copy is sentence case, with no exclamation marks.

Settled in the last review of the window:

- When the app becomes active again and no run or scan is in work, the window
  scans the loaded folder again, so files added from another app show in the
  counts.
- A second click within the system's double-click time of a Run click does
  not cancel the run that the first click started.
- At the end of a run, VoiceOver hears the result counts line.

Known limits of the window:

- Keyboard focus in the custom field selects the custom factor, also when the
  focus came from Tab. The check mark on the field shows it. Look at the
  selected factor before a run from the keyboard.
- If exiftool or the converter never returns, the window stays at
  "Finishing…". Force Quit is the way out. No file is harmed: a write that
  did not complete leaves the DNG as it was.

## 6. Dependencies

| Tool | How the app finds it | When it is missing |
|---|---|---|
| exiftool | `/opt/homebrew/bin/exiftool`, then `/usr/local/bin/exiftool`, then each folder in `PATH` | The app cannot run. The window says so and gives `brew install exiftool`. |
| Adobe DNG Converter | The app with bundle identifier `com.adobe.DNGConverter`, then `/Applications/Adobe DNG Converter.app` | The app still tags DNG files. The summary says the ARW files cannot be converted, and why. |

The converter runs correctly while its own window is open (2.1).

The app holds no path that is specific to Dom's Mac.

The app is not sandboxed. A sandboxed app cannot start exiftool or Adobe DNG
Converter. This rules out the Mac App Store and points a later release at a
signed, notarized download.

## 7. Structure

A Swift package for the logic, and a SwiftUI app generated by XcodeGen.

```
Package.swift                     the core, the tool, and their tests
Sources/DesqueezeCore/            logic, no UI, no AppKit
Sources/DesqueezeCLI/             the command line tool, as a library
Sources/desqueeze/                the tool's entry point
Tests/DesqueezeCoreTests/
Tests/DesqueezeCLITests/
App/PlateworksDesqueeze/          SwiftUI app
App/PlateworksDesqueezeTests/     tests of the window's state, with no app host
MCPServer/                        the MCP server, a package of its own (12.2)
project.yml                       XcodeGen spec
```

- App name: Desqueeze. Bundle identifier: `org.plateworks.desqueeze`.
- Deployment target: macOS 14.
- No network requests.
- No third-party Swift code in `DesqueezeCore`, in the app, or in the
  `desqueeze` command line tool. The MCP server target alone links the
  official Swift MCP library (section 12).

**Units in `DesqueezeCore`**

| Unit | Job | Depends on |
|---|---|---|
| `SqueezeFactor` | Validates a factor and formats the tag value. | nothing |
| `FolderScan` | Turns a folder into lists: DNG files, ARW files, orphan backups. Decides which ARW files are pending. | the file system |
| `FolderScanner` | Joins the folder lists, the tag rows, and the backup state into one `FolderSnapshot`. | `ScaleTagging`, `BackupHandling` |
| `ProcessRunner` | A protocol with one method: run a program with arguments, return exit code, output, and error text. The real one wraps `Process`. | nothing |
| `ToolLocator` | Finds exiftool, dnglab and Adobe DNG Converter. Gives no path for a tool that is not there, and holds the sentence that names it. | the file system |
| `ScaleTag` | Behind the `ScaleTagging` protocol: reads the tag for a folder, writes it for one file, reads it back from one file. A `Scale` is two numbers. An unknown scale is `nil`. | `ProcessRunner` |
| `FileBackups` | Behind the `BackupHandling` protocol: says whether a backup exists, moves it to the Trash, restores it with one rename. | the file system |
| `RawConverter` | A protocol: convert one ARW and confirm the DNG exists. Two implementations: `DnglabConverter` and `AdobeConverter` (13.7). | `ProcessRunner` |
| `DesqueezeJob` | `run(folder:)` scans, then runs section 4.3 in order, reports progress for each step, honors Cancel, returns the result. `plan(folder:)` returns what a run would do and changes nothing. | the units above |

**Text rules live in the core.** The folder counts line, the run count, the
run button label, the folder messages, and the result counts line are pure
functions in `DesqueezeCore` with unit tests. The window and the command line
tool only show them.

**In the app:** one view, and one observable model that owns the folder, the
factor, and the running job. The model calls `DesqueezeJob` off the main thread
and publishes progress to the view. Only one job runs at a time.

## 8. Errors

| Condition | What the user sees |
|---|---|
| exiftool is missing | A message in the window with the install command. Run and Remove do nothing else. |
| Adobe DNG Converter is missing | The summary line says the ARW files cannot be converted. DNG files still run. |
| The folder has no DNG and no ARW | "No DNG or ARW files in this folder." |
| A conversion fails | The ARW is listed as failed. The run continues. A partial DNG that the converter left goes to the Trash, and the note says so. |
| exiftool or the converter is ended by a signal | That file is listed as failed, with the signal number on the detail line. The run continues. |
| A write or check fails | The backup is restored. The DNG is listed as failed. The run continues. |
| A DNG has an existing backup | The DNG is listed as blocked, with the reason. Its note starts "Blocked." |
| The Trash refuses a backup | The DNG is listed as done, with a note that its backup stayed beside it. |
| The folder is not writable | One message for the folder. No file is tried. A read-only file inside a writable folder still writes, because exiftool replaces the file. |
| A DNG's current value is unknown | The write is tried. A file exiftool cannot read is listed as failed. |
| A file is already set and a backup is beside it | Listed as skipped, with a note that names the backup. |
| An orphan backup is in the folder | A message for the folder, and a line in each result, with the name to rename it to. |
| The restore of a backup fails | Listed as failed, with the backup's name and both error texts. |
| The scan itself fails | "This folder could not be read." No file is tried. |

The app never shows raw tool output as the only message. The raw output goes in
a detail line below the plain sentence.

## 9. Testing

- **Unit tests** (`swift test`) use a fake `ProcessRunner`. They assert the
  exact arguments for each call, the parsing of each output, the skip rules,
  the backup rules, and the order of a run. One test asserts that the converter
  is never called for an ARW that a DNG claims: a call there would make a
  second DNG of one photo.
- **`FolderScan` tests** build temporary folders: mixed case extensions, a
  subfolder, a hidden file, an ARW with and without its DNG, a renamed DNG that
  claims its ARW through `OriginalRawFileName`, an existing backup.
- **Integration tests** run the real exiftool and the real converter against
  `fixtures/`, a gitignored folder that holds one DNG and one ARW. The tests
  copy each fixture to a temporary folder first. They skip when `fixtures/` or
  a tool is absent.
- **A behavioral test counts only after it fails against a break.**
- **Acceptance, by hand:** a scratch copy of a real shoot folder. All four
  presets, a custom factor, a second run (every file skipped), Remove, a path
  with spaces, a start with the launch argument `-simulateMissingTools YES`
  (this Mac has exiftool in two places, so a rename proves nothing), and with
  `-simulateMissingDnglab YES` and `-simulateMissingAdobe YES` for the two
  states with one converter. The launch argument
  `-openFolder <path>` loads a folder at launch, because the standard Open
  panel runs in another process that a script cannot drive. Both are read from
  the launch arguments only, never from saved defaults. Then one file opened in
  Lightroom at each factor. Dom's photo folders are never the test target.

## 10. Documentation and filing

Revised 2026-10-09. The first version of this section said Floor tier and a
private repo.

- Documentation tier: Medium, plus `PROJECT_CHARTER.md`, by the Plateworks
  documentation standard, which is kept outside this repo. The standard's
  check is copied to `scripts/docs_check.py` and run by a test. The copy
  names no path outside the repo.
- License: MIT. Copyright Plateworks.
- The repo carries what an open-source repo carries: `CONTRIBUTING.md`,
  `SECURITY.md`, `CHANGELOG.md`, `THIRD_PARTY_NOTICES.md`, and issue and
  pull-request templates.
- A documentation site is built from a DocC catalog in the core package.
- GitHub: `plateworks-desqueeze`, public. It starts with one first commit of
  the cleaned files.
- No document, comment or test in the repo names a path on the maintainer's
  Mac or a private repository.

## 11. Decisions

| Decision | Why |
|---|---|
| Native SwiftUI app | A droplet has no window for progress and errors. A web shell is heavy for one window. |
| DNG beside the ARW, same base name | The app never renames, and a second run can skip converted files. Dom chose this. |
| Top level only | Subfolders hold exports and Capture One data. |
| Backup kept until the check passes, then moved to the Trash | In a folder with no ARW files, the DNG is the only copy. |
| Hold back (block) a DNG that has an existing backup | The app must not remove or replace a backup it did not make. |
| One exiftool call for each write | Clear progress and a failure that stays with one file. At 0.10 s a file, speed is not a reason to batch. |
| Adobe DNG Converter in version 1, behind a protocol | Its output is the file Lightroom's "Copy as DNG" makes, and it keeps 0.09 stops of highlight headroom that dnglab clips (2.1). dnglab is the swap for a release, because Adobe's converter cannot be bundled. |
| Pending rule reads `OriginalRawFileName` | A DNG renamed on import still claims its ARW, so a rerun never converts it twice. |
| Not sandboxed | The app must start external tools. |
| Built for Dom's Mac first, shaped to ship later | Dom chose this. Section 3 lists what waits. |

## 12. Command line and MCP

Added 2026-10-09 at Dom's request, so Claude Code and Cowork can do the app's
job with no window. Both front ends call the same `DesqueezeCore` entry points
as the window, so every rule in section 4 holds for them.

### 12.1 `desqueeze`, the command line tool

A second executable in the package. Hand-written argument parsing, no
third-party code.

```
desqueeze scan <folder> [--json]
desqueeze run <folder> --factor <number> [--no-convert] [--trash-originals]
              [--dry-run] [--json]
desqueeze remove <folder> [--dry-run] [--json]
desqueeze --version
desqueeze --help
```

| Command | Does | Changes files |
|---|---|---|
| `scan` | Prints each DNG with its current scale, the pending ARW files, the orphan backups, whether the folder is writable, and where exiftool, dnglab and Adobe DNG Converter are. | No |
| `run` | Section 4.3 at the given factor. `--no-convert` leaves ARW files alone. | Yes |
| `remove` | Section 4.3 with factor 1 and no conversion. | Yes |
| `--dry-run` | On `run` and `remove`: prints what the run would do, file by file, from `DesqueezeJob.plan(folder:)`. | No |

- `--factor` takes the same values as the window: 1 to 4, at most four decimal
  places. `run` with no `--factor` is a usage error. There is no default.
- Text output is for a person. `--json` prints one JSON object on standard
  output and nothing else there. Progress lines go to standard error in both
  modes.
- A relative folder path is resolved against the working folder. A symbolic
  link to a folder counts as that folder, by the same rule as the window
  (`FolderChoice`), and the report names the folder the link points to. A
  file, or a package such as an app, is not a folder: exit 1.
- Exit code 0: the command completed, no file failed, and no file was
  blocked. Exit code 1: a file failed or was blocked, the run was stopped, the
  folder could not be scanned, a run or a dry run met a read-only folder,
  another run is working in the folder (13.9), or exiftool is missing. Exit
  code 2: a usage error.
- `scan` exits 0 whenever the scan completed, also for a read-only folder: the
  report says `"writable": false`.
- When a command fails with no report to print, `--json` prints one object,
  `{ "error": "…", "detail": "…" }`. A usage error prints nothing on standard
  output.
- JSON is pretty-printed with its keys in alphabetical order.
- The tool looks for Adobe DNG Converter in `/Applications` only. The window
  also asks Launch Services, which needs AppKit.
- `--verbose`, on every command: prints each exiftool and converter command
  line, its exit code, and its raw output to standard error. For
  troubleshooting.
- When no converter is installed, `run` still tags the DNG files, says how
  many ARW files it left, and exits 0.
- Control-C stops the run after the current file, prints the result so far,
  and exits 1. A closed Terminal window (`SIGHUP`) and a plain `kill`
  (`SIGTERM`) do the same. `stopped` is true only when the run left work undone. A
  Control-C that arrives during the last file leaves nothing undone: the
  result is the complete result, `stopped` is false, and the exit code is the
  one the complete run gives. The window's Cancel follows the same rule.
- exiftool and the converter normally do not get the Control-C: each starts
  in a process group of its own. A program that is only just starting can
  still get it (seen once in 27 test runs under load). That one file is then
  reported as failed, with "ended by signal 2" on its detail line, and it is
  left as it was. Run again to complete it.
- A pipe that closes early (`desqueeze run … | head`) does not stop a run. The
  tool ignores `SIGPIPE`, completes the run, and loses only the output.
- `run --factor 1 --no-convert` is not `remove`: it reports the ARW files it
  left, as every `run` does. Only `remove` leaves that line out.

JSON shapes. `scale` is the tag value as text, or `null` when it is unknown.

```json
{ "folder": "/path", "writable": true,
  "exiftool": "/opt/homebrew/bin/exiftool", "dnglab": "/opt/homebrew/bin/dnglab",
  "dngConverter": "/Applications/…",
  "dngs": [ { "name": "a.dng", "scale": "1.5 1", "originalRawFileName": "a.ARW", "hasBackup": false } ],
  "pendingARWs": ["b.ARW"], "orphanBackups": [] }
```

```json
{ "folder": "/path", "factor": "1.5", "dryRun": false,
  "converted": 1, "convertedByDnglab": 1, "convertedByAdobe": 0,
  "set": 2, "skipped": 0, "blocked": 0, "failed": 0,
  "stopped": false, "unconvertedARWs": 0,
  "trashOriginals": false, "originalsInTrash": 0,
  "notes": [ { "name": "x.dng", "kind": "failed", "message": "…", "detail": null } ] }
```

A dry run prints the same object with `"dryRun": true`, the counts a real run
would give if every step passed, and a `"steps"` list of
`{ "name", "action" }`, where action is `convert`, `write`, `skip`,
`blocked`, or `trashOriginal` (14.3). A `convert` step also has `"converter"`: `dnglab` or `adobe`.
`"dngConverter"` is the path of Adobe DNG Converter: the key keeps its first
name.

A note's `kind` is one of `orphanBackup`, `notConverted`, `failed`,
`blockedByBackup`, `leftoverBackup`, `backupKept`, `folderReadOnly`,
`convertedUnmatched` (13.4), `noFolderLock` (13.9), `originalKept` (14.3). A front
end reads the kind, never the English sentence. `unconvertedARWs` is the count
of pending ARW files the run left, from the run's own scan.

The report types are `Codable` structs in `DesqueezeCore`, so the tool and the
MCP server print the same JSON. The dry run and the real run share one
function that decides skip, blocked, or write for a file, so they cannot
disagree.

A folder that holds only an orphan backup is not "empty": every front end
reports the orphan.

### 12.2 `desqueeze-mcp`, the MCP server

A third executable. It speaks MCP over standard input and output and links the
official Swift MCP library, `modelcontextprotocol/swift-sdk`, pinned to one
minor version because the library is not yet at 1.0.

The server is its own Swift package, in the folder `MCPServer/`, and takes
`DesqueezeCore` from the root package by path. The library brings six more
packages, swift-nio among them. In the root manifest, every build of the core
and every Xcode build of the app would fetch them. In its own package, the
root package and the app stay free of third-party code at build time too.
Build and test: `swift build --package-path MCPServer`,
`swift test --package-path MCPServer`.

| Tool | Arguments | Result | Changes files |
|---|---|---|---|
| `desqueeze_scan` | `folder` | The scan JSON | No. Marked read-only. |
| `desqueeze_run` | `folder`, `factor`, `convert` (default true), `dry_run` (default false) | The run JSON | Yes, unless `dry_run` |
| `desqueeze_remove` | `folder`, `dry_run` (default false) | The run JSON | Yes, unless `dry_run` |

- `folder` must be an absolute path to a folder that exists. The server
  rejects anything else with a tool error and changes nothing.
- A tool result that has failed files is still a successful tool call: the
  JSON carries the failures. A scan that cannot run is a tool error.
- When the client sends a progress token, the server sends one progress
  message for each step of the run.
- The server runs one tool call at a time. The job assumes one run in a folder
  at a time, and two at once can produce false notes.
- Each tool's description tells the model what the tool changes, that the
  change is reversible with `desqueeze_remove`, and to call `desqueeze_scan`
  first.
- The server never moves an original. It has no parameter for section 14.
- A client stops a server with a signal. On `SIGTERM`, `SIGINT` or `SIGHUP`
  the server sets the cancel flag of the call in work, starts no waiting
  call, lets the current file complete, writes that call's report with
  `stopped`, and exits 0. A server that ended at once would leave a backup
  beside the file exiftool was writing.
- When standard input closes, the call in work completes and is answered.
  A call that waits and has not started does not start: the client has gone,
  and a file-changing call must not run for nobody.
- One message is written to standard output at a time, and the server does
  not exit while an answer is being written.
- Known limit: a client that stops reading while its pipe is full holds the
  server open, also after a signal, because the answer cannot be written. The
  run has stopped after its file by then and no backup is left. Only the
  unread report is lost when the client then kills the server.

### 12.3 Install

`desqueeze` builds with `swift build -c release`, and `desqueeze-mcp` with
`swift build -c release --package-path MCPServer`. Copy both to a folder on
the `PATH`, such as `~/.local/bin/`. Register the MCP server with Claude Code
by its absolute path. Registering changes the user's Claude configuration, so
an agent does it only when the user says so.

### 12.4 Testing

- The report types and `plan(folder:)` are unit-tested in `DesqueezeCore`.
- The argument parser is unit-tested: every command, every flag, each usage
  error.
- The command line tool is tested end to end by starting the built executable
  against a temporary folder with the fixtures: `scan --json`, `run --dry-run`
  (no file changes), `run`, a second `run` (all skipped), `remove`, and the
  exit codes.
- The MCP server is tested end to end by starting the built executable and
  speaking MCP to it over its standard input and output: initialize, list the
  tools, call each tool against a temporary folder.

## 13. dnglab first, matched to Adobe

Added 2026-10-09 at Dom's request. dnglab converts. Adobe DNG Converter is an
optional backup that the app uses when dnglab cannot give the same file.
Where this section and any earlier one differ, this section wins.

### 13.1 Why

- Adobe DNG Converter starts as an app for each ARW: the Dock shows it once
  for each file, and a test run shows it many times.
- dnglab takes 0.09 s a file against 0.37 s, opens nothing, and can ship
  inside an app later.
- The reason to keep Adobe was the render. The measurements below remove it
  for Dom's camera.

### 13.2 What was measured

All on scratch copies, 2026-10-09, dnglab 0.8.0, Adobe DNG Converter 18.7,
Camera Raw through Photoshop with default settings.

**The gap is five tags.** Adobe's DNG holds values that dnglab's does not.
Written into the dnglab DNG with exiftool, they close the gap:

| Render against Adobe's, ISO 800 frame | Brightness | Pixels that differ by more than 1/255 |
|---|---|---|
| dnglab as it comes | 0.055 stops darker | 66% |
| + `WhiteLevel 16383`, `BaselineExposure 0.15` | 0.007 stops darker | 33% |
| + `CameraCalibration1` and `2` | 0.002 stops darker | 24% |

| Render against Adobe's, other frames, all tags below | Brightness | Pixels that differ by more than 1/255 |
|---|---|---|
| ISO 50 | 0.004 stops darker | 3.5% |
| ISO 12800, a dark frame | 0.027 stops darker | 0.47% |

Section 2.1 says "no tag fix closes the gap". That test changed
`BaselineExposure` alone. The white level and the exposure value must change
together: 16383 against 15360 is 0.096 stops, and 0.15 less 0.096 is the
0.055 that was measured.

**The values, from one ARW at each of 23 ISO settings** (50, and 80 to 12800
with no file at 1250). The data file is
`2026-10-09-ilce-7sm3-adobe-values.json`, beside this document.

| Tag | Adobe's value | Varies with |
|---|---|---|
| `SubIFD:WhiteLevel` | 16383 | Nothing. dnglab writes 15360, and the raw data goes above it. |
| `IFD0:BaselineExposure` | 0.15. At ISO 50: -0.85. | The ISO. |
| `IFD0:CameraCalibration1` and `2` | The diagonal `r 0 0 0 1 0 0 0 b`, with r = 2568 / the red of the ARW's `WB_RGBLevelsDaylight` and b = 1549 / its blue, each rounded to 4 decimal places. | The lens: the camera changes its daylight levels for a lens that reports itself. The rule gave Adobe's exact numbers for all 23 files, with two lenses. |
| `IFD0:NoiseProfile` | Six numbers. | The ISO only: four files at ISO 400 and four at ISO 3200, with different lenses and shutter times, gave the same numbers. |
| `IFD0:BaselineNoise`, `IFD0:BaselineSharpness` | 0.6, 1.25 | Nothing. |
| `SubIFD:AntiAliasStrength`, `SubIFD:BayerGreenSplit` | 1, 250 | Nothing. |

At ISO 12800 the noise tags matter: without `NoiseProfile`, 5.9% of the
pixels differ. With it, 0.47%.

`CameraCalibrationSig` and `ProfileCalibrationSig` changed nothing in the
render and are not written. Adobe's embedded camera profile is not copied:
Camera Raw uses its own profile for the camera model.

**A lens that reports itself.** For a frame from the Sony FE 24-105mm lens,
Adobe writes a lens-correction block (`OpcodeList3`, `WarpRectilinear`) from
data in the ARW. dnglab writes none, and the two renders differ in geometry
(51% of the pixels). For a frame from an adapted lens, which is every
anamorphic frame, the ARW says `DistortionCorrection: No correction params
available`, and neither converter writes a block.

**dnglab's command line.**

| Fact | Consequence |
|---|---|
| `dnglab convert <in.ARW> <out.dng>` embeds the whole ARW in the DNG by default. | Pass `--embed-raw false`. |
| With `--embed-raw false`, dnglab writes no `OriginalRawFileName`. | The app writes it, with the other tags. The pending rule (4.1) needs it. |
| A file it cannot read: exit code 7, no DNG. An output that exists: exit code 6, the file is not touched. | Unlike Adobe's converter, the exit code is the truth. Never pass `-f`. |
| Killed in work, it left a DNG of 0 bytes, 4 bytes, or a cut-off 12.1 MB. | The partial-DNG rule of 4.3 holds for dnglab too. |
| The output is DNG 1.6, lossless, and passes `exiftool -validate`, also after the tags are written. | |

### 13.3 The match, on a work file

dnglab does not write `<base>.dng`. It writes a **work file** in the same
folder, `.<base>.desqueeze-work.dng`. The name starts with a period, so the
scan (4.1), Finder and Lightroom do not see it. The steps:

1. If a work file with that name is there, a run that ended hard left it.
   Its name says it is this app's own, so the app moves it to the Trash and
   goes on.
2. `dnglab convert --embed-raw false <in.ARW> <work file>`.
3. The app writes the tags of 13.2 and `IFD0:OriginalRawFileName` into the
   work file with **one** exiftool call, with `-m` and `-overwrite_original`:
   the file is this run's own, a second old, and has no earlier state to
   keep.
4. It reads the tags back and compares them.
5. It moves the work file to `<base>.dng` with a rename that **fails when
   anything has that name** (`renamex_np` with `RENAME_EXCL`). On a volume
   that does not have that call, it checks the name without following links
   and then renames.

The conversion passes only when dnglab returned 0, the work file has bytes,
the read-back equals what was written, and the rename passed.

Why a work file:

- `<base>.dng` appears only when it is complete and matched. A run that ends
  hard (Force Quit, a crash, a closed Terminal window, power loss) leaves a
  hidden work file and a pending ARW, never a DNG that looks done and is not
  matched. Before this, such a DNG claimed its ARW, and later runs tagged it
  with no note.
- The only file a failed dnglab conversion sends to the Trash is the work
  file. A `<base>.dng` that another program made at the wrong moment is
  never taken for the app's own: the rename fails, the work file goes to the
  Trash, and the note says "A DNG with this name exists already. Not
  converted." The next converter is not tried for that ARW.
- dnglab's exit code 6 (the output exists) should not occur: step 1 removes
  a leftover work file, and when it cannot, dnglab is not started. If it
  occurs, it is a failure with no partial output.
- When the Trash refuses a work file, that ARW is not given to the next
  converter. The note names the hidden file to delete, so no 12 MB file
  stays in the folder with no one told.

**Adobe DNG Converter uses the same work file.** Its command line takes an
output name (`-o`, tested 2026-10-09: it wrote
`.frame 1.desqueeze-work.dng`, and with that name taken it wrote
`.frame 1.desqueeze-work_1.dng`). So the app gives it the work-file name, and
steps 1 and 5 hold for it as they hold for dnglab. Steps 3 and 4 do not
apply: Adobe's file needs no match. The conversion passes when the exit code
is 0, the work file has bytes, and the rename passed. One rule then covers
both converters: the only file a failed conversion sends to the Trash is the
work file, and a `<base>.dng` that the run did not make is never touched.
Where 4.3 step 1 says the app moves a partial `<base>.dng` to the Trash, read
"the work file".

Step 1 also removes `<work file>_exiftool_tmp`, which a hard end during step
3 can leave. Both names are the app's own. Only a regular file is removed: a
folder or a link at either name stops the conversion of that ARW with the
leftover note, and nothing moves.

Before either converter starts, a file named `<base>.dng_exiftool_tmp` (not
the work file's own leftover, which step 1 removes) stops
the conversion of that ARW, with a note that names it: exiftool refuses to
write beside its own leftover, so the tag step could never pass.

The tag step of 4.3 (`DefaultScale`) is not changed. It runs after the
conversion, as before, with its own backup and check.

### 13.4 Which ARW dnglab converts

The app reads these facts for the pending ARW files with one exiftool call
for each 200 files:
the camera model, the ISO, `WB_RGBLevelsDaylight`, `DistortionCorrection`,
and `SonyRawFileType`. The last two are read as numbers (`-n`): 255 means no
lens-correction data, and 2 means compressed raw. Any other number, or none,
fails its rule.

A frame has a **full match** when all five hold:

1. The model has a row in the table. Version 1 has one: `ILCE-7SM3`.
2. The ISO has a row: 50, or one of the 22 measured values from 80 to 12800.
3. The daylight levels are there, with green 1024.
4. The ARW says that it has no lens-correction data.
5. The ARW is compressed raw, the only kind that was measured.

| The ARW | dnglab and Adobe installed | Only dnglab | Only Adobe | Neither |
|---|---|---|---|---|
| Full match | dnglab, matched | dnglab, matched | Adobe | Not converted |
| No full match | Adobe | dnglab, matched as far as the table goes, with a note | Adobe | Not converted |
| dnglab or its match failed | Adobe, then failed if Adobe fails too | Failed | | |

"Matched as far as the table goes": when rules 1, 2, 3 and 5 hold and only
rule 4 fails, the app writes every tag, and the note says the DNG has no built-in
lens correction. When rule 1, 2, 3 or 5 fails, the app writes only
`OriginalRawFileName`, and the note says the levels are dnglab's own. Each
note ends: "Install Adobe DNG Converter for the same file that Lightroom
makes." Such a file counts as converted. It is not failed and not blocked,
and the exit code stays 0. Its note kind is `convertedUnmatched`.

### 13.5 Dependencies and messages

| Tool | How the app finds it | When it is missing |
|---|---|---|
| exiftool | As section 6. | As section 6. |
| dnglab | `/opt/homebrew/bin/dnglab`, then `/usr/local/bin/dnglab`, then each folder in `PATH` | With Adobe installed: Adobe converts every ARW, and one quiet line says "dnglab is faster and opens no window. Install it with: brew install dnglab". With neither: the ARW files are not converted, the DNG files still run, and the message gives `brew install dnglab`. |
| Adobe DNG Converter | As section 6. It is not part of the app. | One quiet line where the folder summary is, and in the scan text of the command line tool: "Adobe DNG Converter is not installed. It is an optional backup for photos that dnglab cannot match." No error, and no line when no ARW is pending. |

The Run button's N counts the pending ARW files when one converter or the
other is installed.

"dnglab converts first" is short for the table of 13.4: dnglab converts each
photo that it can match, and Adobe DNG Converter, when it is installed,
converts the others. Every text for a user or a model says it the long way.

With neither converter, the counts line carries the warning symbol, and the
install line below it carries the information symbol: one warning for one
condition.

### 13.6 Reports

- Scan JSON: a new key `"dnglab"`, the path or `null`, beside `"dngConverter"`
  (Adobe's path, as before).
- Run JSON: two new counts, `"convertedByDnglab"` and `"convertedByAdobe"`.
  Their sum is `"converted"`.
- Dry-run steps: a `convert` step has a new key `"converter"`: `dnglab` or
  `adobe`. The plan reads the ARW facts to decide. That read changes no file.
- A new note kind: `convertedUnmatched`.
- `--verbose` shows each dnglab command, as it shows the others.
- The MCP tools print the same JSON. Their descriptions name dnglab first.

### 13.7 Structure

| Unit | Does |
|---|---|
| `ARWFacts` | The five facts of 13.4 for one ARW, and the exiftool read that gets them for a list of files. |
| `AdobeMatch` | Pure: the table (a Swift literal of the data file), and from an `ARWFacts` the tags to write, or the reason there is no full match. No file access. |
| `DnglabConverter` | A `RawConverter`: the pre-start check, `dnglab convert --embed-raw false`, the match write, the read-back. |
| `ConverterChoice` | Pure: the table of 13.4, from the facts and what is installed to the ordered list of converters to try. The run and the dry run share it. |
| `AdobeConverter` | As before. |

`DesqueezeJob` takes both converters, each optional, in place of one.

### 13.8 Testing

- `AdobeMatch` and `ConverterChoice` are pure and unit-tested: every row of
  both tables, the rounding, ISO 50, an ISO with no row, a lens frame.
- `DnglabConverter` on fakes: each failure point leaves the partial DNG
  reported, and the pre-start check never does.
- With dnglab installed and the fixtures present: a real conversion, then
  the tags read back.
- **The drift check.** With both converters installed and the fixtures
  present, one test converts the fixture ARW with Adobe and with the app's
  dnglab path, and compares every matched tag. It fails when a new Adobe
  version, a new dnglab version, or new camera firmware changes a value.
- The parser of the facts read is pinned with real exiftool output from both
  kinds of frame, kept as text in the test.

### 13.9 Known limits

- The table is one camera, compressed raw, ISO 50 and 80 to 12800 without
  1250. Any other frame goes to Adobe, or gets the note. The values were
  measured at firmware 5.00. The app does not check the firmware: after a
  firmware update, run the drift check on a new frame.
- A matched render is not bit-identical to Adobe's. The mean of each colour
  channel is within 0.7%.
- dnglab 0.8.0 is the version tested. The drift check is the guard for a
  later one.
- exiftool prints a control character in a file name (a tab, a line end) as
  a period. The app compares such names as exiftool prints them. Two files
  whose names print the same get no facts, and so no full match.
- On a volume with no exclusive rename (ExFAT, measured), the app checks the
  name and then renames. A moment lies between the two system calls. A file
  that another program makes at `<base>.dng` in that moment is replaced. This
  is the one path left on which the app can replace a file it did not make.
- A leftover work file is removed only when its ARW is converted again. If
  the ARW is gone, or a DNG now claims it, the hidden work file stays.
- **A long file name.** A file name on a Mac volume can have 255 UTF-16
  units (measured 2026-10-10 on APFS, HFS+ and ExFAT: a name of 255 "あ", 765
  bytes, is made, and 256 is refused). HFS+ stores an accented letter as two
  units, so the app counts the decomposed form of the name. The longest name
  that the app makes for an ARW is exiftool's temporary file beside the work
  file, `.<base>.desqueeze-work.dng_exiftool_tmp`: the base name and 33 more
  units. So a base name of more than 222 units gets no converter, and the
  note says "The file name is too long. Shorten it, then run again." One
  rule holds for both converters. (Until 2026-10-10 the rule counted 255
  bytes and only the work file. That refused a long name with accented or
  Japanese letters that works, and it let a base of 223 to 235 letters fail
  in exiftool with the system's words.) The dry run uses the same rule.
- **One run in a folder at a time.** A second run that starts while the
  first works would remove the first run's work file as a leftover, and each
  could then act on the other's half-written file. So a run takes an advisory
  lock on the folder (`flock` on the folder itself: no lock file is made),
  and a second run in any front end stops at once with "Another Desqueeze
  run is working in this folder. Wait for it to end, then run again." A scan
  and a dry run take no lock. The answer of the lock call decides:

  | Answer | The run |
  |---|---|
  | The lock | Goes on, and frees the lock at its end. |
  | `EWOULDBLOCK` | Stops with the sentence above. |
  | `ENOTSUP`, `EOPNOTSUPP`, `ENOLCK`, `EISDIR`, `ENOSYS`, `EINVAL` | Goes on without a lock: the volume has none. The result has one note of the kind `noFolderLock`, on the folder's name: "This volume gives no folder lock. Do not start a second run in this folder while this run works." It is information, not a failure. |
  | `EINTR` | Asks again. |
  | Any other error | Stops as a folder that could not be read, with the system's words on the detail line. A descriptor that the system calls bad (`EBADF`) is not closed. |

  Measured 2026-10-10: the lock holds on the startup volume and on APFS,
  HFS+, ExFAT and FAT32 images, a second process gets `EWOULDBLOCK`, and the
  lock is gone after a hard end. No network volume was measured. The
  descriptor has `O_CLOEXEC`, so no program that the run starts keeps the
  lock.
- After a hard end of a run, the lock is free at once, and a converter that
  the dead run started can still work for a moment. A run that starts in
  that moment can meet its work file. Both converters end in under half a
  second here, and two trials showed no collision.
- A scan or a dry run that works while a run works can show a file in
  change, for example a DNG as blocked by a backup that the run is about to
  clear. Run it again after the run ends.
- The match table's numbers were measured from files that Adobe DNG
  Converter wrote. The repo publishes them as measurements, as open-source
  raw tools publish values of the same origin. Dom decided this on
  2026-10-10, before the first public commit, and `docs/decisions.md`
  records it.

## 14. The originals to the Trash, on request

Added 2026-10-10 at Dom's request, after his first run in Lightroom. Until
this section the app never moved an ARW. It still does not, unless the user
turns the option on for one run.

### 14.1 Decisions

Dom decided each of these on 2026-10-10.

| Decision | Why |
|---|---|
| The option is off by default, and it is never saved. | A box that stays on from an earlier day is the main way this feature can remove files that the user wants. |
| "Deleted" means moved to the Trash. The app never deletes an ARW. | The rule of the app is that nothing is deleted. The user can put a file back until the Trash is emptied. |
| Only an ARW that this run converted can go. | The run watched that conversion and checked its DNG. For an ARW that an earlier run converted, the only link to its DNG is a name. |
| The window and the command line tool have the option. The MCP server does not. | An agent must never be able to remove a user's originals, by request or by mistake. |

### 14.2 The rule

With the option on, the run has a fifth step after the four steps of 4.3:
**Move the originals.** It starts only when the run was not cancelled before
it. It takes one ARW at a time and reads the cancel flag between files.

An ARW goes to the Trash only when every line holds:

1. This run converted it, and the conversion passed (13.3).
2. The conversion has no `convertedUnmatched` note. A DNG that lacks the
   match is not complete, and the ARW is the way to convert the photo again
   when Adobe DNG Converter is installed.
3. The tag step for its DNG ended with the DNG at the chosen factor: the tag
   was set and read back, or it was at that value already.
4. The ARW is the file that was converted. Before the conversion the run
   records the ARW's size, modification date and file number, with a call
   that does not follow links. Directly before the move it reads them again.
   All three must be equal, and the ARW must be a regular file. A link or a
   folder never goes.
5. Directly before the move, `<base>.dng` is a regular file with bytes, and
   one exiftool read of it gives the ARW's name in `OriginalRawFileName` (by
   the comparison of 13.9) and the chosen factor in `DefaultScale`:

   ```
   exiftool -m -n -T -IFD0:OriginalRawFileName -SubIFD:DefaultScale <file.dng>
   ```

6. `<base>.dng` is the file that this run made. The name in
   `OriginalRawFileName` cannot prove that: another photo's DNG can carry
   the same name (seen 2026-10-10 in a trial: an outside rename put the DNG
   of another `frame.ARW` at `frame.dng` after the conversion, and the ARW
   moved). So the run records the DNG's size, modification date and file
   number, as for the ARW in line 4, at two moments: directly after the
   conversion passed, and directly after the tag step ended (exiftool
   writes a new file, so the record changes there). The first record must
   hold directly before the tag step reads or writes that DNG. The second
   must hold at step 5, before the read of line 5 and again after it. When
   the tag step wrote nothing (the DNG was at the value already), the second
   record is the first one. A DNG that fails a check is still tagged as any
   DNG in the folder is, but its ARW stays.

The run asks the lines in the order 1, 2, 3, 6, 5, 6 again, 4, so the second
read of the ARW is the last thing before the move. An ARW that has no record from before its conversion counts as changed. The name in line 5
is compared exactly, also in letter case. An ARW that is gone gets its own
sentence (14.3), because "it stays" would be false. A DNG whose own backup the Trash
refused (`backupKept`) is still complete.

Then the app moves the ARW to the Trash through the same injected function
that takes a backup there (`BackupHandling.trashFile`). So no test reaches
the real Trash, and `DESQUEEZE_TEST_BACKUP_FOLDER` holds for a built tool.

When a line does not hold, or the Trash refuses the file, the ARW stays, and
a note says why. The app never falls back to a delete, and it never tries a
second method.

The app moves the ARW only. A sidecar file beside it, such as `<base>.xmp`,
is not the app's file and stays.

Step 5 runs inside the folder lock of 13.9. `remove` never has step 5. A run
with `--no-convert` converts nothing, so it has nothing to move.

### 14.3 Notes and reports

A new note kind, `originalKept`, on the ARW's name. It is information, as
`convertedUnmatched` is: it does not count as failed or blocked, the result
does not get the "needs attention" symbol for it, and the exit code does not
change. The core makes each sentence:

| When | Sentence |
|---|---|
| Line 2 | "The original stays, because its DNG has no full match." |
| Line 3 | "The original stays, because its DNG is not complete." |
| Line 4, changed | "The original changed during the run, so it stays." |
| Line 4, not a regular file | "The original is not a regular file, so it stays." |
| Line 5 | "The original stays, because its DNG could not be checked." The detail line has exiftool's words, or what differed. |
| Line 6 | "The original stays, because its DNG changed during the run." |
| The ARW is gone at step 5 | "The original was not in the folder at the end of the run. The app did not move it." |
| The Trash refused | "The original could not go to the Trash, so it stays." The detail line has the system's words. |

An ARW whose conversion failed gets no such note: its `failed` or
`notConverted` note says enough. After a Cancel, the ARW files that step 5
did not reach get no note: the result says "stopped". A Cancel that arrives
during the last tag step, with originals still to move, gives `stopped`
true.

When the option was on, the result has one more line, from the core, in
every front end that has the option: "Originals moved to the Trash: N of M."
M is the count of ARW files that this run converted. A dry run does not
show the line. Its notes carry `originalKept` for each ARW that would stay,
so the plan and the run give the same notes.

Run JSON: two new keys, always present. `"trashOriginals"` is true when the
option was on. `"originalsInTrash"` is the count of ARW files that the run
moved. A dry run with the option on gives the count that a real run would
give if every step passed, and one more step for each such ARW, after the
write steps: `{ "name": "<file.ARW>", "action": "trashOriginal" }`. The plan
knows which conversions would get the `convertedUnmatched` note (13.4), and
gives those no such step. The run and the dry run share the function that
decides.

Progress: one more step for each converted ARW, also one that stays.

For `remove`, `"trashOriginals"` is false whatever the caller gave.

### 14.4 The window

A checkbox between the factor row and the Run button: "Move the original ARW
files to the Trash".

- It shows only when the loaded folder has at least one pending ARW that can
  convert. In any other state it is not shown, and it is off.
- It is off at every launch, when another folder loads, and after every run,
  also a run that was cancelled or that failed. A scan of the same folder
  when the app becomes active again does not change it.
- The app never saves it, and no launch argument turns it on.
- While it is on, a line under it says what the run will do: "N original ARW
  files go to the Trash after their DNG files pass the check." (For one:
  "1 original ARW file goes to the Trash after its DNG file passes the
  check.") N is the count of pending ARW files that can convert.
- While it is on, the Run button reads `Desqueeze N photos, move M ARW to
  Trash`, in the words of Finder's "Move to Trash". The text is the same for
  one and for many. (The first text, "…move M originals to the Trash", was
  cut at the window's width from about 320 points: measured 2026-10-10 with
  228 photos and 12 originals.) The label must fit with four digits in each
  number. The window asks nothing more: the box is the request, and the
  Trash is reversible.
- While a run or a scan is in work, the box cannot change. It keeps its
  state through the run, and goes off when the run has ended.
- The box is not shown for a read-only folder.
- The Remove button is not affected.
- VoiceOver hears the checkbox by its label, and hears the line of 14.3 with
  the result counts.

### 14.5 The command line tool

`desqueeze run <folder> --factor <number> --trash-originals`. The flag is
valid on `run` only.

- With `--no-convert` it is a usage error, exit 2: the pair can do nothing.
- On `scan` and `remove` it is a usage error, exit 2.
- With `--dry-run` it prints the steps of 14.3 and moves nothing. A step in
  text: `  trash    frame.ARW`.
- `--help` says that the flag moves each original to the Trash after its DNG
  passes the check, and that it is off unless given.
- No environment variable and no saved setting turns it on.

### 14.6 Structure and testing

`DesqueezeJob.run` and `DesqueezeJob.plan` take the option as a parameter
with no default value in the job itself, so each caller states it. One pure
function decides, for one converted ARW, "move" or "keep, with this reason".
One unit records and compares the ARW's three facts of line 4.

- The pure function: every row of 14.3, and the case in which all lines hold.
- The job on fakes: with the option off, no ARW reaches the trash function in
  any outcome. With it on: each keep reason; a cancel before step 5 and
  during it; the Trash refuses; the order (no ARW moves before every tag step
  has ended).
- The real tools, in a temporary folder with the injected trash: after a run
  with the option on, the folder holds the DNG and no ARW, and the file in
  the injected trash has the same bytes as the source ARW.
- The command line tool, end to end with `DESQUEEZE_TEST_BACKUP_FOLDER`: the
  flag, the two usage errors, the dry run, the JSON keys.
- The window's model: the box is off at the start, after a run, and after a
  new folder; nothing is written to the saved settings; the button label and
  the line under the box.
- The MCP server: a call with a parameter such as `trash_originals` moves no
  ARW, and the tool descriptions say that the server never moves an original.
- A behavioral test counts only after it fails against a break. The first
  break to try: the option is treated as on when it is off.

### 14.7 Known limits

- Lines 4 and 6 compare size, modification date and file number. They do
  not compare the bytes. A program that writes an ARW in place, keeps its
  size, and puts the date back is not seen. On FAT32, a file that is deleted
  and made again at the same name with the same size and date gets the same
  file number (measured on a disk image; APFS, HFS+ and ExFAT gave another
  number).
- A moment lies between the end of a conversion and the first record of its
  DNG. A second, longer one lies between the check before a tag step that
  writes and the record after it: exiftool works on the DNG in that time,
  about a tenth of a second, and its write gives the file a new record, so
  the run cannot tell exiftool's new file from another one. A swap after
  the last check of step 5 is the same as a swap after the run. A file that another
  program puts at `<base>.dng` in one of those moments is taken as the
  run's own. Line 5 still holds for it: it must name the ARW and carry the
  factor.
- An ARW that cannot be read at step 5, for any reason, gets the sentence
  of a gone ARW. No file moves.
- The Run button's count N includes a pending ARW whose name is too long,
  so the run starts and its note says why that ARW did not convert. The
  box, its line, and M leave it out.
- The line under the box, the Run button and a dry run count from the last
  scan. The run scans again (4.3), so it can convert and move more or fewer
  ARW files than they said, when the folder changed in between.
- A dry run lists a `trashOriginal` step for each ARW that it expects to
  convert. When a conversion then fails in the real run, that ARW stays.
- The MCP server has no parameter for the option, but an agent that has a
  shell can start the command line tool with the flag. The server's text
  does not tell a model where the option is.
- The check of line 5 reads the DNG's structure and tags. It does not decode
  the picture. The Trash is the guard for the rest: look at the DNG files in
  Lightroom before the Trash is emptied.
- With the ARW gone, the photo cannot be converted again with a later
  converter or a later match table.
- A catalog that already holds the ARW files shows them as missing after the
  move. Use the option before the import, or import the DNG files.
- On a volume that has no Trash, the move is refused and every ARW stays.
- On an external volume the ARW goes to that volume's Trash, and its space
  is free only after the Trash is emptied with the volume connected.

## 15. The download

Until this section, a person got the app only by a build from source, and
installed exiftool and dnglab with Homebrew. Section 6 pointed a later
release at a signed, notarized download. This section is that release.

### 15.1 Decisions

Dom decided these on 2026-10-10.

- The project has a download: one disk image on the Releases page of the
  repo on GitHub.
- A person installs nothing more. exiftool and dnglab are inside the app.
- The first download is for a Mac with Apple silicon only.

These follow from them:

- The download holds the window only. The command line tool and the MCP
  server stay a build from source, and they still find the two programs on
  the Mac (sections 6 and 13.5).
- Adobe DNG Converter is never inside. Its license does not allow that, and
  the app works with no copy of it.
- The app has no update check. It makes no network connection, and this
  section does not change that.

### 15.2 What a person gets

| Item | Value |
|---|---|
| File | `Desqueeze-<version>.dmg` |
| Holds | `Desqueeze.app`, and a link to the Applications folder |
| Signature | Developer ID, with the hardened runtime and a secure time stamp |
| Notarization | By Apple. The ticket is stapled to the app and to the disk image, so the first start needs no network connection. |
| Mac | Apple silicon. macOS 14 or later. |

The app has no entitlement and is not sandboxed (section 6). The hardened
runtime needs no exception: the app starts other programs, and loads no code
of another signer.

### 15.3 The programs inside

| Program | Version | Place in the app |
|---|---|---|
| dnglab | 0.8.0 | `Contents/Helpers/dnglab` |
| exiftool | 13.55 | `Contents/Resources/exiftool/exiftool`, with its `lib` folder beside it |
| License texts | | `Contents/Resources/licenses/` |

- **The copies come from Homebrew on the Mac that makes the release.** The
  release script holds the version of each program and three SHA-256
  values: of the dnglab binary, of the exiftool script, and of exiftool's
  `lib` folder. It stops when one differs. A new version of a tool is a new
  measurement first (13.2), then a new pin.
- **dnglab is the file that the match table of 13.2 was measured with.**
  Its code is not changed. The script signs it with the Developer ID, as it
  signs the app. That replaces the code signature, so the SHA-256 of the
  copy in the app differs from the pin.
- **Homebrew has two copies of the exiftool script, and the app takes the
  one that can move.** The copy on the `PATH`, `bin/exiftool`, has the path
  of Homebrew's own folder written into its include lines. The copy in
  `libexec/bin` looks for `lib` beside itself. The two differ in those
  lines only. The measurement of 13.2 ran the first, and the app holds the
  second.
- **One line of that script changes: the first.** Homebrew's copy starts
  with the path of one Perl version. The copy in the app starts with
  `#!/usr/bin/perl`, the Perl of macOS.
- **The `lib` folder holds exiftool's own files only**: the `Image` folder
  and `File/RandomAccess`, not changed. Homebrew keeps them in one folder
  with other Perl packages, one of them compiled. Those stay out. A DNG
  needs none of them.
- A Mach-O program goes in `Contents/Helpers`, and a script goes in
  `Contents/Resources`. The code signature of a bundle needs it so.

### 15.4 Where the window looks

The window looks in its own bundle first, then where it looked before.

| Program | Order |
|---|---|
| exiftool | The copy in the bundle, when it can be run and `/usr/bin/perl` can be run. Then as section 6. |
| dnglab | The copy in the bundle, when it can be run. Then as 13.5. |
| Adobe DNG Converter | As section 6. |

- The bundle comes first because its versions are the tested ones. A person
  cannot make the downloaded app use another copy. That is on purpose.
- A build from source has no program inside, so it looks as before. Nothing
  changes for it.
- `ToolLocator` gets the two places from the app layer, as it gets the
  registered Adobe app. The core still holds no path of one Mac. A value
  type in the app layer turns the URL of the bundle into the two places, so
  a unit test can check them.
- The command line tool and the MCP server pass no place, and look as
  before.
- The launch hooks of section 9 still hide a program, also one in the
  bundle.
- No message changes. In the downloaded app, the messages about a missing
  exiftool or dnglab can show only when macOS has no Perl.

### 15.5 The release script

`scripts/make_release.sh` makes the disk image on the Mac that has the
Developer ID. It uploads nothing. Each step stops the script when it fails.

1. **Check.** The work tree is clean. The version of `project.yml` has a
   dated section in `CHANGELOG.md`. The two programs are at the pinned
   versions and hashes. The keychain has one "Developer ID Application"
   identity. The keychain profile for the notary service exists.
2. **Build.** `xcodegen generate`, then a Release build for arm64 into a new
   folder under `build/release/`.
3. **Put the programs inside**, with the license texts (15.6).
4. **Sign from the inside out**: dnglab first, then the app. Each with the
   hardened runtime and a time stamp. Never `--deep`.
5. **Prove the bundle.** `codesign --verify --strict` passes. The two
   programs, started from inside the bundle, give their pinned versions.
   The executable of the app holds no path of the Mac that built it: the
   script strips the debug records, and stops when one is left.
6. **Notarize the app** from a zip, and staple the ticket to the app.
7. **Make the disk image** from the stapled app, sign it, notarize it, and
   staple it.
8. **Prove the result.** `spctl` accepts the app, the disk image, and the
   app inside the disk image. The script prints the path of the disk image
   and its SHA-256.

- The script holds no name of a person, no Apple ID and no team. It finds
  the identity in the keychain by its kind. The notary credentials are in a
  keychain profile that `xcrun notarytool store-credentials` makes. The
  name of the profile comes from `DESQUEEZE_NOTARY_PROFILE`, and is
  `desqueeze-notary` when the variable is not set.
- `--local` checks the pins, then does steps 2, 3 and 5 with an ad hoc
  signature, and stops. It needs no Developer ID, a clean tree is not
  required, and it makes no disk image. The app is at `build/release/local/Desqueeze.app`. It is for
  checks, and for the Mac that built it.
- The script never writes outside `build/release/`, with one exception:
  `xcodegen` writes the Xcode project at the root of the repo, as every
  build does. The script removes only what an earlier run of the script put
  in `build/release/`: each folder that it makes carries a marker file, and
  a folder with no marker is never removed.
- Step 1 makes every check, says one sentence for each one that failed,
  and then stops. The check of the notary profile needs the network, so it
  runs only when every other check passed.
- The notary service can accept a file some seconds before its ticket can
  be fetched. So the script tries each staple again, a few times, before
  it stops.
- When a disk image for the version is there already, the script stops at
  step 1. A signed disk image is never removed by the script.
- A release is published by hand, on Dom's yes: `gh release create` with
  the disk image, and the source archive of 15.6.
- GitHub Actions makes no release. The identity stays on one Mac.

### 15.6 Licenses

- **dnglab, LGPL-2.1-only.** The app holds the binary as a separate program,
  not linked, and with no change but its code signature. The app holds dnglab's license text. Each
  release page also has the source archive of that dnglab version as a
  file, so the source is at the same place as the binary.
- **exiftool, the terms of Perl.** The app holds exiftool's README, which
  states the terms, and a note about the one changed line.
- `THIRD_PARTY_NOTICES.md` gets a part for the programs inside the
  download, and a copy of the file goes into `Contents/Resources/licenses/`.
- The project stays under MIT. These files state facts and make no legal
  claim.

### 15.7 Testing

- Unit tests of `ToolLocator`: the bundle comes first; with no place given,
  the order is as before; the exiftool of the bundle is taken only with
  `/usr/bin/perl`; a place that cannot be run falls through.
- A unit test of the value type that makes the two places from a bundle URL.
- The window finds its three programs through one function of the app
  layer, and the tests call the same function. So a test fails when that
  function passes no place, or when a launch hook no longer hides a
  program. The call of the function in `AppModel.live` has no test: no
  argument has a default, so a call with an argument left out does not
  compile, and the trial below checks the rest by hand.
- A test reads the release script, and fails when the two places in the
  script differ from the two places of that value type.
- `scripts/make_release.sh --local` on the release Mac, then a real run in
  the window of that app, on copies, with the process list as the proof that
  the two programs of the bundle did the work.
- A trial in the window reaches the Trash (section 9). So a trial uses a
  folder on a scratch disk image: a file that goes to the Trash there goes
  to the Trash of that image, and leaves with it. Prove that on one file
  first.
- Steps 6 to 8 need the Developer ID. The release of version 0.1.0 proved
  them, on macOS 27.2: all eight steps passed, and the app from the disk
  image ran its two programs in a window trial. `hdiutil` says there that a
  later macOS wants `diskutil image` in its place.
- Step 4 with the Developer ID asks for the key in the keychain the first
  time, with a dialog. When the answer comes late, the time stamp is too
  old and `codesign` fails. A second run is the fix.

### 15.8 Known limits

- The download is for Apple silicon. On an Intel Mac the app does not
  start. A build from source on an Intel Mac was not tested either.
- The exiftool inside needs the Perl of macOS. Apple has said that a later
  macOS can come without it. Then the window looks for exiftool as a build
  from source does.
- A person cannot replace a program inside the downloaded app. A newer
  dnglab reaches the app only with a new release.
- The app cannot say that a new release exists.
- The dnglab binary holds Rust libraries of other people. The app carries
  the notices that dnglab's own Homebrew package carries, and no more.
- Only the Mac with the Developer ID can make a release.
- The command line tool and the MCP server are not in the download.

## 16. The privacy page

Added 2026-10-12, after the first release. Desqueeze is a Plateworks
property, and each property has a privacy page that is exact about what it
loads and saves. Dom also decided the register and the accent of Desqueeze
that day. Those two live in the canon of the Plateworks workspace, not in
this repo: `PROJECT_CHARTER.md` has the register, and section 16.6 says what
the accent means here.

### 16.1 Decisions

| Decision | Why |
|---|---|
| The page is an article of the DocC catalog, `Privacy.md`. | The site is the one public page of the property, and DocC has no footer and no free page. An article is in the search and the navigation of the site. |
| The first page of the site and `README.md` link to it. | A footer link is not possible. These are the two first pages that a person reads. |
| The site build writes a page at `/privacy/` that sends a person to the article. | Each Plateworks property has its privacy page at that address. |
| The contact is `dom@plateworks.org`, written in full, as a link. | A form such as `dom[at]plateworks.org` stops few scrapers. It is worse for a screen reader and for a person who copies it. |
| The page has a line "Last updated" with an ISO date. | A person can see how old the statements are. |
| When what a part loads or saves changes, the page changes in the same commit. | A privacy page that is not true is worse than none. |

### 16.2 What the page says

The article has five parts, in this order. Each statement is in the present
tense and is about one thing. The page states facts and makes no legal
claim.

1. **The first line.** Desqueeze collects nothing.
2. **The app.** No account, no analytics, no crash report, no advertisement.
   It makes no network connection, so it has no update check. It reads and
   changes files only in the folder that the person chooses, and a file that
   it discards goes to the Trash of the Mac. It saves one setting of its
   own on the Mac: the last squeeze factor. macOS saves three more for the
   app, as it does for each app: the place and size of the window, the
   size of the folder dialog, and the last folder that the folder dialog
   showed. One item is about Adobe DNG Converter: it is
   an optional program of Adobe, the app starts it only as the backup
   converter, and the page makes no statement about what that program
   does. One sentence is about macOS and not about
   the app: when a person opens a downloaded app the first time, macOS
   checks it, and macOS can contact Apple for that.
3. **The command line tool and the MCP server.** The same: no network
   connection, nothing collected. The server talks only to the program that
   started it, through standard input, standard output and standard
   error. An answer of the server holds the path of the folder and the
   names of its files. The answer of a scan also holds the paths of the
   programs on the Mac and two tag values of each DNG. The answer of a run
   can hold the camera model or the ISO of a photo, and the error text of a
   program. What that program sends to its own service is the matter of
   that program.
4. **The website and the download.** No cookie, no analytics, no form. The
   pages load no file from another host. The site saves three things in
   the browser of the person, and they stay there: display settings, the
   scroll position of the session, and the state of the page list for the
   session, with the text that the person types in its filter. GitHub hosts
   the site and the download.
   GitHub keeps server logs, which have the IP address of a visitor, and it
   counts the downloads of each file. The page links to GitHub's privacy
   statement.
5. **Contact and date.** `dom@plateworks.org`, and "Last updated" with the
   date.

### 16.3 The proof of each statement

No statement goes on the page before its proof was run. The proofs are part
of the work, and `docs/changing-things.md` gets a section that names them,
for the next change.

| Statement | Proof |
|---|---|
| The app, the tool and the server have no code that makes a network connection. | A search of the sources of the core, the app, the tool and the server for the network types of Foundation and the Network framework finds none. The server's use of its library is the standard input and output transport only. |
| exiftool and dnglab make no network connection in a run. | During the tests on the real programs, a sample of the open network sockets of the processes of exiftool, perl and dnglab shows none. |
| The app saves one setting of its own, and macOS saves three more. | A search of the app's sources for the defaults of the system finds one key that is written, `lastFactor`. After the folder dialog was open one time, `defaults read org.plateworks.desqueeze` shows that key and three keys of macOS: `NSWindow Frame main`, `NSNavPanelExpandedSizeForOpenMode`, and `NSOSPLastRootDirectory`, a bookmark of the last folder that the dialog showed. The review found the third key: it is not there before the dialog opens. So this proof reads the defaults after a use of the dialog. |
| The pages load no file from another host. | `scripts/check_site_privacy.sh` searches the built site for a `src`, an `href` to a style or a script, and a `url()` with another host, and finds none. The data files of the site hold links to the sources on GitHub. They are links, and the pages load nothing from them. |
| The site saves three things in the browser. | A search of the scripts of the built site finds: in the local storage, display settings with the prefixes `developer.setting.` and `docs.setting.`. In the session storage, `scrollPosition`, and `developer.setting.navigator.state`, which holds the page, the open items, the selected tags and the filter text of the page list. No cookie. The same script makes this search: it prints each key that it finds, and it fails for a key that is not in its list, for a cookie, a beacon, a database or a service worker. |
| GitHub keeps logs and counts downloads. | GitHub's document about GitHub Pages says that it logs the IP address of a visitor. GitHub's API gives a `download_count` for each file of a release. The page links to GitHub's privacy statement and claims no more than that. |
| The page makes no statement about Adobe DNG Converter. | Nothing to prove. The proofs watch exiftool and dnglab only, so the page must not speak for Adobe's program. |

The search of the built site was run on 2026-10-12, with Xcode 27.0: it
found no file from another host, the keys above, and no cookie, beacon,
request to another host, database or service worker. A first, shorter search
missed the state of the page list, so the proof names each key that it
finds. DocC's scripts change with Xcode, and the published site is built by
GitHub's runner, with its own Xcode. So `scripts/build_docs.sh` runs
`scripts/check_site_privacy.sh` at its end, each time and on each machine.
A build with a new key fails, and a person then changes the page and the
list in the same commit. On 2026-10-12 the script also ran on the site that
GitHub's runner had built for the live pages: it passed, with the same keys
as the build with Xcode 27.0. One key in the list, `docs.setting.preferredColorScheme`,
is an older name that the scripts read and never write.

### 16.4 The files

| File | Change |
|---|---|
| `Sources/DesqueezeCore/DesqueezeCore.docc/Privacy.md` | New. The article. |
| `Sources/DesqueezeCore/DesqueezeCore.docc/DesqueezeCore.md` | A link to the article in the topics for a photographer, and one sentence in the text. |
| `scripts/build_docs.sh` | After `docc convert`, it writes `privacy/index.html`, in the form of the page that it writes for the first address. The link is relative, so it holds under any base path. The script stops when the article is not in the built site. At its end it runs `scripts/check_site_privacy.sh`. |
| `scripts/check_site_privacy.sh` | New. The search of the built site of 16.3: files from another host, cookies, and the keys of the browser storage against a list. |
| `README.md` | One line with the link, in the section "Where to go next". |
| `PROJECT_CHARTER.md` | The section "Register" gets the register that Dom decided. |
| `docs/changing-things.md` | A section "Change what a part loads or saves": change `Privacy.md` and its date in the same commit, and run the proofs of 16.3. |
| `docs/decisions.md`, `CHANGELOG.md`, `SECURITY.md`, `docs/README.md` | The decision rows, the entry, a link to the article, and the row for the new article. |
| `Tests/DesqueezeCoreTests/DocsCheckTests.swift` | One test, 16.5. |

### 16.5 Testing

- One test reads `Privacy.md`. It fails when the article has no line "Last
  updated" with an ISO date, when the contact is not there, or when the
  first page of the catalog does not link to the article.
- `scripts/build_docs.sh` stops when `docc` gives a warning, as before, and
  when the built site has no page for the article.
- By hand, after the publish: the live site shows the article, the first
  page links to it, and the address `/privacy/` reaches it.
- `scripts/check_site_privacy.sh` runs in each site build, also on GitHub's
  runner. It was tried against a built site with one more storage key, with
  a script from another host and with a cookie: it fails for each.
- No test asks a network. The other proofs of 16.3 are run by hand.

### 16.6 The register and the accent

The register is in `PROJECT_CHARTER.md`: an operational tool. The accent of
Desqueeze in the Plateworks color standard is Chalcanthite, a copper blue.
It is assigned, and not in use: the app follows the accent color of each
person's Mac, and the site has DocC's own colors. This repo holds no color
value. A later release can put the accent into the app and the site, and
that release takes the values from the color standard, never by hand.

Version 0.1.1 is that release. Section 17 has it, and since then this repo
holds the color values that section 17.1 lists.

### 16.7 Known limits

- The address `/privacy/` holds a page that sends a person on. It is not
  the article itself.
- The statements about GitHub are GitHub's to keep. The page links to them
  and cannot prove them.
- The proofs of 16.3 about the app, the tool and the server are run by
  hand. A later change can make a statement false with no failing test. The
  section in `docs/changing-things.md` is the guard.
- The search of the site reads minified scripts. It finds a storage key
  that is written as text. A key that a script builds in a way that the
  search does not know can pass. The header of the script lists the forms
  that it cannot see, for example a cookie that is reached through another
  name for the document, and a request that a script makes to another host.
- The page speaks for the scripts of the site. It cannot prove what GitHub
  sets when it serves a page.

### 16.8 The pictures for a reader with no JavaScript

Added 2026-10-12. The second review of the privacy page found it, and it
is a fault of the site, not a privacy statement.

`docc` writes the text of each page a second time, into a `noscript`
element, for a browser with no JavaScript and for a search engine. Its
`picture` element there has three faults. Each `source` has a `src`, and a
browser reads only `srcset` in a `picture`. That `src` is the path of the
file in the checkout of the build, in small letters, not the address of the
file in the site. The `img` has no `src`. So such a reader got the text
alternative and no picture, and two public pages named a folder of the
machine that built them. The docc of Xcode 26.6 and of Xcode 27.0 both do
this.

`scripts/fix_static_pictures.py` corrects each such `picture` after `docc
convert`:

- For each `source`, it takes the file name from the wrong `src`, finds the
  one file with that name under `images/` of the site, and writes its
  address as `srcset`, relative to the page. The name is written as the
  site has it, because a web server tells `A.png` from `a.png`. A name with
  `@2x` gets the density `2x`, so the picture has its correct size.
- The `img` gets the address of the light variant as its `src`. For a name
  with `@2x` it gets a `srcset` with the density too. So a reader that
  ignores the `source` elements shows the picture at its correct size.
- A picture with one variant has no `source`: `docc` gives its `img` the
  wrong address directly. The script corrects that `src` in the same way.
  The independent review found this form with a real build.
- It reads and corrects each page before it writes the first one. When a
  picture has no file under `images/`, or more than one, it stops the build
  and changes no page.
- A `picture` that is correct already stays as it is. So a second run
  changes nothing, and a later `docc` with no fault passes.

`scripts/check_site_privacy.sh` then fails for a page that holds the path
of this checkout. It also fails for the address of a picture that has the
end of the path of a catalog in it, which a site from another machine has.
Before, it printed the count and did not judge it.

Testing. `StaticPicturesTests` gives the script a small site in a temporary
folder. Its cases are: the wrong form, a name in capital letters, the dark
variant first, a picture with one variant and a space in its name, a fault
on a later page, a second run, a correct page, a missing file, and two
files with one name. By hand, the page "Using the window" was loaded as
plain content, as a browser with JavaScript off shows it. Before the
correction no picture loaded. After it, each picture in view loaded at 552
points wide.

Known limits. The script knows the form that `docc` writes today: one `img`
in each `picture`. Another form stops the build with a sentence. A web view
that only blocks scripts hides the `noscript` part, so it cannot show this
part of a page: use a browser with JavaScript off.

## 17. The accent and the icon

Added 2026-10-12, for version 0.1.1. Before it, the app took the accent of
each Mac, the site had DocC's colors, and the app had no icon of its own.
Each claim about macOS in this section was tried on macOS 27.2, on a Mac
whose accent is red.

### 17.1 Decisions

- The accent is Chalcanthite, the accent of Desqueeze in the Plateworks
  color standard. The values come from that standard, never by hand:

  | Part | Light | Dark |
  |---|---|---|
  | Ink, for text | `#00688F` | `#65B4DD` |
  | Fill | `#157BA6` | `#4595BC` |
  | Hover | `#004C6A` | `#7DCDF7` |
  | A label on the fill | `#FFFFFF` | `#020306` |

- The app uses one value in both appearances: the light fill, `#157BA6`.
  White on it is 4.76:1. The app does not use the dark fill, because macOS
  draws white text on the accent in its own controls, and white on
  `#4595BC` is 3.34:1.
- macOS uses the `AccentColor` of an app only when the accent of the Mac is
  Multicolor. Any other choice wins over it. Proof: a build with the color
  asset and no other change showed the selected preset in red. So the app
  does not rely on `AccentColor`. The content view has
  `.tint(Color.chalcanthite)`, and each view that used `Color.accentColor`
  uses the named color. The asset `AccentColor` stays, with the same value,
  for the parts that macOS draws outside the view.
- The site gets `theme-settings.json` in the catalog. It holds colors only:
  no font, no address. `scripts/check_site_privacy.sh` reads it in each
  build. Its keys:

  | Key of DocC | Value |
  |---|---|
  | `link`, `figure-blue` | The ink |
  | `nav-link-color-hover`, `nav-dark-link-color-hover` | The light ink, the dark ink |
  | `fill-blue`, `button-background`, `focus-border-color`, `focus-color` | The fill |
  | `button-background-hover`, `button-background-active` | The hover |
  | `button-text` | The label on the fill: white in light, `#020306` in dark |

  The site keeps DocC's grounds, white and black. The ink is 6.22:1 on
  white, and 9.13:1 on black. The label is 4.76:1 on the light fill, and
  6.17:1 on the dark fill.
- The icon is the drawing on plateworks.org/apps/ (concept "Desqueeze A"),
  in the color that Dom chose: the four contours of the Plateworks mark,
  verbatim, as lines, over a copy of them squeezed to 0.52 of their width.
  The true rings are Chalcanthite. The squeezed copy is a grey of the
  ground. It says what the app does: the squeezed photo, and the photo at
  its correct shape.

### 17.2 The window

- The tint is on the content view, before `onAppear`, and not on the view
  in `DesqueezeApp.swift`. Proof: with the tint in `DesqueezeApp.swift`,
  the window opened with the custom factor selected, three times of three.
  The first focus of the custom field then came after the block that
  ignores it (section 6). With the tint in the content view, the window
  opened with the preset selected, as before.
- The selected preset and the Run button have white text on the accent.
- The tint of a window also colors the label of each bordered button. So
  "Choose folder", "Remove" and "Cancel" take no tint, and stay grey. Only
  the main action has the accent, and it stands out.
- The custom-factor field keeps its border in the text color. The reason
  changes: before, the accent could be red. Now, a border in the accent
  beside a preset that is filled with the accent reads as a second
  selection. The comment in `ContentView.swift` says the new reason.
- The drop target uses the accent for its border and its 12% tint.
- `SymbolLine` keeps its rule: the symbol carries the meaning, never the
  color alone. Its comment no longer names a red accent.

### 17.3 The icon

- `scripts/make_app_icon.py` writes the vector, `App/AppIcon.svg`, and
  each slot of `App/PlateworksDesqueeze/Assets.xcassets/AppIcon.appiconset`
  (16, 32, 128, 256 and 512 points, each at 1x and 2x) from one set of
  constants. It draws each size from the vector. With `--master` and the
  file of the master mark, it stops when the four contours differ. The
  master is kept outside this repo, so with no path the script says that
  it did not compare. It stops when `Contents.json` names other files.
  With `--check` it writes nothing, and fails for a file that differs.
- The tile is the shape of a Mac icon since macOS 11: at 1024 pixels, a
  square of 824 with corners of radius 185.4, and nothing around it. The
  first plan was a tile that fills the square, for macOS to cut. macOS 27.2
  does cut such a tile, and it draws both forms the same. macOS 14 and 15
  draw an icon as it is given, so the full square would be a hard square
  there. Those versions were not tried: no such Mac is here.
- Geometry on a grid of 200 units. The tile is 160.9 units wide. The mark
  is scaled about the center of its ink (50, 49.2 in mark units) onto the
  center of the tile, at 1.448 grid units for each mark unit. That is the
  1.8 of the drawing, times the part of the grid that the tile fills. The
  lines are 4.5 mark units for the true rings and 3.4 for the squeezed
  copy. The lines of the copy are squeezed with it. Each core is filled.
- Values: the ground is Halite, `#EAEEE9`. The true rings are the fill,
  `#157BA6`, 4.05:1 on the ground. The squeezed copy is `#AEB6AD`: the hue
  of the ground, darker. It is derived for this icon, and it is no token of
  the color standard.
- The ink is 66.7 grid units from the center at its farthest, and the tile
  has 80.5 to its edge.
- The script's file of 1024 pixels and a Quick Look render of the vector
  differ by a mean of 0.06 of a level for each channel.
- The Plateworks standard for marks gets the icon's geometry, values and
  fit, in the maintainer's workspace, not in this repo.
- The browser tab of the site keeps DocC's favicon. The site has no mark.

### 17.4 Testing

`AccentAndIconTests` reads files of the repo, and starts no app:

- The two color assets hold `#157BA6`, with one value for both appearances.
- The content view has the tint before `onAppear`, `DesqueezeApp.swift` has
  none, and no view asks for the accent of the Mac.
- `project.yml` names the accent and the icon.
- `theme-settings.json` holds the key `theme` with the key `color` only,
  and each value is a value of 17.1. A font, an address or another color
  fails.
- Each slot of the icon set has a file of its size in pixels.

Each test failed against a break first: a changed value, a second value for
the dark appearance, `Color.accentColor` in a view, no tint, the tint in
the other file, a line of `project.yml` removed, a font, an address and
another color in the theme, a slot removed, and a file of the wrong size.
The three stops of the icon script were tried too.

By hand:

- On a Mac with a red accent: the presets, the Run button, the checkbox,
  the progress bar and the drop target are Chalcanthite, in both
  appearances. "Choose folder", "Remove" and "Cancel" are grey.
- The site in a browser, in both appearances: the variables of 17.1 have
  their values, and a link in an article has the ink.
- The ten screenshots again ("Take the screenshots again").
- The icon in the Dock, in Finder, and in the window of the disk image.

### 17.5 Known limits

- A person who wants their own accent in the app cannot have it.
- The icon has one appearance. macOS 26 and later can tint or darken it.
- The icon has no shadow of its own, which the icons of macOS 11 to 15
  have.
- macOS 14 to 26 were not tried, for the tint, the buttons and the icon.
- The tests read the source. They cannot see a color on the screen, so the
  check by hand stays.
