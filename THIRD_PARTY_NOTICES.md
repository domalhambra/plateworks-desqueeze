# Third-party notices

Plateworks Desqueeze is under the MIT license (`LICENSE`). This file lists the
software of other people that it starts or links. It states facts and makes
no legal claim. Read each project's own license for its terms.

## Programs that the app starts and does not contain

Desqueeze finds these programs on the Mac and starts them as separate
processes. No part of them is in this repo or in a built copy of the app,
the command line tool or the MCP server. You install each one yourself.

| Program | Used for | License | Source |
|---|---|---|---|
| exiftool | Reads and writes the tags | Artistic-1.0-Perl or GPL-1.0-or-later | https://exiftool.org |
| dnglab | Converts an ARW to a DNG | LGPL-2.1-only | https://github.com/dnglab/dnglab |
| Adobe DNG Converter | Optional. Converts the photos that dnglab cannot match. | Adobe's own license | Adobe |

Adobe DNG Converter is not part of this project. Desqueeze works with no
copy of it on the Mac.

The versions that were tested are in `README.md`, under "Built and tested
on". The license names for exiftool and dnglab are the ones that their
Homebrew formulas give.

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
