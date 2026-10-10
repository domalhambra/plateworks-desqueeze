# How version 1 was built

This is a short history. The contract is the design,
`superpowers/specs/2026-10-05-desqueeze-design.md`. The reasons for each
choice are in `decisions.md`. The commit history of the build is not
published: the repo starts with one commit.

## The method

A coding agent wrote version 1 between 2026-10-05 and 2026-10-10, with the
maintainer deciding each question of behavior. Each task went through the
same steps:

1. A written brief, with the design section that governs it.
2. One builder, working test-first.
3. An independent review in a separate checkout. The reviewer did not get
   the builder's report. It broke the product code on purpose and looked for
   a test that failed.
4. A fix round for each finding, and a second review where a fix changed a
   rule that guards a file.

Two rules came from this method and stay in force (`CLAUDE.md`):

- A behavioral test counts only after it fails against a break.
- Each claim about an external program was tested by hand before the design
  used it (design 2.1 and 13.2).

## The order of the work

| Step | What was built |
|---|---|
| 1 to 7 | The core package: the squeeze factor, the process runner and the tool locator, the folder scan and the pending rule, the tag write and read-back, the backups, the job, and the tests on the real programs. |
| 8 | The window. |
| 9 | The command line tool, `desqueeze`, and the shared reports. |
| 10 | The MCP server, `desqueeze-mcp`, as a package of its own. |
| 11 | The repo documents. |
| 15 | dnglab as the first converter, matched to the values that Adobe DNG Converter writes, with Adobe DNG Converter as the optional backup. The hidden work file and the exclusive rename, for both converters. |
| 16 | The documentation site. |
| 17 | The repo made ready to be public: the license, and no private path or name. |
| 18 | The fixes from two reviews of the whole build: one run in a folder at a time, one rule for each line that two front ends show, the long file name. |
| 19 to 21 | The option that moves the originals to the Trash, its hostile review, and the rule that the DNG must be the file that the run made. |

Steps 12 to 14 were the maintainer's own: filing, the acceptance pass, and
the repository.

## What changed on the way

- **The converter.** The first design used Adobe DNG Converter alone. It
  starts as an app for each file, so the Dock showed it once for each photo.
  A first test of dnglab found a difference in highlight headroom, and the
  first conclusion was that no tag could close it. That was wrong: a second
  measurement, of the white level and the baseline exposure together, closed
  it. The match table is the result (design 13).
- **A skipped file.** "Skipped" first meant two things: already at the
  value, and held back by a backup. A count of skipped files could then hide
  a file that the run did not look at. "Blocked" became its own outcome.
- **The partial DNG.** A converter that is ended in work can leave a DNG
  with no bytes, which then claims its ARW in every later scan. The work
  file is the answer: `<base>.dng` appears only when it is complete.
- **The originals.** Until 2026-10-10 the app never moved an ARW. The
  option is off by default, is never saved, and is not in the MCP server
  (design 14).

## What the reviews found that tests had missed

Each of these is now pinned by a test that was seen to fail:

- A closed pipe ended the command line tool in the middle of a run.
- A DNG of the user could reach the Trash when another program made a file
  at the output name at the wrong moment.
- A hard end left a DNG that looked done but had no match.
- Two runs in one folder could act on each other's work files.
- With the option on, an ARW could move though the DNG beside it was another
  photo's.
