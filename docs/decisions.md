# Decisions

Durable choices that constrain later work. Each row has its date, the reason,
and the place that carries the decision. Never delete a row. When a decision
is reversed, mark the old row superseded and add the new one under its own
date.

"Design" is `docs/superpowers/specs/2026-10-05-desqueeze-design.md`. "Design
13.3" is its section 13.3. Sections 12 and 13 are the newest, and they win
where they differ from an earlier section. Dom is the maintainer.

## 2026-10-05

| Decision | Why | Source |
|---|---|---|
| The app sets the DNG `DefaultScale` tag. It never resamples or exports an image. | The tag is reversible and changes no pixels. Lightroom and Camera Raw stretch the image when they render it. | Design 1 |
| An ARW is converted to DNG first. | Adobe discards `DefaultScale` in an ARW. Tested: a tagged ARW converted to a DNG with `1 1`. | Design 2 |
| The first front end is a native SwiftUI window. | A droplet has no window for progress and errors. A web shell is heavy for one window. | Design 11 |
| The DNG goes beside the ARW with the same base name. The app never renames, moves, or deletes an ARW. | A second run can skip converted files. Dom chose this. | Design 11 |
| The scan reads the top level of the folder only. | Subfolders of a shoot folder hold exports and the data of other programs. They must stay untouched. | Design 4.1 |
| A DNG keeps its `_original` backup until the tag reads back correctly. Then the backup goes to the Trash. | In a folder with no ARW files, the DNG is the only copy of the photo. | Design 4.3 |
| **Superseded 2026-10-09: such a DNG is blocked, not skipped.** A DNG that already has a backup is skipped and reported. | exiftool never replaces an existing `_original`, so a write would leave a backup of the wrong state. The app must not discard a backup it did not make. | Design 2.1 |
| The app is not sandboxed. | It starts external programs, which a sandboxed app cannot do. This rules out the Mac App Store. | Design 6, `project.yml` |
| Version 1 is built for one Mac first, and shaped to ship later. | Dom chose this. | Design 3, 11 |

## 2026-10-09

