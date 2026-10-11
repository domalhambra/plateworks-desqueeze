# Using the window

Drop a folder, select the squeeze factor of the lens, and run.

## Overview

The app is named Desqueeze. It has one window with a fixed width. From top
to bottom, the window has a drop zone, a row of squeeze factors, a box for
the originals when the folder has ARW files to convert, two buttons, and,
after a run, the result.

![The Desqueeze window with the folder "Shoot 1" loaded. The drop zone says 8 DNG and 4 ARW to convert. The factor 1.5 is selected. The box for the originals is off. The run button says "Desqueeze 12 photos".](window-folder)

The screenshots on this page show one folder of 8 DNG files and 4 ARW
files, before, during and after one run.

## Load a folder

Drag one folder onto the drop zone, or click "Choose folder". The window
then shows the name of the folder and one line of counts, for example:

```
216 DNG · 12 ARW to convert
```

The counts are for the top level of the folder. The window does not read
subfolders, and it ignores hidden files. "ARW to convert" counts each ARW
that has no DNG yet. An ARW that has a DNG is not converted again.

- A symbolic link to a folder counts as that folder.
- A package, such as an app or a photo library, is not a folder here. For a
  package, a file, or more than one item, the window shows "Drop a folder",
  and the folder that was loaded stays loaded.
- A folder with no photo shows "No DNG or ARW files in this folder."
- The window reads the folder again each time the app becomes active, and
  after each run. So a file that another app added shows in the counts.

The drop zone also shows the messages about the folder. Each one has a
warning symbol:

| Message | Meaning |
|---|---|
| This folder is read-only. Desqueeze cannot change its files. | Both buttons are off. |
| `<name>.dng_original`: A backup with no DNG beside it. Rename it to `<name>.dng` to get the photo back. | An earlier write did not complete. <doc:Troubleshooting> says what to do. The window names up to five such files, then gives a count of the others. |
| This folder could not be read. | The scan failed. No file is tried. When a click on a button started no run because the lock call of the system failed, a small line below the message has the words of the system, for example "Input/output error". The line goes when the window reads the folder again. |
| Another Desqueeze run is working in this folder. Wait for it to end, then run again. | A click on a button started no run, and no file was changed. Another run works in this folder: in the command line tool, in the MCP server, or in a second copy of the app. The message goes at the next click that starts a run, or when another folder loads. It also goes when the window cannot read the folder: the window then shows "This folder could not be read." alone, and VoiceOver says the same. |

## Select the squeeze factor

The row has one button for each common factor: 1.33, 1.5, 1.8 and 2. The
field after them takes any other factor: a number from 1 to 4, with at most
four decimal places. One factor is selected at a time. A click in the field
selects the factor in the field, and the field then shows a check mark.

The window remembers the factor of the last run. Before the first run, 1.5
is selected. A click that started no run saves nothing: when another run
works in the folder, or the folder could not be read, the next launch has
the factor of the last run that worked.

When the text in the field is not a factor, a click on the run button shows
"Enter a number from 1 to 4, with at most four decimal places." and starts
nothing. For text with a comma, such as "1,5", the window adds: "Use a
period for the decimal point."

## Move the originals to the Trash

When the folder has an ARW that can convert, a box shows between the factors
and the buttons:

```
Move the original ARW files to the Trash
```

The box is off. Tick it, and the next run moves each ARW that it converted
to the Trash, after the DNG of that ARW passed a check.
<doc:WhatHappensToYourFiles> has the rule and its limits.

![The window with the box for the originals on. A line under the box says that 4 original ARW files go to the Trash after their DNG files pass the check. The run button says "Desqueeze 12 photos, move 4 ARW to Trash".](window-originals)

- While the box is on, a line under it says what the run will do, for
  example "12 original ARW files go to the Trash after their DNG files pass
  the check." The run button then names the count of the originals too,
  for example "Desqueeze 14 photos, move 12 ARW to Trash".
- The window asks nothing more. The box is the request, and you can put a
  file back from the Trash.
- The box is off when the app opens, when a folder loads, and after every
  run, also a run that you cancelled or that failed. The window never saves
  it. Tick it again for each run that must move the originals.
- The box does not show for a folder with no ARW to convert, for a
  read-only folder, and when no converter is installed. An ARW whose name
  is too long cannot convert, so the box and its count leave it out. The
  run button still counts that ARW, and the result of the run says what to
  do with it.
- The line and the run button count from the last time that the window
  read the folder. The run reads the folder again, so it can move more or
  fewer ARW files than they said.
- The box cannot change while a run works, or while the window reads the
  folder.
- "Remove" never moves an original, also with the box on.

## Run

The run button shows how many photos a run works on: "Desqueeze 228 photos",
"Desqueeze 1 photo", or "Desqueeze" when there is nothing to run. The count
is the DNG files plus the ARW files that can convert. The Return key presses
the button.

