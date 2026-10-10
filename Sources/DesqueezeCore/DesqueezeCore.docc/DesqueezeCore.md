# ``DesqueezeCore``

Show a photo from an anamorphic lens at its correct shape in Lightroom, with one tag in the DNG and no change to a pixel.

@Metadata {
    @DisplayName("Plateworks Desqueeze")
}

## Overview

An anamorphic lens squeezes the width of each photo. Plateworks Desqueeze is
a Mac tool that sets the `DefaultScale` tag in every DNG of one folder.
Lightroom and Camera Raw read the tag and stretch the photo when they show
it. The tag works only in a DNG, so the tool converts Sony ARW files to DNG
first.

The tool has three front ends, and all three do the same work:

- A window. Drop a folder on it, select the squeeze factor of the lens, and
  click the run button.
- A command line tool, `desqueeze`.
- An MCP server, `desqueeze-mcp`, for an MCP client such as Claude Code.

`DesqueezeCore` is the Swift module that holds every rule. Each front end
collects input, calls the core, and shows what the core returns. Three
external programs do the file work: exiftool reads and writes the tags,
dnglab converts ARW files, and Adobe DNG Converter is an optional backup for
the photos that dnglab cannot match.

The tool is open source under the MIT license. It is built from source: there
is no download. The build was tested on macOS 27.2 with Xcode 27 only.

### Where to start

- To use the tool, start with <doc:GettingStarted>. Before the first run on
  photos that matter, read <doc:WhatHappensToYourFiles>.
- To change the code, start with <doc:Architecture>, then read
  <doc:SafetyRulesForCode>.
- To add your camera, read <doc:HowTheMatchWorks>, then <doc:AddingACamera>.

## Topics

### For a photographer

- <doc:GettingStarted>
- <doc:UsingTheWindow>
- <doc:UsingTheCommandLineTool>
- <doc:UsingItFromClaudeCode>
- <doc:WhatHappensToYourFiles>
- <doc:CamerasAndLenses>
- <doc:Troubleshooting>

### For a contributor

- <doc:Architecture>
- <doc:HowTheMatchWorks>
- <doc:AddingACamera>
- <doc:SafetyRulesForCode>
- <doc:Testing>
- <doc:TheJSONReports>

### Scan and snapshot

- ``FolderChoice``
- ``FolderScan``
- ``FolderContents``
- ``FolderScanner``
- ``FolderSnapshot``
- ``DNGFile``

### Factor and tag

- ``SqueezeFactor``
- ``Scale``
- ``ScaleTagging``
- ``ScaleTag``
- ``TagRow``
- ``TagError``
- ``BackupHandling``
- ``FileBackups``

### Converters and the match

- ``RawConverter``
- ``RawConverters``
- ``DnglabConverter``
- ``AdobeConverter``
- ``Conversion``
- ``ConvertError``
- ``ConverterOutput``
- ``ExclusiveRename``
- ``ARWFacts``
- ``ARWFactsReading``
- ``ARWFactsReader``
- ``AdobeMatch``
- ``ConverterChoice``
- ``ConverterKind``

### The job, the plan and the summary

- ``DesqueezeJob``
- ``FolderLock``
- ``TagDecision``
- ``RunPlan``
- ``RunSummary``
- ``FileNote``
- ``RunProgress``
- ``CancelFlag``
- ``InterruptWatcher``

### The originals, on request

- ``OriginalDecision``
- ``OriginalState``
- ``FileRecord``
- ``DNGCheck``
- ``OriginalCheckTags``

### Reports

- ``DesqueezeOperations``
- ``ScanReport``
- ``RunReport``
- ``ErrorReport``
- ``ReportJSON``

### Front-end text

- ``FolderText``
- ``ConverterText``
- ``DesqueezeVersion``

### Process and tools

- ``ProcessRunner``
- ``SystemProcessRunner``
- ``LoggingProcessRunner``
- ``ProcessResult``
- ``ProcessSignalError``
- ``ToolLocator``
