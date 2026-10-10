# The JSON reports

Every key of the scan report and of the run report, and every kind of note, for a tool that you write on top.

## Overview

`desqueeze --json` and the three tools of `desqueeze-mcp` print the same
reports, because both print the same types of the core: ``ScanReport`` and
``RunReport``, through ``ReportJSON/text(_:)``.

These rules hold for every report:

- Standard output holds exactly one JSON object.
- The object is printed over several lines, with its keys in alphabetical
  order. A slash in a path is not escaped. An empty list is `[]`.
- Every key is always there. A value that is not known is `null`. Two keys
  are left out on purpose: `steps` in the report of a real run, and
  `converter` in a step that is no conversion.
- A file is named by its file name, not by its path. The folder is in
  `folder`.
- Read the `kind` of a note, and never the English sentence in `message`.
  A sentence can change from one version to the next.

A later version can add a key or a kind of note. Write your tool so that it
passes over a key or a kind that it does not know. A key is not renamed or
removed without a recorded decision in the repo.

## The scan report

`desqueeze scan <folder> --json`, and the tool `desqueeze_scan`.

```json
{
  "dngConverter" : "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter",
  "dnglab" : "/opt/homebrew/bin/dnglab",
  "dngs" : [
    {
      "hasBackup" : false,
      "name" : "sample.dng",
      "originalRawFileName" : "sample.ARW",
      "scale" : "1 1"
    }
  ],
  "exiftool" : "/opt/homebrew/bin/exiftool",
  "folder" : "/Volumes/Card/Shoot 1",
  "orphanBackups" : [],
  "pendingARWs" : [
    "frame.ARW"
  ],
  "writable" : true
}
```

| Key | Type | Meaning |
|---|---|---|
| `folder` | Text | The absolute path of the folder. When the path that was given is a link to a folder, this is the folder itself. |
| `writable` | Boolean | False means that a run can change nothing in this folder. |
| `exiftool` | Text | The path of exiftool. |
| `dnglab` | Text or `null` | The path of dnglab. `null` when it is not installed. |
| `dngConverter` | Text or `null` | The path of Adobe DNG Converter. `null` when it is not installed. |
| `dngs` | List of objects | Each DNG at the top level of the folder, sorted by name as Finder sorts. |
| `pendingARWs` | List of text | The name of each ARW that has no DNG. A run converts these. |
| `orphanBackups` | List of text | The name of each `<name>.dng_original` that has no `<name>.dng` beside it. |

Each object in `dngs`:

| Key | Type | Meaning |
|---|---|---|
| `name` | Text | The file name. |
| `scale` | Text or `null` | The value of the `DefaultScale` tag: the horizontal stretch, a space, the vertical stretch. `"1 1"` is no stretch. `null` means that exiftool gave no value: the DNG has no tag, or exiftool cannot read the file. A run does not skip such a file. |
| `originalRawFileName` | Text or `null` | The name of the raw file that the DNG was made from, when the DNG holds it. |
| `hasBackup` | Boolean | True when `<name>.dng_original` is beside the DNG. |

With no converter installed, `dnglab` and `dngConverter` are both `null`,
and the ARW files in `pendingARWs` cannot convert.

## The run report

`desqueeze run` and `desqueeze remove` with `--json`, and the tools
`desqueeze_run` and `desqueeze_remove`. This is a run with `--no-convert`
that met one DNG with an older backup beside it, and left one ARW:

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

| Key | Type | Meaning |
|---|---|---|
| `folder` | Text | The absolute path of the folder. |
| `factor` | Text | The factor, with no zeros at its end: `"1.5"`, `"2"`. For Remove it is `"1"`. |
| `dryRun` | Boolean | True for a dry run. No file was changed. |
| `converted` | Number | The ARW files that became a DNG. It is the sum of the next two. |
| `convertedByDnglab` | Number | The ARW files that dnglab converted. |
| `convertedByAdobe` | Number | The ARW files that Adobe DNG Converter converted. |
| `set` | Number | The DNG files that got the tag, with a read-back that passed. |
| `skipped` | Number | The DNG files that had the value already. Nothing else counts here. |
| `blocked` | Number | The DNG files that the run held back, because an older backup is beside each one. |
| `failed` | Number | The files with an error: each ARW that no converter converted, and each DNG whose write or check failed. |
| `stopped` | Boolean | True when the run was cancelled and left work undone. A cancel during the last file leaves nothing undone, and gives false. |
| `unconvertedARWs` | Number | The pending ARW files of the run's own scan that have no DNG when the run returns. It counts an ARW whose conversion failed, the ARW files that a stopped run did not reach, and every pending ARW when no converter is installed or when the run was told not to convert. Remove gives 0. |
| `trashOriginals` | Boolean | True when the run was asked to move the originals to the Trash: the box of the window, or `--trash-originals`. The key is always there. From the MCP server, and for Remove, it is always false. |
| `originalsInTrash` | Number | The ARW files that the run moved to the Trash. In a dry run, the count that a run gives when every step passes. The key is always there. It is 0 when `trashOriginals` is false. |
| `notes` | List of objects | One note for each file that has something to say. |
| `steps` | List of objects | Only in a dry run. |

Each note:

| Key | Type | Meaning |
|---|---|---|
| `name` | Text | The file name. For the kind `folderReadOnly`, the name of the folder. |
| `kind` | Text | Why the note exists. The next table has the kinds. |
| `message` | Text | One plain sentence for a person. |
| `detail` | Text or `null` | The words of the program that did the work. It can hold more than one line. |

