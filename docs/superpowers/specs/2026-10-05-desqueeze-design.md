# Desqueeze design

Date: 2026-10-05. Red-teamed 2026-10-09; section 2.1 holds the findings and
each one's fix is in the body. Revised 2026-10-09 after the code reviews of
the job and the window, and extended with section 12 (command line and MCP). Status: approved by Dom in session, pending his
read of this file.

## 1. Purpose

Dom shoots stills on a Sony A7S III with anamorphic lenses of different squeeze
factors. The photos are squeezed. A DNG file can carry a `DefaultScale`
tag, and Lightroom and Camera Raw stretch the image by that tag when they render
it. No pixels change, and the tag is reversible.

Until now Dom wrote the tag with six terminal steps
(`~/My Drive/To file/dng-desqueeze-guide.md`). Desqueeze is one Mac window that
does the same job: drop a folder, pick a factor, run.

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
| Both converters write `OriginalRawFileName` into the DNG. | 4.1: the pending rule reads it. |
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
| Time for one file | 0.07 s | 0.37 s |
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
| A bundled dnglab | dnglab is the first converter since 2026-10-09 (section 13). Version 1 finds the one Homebrew installed. A shipped app must carry its own. |
| A match table for cameras other than the A7S III | Section 13 has one measured row. Each other camera needs its own. |
| Code signing and notarization | Needed only for other people's Macs. |
| Brand marks, accent color, app icon art | `00_Resources/brand-marks.md` and `00_Resources/color-standards.md` govern them. Version 1 uses system colors and the system font. |
| Register row in `00_Resources/plateworks-principles.md` | A register belongs to a published property. |
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
  ignore letter case. Both converters write that tag, so a DNG that was renamed
  on import still claims its ARW.
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
   "<Adobe DNG Converter>" -c -d <folder> <file.ARW>
   ```

   The conversion passes when the exit code is 0 and `<base>.dng` exists. Both
   conditions are needed: the converter returns 0 on a file it cannot read, and
   makes no DNG. A DNG with no bytes is not a DNG: that conversion failed.
   The app never changes, moves, or deletes an ARW. If `<base>.dng` appeared
   after the scan, the app does not start the converter for that ARW, and
   reports it.

   A converter that is ended before it completes can leave a `<base>.dng`
   with no bytes (tested 2026-10-09: the terminate and kill signals at 0.30 s
   of a 0.37 s conversion). Left there, that file would claim the ARW in every
   later scan, and the photo would never convert. So when a conversion fails
   after the converter started, and `<base>.dng` is there, the app moves that
   file to the Trash and says so on the note's detail line. The app made the
   file in this run: the check before the start proved that no DNG had that
   name. If the Trash refuses, the note names the file to delete by hand.

   The command line ignores the converter's window preferences. With `-c` it
   writes DNG 1.4, lossless raw, JPEG previews. That is the format of every DNG
   this app makes. Never pass `-h`: it opens a window and the process never
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

When a run left ARW files unconverted because Adobe DNG Converter is missing,
the result says so, with the count.

The result line and each error message carry a symbol, and the counts stay in
the primary text colour. Colour is never the only signal: the Mac's accent
colour can be the same red as an error. A result with a failed or blocked file
gets the "needs attention" symbol.

Under the counts, one fixed line: "Photos already in Lightroom: Metadata ›
Read Metadata from File." Lightroom caches the tag at import.

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
| Run button | Label: `Desqueeze N photos`, `Desqueeze 1 photo`, or `Desqueeze` when there is nothing to run. N is the count of DNG files plus the pending ARW files that can convert. When Adobe DNG Converter is missing, the ARW files are not in N. |
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

The repo follows Plateworks Undercurrent: a Swift package for the logic, and a
SwiftUI app generated by XcodeGen.

```
Package.swift                     DesqueezeCore library and its tests
Sources/DesqueezeCore/            logic, no UI, no AppKit
Tests/DesqueezeCoreTests/
App/PlateworksDesqueeze/          SwiftUI app
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
| `ToolLocator` | Finds exiftool and Adobe DNG Converter. Returns a typed error that names the missing tool. | the file system |
| `ScaleTag` | Behind the `ScaleTagging` protocol: reads the tag for a folder, writes it for one file, reads it back from one file. A `Scale` is two numbers. An unknown scale is `nil`. | `ProcessRunner` |
| `FileBackups` | Behind the `BackupHandling` protocol: says whether a backup exists, moves it to the Trash, restores it with one rename. | the file system |
| `RawConverter` | A protocol: convert one ARW and confirm the DNG exists. Version 1 has one implementation, `AdobeConverter`. A dnglab one is the planned swap (section 3). | `ProcessRunner` |
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
  `_1.dng` duplicate.
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
  (this Mac has exiftool in two places, so a rename proves nothing). The launch argument
  `-openFolder <path>` loads a folder at launch, because the standard Open
  panel runs in another process that a script cannot drive. Both are read from
  the launch arguments only, never from saved defaults. Then one file opened in
  Lightroom at each factor. Dom's photo folders are never the test target.

