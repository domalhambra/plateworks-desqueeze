# Troubleshooting

What each note and each message means, what to do, and how to make a report for a bug.

## Overview

The three front ends say the same sentences, because each sentence is made
once, in the core. A result has one *note* for each file that has something
to say: the name of the file, one plain sentence, and often a detail line
with the words of the program that did the work. In the JSON, each note also
has a `kind`. The sections below are in the order of the kinds.

In every case below, an ARW is as it was, and where it was. The tool never
changes one. It moves one only when you asked a run to move the originals,
and then only after its checks: the section "The original stays" has each
case in which it does not.

## The photo still looks squeezed

- **In Finder or Quick Look.** This is correct. Finder ignores the tag.
  Look at the photo in Lightroom or Camera Raw.
- **In Lightroom, for a photo that was in the catalog before the run.**
  Lightroom keeps the value that it read at import. Select the photo and use
  Metadata › Read Metadata from File.
- **In the scan.** Run `desqueeze scan` on the folder. A scale of `1 1` is
  no stretch: the run did not set that file. Read the notes of the run.

## Notes about a DNG

### Blocked

```
Blocked. An older backup, <name>.dng_original, is beside this file. Move it away, then run again.
```

Kind: `blockedByBackup`. The run did not write this DNG. A backup from an
earlier write is beside it, and the tool does not touch a backup that it
did not make in this run. The backup can be the photo as it was before a
write that did not complete.

1. Open the DNG in Lightroom or Camera Raw. Is the photo good?
2. If it is good, move the backup to another folder. Keep it until you are
   sure.
3. If it is not good, the backup is the earlier file. Move the DNG away, and
   rename the backup to `<name>.dng`.
4. Run again.

### Already at this value, with a backup

```
Already at this value. A backup, <name>.dng_original, is beside this file.
```

Kind: `leftoverBackup`. The DNG has the wanted value, so the run skipped it.
A backup from an earlier write is still beside it. This happens when a run
ended hard after a write and before its check.

Open the DNG and look at it. When it is good, move the backup away. While
the backup is there, a run with another factor blocks this file.

### Done, and the backup stayed

```
Done. The backup stayed beside the file, because the Trash refused it.
```

Kind: `backupKept`. The tag is set, and it read back correctly. The Trash
did not take the backup, which can happen on an external volume. The detail
line has the reason. Move the backup away yourself. While it is there, a run
with another factor blocks this file.

### Not changed

```
Not changed.
Not changed. The backup was restored.
```

Kind: `failed`. The write or its check failed, and the DNG is as it was
before the run. The detail line has the words of exiftool.

| The detail line | Meaning |
|---|---|
| "Error: Not a valid DNG (looks more like a TXT)", or another error of exiftool about the file | exiftool cannot read or write this file. A file that is not a DNG, with the extension `dng`, gives this. The scan shows the scale of such a file as `unknown`. |
| "The tag did not read back as `1.5 1`." | The write passed and the check did not. The tool put the backup back. |
| "Error: Temporary file already exists: …" | A file named `<name>.dng_exiftool_tmp` is beside the DNG. exiftool left it when it was ended in the middle of a write, and it refuses to write beside it. Delete that file, then run again. |
| "The program was ended by signal 2." | A Control-C reached exiftool at the moment that it started. This is rare. Run again. |

### The backup could not be restored

```
The change failed, and the backup could not be restored. The backup is <name>.dng_original.
```

Kind: `failed`. The check failed, and the rename that puts the backup back
failed too. The detail has both errors. The backup is the photo as it was.
Look at the folder: when `<name>.dng` is missing or not good, rename the
backup to `<name>.dng`.

### A backup with no DNG beside it

```
A backup with no DNG beside it. Rename it to <name>.dng to get the photo back.
```

Kind: `orphanBackup`. The folder holds `<name>.dng_original` and no
`<name>.dng`. exiftool was ended between its two renames. In a folder with
no ARW files, this file is the only copy of the photo. The tool does not
touch it, and every scan and every run names it first.

