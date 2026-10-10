# Using the command line tool

Scan a folder, see what a run would do, run, and remove, with `desqueeze`.

## Overview

`desqueeze` does the work of the window from a terminal or a script.

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
| `scan` | Shows each DNG with its current scale, the ARW files that have no DNG, each backup that has lost its DNG, and where the three programs are. | No |
| `run` | Converts each ARW that has no DNG, then sets the stretch on every DNG. | Yes |
| `remove` | Sets every DNG back to no stretch. Converts nothing. | Yes |

| Option | Does |
|---|---|
| `--factor <number>` | The squeeze factor of the lens: a number from 1 to 4, with at most four decimal places. For `run` only, and `run` needs it. There is no default. `--factor=1.5` is the same as `--factor 1.5`. Use a period for the decimal point: the tool refuses `1,5`, and says so. |
| `--no-convert` | For `run`: leaves the ARW files alone. |
| `--trash-originals` | For `run`: moves each original ARW to the Trash after its DNG passes the check. Off unless given. The section "Move the originals to the Trash" has its rules. |
| `--dry-run` | For `run` and `remove`: shows what the run would do, file by file, and which converter gets each ARW. Changes no file. |
| `--json` | Prints one JSON object on standard output, and nothing else there. |
| `--verbose` | Prints each exiftool and converter command, its exit code, and its output on standard error. Also says when it removed a leftover work file, and the error number when the volume gave no folder lock. |

An option can stand before or after the command and the folder. `--` ends
the options, so a folder whose name starts with a dash can follow it.

The folder can be a relative path. A symbolic link to a folder counts as that
folder, and the result names the folder itself. A file, or a package such as
an app, is not a folder.

The examples below are the output of the tool on a folder with one DNG,
`sample.dng`, and one ARW, `frame.ARW`.

## Scan

```bash
desqueeze scan "/Volumes/Card/Shoot 1"
```

```
/Volumes/Card/Shoot 1

DNG files: 1
  Name        Scale
  sample.dng  1 1

ARW files with no DNG: 1
  frame.ARW

exiftool: /opt/homebrew/bin/exiftool
dnglab: /opt/homebrew/bin/dnglab
Adobe DNG Converter: /Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter
```

The scale is the value of the tag: the horizontal stretch, then the vertical
stretch. `1 1` is no stretch, and `1.5 1` is a horizontal stretch of 1.5.
`unknown` means that exiftool gave no value for the file. A run still tries
such a file.

A converter that is not installed shows as `not installed`. When a converter
is missing and an ARW waits, one more line says what that means.

## Dry run

```bash
desqueeze run "/Volumes/Card/Shoot 1" --factor 1.5 --dry-run
```

```
Dry run. No file was changed.
  convert  frame.ARW  with dnglab
  write    sample.dng
  write    frame.dng
A run would give: 1 converted · 2 set · 0 skipped · 0 failed
```

Each line is one step, in the order of the run. The action is `convert`,
`write`, `skip` or `blocked`, and `trash` in a dry run with
`--trash-originals`. A dry run reads the folder and the ARW files. It starts
no converter, writes nothing and moves nothing. The counts are those of a
run in which every step passes.

## Run

```bash
desqueeze run "/Volumes/Card/Shoot 1" --factor 1.5
```

Standard output gets the result:

```
1 converted · 2 set · 0 skipped · 0 failed
Photos already in Lightroom: Metadata › Read Metadata from File.
```

Standard error gets one line for each completed step:

```
1/3 frame.ARW
2/3 sample.dng
3/3 frame.dng
```

After the counts, the tool prints one line for each file that has something
to say, with the words of the program below it. <doc:Troubleshooting>
explains each one.

A second run with the same factor changes nothing:

```
0 set · 2 skipped · 0 failed
```

The Lightroom line shows only after a run that set the tag in at least one
photo. A dry run never shows it. When both converters did work in a run, one
more line follows the counts: `Converted with dnglab: 11. With Adobe DNG
Converter: 1.`

## Move the originals to the Trash

```bash
desqueeze run "/Volumes/Card/Shoot 1" --factor 1.5 --trash-originals
```

With `--trash-originals`, the run moves each ARW that it converted to the
Trash, after the tag of the last DNG is set. An ARW moves only when its DNG
passes the check. <doc:WhatHappensToYourFiles> has the six conditions and
the limits. The result has one more line:

```
1 converted · 2 set · 0 skipped · 0 failed
Originals moved to the Trash: 1 of 1.
Photos already in Lightroom: Metadata › Read Metadata from File.
```

The second number is the count of the ARW files that this run converted. An
ARW that stays has a note that says why. Such a note does not change the
exit code. Each converted ARW has one more step in the progress:

```
1/4 frame.ARW
2/4 sample.dng
3/4 frame.dng
4/4 frame.ARW
```

See first what the run would do. A dry run moves nothing:

```bash
desqueeze run "/Volumes/Card/Shoot 1" --factor 1.5 --trash-originals --dry-run
```

```
Dry run. No file was changed.
  convert  frame.ARW  with dnglab
  write    sample.dng
  write    frame.dng
  trash    frame.ARW
A run would give: 1 converted · 2 set · 0 skipped · 0 failed
```

