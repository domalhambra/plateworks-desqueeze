# Using it from Claude Code

Give the tool to an MCP client, so a model can scan a folder and set the stretch for you.

## Overview

`desqueeze-mcp` is an MCP server. MCP, the Model Context Protocol, is how a
client such as Claude Code gives tools to a model. The client starts the
server and speaks to it on standard input and standard output. A person
does not type to the server.

The server has three tools. They do the work of the three commands of
`desqueeze`, and they return the same JSON.

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
desqueeze_run. The server runs one tool call at a time.
```

Each tool also has a description that the model reads. Together, the
descriptions say:

- What the tool changes, and what it never changes: an ARW, a pixel, a
  subfolder.
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

## What the server returns

A tool result is one JSON object: the scan report, or the run report.
<doc:TheJSONReports> describes every key. A result that holds a failed or a
blocked file is still a successful tool call. The failure is in the counts
and in the notes of the report.

A tool error means that the server could give no report: the call broke a
rule, the folder could not be read, or exiftool is not installed.

## How the server runs

- It runs one tool call at a time. A second call waits for the first.
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
backup until the new tag reads back.
