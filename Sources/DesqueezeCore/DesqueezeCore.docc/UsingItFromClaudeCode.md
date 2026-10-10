# Using it from Claude Code

Give the tool to an MCP client, so a model can scan a folder and set the stretch for you.

## Overview

`desqueeze-mcp` is an MCP server. MCP, the Model Context Protocol, is how a
client such as Claude Code gives tools to a model. The client starts the
server and speaks to it on standard input and standard output. A person
does not type to the server.

The server has three tools. They do the work of the three commands of
`desqueeze`, and they return the same JSON.

One thing the server cannot do: it never moves an original ARW to the Trash.
The window and the command line tool can, on your request. No tool of the
server has an argument for that, so a model cannot remove your originals
through the server, by request or by mistake.

One limit: a model that can start programs on your Mac can start the command
line tool itself, with the flag. The server cannot prevent that. Its text
for the model does not say where the option is.

| Tool | Arguments | Changes files |
|---|---|---|
| `desqueeze_scan` | `folder` | No. It is marked read-only. |
| `desqueeze_run` | `folder`, `factor`, `convert` (the default is true), `dry_run` (the default is false) | Yes, unless `dry_run` is true |
| `desqueeze_remove` | `folder`, `dry_run` (the default is false) | Yes, unless `dry_run` is true |

## Build the server and register it

1. Build the server from the root of the repo. The first build fetches the
   MCP library for Swift, so it needs a network connection.

   ```bash
   swift build -c release --package-path MCPServer
   ```

2. Copy `MCPServer/.build/release/desqueeze-mcp` to a folder of your choice.

3. Give your MCP client the absolute path of the server. The help of the
   server gives the command for Claude Code:

   ```
   claude mcp add desqueeze -- /absolute/path/to/desqueeze-mcp
   ```

   This command changes the configuration of Claude Code. For another
   client, read how that client adds a server that it starts as a program.

The server needs exiftool, and dnglab for the conversion, as the other front
ends do. It looks for the programs at each tool call, so a program that you
install later is found with no new start of the server.

## What a model is told

When a session starts, the server gives the client these instructions for
the model:

```
Plateworks Desqueeze sets the DefaultScale tag of DNG photos, so Lightroom
shows anamorphic photos at the correct shape. Call desqueeze_scan first. Use
dry_run true before a run that changes files. desqueeze_remove reverses
desqueeze_run. The server runs one tool call at a time. This server never
moves an original ARW file to the Trash, and it has no argument for that.
Only the user can ask for it.
```

Each tool also has a description that the model reads. Together, the
descriptions say:

- What the tool changes, and what it never changes: an ARW, a pixel, a
  subfolder.
- That the server never moves an original ARW to the Trash, and that only
  you can ask for that. The text does not say where the option is.
- That the change is reversible: `desqueeze_remove` sets every DNG back to
  no stretch, and does not delete a DNG that a run converted.
- Which converter converts, and what to tell you when none is installed.
- The keys of the JSON result.
- That the factor has no default, and that the model must ask you for it.

The server also marks each tool for the client. `desqueeze_scan` is marked
as read-only. `desqueeze_run` and `desqueeze_remove` are marked as tools
that change files and destroy nothing. A second call with the same arguments
changes nothing more.

## The safe order

The descriptions give the model one safe path, and you can ask for it in
your own words:

1. **Scan.** `desqueeze_scan` reports what the folder holds. It changes no
   file.
2. **Dry run.** `desqueeze_run` with `dry_run` true lists what each file
   would get, in `steps`. It changes no file.
3. **Run.** `desqueeze_run` with `dry_run` false does the work.

Give the model the folder as an absolute path, and the squeeze factor of
your lens. For the first time, give it a copy of a folder.

## What the server accepts

- `folder` must be an absolute path that starts with `/`. The server has no
  working folder that a client knows, and `~` is only a character to it. A
  symbolic link to a folder counts as that folder.
- `factor` must be a number from 1 to 4, with at most four decimal places.

The server refuses a call that breaks a rule. The model gets one plain
sentence as a tool error, and no file changes:

```
The folder must be an absolute path, which starts with /. A relative path and ~ do not work. It was "relative/path".
```

```
desqueeze_run needs the argument "factor": the squeeze factor of the lens, a number from 1 to 4, with at most four decimal places. There is no default.
```

A call with an argument that the tool does not have is refused in the same
way. So a call that asks the server to move the originals changes nothing:

```
desqueeze_run has no argument "trash_originals". Its arguments are: folder, factor, convert, dry_run.
```

## What the server returns

A tool result is one JSON object: the scan report, or the run report.
<doc:TheJSONReports> describes every key. A result that holds a failed or a
blocked file is still a successful tool call. The failure is in the counts
and in the notes of the report.

In every result of the server, `trashOriginals` is false and
`originalsInTrash` is 0.

A tool error means that the server could give no report: the call broke a
rule, the folder could not be read, another run works in the folder, or
exiftool is not installed.

The line about Lightroom is not in the JSON. The description of
`desqueeze_run` and of `desqueeze_remove` gives the model the rule of the
other two front ends: when `set` is above 0 and `dry_run` was false, the
model tells you "Photos already in Lightroom: Metadata › Read Metadata from
File." After a dry run, and when `set` is 0, it does not.

## How the server runs

- It runs one tool call at a time. A second call waits for the first.
- One run works in a folder at a time, across all three front ends. While
  the window or the command line tool runs in a folder, `desqueeze_run` and
  `desqueeze_remove` on that folder are a tool error, and change no file:
  "Another Desqueeze run is working in this folder. Wait for it to end,
  then run again." `desqueeze_scan` and a call with `dry_run` true still
  work. Their result can then be of a folder in change.
- When the client asks for progress, the server sends one progress message
  for each step of a run.
- When the client stops the server with a signal, the run in work stops
  after its current file. The server writes that report, with `stopped` in
  it, and then ends. It does not end in the middle of a file.
- When the client closes standard input, the call in work completes and is
  answered. A call that waits does not start.

## Before you give the server to a client

The server changes files when the client calls `desqueeze_run` or
`desqueeze_remove`. Give it only to a client that you trust with your photo
folders. The rules of <doc:WhatHappensToYourFiles> hold for the server as
they hold for the window: an ARW is never changed, and each DNG keeps a
backup until the new tag reads back. The server never moves an ARW.
