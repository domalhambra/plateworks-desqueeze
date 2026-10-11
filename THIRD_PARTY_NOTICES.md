# Third-party notices

Plateworks Desqueeze is under the MIT license (`LICENSE`). This file lists the
software of other people that it starts or links. It states facts and makes
no legal claim. Read each project's own license for its terms.

## Programs that the app starts

Desqueeze starts these programs as separate processes. No part of them is in
this repo. A build from source contains none of them: the app, the command
line tool and the MCP server then find them on the Mac, and you install each
one yourself. The app of the download is different: it contains two of them.
The next section says which, and how.

| Program | Used for | License | Source |
|---|---|---|---|
| exiftool | Reads and writes the tags | Artistic-1.0-Perl or GPL-1.0-or-later | https://exiftool.org |
| dnglab | Converts an ARW to a DNG | LGPL-2.1-only | https://github.com/dnglab/dnglab |
| Adobe DNG Converter | Optional. Converts the photos that dnglab cannot match. | Adobe's own license | Adobe |

Adobe DNG Converter is not part of this project, and it is never inside the
app. Desqueeze works with no copy of it on the Mac.

The versions that were tested are in `README.md`, under "Built and tested
on". The license names for exiftool and dnglab are the ones that their
Homebrew formulas give.

## Programs inside the download

`scripts/make_release.sh` makes the download: a disk image with
Desqueeze.app. That app holds a copy of dnglab and a copy of exiftool, so a
person installs nothing more. The copies come from the Homebrew packages on
the Mac that makes the release. The script holds the version of each
program and the SHA-256 of its files, and it stops when one differs.

| Program | Version | Place in the app | License |
|---|---|---|---|
| dnglab | 0.8.0 | `Contents/Helpers/dnglab` | LGPL-2.1-only |
| exiftool | 13.55 | `Contents/Resources/exiftool/exiftool`, with its `lib` folder beside it | The terms of Perl: the Perl Artistic License or the GPL |
| The license texts | | `Contents/Resources/licenses/` | |

**dnglab.** The app holds the binary of the Homebrew package as a separate
program. It is not changed, and nothing is linked with it: the app starts
it as a process of its own. The release script signs it, as it signs the
app. The app holds dnglab's license text, `dnglab-LICENSE.txt`, and its
list of authors, `dnglab-AUTHORS.txt`. The steps of a release put the source
archive of that dnglab version on the release page, as a file beside the
disk image, so the source is at the same place as the binary. The dnglab
binary holds Rust libraries of other people. The app carries the notices
that dnglab's own Homebrew package carries, and no more.

**exiftool.** The app holds the exiftool script and exiftool's own Perl
modules, `Image::ExifTool` and `File::RandomAccess`, from the Homebrew
package. One line of the script is changed: the first. Homebrew's copy
starts with the path of one Perl version. The copy in the app starts with
`#!/usr/bin/perl`, the Perl of macOS. No other line is changed, and no file
of the `lib` folder is changed. The app holds exiftool's README, which
states its terms, as `exiftool-README.txt`, and a note about the changed
line, `exiftool-CHANGED-LINE.txt`. exiftool is by Phil Harvey.

The Perl that runs exiftool is a part of macOS. It is not inside the app.

A copy of this file is in the app too, beside the license texts.

No release was made yet. When the first one is, its page has the disk image
and the source archive of dnglab.

## Libraries that only the MCP server links

The window and the command line tool have no third-party code. The MCP
server, `desqueeze-mcp`, links the MCP library for Swift, and that library
brings six more packages. `MCPServer/Package.resolved` pins all seven. A
build of the server fetches them, and no copy of them is in this repo.

Each license below was read from the license file of the pinned version.

| Package | Version | License | Source |
|---|---|---|---|
| swift-sdk, the MCP library | 0.12.1 | Apache-2.0 and MIT. See the note below. | https://github.com/modelcontextprotocol/swift-sdk |
| swift-nio | 2.104.0 | Apache-2.0 | https://github.com/apple/swift-nio |
| swift-log | 1.16.1 | Apache-2.0 | https://github.com/apple/swift-log |
| swift-system | 1.8.1 | Apache-2.0 with the Runtime Library Exception | https://github.com/apple/swift-system |
| swift-atomics | 1.3.1 | Apache-2.0 with the Runtime Library Exception | https://github.com/apple/swift-atomics |
| swift-collections | 1.7.2 | Apache-2.0 with the Runtime Library Exception | https://github.com/apple/swift-collections |
| eventsource | 1.5.1 | MIT | https://github.com/mattt/eventsource |

**swift-sdk.** Its license file says that the MCP project is "undergoing a
licensing transition from the MIT License to the Apache License, Version
2.0". The file says that new contributions are under Apache-2.0, and that a
contribution whose author has not yet agreed to the change stays under the
MIT license. The file holds the text of both licenses.

swift-nio and swift-log each carry a notice file beside the license file.

To read a license yourself, resolve the packages and open the file:

```bash
swift package resolve --package-path MCPServer
ls MCPServer/.build/checkouts
```

When the pin of the MCP library changes, update this table.
`docs/changing-things.md` has the steps.

## The match table

`Sources/DesqueezeCore/AdobeMatch.swift` and
`docs/superpowers/specs/2026-10-09-ilce-7sm3-adobe-values.json` hold numbers
for one camera, the Sony A7S III: a white level, a baseline exposure, six
noise values for each ISO setting, the two reference levels of the camera
calibration rule, and four fixed values. Each number was measured from a DNG
file that Adobe DNG Converter 18.7 wrote from an ARW of that camera, on
2026-10-09. The method is in the design,
`docs/superpowers/specs/2026-10-05-desqueeze-design.md`, section 13.2. The
table holds no code and no camera profile of Adobe's.
