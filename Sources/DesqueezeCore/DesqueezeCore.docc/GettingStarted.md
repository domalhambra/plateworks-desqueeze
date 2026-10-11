# Getting started

Build the tool from source, and make a first run on a copy of a folder.

## Overview

Plateworks Desqueeze sets one tag, `DefaultScale`, in each DNG of a folder.
Lightroom and Camera Raw read the tag and show the photo at its correct
shape. The tool converts each Sony ARW to a DNG first, because the tag works
only in a DNG. No pixel changes.

![The Desqueeze window after a run on the folder "Shoot 1". The result line says "4 converted · 12 set · 0 skipped · 0 failed".](window-result)

The tool is for you when all of these are true:

- You use Lightroom or Camera Raw. Finder and Quick Look ignore the tag, so
  their previews stay squeezed. Other raw editors were not tested.
- Your photos are DNG files from any camera, or ARW files from a Sony camera.
- Your lens squeezes the width, by a factor from 1 to 4.
- You have a Mac, and you can build from source with Xcode.

The tool does not stretch pixels and does not export an image. It does not
read subfolders. It does not convert raw files other than Sony ARW. It does
not set a vertical stretch.

## Install what the tool needs

| Program | Needed for | Install |
|---|---|---|
| exiftool | Everything. It reads and writes the tags. | `brew install exiftool` |
| dnglab | The conversion of ARW files to DNG | `brew install dnglab` |
| Adobe DNG Converter | Optional. A backup for the photos that dnglab cannot match. | A download from Adobe, installed in the Applications folder |
| Xcode | The build | The Mac App Store |
| XcodeGen | The build of the window | `brew install xcodegen` |

Adobe DNG Converter is not part of this project, and you do not need it.
<doc:CamerasAndLenses> says when it is used. With no converter at all, the
tool still sets the tag in the DNG files that you have, and leaves the ARW
files as they are.

The versions that were tested are in the `README.md` of the repo. No other
version was tested.

## Build the front end that you want

The three front ends do the same work. Build one, or all three. Run each
command from the root of the repo.

### The command line tool

```bash
swift build -c release
.build/release/desqueeze --help
```

To use the tool by its name, copy `.build/release/desqueeze` to a folder that
is on your `PATH`. `~/.local/bin` is a usual one. Make it first, with
`mkdir -p ~/.local/bin`, and see that it is on your `PATH`: a new Mac does
not have it there. <doc:UsingTheCommandLineTool> has every command.

### The window

```bash
xcodegen generate
xcodebuild -project PlateworksDesqueeze.xcodeproj -scheme PlateworksDesqueeze -configuration Release -derivedDataPath build build
```

The app is then at `build/Build/Products/Release/Desqueeze.app`. Copy it to
the Applications folder, and open it. The build signs the app for the Mac
that built it. It is not signed with a Developer ID and it is not notarized,
so build it on the Mac that uses it. <doc:UsingTheWindow> describes each
part of the window.

### The MCP server

```bash
swift build -c release --package-path MCPServer
MCPServer/.build/release/desqueeze-mcp --help
```

The first build fetches the MCP library for Swift, so it needs a network
connection. <doc:UsingItFromClaudeCode> says how to give the server to an
MCP client.

## Make the first run on a copy

Do not start with a folder of photos that you cannot lose. In Finder,
duplicate one folder of photos, and work on the duplicate. The steps below
use the command line tool. In the window, the same steps are a drop, a
factor, and one click.

1. Look at what the folder holds. This changes no file.

   ```bash
   desqueeze scan "/Volumes/Card/Shoot 1"
   ```

   ```
   /Volumes/Card/Shoot 1

   DNG files: 1
     Name        Scale
     sample.dng  1 1

   ARW files with no DNG: 1
     frame.ARW

   exiftool: /opt/homebrew/bin/exiftool
   dnglab: /opt/homebrew/bin/dnglab
   Adobe DNG Converter: /Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter
   ```

   A scale of `1 1` is no stretch.

2. Ask what a run would do. This changes no file.

   ```bash
   desqueeze run "/Volumes/Card/Shoot 1" --factor 1.5 --dry-run
   ```

   ```
   Dry run. No file was changed.
     convert  frame.ARW  with dnglab
     write    sample.dng
     write    frame.dng
   A run would give: 1 converted · 2 set · 0 skipped · 0 failed
   ```

3. Run. Use the squeeze factor of your lens. The common factors are 1.33,
   1.5, 1.8 and 2.

   ```bash
   desqueeze run "/Volumes/Card/Shoot 1" --factor 1.5
   ```

   ```
   1 converted · 2 set · 0 skipped · 0 failed
   Photos already in Lightroom: Metadata › Read Metadata from File.
   ```

4. Open one DNG in Lightroom or Camera Raw, and look at its shape. Finder
   still shows the photo squeezed. That is correct: Finder ignores the tag.

5. To set every DNG back to no stretch, remove the stretch:

   ```bash
   desqueeze remove "/Volumes/Card/Shoot 1"
   ```

When the result is what you expect, run the tool on the real folder.
<doc:WhatHappensToYourFiles> says what the tool does to each file, and how
to undo it.