| Decision | Why | Source |
|---|---|---|
| **Superseded the same day by the next row.** Adobe DNG Converter is the converter for version 1, behind the `RawConverter` protocol. | Its output is the file that Lightroom's "Copy as DNG" makes. dnglab's white level cut about 0.09 stops of highlight headroom on the test frame. | Design 2.1, 11 |
| dnglab converts each photo that it can match. The app writes Adobe's values into the dnglab DNG with exiftool. Adobe DNG Converter is the optional backup for the other photos. | Adobe DNG Converter starts as an app for each ARW, so the Dock shows it once for each file. dnglab takes 0.09 s a file against 0.37 s and opens nothing. The measurement removed the reason to keep Adobe first: the white level and the baseline exposure must change together, and with the other tags of the table the render is within 0.002 stops at ISO 800. | Design 13.1, 13.2, `Sources/DesqueezeCore/DnglabConverter.swift` |
| The match table holds one camera, the Sony A7S III, measured at 23 ISO settings. A frame with no full match goes to Adobe DNG Converter. A frame from a lens that reports itself is one of them. | Each value comes from a file that Adobe DNG Converter wrote. Nothing is estimated. For a lens that reports itself, Adobe writes a lens-correction block and dnglab writes none. | Design 13.2, 13.4, `Sources/DesqueezeCore/AdobeMatch.swift` |
| A converter writes a hidden work file, `.<base>.desqueeze-work.dng`. A rename that fails when the name is taken gives the DNG its name. | `<base>.dng` appears only when it is complete and matched. A run that ends hard leaves a hidden file and a pending ARW, never a DNG that looks done. A DNG that another program made is never replaced. | Design 13.3, `Sources/DesqueezeCore/ExclusiveRename.swift` |
| The only file that a failed conversion sends to the Trash is the work file. | A partial DNG that stays in the folder would claim its ARW in every later scan, and the photo would never convert. The work file's name is the app's own, so no file of the user is at risk. | Design 4.3 step 1, 13.3 |
| A conversion passes only when the exit code is 0, the work file has bytes, and the rename passed. For dnglab, the tags must also read back. | Adobe DNG Converter returns 0 for a file that it cannot read. A converter that is ended in work can leave a file with no bytes. | Design 13.3, `Sources/DesqueezeCore/RawConverter.swift` |
| Never pass `-f` to dnglab. Never pass `-h` to Adobe DNG Converter. | `-f` writes over an existing file. `-h` opens a window and the process never returns. | Design 4.3 step 1, 13.2, `Sources/DesqueezeCore/DnglabConverter.swift` |
| A DNG that already has a backup is blocked. The run holds it back, reports it, and does not touch the backup. | The reason of 2026-10-05 holds. "Skipped" now means only "already at this value", so a count of skipped files never hides a file that the run did not look at. | Design 4.3 step 2, 11 |
| An ARW is pending unless a DNG has its base name or names it in `OriginalRawFileName`. An orphan backup claims its ARW by base name. | A DNG that was renamed on import still claims its ARW, so a second run never converts the ARW again. | Design 4.1, `Sources/DesqueezeCore/FolderScan.swift` |
| Every read and write of `DefaultScale` names the group `SubIFD`. | That is the image directory Camera Raw reads. | Design 4.1, `Sources/DesqueezeCore/ScaleTag.swift` |
| One exiftool call for each `DefaultScale` write. | Clear progress, and a failure stays with one file. At 0.10 s a file, speed is not a reason to batch. | Design 2.1, 11 |
| A DNG whose scale is unknown is never skipped. The run tries the write. | exiftool prints `-` for a DNG with no tag and for a file that it cannot read. Only the write tells the two apart. | Design 4.1, `Sources/DesqueezeCore/RunPlan.swift` |
| A run always starts with its own scan. No front end can hand the run an earlier scan. | Files and tag values can change between a scan and a click. A run on old values reported "skipped" for a file that it never looked at. | Design 4.3, `Sources/DesqueezeCore/DesqueezeJob.swift` |
| Remove is an intent that the caller states. The job does not guess it from factor 1. | `run` at factor 1 with no conversion still reports the ARW files that it left. Only Remove leaves that line out. | Design 12.1, `Sources/DesqueezeCore/Operations.swift` |
| A command line tool, `desqueeze`, and an MCP server, `desqueeze-mcp`, call the same core as the window. | Dom asked for them, so an agent can do the app's job with no window. Every rule of design 4 holds for all three front ends. | Design 12 |
| The MCP server is its own Swift package, in `MCPServer/`. | The MCP library brings six more packages. In the root manifest, every build of the core and of the app would fetch them. The root package and the app stay free of third-party code. | Design 12.2, `MCPServer/Package.swift` |
| The MCP library is pinned to one minor version. | The library is not yet at 1.0, and its API changes between minor versions. | Design 12.2, `MCPServer/Package.swift` |
| The tool and the server print the same report types as JSON. A front end reads a note's `kind`, never the English sentence. | Two front ends cannot disagree about a result, and a sentence can change with no break. | Design 12.1, `Sources/DesqueezeCore/Reports.swift` |
| Every sentence that more than one front end says is made once, in `DesqueezeCore`. | The window, the tool and the server cannot say different things about one folder. | Design 7, 13.5, `Sources/DesqueezeCore/FolderText.swift` |
| Control-C, a plain `kill` and a closed Terminal window stop the tool after the current file. The tool ignores a closed pipe. | A tool that ended at once would leave a backup beside the file that exiftool was writing. | Design 12.1, `Sources/DesqueezeCore/InterruptWatcher.swift` |
| On a signal, the server lets the current file complete, writes that call's report with `stopped`, and exits 0. When standard input closes, the call in work completes, and a call that waits does not start. | A server that ended at once would leave a backup beside a file. A call that changes files must not run for a client that is gone. | Design 12.2, `MCPServer/Sources/desqueeze-mcp/AnsweringTransport.swift` |
| The server runs one tool call at a time. | The job assumes one run in a folder at a time. Two at once can give false notes. | Design 12.2, `MCPServer/Sources/desqueeze-mcp/CallQueue.swift` |
| No test uses the real Trash. `FileBackups` takes the trash function as a parameter with no default, and the built tools take `DESQUEEZE_TEST_BACKUP_FOLDER`. | A test run must not fill a person's Trash. The real Trash is checked by hand. | `Sources/DesqueezeCore/Backups.swift` |
| Capture One is out of scope. | Dom's workflow is moving to Lightroom. | Design 2 |
| The license is MIT. The copyright holder is Plateworks. The repo becomes public. | Dom's decision. It supersedes design 10, which says that the repo is private. | `LICENSE` |
| The repo is documented to the Medium tier of the Plateworks documentation standard, with the files that an open-source repo carries. | Dom's decision. It supersedes design 10, which says Floor tier. A reader with no access to the maintainer's Mac must be able to build, test and change the code. | `docs/README.md` |
| The header of the repo's copy of the docs check names no path outside the repo. Only that header differs from the standard's check. | Dom's decision, for a public repo. | `scripts/docs_check.py` |
| A documentation site is built with DocC and published later, on Dom's yes. | The public types of `DesqueezeCore` carry their documentation in the source. | `docs/superpowers/plans/2026-10-09-desqueeze-v1.md`, Task 16. Not built yet. |
| The site is built with the `docc` of Xcode, from the symbol graph that the compiler writes. The package gets no dependency for it. A workflow publishes the site to GitHub Pages when the repo is public. | The root package must stay free of third-party code, also at build time, and `swift-docc-plugin` is a package dependency. Nothing is published before the repo is. | `scripts/build_docs.sh`, `Sources/DesqueezeCore/DesqueezeCore.docc`, `.github/workflows/docs.yml`. Built. The workflow has not run yet. |