A `trash` step names an ARW that the run would move. An ARW whose DNG would
have no full match has no such step, and a note says why. A dry run plans a
run in which each step passes: when a conversion then fails in the real run,
that ARW stays. A dry run counts from its own scan, and the run scans again.

The rules of the flag:

- It is off unless it is on the command line. No environment variable and
  no saved setting turns it on.
- It goes with `run` only. On `scan` and on `remove` it is a wrong command
  line, with the exit code 2.
- It does not go with `--no-convert`: a run that converts nothing has no
  original to move. That is a wrong command line too.
- Control-C before the originals move leaves every ARW in the folder. The
  result says "stopped".

## One run in a folder at a time

A run holds a lock on the folder until it ends. A second `run` or `remove`
in the same folder does not start, also when the first run is in the window
or in the MCP server. It changes no file, and the exit code is 1:

```
desqueeze: Another Desqueeze run is working in this folder. Wait for it to end, then run again.
```

With `--json`, standard output gets the object with the keys `error` and
`detail`. Wait for the first run, then run again.

`scan` and `--dry-run` take no lock. While a run works, they can show a
folder in change: for example a DNG as blocked, by a backup that the run is
about to clear. Run the command again after the run ends.

On a volume that gives no lock for a folder, a run goes on without one. Its
result then starts with a note on the name of the folder, and the exit code
does not change:

```
Shoot 1: This volume gives no folder lock. Do not start a second run in this folder while this run works.
```

With `--verbose`, standard error also has the error number that the system
gave: `The volume gave no folder lock: error 45, Operation not supported`.
<doc:WhatHappensToYourFiles> says more about the lock.

## Remove

```bash
desqueeze remove "/Volumes/Card/Shoot 1"
```

```
2 set · 0 skipped · 0 failed
Photos already in Lightroom: Metadata › Read Metadata from File.
```

Each DNG now has the scale `1 1`. Remove does not delete a DNG that a run
converted, and it does not touch an ARW. It never moves an original, and it
does not take `--trash-originals`.

## JSON for a script

With `--json`, standard output holds exactly one JSON object. Progress still
goes to standard error.

```bash
desqueeze run "/Volumes/Card/Shoot 1" --factor 2 --no-convert --json
```

This run met a DNG with an older backup beside it:

```json
{
  "blocked" : 1,
  "converted" : 0,
  "convertedByAdobe" : 0,
  "convertedByDnglab" : 0,
  "dryRun" : false,
  "factor" : "2",
  "failed" : 0,
  "folder" : "/Volumes/Card/Shoot 1",
  "notes" : [
    {
      "detail" : null,
      "kind" : "blockedByBackup",
      "message" : "Blocked. An older backup, sample.dng_original, is beside this file. Move it away, then run again.",
      "name" : "sample.dng"
    }
  ],
  "originalsInTrash" : 0,
  "set" : 0,
  "skipped" : 0,
  "stopped" : false,
  "trashOriginals" : false,
  "unconvertedARWs" : 1
}
```

<doc:TheJSONReports> describes every key. A script reads the `kind` of a
note, and never the English sentence.

## See each command with --verbose

`--verbose` shows, on standard error, each program that the tool starts.
This is the tag write and the read-back for one DNG:

```
$ /opt/homebrew/bin/exiftool -m '-SubIFD:DefaultScale=1.5 1' '/Volumes/Card/Shoot 1/frame.dng'
  exit 0
  stdout:     1 image files updated
$ /opt/homebrew/bin/exiftool -s3 -SubIFD:DefaultScale '/Volumes/Card/Shoot 1/frame.dng'
  exit 0
  stdout: 1.5 1
3/3 frame.dng
```

The tool starts each program with no shell. The quotes are in the output so
that you can read each argument, and paste the line into a shell.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The command completed, no file failed, and no file was blocked. A scan that completed gives 0, also for a read-only folder. |
| 1 | A file failed or was blocked, the run was stopped, the folder could not be read, a run or a dry run met a read-only folder, another run works in the folder, or exiftool is missing. |
| 2 | The command line was wrong. Nothing ran. |

A wrong command line prints the reason and one line that points to the help,
both on standard error:

```
desqueeze: run needs --factor <number>. There is no default.
See desqueeze --help.
```

A folder that cannot be read gives 1:

```
desqueeze: This folder could not be read: /Volumes/Card/Shoot 1/frame.ARW
    It is a file, not a folder.
```

With `--json`, a command that can give no report prints one object with the
keys `error` and `detail` on standard output. A wrong command line prints
nothing on standard output.

When no converter is installed, `run` still sets the stretch on the DNG
files, says how many ARW files it left, and gives 0.

## Stop a run

Control-C stops a run after the current file. The tool prints "Stopping
after the current file." on standard error, then the result so far, and the
exit code is 1. A plain `kill` and a closed Terminal window do the same.

A Control-C during the last file leaves nothing undone. The result is then
the complete result, and the exit code is that of the complete run.

A pipe that closes early, as in `desqueeze run … | head`, does not stop a
run. The run completes, and only the output is lost.

## Where the tool looks for the programs

The tool looks for exiftool and dnglab in `/opt/homebrew/bin`, then in
`/usr/local/bin`, then in each folder of `PATH`. It looks for Adobe DNG
Converter in `/Applications` only.