## 10. Documentation and filing

- Documentation tier: Floor, plus `PROJECT_CHARTER.md`
  (`00_Resources/documentation-standard.md`). The docs check is vendored to
  `scripts/docs_check.py` and run by a test, as Undercurrent does.
- Workspace filing: a row in `00.00 JDex.md` and a `local` row in the
  allowlist ledger at charter time. The Projects row in the workspace
  `CLAUDE.md`, the repository row in `00_Resources/system-architecture.md`, and
  the section in the workspace docs index land with this repo's own
  `CLAUDE.md`.
- GitHub: `plateworks-desqueeze`, private. Created when Dom confirms.

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
| Not sandboxed | The app must start two external tools. |
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
desqueeze run <folder> --factor <number> [--no-convert] [--dry-run] [--json]
desqueeze remove <folder> [--dry-run] [--json]
desqueeze --version
desqueeze --help
```

| Command | Does | Changes files |
|---|---|---|
| `scan` | Prints each DNG with its current scale, the pending ARW files, the orphan backups, whether the folder is writable, and where the two tools are. | No |
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
  folder could not be scanned, a run or a dry run met a read-only folder, or
  exiftool is missing. Exit code 2: a usage error.
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
- When Adobe DNG Converter is missing, `run` still tags the DNG files, says
  how many ARW files it left, and exits 0.
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
  "exiftool": "/opt/homebrew/bin/exiftool", "dngConverter": "/Applications/…",
  "dngs": [ { "name": "a.dng", "scale": "1.5 1", "originalRawFileName": "a.ARW", "hasBackup": false } ],
  "pendingARWs": ["b.ARW"], "orphanBackups": [] }
```

```json
{ "folder": "/path", "factor": "1.5", "dryRun": false,
  "converted": 1, "set": 2, "skipped": 0, "blocked": 0, "failed": 0,
  "stopped": false, "unconvertedARWs": 0,
  "notes": [ { "name": "x.dng", "kind": "failed", "message": "…", "detail": null } ] }
```

A dry run prints the same object with `"dryRun": true`, the counts a real run
would give if every step passed, and a `"steps"` list of
`{ "name", "action" }`, where action is `convert`, `write`, `skip`, or
`blocked`.

A note's `kind` is one of `orphanBackup`, `notConverted`, `failed`,
`blockedByBackup`, `leftoverBackup`, `backupKept`, `folderReadOnly`. A front
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
`swift build -c release --package-path MCPServer`. For Dom's Mac they are
copied to `~/.local/bin/`. The MCP server is registered with Claude Code by its
absolute path. Registering it is a change to Dom's Claude configuration, so it
is done only on his yes.

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
Where this section and an earlier one differ (2.1, 3, 4.3 step 1, 6, 8, 11,
12), this section wins.

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
- dnglab's exit code 6 (the output exists) can then mean only a leftover
  work file that step 1 could not remove. It is reported as a failure with
  no partial output.

Adobe DNG Converter cannot write to a name the app gives it, so its rule
stays as 4.3 has it: the check before the start, and the partial-DNG rule.

Before either converter starts, a file named `<base>.dng_exiftool_tmp` stops
the conversion of that ARW, with a note that names it: exiftool refuses to
write beside its own leftover, so the tag step could never pass.

The tag step of 4.3 (`DefaultScale`) is not changed. It runs after the
conversion, as before, with its own backup and check.

### 13.4 Which ARW dnglab converts

The app reads these facts for the pending ARW files with one exiftool call
for each 200 files:
the camera model, the ISO, `WB_RGBLevelsDaylight`, and
`DistortionCorrection`.

A frame has a **full match** when all four hold:

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
| dnglab | `/opt/homebrew/bin/dnglab`, then `/usr/local/bin/dnglab`, then each folder in `PATH` | With Adobe installed: Adobe converts every ARW, and one line says "dnglab is faster and opens no window: `brew install dnglab`". With neither: the ARW files are not converted, the DNG files still run, and the message gives `brew install dnglab`. |
| Adobe DNG Converter | As section 6. It is not part of the app. | One quiet line where the folder summary is, and in the scan text of the command line tool: "Adobe DNG Converter is not installed. It is an optional backup for photos that dnglab cannot match." No error, and no line when no ARW is pending. |

The Run button's N counts the pending ARW files when one converter or the
other is installed.

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
| `ARWFacts` | The four facts of 13.4 for one ARW, and the exiftool read that gets them for a list of files. |
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
- The table's numbers come from Adobe DNG Converter's output. Before a public
  release, decide if a shipped app may carry them.
- dnglab 0.8.0 is the version tested. The drift check is the guard for a
  later one.

