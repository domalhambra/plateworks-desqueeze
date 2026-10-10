# Using the window

Drop a folder, select the squeeze factor of the lens, and run.

## Overview

The app is named Desqueeze. It has one window with a fixed width. From top
to bottom, the window has a drop zone, a row of squeeze factors, two
buttons, and, after a run, the result.

@Comment {
    A screenshot belongs here: the window with a folder loaded, before a run.
    No screenshot is in the catalog yet.
}

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
| This folder could not be read. | The scan failed. No file is tried. |

## Select the squeeze factor

The row has one button for each common factor: 1.33, 1.5, 1.8 and 2. The
field after them takes any other factor: a number from 1 to 4, with at most
four decimal places. One factor is selected at a time. A click in the field
selects the factor in the field, and the field then shows a check mark.

The window remembers the factor of the last run. Before the first run, 1.5
is selected.

When the text in the field is not a factor, a click on the run button shows
"Enter a number from 1 to 4, with at most four decimal places." and starts
nothing.

## Run

The run button shows how many photos a run works on: "Desqueeze 228 photos",
"Desqueeze 1 photo", or "Desqueeze" when there is nothing to run. The count
is the DNG files plus the ARW files that can convert. The Return key presses
the button.

A run converts each ARW that has no DNG, then sets the tag in every DNG, one
file at a time. During a run:

- A bar shows the progress, with one step for each conversion and one for
  each DNG. The line below it names the last file that is complete.
- The run button becomes "Cancel", and the Escape key presses it. A cancel
  stops the run after the current file. The files that are complete stay as
  the run left them. After the click the button reads "Finishing…" until the
  run has ended.
- A drop is refused, and the factor row is off.

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

Below the counts, the window can show how many ARW files the run left, and
it always shows this line:

```
Photos already in Lightroom: Metadata › Read Metadata from File.
```

Lightroom reads the tag when it imports a photo, and keeps what it read. For
a photo that is in the catalog already, select it in Lightroom and use that
menu command.

Then comes a list, with one entry for each file that has something to say:
the name of the file, one plain sentence, and, on a smaller line, the words
of the program that did the work. <doc:Troubleshooting> explains each
sentence.

## The messages about missing programs

The window looks for the three programs each time it opens.

| Missing | What the window shows | What still works |
|---|---|---|
| exiftool | "Desqueeze needs exiftool, and it is not installed.", with the command `brew install exiftool`. Install it, then open Desqueeze again. | Nothing. |
| Adobe DNG Converter | "Adobe DNG Converter is not installed. It is an optional backup for photos that dnglab cannot match." | Everything. dnglab converts every ARW. A photo that it cannot match gets a note in the result. |
| dnglab | "dnglab is faster and opens no window. Install it with: brew install dnglab" | Everything. Adobe DNG Converter converts every ARW. |
| dnglab and Adobe DNG Converter | The counts line says, for example, "12 ARW cannot be converted: no converter is installed". The line below gives the command `brew install dnglab`. | The DNG files still run. The ARW files stay as they are. |

The lines about the converters show only when the folder has an ARW that
waits for a conversion.

## Limits of the window

- The Tab key can move the keyboard focus into the field of the custom
  factor. That selects the factor in the field. Before a run from the
  keyboard, look at which factor is selected.
- A second click on the run button within the double-click time of the
  system does not cancel the run that the first click started.
- If exiftool or a converter never returns, the run does not end. Use Force
  Quit. A write that did not complete leaves the DNG as it was.
- The window sends each backup to the Trash of the Mac.
  <doc:WhatHappensToYourFiles> says when.
