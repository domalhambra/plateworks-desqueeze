# What happens to your files

What the tool does to each file, what it sends to the Trash, and how to undo a run.

## Overview

The window, the command line tool and the MCP server follow the same rules,
because one piece of code does the file work for all three.

- **An ARW is never changed and never deleted.** The tool only reads it.
- **An ARW moves only when you ask for it.** For one run, you can tell the
  tool to move each ARW that it converted to the Trash. The option is off
  unless you turn it on for that run.
- **No pixel changes.** The tool sets a tag. It never resamples a photo and
  never exports one.
- **A DNG keeps a backup until the new tag reads back correctly.**
- **Nothing is deleted.** The tool moves two kinds of file to the Trash on
  its own: the backup of a DNG after a good write, and its own hidden work
  files. It moves a third kind, an original ARW, only on your request.
- **A conversion never replaces a DNG that is there already.**
- **One run works in a folder at a time.** A second run does not start.
- **The tool works on the top level of one folder.** It does not read a
  subfolder, and it ignores hidden files.
- **The tool is offline.** It makes no network request and collects no data.

The rest of this page says how each rule is kept.

## What a run does to an ARW

A run converts each ARW that has no DNG. The new DNG goes beside the ARW,
with the same base name: `frame.ARW` gives `frame.dng`.

An ARW has a DNG already, and is not converted again, in two cases: a DNG in
the folder has the same base name, or a DNG in the folder names the ARW in
its `OriginalRawFileName` tag. Each DNG that the tool makes holds that tag,
and so does a DNG that Adobe DNG Converter makes. So a DNG that you renamed
still belongs to its ARW.

The conversion has four steps:

1. **The check.** When anything in the folder has the name `frame.dng`
   already, no converter starts for `frame.ARW`. No converter starts either
   for an ARW whose name is too long: the last section says how long.
2. **The work file.** No converter writes `frame.dng`. dnglab and Adobe DNG
   Converter both write a hidden file in the same folder,
   `.frame.desqueeze-work.dng`. The name starts with a period, so Finder and
   Lightroom do not show it. A work file that an earlier run left goes to
   the Trash first.
3. **The match.** For a DNG from dnglab, the tool writes its match into the
   work file: the values that Adobe DNG Converter writes, as far as it has
   them for that photo. Then it reads them back. <doc:CamerasAndLenses> says
   what those values are for.
4. **The name.** The tool renames the work file to `frame.dng`. This rename
   fails when anything has that name. So a DNG that another program made in
   the meantime is not replaced.

`frame.dng` appears only when it is complete. When a step fails, the work
file goes to the Trash. When a second converter is installed, it can get the
ARW next. When no converter made the DNG, the result lists the ARW as not
converted, and the ARW waits for the next run. No half-made DNG stays in the
folder under a name that looks complete.

## What a run does to a DNG

A run looks at each DNG, also the ones that it has just converted, and does
one of three things.

- **Skipped.** The DNG has the wanted value already. Nothing is written.
- **Blocked.** The DNG does not have the wanted value, and a file named
  `<name>.dng_original` is beside it. That is an older backup, and the tool
  did not make it in this run. The tool does not write the DNG and does not
  touch the backup. The result says "Blocked", with the name of the backup.
- **Written.** In every other case, the run writes the tag:
  1. exiftool writes a new file with the tag, and keeps the earlier file
     beside it as `<name>.dng_original`. That backup is the DNG as it was.
  2. The tool reads the tag back from the new file.
  3. When the value is the wanted one, the backup goes to the Trash.
  4. When the write fails, the DNG is as it was: a write that fails makes
     no backup. When the read-back fails, the tool gives the backup the name
     `<name>.dng` again, with one rename. In both cases the result lists the
     file as failed.

Remove is the same write, with the value for no stretch.

## Move the originals to the Trash, on request

After a conversion you have two files of one photo: the ARW and its DNG. The
tool can move the ARW to the Trash for you. It does so only when you ask,
and only for one run:

- **In the window,** tick the box "Move the original ARW files to the
  Trash" before you click the run button. <doc:UsingTheWindow> says when
  the box shows.
- **With the command line tool,** add `--trash-originals` to `desqueeze run`.
  <doc:UsingTheCommandLineTool> has the rules of the flag.
- **The MCP server cannot do it.** No tool of the server has such an
  argument, so an agent cannot remove your originals through the server.
  The limits below say what the server cannot prevent.

The option is off each time. The window does not save the box: it is off
when the app opens, when a folder loads, and after every run. The command
line tool needs the flag on each command.

The originals move last, after the tag of the last DNG is set. An ARW goes
to the Trash only when all of these are true:

1. This run converted the ARW, and the conversion passed. An ARW that an
   earlier run converted stays.
2. The DNG has a full match. A DNG with the note "Converted. … Install
   Adobe DNG Converter for the same file that Lightroom makes." is not
   complete, and you need the ARW to convert the photo again.
3. The DNG has the stretch of this run: the tag was set and read back, or
   the DNG had the value already.
4. The ARW is the file that was converted. Before the conversion, the tool
   records the size, the modification date and the file number of the ARW.
   Directly before the move it reads them again. All three must be the
   same, and the ARW must be a regular file. A link or a folder never goes.
5. Directly before the move, the DNG is a regular file with bytes, it names
   the ARW in its `OriginalRawFileName` tag, and its `DefaultScale` tag is
   the stretch of this run. The tool reads both tags with one exiftool call.
6. The DNG is the file that this run made. The name in the DNG cannot prove
   that: the DNG of another photo can hold the same name. So the tool
   records the size, the modification date and the file number of the DNG
   two times: directly after the conversion, and directly after it set the
   stretch. The first record must still be true directly before the tool
   sets the stretch. The second record must still be true at the move: the
   tool compares it before check 5, and again after the exiftool read of
   check 5. When the DNG had the stretch already, the tool writes nothing,
   and the first record must be true to the end. A DNG that fails one of
   these is handled as each DNG in the folder is. Only its ARW stays.

The tool asks them in the order 1, 2, 3, 6, 5, 6 again, 4. So the second
read of the ARW is the last thing before the move.

When one of them is not true, the ARW stays, and the result has a note that
says why. <doc:Troubleshooting> lists the eight sentences. When the Trash
refuses the file, the ARW stays too. The tool never deletes an ARW, and it
tries no second way to remove one. When the ARW is not in the folder at the
move, the tool moves nothing, and the note says that.

The tool moves the ARW only. A file beside it, such as `frame.xmp`, is not
the tool's file and stays.

The result then has one more line, with the count of the originals that
moved and the count of the ARW files that the run converted:

```
Originals moved to the Trash: 11 of 12.
```

Know these limits before you turn the option on:

- **The check does not look at the picture.** It reads the structure and
  the two tags of the DNG. Look at the DNG files in Lightroom before you
  empty the Trash.
- **Without the ARW, the photo cannot be converted again** with a later
  converter or a later match table.
- **A Lightroom catalog that holds the ARW files already** shows them as
  missing after the move. Turn the option on before the import, or import
  the DNG files.
- **A volume with no Trash.** The move is refused, and every ARW stays.
- **An external volume.** The ARW goes to the Trash of that volume. Its
  space is free only after you empty the Trash with the volume connected.
- **The tool compares three facts, and not the bytes.** Checks 4 and 6
  compare the size, the modification date and the file number of a file. A
  program that writes an ARW in place, keeps its size, and puts the date
  back is not seen. On a FAT32 volume, a file that is deleted and made
  again with the same name, size and date gets the same file number. That
  was measured on a disk image. APFS, HFS+ and ExFAT gave another number.
- **Three moments that the tool cannot see.** Another program can put a
  file at `<base>.dng` in one of them, and the tool takes that file as its
  own DNG. Check 5 still holds for such a file: it must name the ARW and
  have the stretch of this run.
  - The moment between the end of a conversion and the first record.
  - The time that exiftool works on the DNG when it sets the stretch, about
    a tenth of a second. exiftool writes a new file, so the tool cannot
    tell that file from another one.
  - After the last read of the DNG, directly before the move. That is the
    same as a file that arrives after the run.
