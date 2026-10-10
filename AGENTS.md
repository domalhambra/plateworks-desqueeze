# Agents

This repo's guide for any coding agent is `CLAUDE.md`. Read it first. It
routes every change to the one document that governs it. The index of
everything under `docs/` is `docs/README.md`.

Tests, all three before any claim of done: `swift test` (the core, the
command line tool, and the docs check), `swift test --package-path MCPServer`
(the MCP server), then `xcodegen generate` and
`xcodebuild -project PlateworksDesqueeze.xcodeproj -scheme PlateworksDesqueeze -derivedDataPath build test`
(the state of the window). The tests on the real programs skip until
`fixtures/` exists.

Build: `swift build -c release` (the tool),
`swift build -c release --package-path MCPServer` (the server), and
`xcodegen generate`, then
`xcodebuild -project PlateworksDesqueeze.xcodeproj -scheme PlateworksDesqueeze -configuration Release -derivedDataPath build build`
(the app).

Four rules that an agent breaks most easily:

- Never run the tool, the server, a test or exiftool on a real photo folder.
  Use a copy in a temporary folder.
- Never call Adobe DNG Converter with `-h`. It opens a window, and the
  process never returns.
- Never pass `-f` to dnglab. It writes over an existing file.
- Never let a test reach the real Trash. Give `FileBackups` a function of
  your own, or set `DESQUEEZE_TEST_BACKUP_FOLDER` to a temporary folder for a
  built tool or a built server.