Rename the file to `<name>.dng` in Finder, then run again. Until you do, the
ARW with the same base name is not converted: its DNG is waiting.

## Notes about an ARW

### Not converted

```
Not converted.
```

Kind: `notConverted`. No converter made a DNG from this ARW. The detail has
one line for each converter that was tried.

| The detail line | Meaning, and what to do |
|---|---|
| "A DNG with this name exists already. Not converted." | Something has the name `<base>.dng`: a file, a folder, or a link. It can also be a DNG that another program made while the converter worked. The tool did not touch it. Look at what has the name. |
| "The file name is too long. Shorten it, then run again." | The base name of the ARW has more than 222 characters. A temporary file of the conversion has that name and 33 more characters, and a file name can have 255. An accented letter can count as two. No converter started. Give the ARW a shorter name, then run again. |
| "A leftover file, `<name>`, is beside this photo. Delete it, then run again." | The file is `<base>.dng_exiftool_tmp`, which exiftool left when it was ended in the middle of a write. Or it is a hidden work file that the tool could not move to the Trash, or a folder or a link with the name of a work file. The tool removes only a regular file. Look at what the line names, and delete it. For a hidden file, press Command-Shift-Period in Finder to see it. |
| "dnglab returned 7.", with a reason | dnglab cannot read this file. Is it a Sony ARW? |
| "Adobe DNG Converter made no DNG. It may not support this file." | Adobe DNG Converter cannot read this file. |
| "… made an empty DNG." or "The program was ended by signal …" | The converter was ended before it completed. Run again. |
| "The tag … did not read back as …" or "The tags could not be written: …" | dnglab made the DNG, and the match did not pass its check. Run with `--verbose` and make a report. |
| "A partial DNG, `<name>`, is beside the ARW. Delete it, then run again." | The conversion failed, and the Trash refused the hidden work file. Delete the file that the line names. |

After most of these lines you also read "The partial DNG was moved to the
Trash." That is the hidden work file of the failed conversion.

### Converted, with a note about the match

```
Converted. The levels are dnglab's own. Install Adobe DNG Converter for the same file that Lightroom makes.
Converted. The DNG has no built-in lens correction. Install Adobe DNG Converter for the same file that Lightroom makes.
```

Kind: `convertedUnmatched`. This is not an error. dnglab converted the
photo, Adobe DNG Converter is not installed, and the note says what the DNG
lacks. <doc:CamerasAndLenses> explains both sentences.

### The volume gives no folder lock

```
This volume gives no folder lock. Do not start a second run in this folder while this run works.
```

Kind: `noFolderLock`. This is not an error. The note is on the name of the
folder, and it is the first note of the result. A run holds a lock on its
folder, so that a second run in the same folder does not start. This volume
gives no such lock, so the run worked without one, and nothing would have
stopped a second run. On this volume, wait for a run to end before you
start the next one in the same folder: in the window, in the tool, or
through the MCP server. `--verbose` prints the error number that the system
gave. <doc:WhatHappensToYourFiles> says which volumes were tested.

### The original stays

```
The original stays, because its DNG has no full match.
The original stays, because its DNG is not complete.
The original changed during the run, so it stays.
The original is not a regular file, so it stays.
The original stays, because its DNG could not be checked.
The original stays, because its DNG changed during the run.
The original was not in the folder at the end of the run. The app did not move it.
The original could not go to the Trash, so it stays.
```

Kind: `originalKept`. This is not an error. You asked the run to move the
originals to the Trash, the run converted this ARW, and the run did not move
it. The tool sent no file to the Trash for this ARW. For each sentence that
says "stays", the ARW is still in the folder. One sentence does not say it:
the ARW was not in the folder when the run came to move it, and the table
says where to look. The result line says how many moved: "Originals moved to
the Trash: 11 of 12."