- **The counts come from the last scan.** The line under the box, the run
  button and a dry run count the ARW files of the last scan. The run scans
  the folder again. When the folder changed in between, the run can convert
  and move more or fewer ARW files than they said.
- **A dry run plans a run in which each step passes.** It lists a `trash`
  step for each ARW that it expects to convert. When a conversion then
  fails in the real run, that ARW stays.
- **An agent that has a shell.** The MCP server has no argument for the
  option. An agent that can start programs on your Mac can still start the
  command line tool with the flag. The text that the server gives a model
  does not say where the option is.

## What goes to the Trash, and when

| File | When |
|---|---|
| `<name>.dng_original`, the backup of a DNG | After the new tag of that DNG read back correctly. Never before. |
| `.<base>.desqueeze-work.dng`, a hidden work file of the tool | After a conversion that failed. Also when a later run finds one that an earlier run left, at the moment that it converts the same ARW again. |
| `.<base>.desqueeze-work.dng_exiftool_tmp` | When a later run finds it, at the moment that it converts the same ARW again. exiftool can leave this file when it is ended in the middle of the match. |
| `<base>.ARW`, an original | Only in a run that you asked to move the originals, and only after the six checks of the section before this one. |

Nothing else goes to the Trash, and the tool never empties the Trash. When
the Trash refuses a work file, the result names the hidden file, so that you
can delete it.

The tool takes a leftover only when it is a regular file. A folder or a link
with the name of a work file is not the tool's to remove. It stays where it
is, that ARW is not converted, and the result names it.

Each backup is as large as its DNG. So a run on a large folder puts as much
in the Trash as the DNG files that it wrote. The space is free again when
you empty the Trash. Empty it when you are sure of the result.

When the Trash refuses a backup, the backup stays beside its DNG and the
result says so: "Done. The backup stayed beside the file, because the Trash
refused it." The Trash was tested on disk images with the APFS, HFS+ and
ExFAT file systems. A physical card and a network share were not tested.

## One run in a folder at a time

A run holds a lock on the folder from its start to its end. A second run in
the same folder does not start. It reads no photo and changes no file, and
it says:

```
Another Desqueeze run is working in this folder. Wait for it to end, then run again.
```

This holds between the window, the command line tool and the MCP server,
and between two copies of one of them. Run and Remove both take the lock.

- **The lock makes no file.** It is a mark that the system keeps on the
  folder itself. Nothing shows in Finder.
- **The lock goes with the run.** It goes when the run ends, and when the
  program ends for any reason: a crash, a Force Quit, a loss of power. No
  lock stays behind, and there is nothing to clean.
- **A scan and a dry run take no lock.** You can scan a folder while a run
  works in it. The result can then be of a folder in change. For example, a
  DNG can show as blocked by a backup that the run is about to clear. Scan
  again after the run ends.
- **The lock stops only Desqueeze.** Finder, Lightroom and other programs
  work in the folder as before.

Without the lock, the second run would take the hidden work file of the
first run for a leftover, and send it to the Trash.

## When a run stops early

**You cancel.** Cancel in the window, and Control-C in the terminal, stop
the run after the current file. The file in work completes with its check.
The files before it stay as the run left them, and the files after it are
not touched. After a cancel, no original that the run did not reach moves:
each such ARW stays in the folder.

**The run ends hard.** A Force Quit, a crash or a loss of power can end a
run in the middle of a file. The next scan or run reports what it finds:

| What is left | What the tool does next |
|---|---|
| A hidden work file beside an ARW | The ARW still has no DNG. The next run sends the work file to the Trash and converts the ARW again. |
| A DNG with its backup beside it | When the DNG has the wanted value, it is skipped, with a note that names the backup. When it does not, it is blocked. The tool never removes this backup. |
| A backup with no DNG beside it | This can be the only copy of the photo. The tool does not touch it. Every scan and every run names it, with the name to rename it to. While it waits, the ARW with the same base name is not converted. |

