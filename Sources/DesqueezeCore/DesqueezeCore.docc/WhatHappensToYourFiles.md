# What happens to your files

What the tool does to each file, what it sends to the Trash, and how to undo a run.

## Overview

The window, the command line tool and the MCP server follow the same rules,
because one piece of code does the file work for all three.

- **An ARW is never changed, moved or deleted.** The tool only reads it.
- **No pixel changes.** The tool sets a tag. It never resamples a photo and
  never exports one.
- **A DNG keeps a backup until the new tag reads back correctly.**
- **Nothing is deleted.** The tool moves two kinds of file to the Trash, and
  no other: the backup of a DNG after a good write, and its own hidden work
  files.
- **A conversion never replaces a DNG that is there already.**
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
   already, no converter starts for `frame.ARW`.
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

## What goes to the Trash, and when

| File | When |
|---|---|
| `<name>.dng_original`, the backup of a DNG | After the new tag of that DNG read back correctly. Never before. |
| `.<base>.desqueeze-work.dng`, a hidden work file of the tool | After a conversion that failed. Also when a later run finds one that an earlier run left, at the moment that it converts the same ARW again. |
| `.<base>.desqueeze-work.dng_exiftool_tmp` | When a later run finds it, at the moment that it converts the same ARW again. exiftool can leave this file when it is ended in the middle of the match. |

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

## When a run stops early

**You cancel.** Cancel in the window, and Control-C in the terminal, stop
the run after the current file. The file in work completes with its check.
The files before it stay as the run left them, and the files after it are
not touched.

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
- **A leftover work file can stay.** The tool removes a leftover work file
  only when it converts the same ARW again. If the ARW is gone, or if a DNG
  now belongs to it, the hidden file stays until you delete it.
- **A program that never returns.** If exiftool or a converter hangs, the
  run waits. Force Quit ends it. A write that did not complete leaves the
  DNG as it was.
- **The app is not sandboxed.** A sandboxed app cannot start exiftool, dnglab
  and Adobe DNG Converter. The tool runs with your rights, and reads only the
  folder that you give it.