A run converts each ARW that has no DNG, then sets the tag in every DNG, one
file at a time. During a run:

- A bar shows the progress, with one step for each conversion and one for
  each DNG. With the box for the originals on, each converted ARW has one
  more step, at the end. The line below the bar names the last file that is
  complete.
- The run button becomes "Cancel", and the Escape key presses it. A cancel
  stops the run after the current file. The files that are complete stay as
  the run left them. After the click the button reads "Finishing…" until the
  run has ended.
- A drop is refused, and the factor row is off.

![The window during a run. The factors, the box and "Remove" are off. The run button says "Cancel". A progress bar is about one third full, and the line below it says "6 of 20 · last finished: DSC04094.dng".](window-run)

If you quit the app during a run, the app cancels the run, lets the current
file complete, and then quits.

## Remove

"Remove" sets every DNG in the folder back to no stretch. It converts
nothing. It asks nothing and starts at once, because a run with the factor
sets the stretch again. The button is on only when the folder has a DNG.

## Read the result

After a run, the window shows one line of counts with a symbol before it:

```
12 converted · 228 set · 0 skipped · 0 failed
```

| Count | Meaning |
|---|---|
| converted | ARW files that became a DNG. Not shown when it is zero. |
| set | DNG files that got the tag. |
| skipped | DNG files that had this value already. Nothing was written. |
| blocked | DNG files that the run held back, because an older backup is beside each one. Not shown when it is zero. |
| failed | Files with an error. Each one is as it was before the run. |
| stopped | The run was cancelled and left work undone. |

The symbol is a check mark when the run is complete, a warning triangle when
a file failed or was blocked, and a stop symbol when the run was cancelled. The
meaning is never in a colour alone.

![The window after a run. Below the buttons, a check mark and the line "4 converted · 12 set · 0 skipped · 0 failed". Then "Originals moved to the Trash: 4 of 4." Then the line about photos that are already in Lightroom.](window-result)

Below the counts, the window can show four more lines.

When both converters did work in the run, one line says how many photos
each converted:

```
Converted with dnglab: 11. With Adobe DNG Converter: 1.
```

After a run with the box for the originals on, one line says how many
originals moved, of the ARW files that the run converted. VoiceOver speaks
it with the counts.

```
Originals moved to the Trash: 11 of 12.
```

When the run left ARW files, one line says how many.

When the run set the tag in at least one photo, the window shows this line:

```
Photos already in Lightroom: Metadata › Read Metadata from File.
```

Lightroom reads the tag when it imports a photo, and keeps what it read. For
a photo that is in the catalog already, select it in Lightroom and use that
menu command. After a run that set no photo, the line does not show: there
is nothing to read again.

Then comes a list, with one entry for each file that has something to say:
the name of the file, one plain sentence, and, on a smaller line, the words
of the program that did the work. <doc:Troubleshooting> explains each
sentence.

## The messages about missing programs

The window looks for the three programs each time it opens. It looks for
exiftool and dnglab in `/opt/homebrew/bin`, then in `/usr/local/bin`, then
in each folder of `PATH`. An app that Finder starts gets a short `PATH`, so
in practice it finds the two programs in the two Homebrew folders. It asks
macOS where Adobe DNG Converter is, so it finds that app wherever it is
installed.

| Missing | What the window shows | What still works |
|---|---|---|
| exiftool | "Desqueeze needs exiftool, and it is not installed.", with the command `brew install exiftool`. Install it, then open Desqueeze again. | Nothing. |
| Adobe DNG Converter | "Adobe DNG Converter is not installed. It is an optional backup for photos that dnglab cannot match." | Everything. dnglab converts every ARW. A photo that it cannot match gets a note in the result. |
| dnglab | "dnglab is faster and opens no window. Install it with: brew install dnglab" | Everything. Adobe DNG Converter converts every ARW. |
| dnglab and Adobe DNG Converter | The counts line says, for example, "12 ARW cannot be converted: no converter is installed". The line below gives the command `brew install dnglab`. | The DNG files still run. The ARW files stay as they are. |

The lines about the converters show only when the folder has an ARW that
waits for a conversion.

![The window on a Mac with no exiftool. A box at the top has a warning symbol and says "Desqueeze needs exiftool, and it is not installed. Install it in Terminal, then open Desqueeze again: brew install exiftool". Both buttons are off.](window-no-exiftool)

## Limits of the window

- The Tab key can move the keyboard focus into the field of the custom
  factor. That selects the factor in the field. Before a run from the
  keyboard, look at which factor is selected.
- A second click on the run button within the double-click time of the
  system does not cancel the run that the first click started.
- If exiftool or a converter never returns, the run does not end. Use Force
  Quit. A write that did not complete leaves the DNG as it was.
- The window sends each backup to the Trash of the Mac, and each original
  when the box is on. <doc:WhatHappensToYourFiles> says when.
