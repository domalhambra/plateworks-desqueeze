# Changelog

Each version of Plateworks Desqueeze, newest first. The form follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The version number is `DesqueezeVersion.current` in
`Sources/DesqueezeCore/Version.swift`. A test fails when the newest entry
below is not that number.

## [0.1.0] - 2026-10-12

The first version. No release is published yet. Until one is, it is built
from source.

### Added

- Screenshots of the window, in a light and a dark variant, in the
  articles "Using the window" and "Getting started" of the documentation
  site, and in `README.md`.
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
- On request, a run moves each original ARW that it converted to the Trash,
  after its DNG passes a check. The window has a box for it, "Move the
  original ARW files to the Trash", and the tool has `--trash-originals`.
  The option is off unless the user turns it on for that run, and it is
  never saved. The MCP server does not have it.
- JSON output, the same from the tool and from the server.
- `--verbose`, which shows each command that the tool starts.
- A documentation site: guides for a photographer and for a contributor,
  and the API reference of `DesqueezeCore`. `scripts/build_docs.sh` builds
  it from the DocC catalog. It is published at <https://domalhambra.github.io/plateworks-desqueeze/>.
- `scripts/make_release.sh`, which makes the download: one disk image with
  the app of the window, for a Mac with Apple silicon and macOS 14 or
  later. The script signs the app and the disk image with a Developer ID
  and the hardened runtime, and has Apple notarize both. With `--local` it
  makes the app only, signed ad hoc, for checks.
- The app of the download has exiftool 13.55 and dnglab 0.8.0 inside, with
  their license texts, so a person installs nothing more. The window looks
  for the two programs inside its own app first, then on the Mac. An app
  that is built from source has no program inside, and looks as before. The
  command line tool and the MCP server are not in the download, and look on
  the Mac only.

### Safety

- An ARW is never changed and never deleted. It moves only to the Trash,
  and only when the user asks for it for one run.
- An original moves only when the run converted it, its DNG has a full
  match and the chosen factor, the DNG is the file that this run made and
  names that ARW, and the ARW did not change during the run. When a check
  does not pass, or the Trash refuses the file, the ARW stays, and a note of
  the kind `originalKept` says why. An ARW that is not in the folder when
  the run comes to move it gets a note that says so.
- The MCP server never moves an original. A tool call that asks for it is
  refused. The text that the server gives a model does not say where the
  option is.
- A DNG keeps its backup until the new tag reads back correctly. Then the
  backup goes to the Trash. A write that fails restores the backup.
- A DNG that has an older backup beside it is blocked, and the backup is not
  touched.
- A converter writes a hidden work file, and the DNG gets its name only when
  it is complete. A DNG that another program made is never replaced.
- A hidden work file that a run left when it ended hard goes to the Trash
  before its photo converts again. `--verbose` says so.
- One run in a folder at a time. A run holds a lock on the folder, which
  makes no file. A second run in the same folder does not start, from any
  front end, and says: "Another Desqueeze run is working in this folder.
  Wait for it to end, then run again." A scan and a dry run take no lock.
- When the lock call fails for a reason that says nothing about the lock,
  the run does not start, and the front end says that the folder could not
  be read, with the system's words.
- The window saves the factor only for a run that started. A click that
  another run refused saves nothing.
- An ARW whose name is too long for the files that a conversion makes gets
  no converter. The note says: "The file name is too long. Shorten it, then
  run again." The limit is a base name of 222 UTF-16 units, counted in the
  decomposed form of the name.
- A factor with a comma, such as "1,5", is refused with the rule and one
  more sentence: "Use a period for the decimal point."
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
- On a volume that gives no lock for a folder, a run goes on without one.
  Its result says so with a note of the kind `noFolderLock`. Two runs at
  once in one folder are then the user's to prevent.
- After a hard end of a run, its lock is free at once, and a converter that
  it started can still work for a moment. A run that starts in that moment
  can meet its work file.
- A scan or a dry run during a run can show a file in change. Scan again
  after the run ends.
- The check before an original moves reads the structure and the tags of
  the DNG. It does not decode the picture. Look at the DNG files in
  Lightroom before the Trash is emptied.
- With the ARW gone, a photo cannot be converted again with a later
  converter or a later match table.
- A Lightroom catalog that holds the ARW files already shows them as
  missing after the move.
- On a volume that has no Trash, the move is refused and every ARW stays.
- The checks before an original moves compare the size, the modification
  date and the file number of the ARW and of its DNG. They do not compare
  the bytes.
- Another program can put a file at the name of a DNG in a moment that the
  run cannot see: before the first record of the DNG, while exiftool works
  in a tag step that writes (about a tenth of a second), or after the last
  read of the DNG before the move. The run takes such a file as its own.
- The box of the window, the run button and a dry run count from the last
  scan. The run scans again, so it can convert and move more or fewer ARW
  files than they said.
- A dry run lists a move for each ARW that it expects to convert. When a
  conversion then fails in the real run, that ARW stays.
- The MCP server has no argument that moves an original, but an agent that
  has a shell can start the command line tool with the flag.
- An app that is built from source is not signed with a Developer ID and
  not notarized. The release script does both for the download. No release
  was made with it yet: the steps that need the Developer ID were not run.
- The download is for Apple silicon. On an Intel Mac the app does not
  start. A build from source on an Intel Mac was not tested either.
- The exiftool inside the app needs the Perl of macOS. Apple has said that
  a later macOS can come without it. The window then looks for exiftool on
  the Mac, as a build from source does.
- A person cannot replace a program inside the downloaded app. A newer
  dnglab or exiftool reaches the app only with a new release.
- The app has no update check. It cannot say that a new release exists.
- The dnglab binary holds Rust libraries of other people. The app carries
  the notices that dnglab's own Homebrew package carries, and no more.
- Only the Mac that has the Developer ID can make a release.