## The kinds of note

| Kind | The file | Meaning | Counts in |
|---|---|---|---|
| `orphanBackup` | A `<name>.dng_original` | A backup with no DNG beside it. The tool does not touch it. These notes come first, after a `noFolderLock` note when there is one. | Nothing |
| `notConverted` | An ARW | No converter made its DNG. `detail` has one line for each converter that was tried. | `failed` |
| `failed` | A DNG | The write or its check failed. The file is as it was, unless `message` says that the backup could not be restored. | `failed` |
| `blockedByBackup` | A DNG | The run held the file back, because an older backup is beside it. | `blocked` |
| `leftoverBackup` | A DNG | The file had the value already, and a backup is beside it. | `skipped` |
| `backupKept` | A DNG | The tag is set. The Trash refused the backup, and it stayed beside the file. | `set` |
| `folderReadOnly` | The folder | The folder is read-only. No file was tried, and no file has a note. | Nothing |
| `convertedUnmatched` | A DNG | dnglab converted the photo with no full match, because Adobe DNG Converter is not installed. This is not an error. `detail` has the reason. | `converted` |
| `originalKept` | An ARW | The run was asked to move the originals, it converted this ARW, and it did not move it. `message` says why. The ARW stays in the folder, but for one message: the ARW was not in the folder when the run came to move it. This is not an error. For a DNG that did not pass its check, and for a Trash that refused the file, `detail` has the reason. | Nothing. The ARW is in `converted`, and not in `originalsInTrash`. |
| `noFolderLock` | The folder | The volume gives no lock for a folder, so the run worked without the lock that keeps a second run out. This is not an error. It is the first note. A dry run takes no lock, and never has this note. | Nothing |

<doc:Troubleshooting> has the sentence of each kind, and what a person can
do.

## The steps of a dry run

A dry run gives the same object with `dryRun` true and one more key,
`steps`. The counts are those of a run in which every step passes, and each
conversion passes with the first converter that the ARW would get.

```json
{
  "blocked" : 0,
  "converted" : 1,
  "convertedByAdobe" : 0,
  "convertedByDnglab" : 1,
  "dryRun" : true,
  "factor" : "1.5",
  "failed" : 0,
  "folder" : "/Volumes/Card/Shoot 1",
  "notes" : [],
  "originalsInTrash" : 0,
  "set" : 2,
  "skipped" : 0,
  "steps" : [
    {
      "action" : "convert",
      "converter" : "dnglab",
      "name" : "frame.ARW"
    },
    {
      "action" : "write",
      "name" : "sample.dng"
    },
    {
      "action" : "write",
      "name" : "frame.dng"
    }
  ],
  "stopped" : false,
  "trashOriginals" : false,
  "unconvertedARWs" : 0
}
```

| Key | Type | Meaning |
|---|---|---|
| `name` | Text | The file of the step. For a `convert` step and for a `trashOriginal` step, the ARW. |
| `action` | Text | `convert`, `write`, `skip`, `blocked` or `trashOriginal`. |
| `converter` | Text | Only in a `convert` step: `dnglab` or `adobe`, the converter that gets the ARW first. |

The steps are in the order of the run: each conversion, then each DNG, with
the new DNG files last. A dry run with nothing to do has `"steps" : []`.

A dry run that was asked to move the originals has one more step for each
ARW that a run would move, after the steps of the DNG files:

```json
{
  "action" : "trashOriginal",
  "name" : "frame.ARW"
}
```

`originalsInTrash` is then the count of those steps. An ARW that would stay
has no such step, and has an `originalKept` note in `notes`: an ARW whose
DNG would have no full match, and an ARW whose new DNG would be blocked. A
dry run reads no ARW and no DNG for these steps. It plans a run in which
every check passes.

An ARW whose name is too long for the files that a conversion makes has no
`convert` step. It counts in `failed`, with the `notConverted` note of the run.

## When there is no report

When `desqueeze --json` can give no report, it prints one object with two
keys, and its exit code is 1:

```json
{
  "detail" : "Nothing is at this path.",
  "error" : "This folder could not be read: /Volumes/Card/Nothing here"
}
```

`detail` is text or `null`. This happens when the folder cannot be read,
when the lock call of a run failed, when another run works in the folder,
and when exiftool is not installed. A wrong command line prints nothing on
standard output, and its exit code is 2.

The MCP server does not print this object. A call that can give no report
is a tool error, and its text is one plain sentence.

## The report and the exit code

The exit code of `desqueeze` follows from the report of a run:

- 1 when `failed` or `blocked` is above 0, when `stopped` is true, or when a
  note has the kind `folderReadOnly`.
- 0 in every other case. A note of the kind `convertedUnmatched`,
  `originalKept` or `noFolderLock` does not change the exit code.

A dry run has the exit code of the run that it plans. A scan that completed
gives 0, also when `writable` is false.

## The types in the core

| JSON | Type |
|---|---|
| The scan report | ``ScanReport``, and ``ScanReport/DNG`` for each DNG |
| The run report | ``RunReport`` |
| A note, and its kind | ``FileNote``, ``FileNote/Kind`` |
| A step, and its action | ``RunPlan/Step``, ``RunPlan/Action`` |
| Why an original stays | ``OriginalDecision/KeepReason`` |
| The name of a converter | ``ConverterKind`` |
| The object with `error` and `detail` | ``ErrorReport`` |

``DesqueezeOperations`` makes each report. To add a key or a kind, follow
the steps in `docs/changing-things.md` of the repo.