| The sentence | Meaning, and what to do |
|---|---|
| "The original stays, because its DNG has no full match." | dnglab converted the photo with no full match, and the DNG has the note "Converted. …" too. You need the ARW to convert the photo again when Adobe DNG Converter is installed. Keep it. |
| "The original stays, because its DNG is not complete." | The tag step of the DNG did not end with the stretch of this run: the DNG is blocked, or its write failed. Read the note of the DNG, and follow it. |
| "The original changed during the run, so it stays." | The size, the modification date or the file number of the ARW is not what it was before the conversion. Another program wrote the file or replaced it. The DNG is from the earlier file. Look at both. |
| "The original is not a regular file, so it stays." | A link or a folder has the name of the ARW now. The tool never moves one. |
| "The original stays, because its DNG could not be checked." | The detail line has the reason: the DNG is not a regular file or has no bytes, exiftool could not read it, it does not name this ARW in `OriginalRawFileName`, or its `DefaultScale` is not the stretch of this run. Another program changed the DNG during the run. Scan the folder, and look at the DNG. |
| "The original stays, because its DNG changed during the run." | `<base>.dng` is not the file that this run made. The tool records the size, the modification date and the file number of the DNG after the conversion, and again after it set the stretch. One of the two records was not true later: another program wrote the DNG, or put another file at its name. The file at that name can be the DNG of another photo. Scan the folder, and look at the value of that DNG: it can have another stretch than the one of this run. Then open it. When it is not this photo, move it away and run again: the run then converts the ARW again. |
| "The original was not in the folder at the end of the run. The app did not move it." | Nothing had the name of the ARW when the run came to move it. The tool did not move it, and it is not in the Trash from this run. Another program, or a person, moved or deleted the file while the run worked. Look where that program puts its files. The DNG of this run is in the folder. |
| "The original could not go to the Trash, so it stays." | The Trash refused the file. The detail line has the words of the system. A volume with no Trash gives this for every ARW. Move the file yourself, when you want it gone. |

A later run does not move an ARW that stayed: its DNG is there now, so no
run converts it again, and a run moves only an ARW that it converted itself.
When you want the ARW gone, move it to the Trash yourself.

An ARW whose conversion failed has no such note. Its "Not converted." note
says enough, and the ARW stays. After a cancel, the ARW files that the run
did not reach have no note either: the result says "stopped", and each of
them is in the folder.

### An ARW is not converted, and there is no note

The tool converts only an ARW that has no DNG. An ARW has a DNG when one of
these is in the folder:

- A DNG with the same base name.
- A DNG whose `OriginalRawFileName` tag is the name of the ARW. Run
  `desqueeze scan <folder> --json`, and look for the name of the ARW in
  `originalRawFileName`.
- A backup with no DNG, `<base>.dng_original`.

One known limit: a DNG that was renamed to the base name of another photo
claims the ARW of that photo too.

When the result says "1 ARW file was not converted." with no note for the
file, the run was told not to convert, it was stopped, or no converter is
installed.

## Messages about the folder

| Message | Meaning, and what to do |
|---|---|
| "No DNG or ARW files in this folder." | The top level of the folder has no photo that the tool works on. The tool does not read subfolders. Give it the folder that holds the photos. |
| "This folder could not be read." | The line below it says why: nothing is at the path, the path is a file, or the path is a package such as an app or a photo library. For a run that did not start because the lock call of the system failed, the line has the words of the system, for example "Input/output error", in the window too. No file was changed. Run again. When it fails again, look at the volume. |
| "This folder is read-only. Desqueeze cannot change its files." | A scan works, and a run changes nothing and moves nothing. Unlock the card, or copy the folder to a disk that you can write to. The note of a run has the kind `folderReadOnly`. |
| "Drop a folder" | The window got a file, a package, or more than one item. |
| "Another Desqueeze run is working in this folder. Wait for it to end, then run again." | The run did not start, and no file was changed. Another run holds the folder: in the window, in the command line tool, or in the MCP server. Wait for that run, then run again. If you see no run, look in Activity Monitor for a Desqueeze, a `desqueeze` or a `desqueeze-mcp` that still runs. The lock goes when that program ends. |

