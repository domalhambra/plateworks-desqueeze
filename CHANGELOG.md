# Changelog

Each version of Plateworks Desqueeze, newest first. The form follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The version number is `DesqueezeVersion.current` in
`Sources/DesqueezeCore/Version.swift`. A test fails when the newest entry
below is not that number.

## [0.1.0] - Unreleased

The first version. It is built from source, and there is no download.

### Added

- Sets the DNG `DefaultScale` tag on every DNG at the top level of one
  folder, so Lightroom and Camera Raw show each anamorphic photo at its
  correct shape. No pixel changes.
- Four preset squeeze factors (1.33, 1.5, 1.8, 2), and any factor from 1 to
  4 with at most four decimal places.
- Remove: sets every DNG back to no stretch.
- Converts each Sony ARW that has no DNG to a DNG beside it. dnglab converts
  each photo that it can match, and Adobe DNG Converter, when it is
  installed, converts the others.
- The match: a dnglab DNG gets the values that Adobe DNG Converter writes,
  so Lightroom shows the same photo. Measured for one camera, the Sony
  A7S III, compressed raw, at 23 ISO settings: 50, and 80 to 12800 without
  1250.
- Three front ends on one core: a window, the command line tool `desqueeze`
  (`scan`, `run`, `remove`), and the MCP server `desqueeze-mcp`
  (`desqueeze_scan`, `desqueeze_run`, `desqueeze_remove`).
- A dry run that lists what each file would get and changes no file.
- JSON output, the same from the tool and from the server.
- `--verbose`, which shows each command that the tool starts.

### Safety

- An ARW is never changed, moved or deleted.
- A DNG keeps its backup until the new tag reads back correctly. Then the
  backup goes to the Trash. A write that fails restores the backup.
- A DNG that has an older backup beside it is blocked, and the backup is not
  touched.
- A converter writes a hidden work file, and the DNG gets its name only when
  it is complete. A DNG that another program made is never replaced.
- A hidden work file that a run left when it ended hard goes to the Trash
  before its photo converts again. `--verbose` says so.
- Control-C, a plain `kill` and a closed Terminal window stop a run after
  the current file.

### Known limits

- The match table has one camera. Another frame goes to Adobe DNG Converter,
  or converts with dnglab and gets a note that says what the DNG lacks.
- Finder and Quick Look ignore the tag, so their previews stay squeezed.
- A DNG that got the tag is a new file: Finder shows the time of the run as
  its creation date, and Finder tags on the earlier file are gone.
- If exiftool or a converter never returns, the run waits. Force Quit is the
  way out, and no file is harmed.
- On a volume with no exclusive rename, such as ExFAT, the app checks the
  name and then renames. A moment lies between the two calls.
- The app is not signed with a Developer ID and not notarized.