<doc:Troubleshooting> gives the steps for each case.

## Undo a run

- **To take the stretch off,** use Remove: the button in the window,
  `desqueeze remove`, or `desqueeze_remove`. Each DNG gets the value `1 1`,
  which is no stretch. A DNG from either converter has this value before a
  run.
- **To change the stretch,** run again with another factor.
- **To get a DNG back exactly as it was,** find its backup in the Trash. Its
  name is `<name>.dng_original`. Move the DNG away, move the backup into the
  folder, and rename it to `<name>.dng`. This is possible until you empty
  the Trash.
- **To undo a conversion,** move the new DNG to the Trash yourself. The tool
  never deletes a DNG, and the ARW is as it was.
- **To get an original back,** find the ARW in the Trash and use Put Back.
  This is possible until you empty the Trash.

## What Finder and Lightroom show

- **Finder and Quick Look ignore the tag.** Their previews stay squeezed
  after a run. That is not an error.
- **Lightroom and Camera Raw show the correct shape.** Lightroom reads the
  tag when it imports a photo, and keeps what it read. For a photo that was
  in the catalog before the run, select it and use Metadata › Read Metadata
  from File.
- **A DNG that got the tag is a new file.** exiftool wrote it. Finder shows
  the time of the run as its creation date, and the Finder tags of the
  earlier file are gone: the file that had them is the backup. The capture
  date inside the photo does not change, and Lightroom reads that date.
- **You can see a hidden file in Finder** with Command-Shift-Period.

## Limits that you must know

- **A volume with no exclusive rename.** On a volume with the ExFAT file
  system, the system cannot check a name and rename in one step. The tool
  checks the name and then renames. If another program makes a file named
  `<base>.dng` in the moment between the two, that file is replaced. This is
  the one case in which the tool can replace a file that it did not make. On
  an APFS or HFS+ volume, the system does both in one step.
- **A volume that gives no lock.** The lock of a run was tested on disk
  images with the APFS, HFS+, ExFAT and MS-DOS (FAT32) file systems. Each
  one gave it. A network share was not tested. When a volume gives no lock
  for a folder, the run goes on without one, and its result says so: "This
  volume gives no folder lock. Do not start a second run in this folder
  while this run works." On such a volume, do not start two runs in one
  folder. When the lock call fails for any other reason, the run does not
  start, and the tool says that the folder could not be read.
- **The moment after a hard end.** When a run ends hard, for example with
  a Force Quit, its lock is free at once. A converter that this run started
  can still work for a moment. A run that starts in that moment can meet
  the work file of that converter. Both converters end in under half a
  second on the Mac of the test, and two trials showed no collision. After
  a hard end, wait a moment before the next run.
- **A long file name.** A file name on a Mac volume can have 255 UTF-16
  units. Most letters are one unit, also a Japanese letter. An emoji is
  two or more. Some volumes store an accented letter as two units, so the
  tool counts each accented letter as two. The longest name that a conversion
  makes is a temporary file that exiftool makes beside the hidden work
  file, `.<base>.desqueeze-work.dng_exiftool_tmp`: the base name of the ARW
  and 33 more units. So for an ARW whose base name has more than 222 units,
  no converter starts. The result lists the ARW as not converted: "The file
  name is too long. Shorten it, then run again." The rule is the same for
  both converters, and a dry run uses it too.
- **A leftover work file can stay.** The tool removes a leftover work file
  only when it converts the same ARW again. If the ARW is gone, or if a DNG
  now belongs to it, the hidden file stays until you delete it.
- **A program that never returns.** If exiftool or a converter hangs, the
  run waits. Force Quit ends it. A write that did not complete leaves the
  DNG as it was.
- **The app is not sandboxed.** A sandboxed app cannot start exiftool, dnglab
  and Adobe DNG Converter. The tool runs with your rights, and reads only the
  folder that you give it.