## A message about the factor

```
The factor must be a number from 1 to 4, with at most four decimal places. It was "1,5". Use a period for the decimal point.
```

The tool takes a period for the decimal point, and no comma: `1.5`, not
`1,5`. The window says the same after its own first words, "Enter a number
from 1 to 4, with at most four decimal places."

## Messages about missing programs

| Message | What to do |
|---|---|
| "Desqueeze needs exiftool, and it is not installed." | Run `brew install exiftool`. Nothing works without exiftool. Then open the window again. |
| "12 ARW cannot be converted: no converter is installed", then "Install dnglab with: brew install dnglab" | Run `brew install dnglab`. Until then, a run sets the tag in the DNG files and leaves the ARW files. |
| "Adobe DNG Converter is not installed. It is an optional backup for photos that dnglab cannot match." | Nothing, when your photos have a full match. This is not an error. |
| "dnglab is faster and opens no window. Install it with: brew install dnglab" | Nothing, or install dnglab. Adobe DNG Converter converts every ARW until then. |

The tool looks for exiftool and dnglab in `/opt/homebrew/bin`, then in
`/usr/local/bin`, then in each folder of `PATH`. `desqueeze scan` shows
where it found each program. The window looks inside its own app first:
the app of the download has exiftool and dnglab there.

## The downloaded app

These are the limits of the app of the download.

| What you see | Why, and what to do |
|---|---|
| The app does not start on an Intel Mac. | The download is for a Mac with Apple silicon. There is none for an Intel Mac, and a build from source on an Intel Mac was not tested either. |
| The app does not start on a macOS older than 14. | The app needs macOS 14 or later. |
| "Desqueeze needs exiftool, and it is not installed." in the downloaded app | The exiftool inside the app is a Perl script, and it needs the Perl of macOS, `/usr/bin/perl`. Apple has said that a later macOS can come without it. With no Perl there, the window looks for exiftool on the Mac, as a build from source does. Run `brew install exiftool`, then open the window again. To see if the Mac has that Perl, run `/usr/bin/perl -v`. |
| The app uses its own exiftool and dnglab, not the newer ones of Homebrew. | That is on purpose: the versions inside are the tested ones. You cannot replace a program inside the app. A newer one comes only with a new release. To use the programs of the Mac, build the app from source. |
| The app does not say that a new release exists. | The app makes no network connection, so it has no update check. Look at the Releases page of the repo on GitHub. |

## A run does not end

If exiftool or a converter never returns, the run waits for it. Cancel and
Control-C do not help here: both stop a run only after the current file.

Open Activity Monitor, and end the program that hangs: exiftool, dnglab or
Adobe DNG Converter. The tool lists that file as failed, with "The program
was ended by signal …" on the detail line, and goes on to the next file. In
the window, Force Quit also ends the run. A write that did not complete
leaves the DNG as it was. Then scan the folder, and follow the notes.

## Make a report for a bug

Work on a copy of the folder. The output holds the path of your folder and
your file names: remove what you do not want public. Do not attach a photo
that you do not want public.

1. Write down what you did, what you expected, and what happened.
2. Get the scan of the folder:

   ```bash
   desqueeze scan "/Volumes/Card/Shoot 1" --json
   ```

3. Get the run with every command. `--verbose` prints on standard error, so
   send that to a file:

   ```bash
   desqueeze run "/Volumes/Card/Shoot 1" --factor 1.5 --verbose 2> desqueeze-run.txt
   ```

4. Get the versions:

   ```bash
   sw_vers
   desqueeze --version
   exiftool -ver
   dnglab --version
   ```

5. Add the camera model, the lens, and the ISO of a photo that shows the
   problem.

A problem that can damage or lose a person's files is a security problem
for this project. Report it in private, as `SECURITY.md` in the repo says.