## Rejected and deferred

| Item | Status | Why |
|---|---|---|
| A Photoshop script that stretches the photos | Rejected | It converts the raw data to a JPEG. The editing range is gone. |
| Writing the tag into the ARW | Rejected | Adobe discards it (design 2). |
| Adobe's embedded camera profile, copied into the dnglab DNG | Rejected | Camera Raw uses its own profile for the camera model (design 13.2). |
| A bundled dnglab and a bundled exiftool | Deferred to a release | Version 1 finds the programs that Homebrew installed. A shipped app must carry its own (design 3). |
| Signing and notarization | Deferred to a release | Needed only when the app is given to other people as a built app. |
| Match rows for other cameras | Deferred | Each camera needs its own measurement (design 13.9). `CONTRIBUTING.md` has the steps. |
| Brand marks, an accent color, app icon art, a privacy page | Deferred to a release | These belong to a published app. Version 1 uses system colors and the system font. |
| Subfolder scan | Deferred | Subfolders hold exports and the data of other programs. |
| Folder drop on the Dock icon | Deferred | The window drop does the job. |
| Parallel writes | Rejected for now | Design 2.1 measured about 30 s for a 228-file folder, one file at a time. |
| Vertical squeeze | Deferred | No lens that the maintainer owns needs it. |
| A timeout for a tool that never returns | Left, a known limit | The window stays at "Finishing…" and Force Quit is the way out. No file is harmed: a write that did not complete leaves the DNG as it was (design 5). |
| A full fix for a Control-C that reaches a tool that is just starting | Left, a known limit | Seen once in 27 test runs under load. That one file is reported as failed and is left as it was. A second run completes it (design 12.1). |
| An exclusive rename on a volume that has none, such as ExFAT | Left, a known limit | The app checks the name and then renames. A moment lies between the two calls (design 13.9). |
