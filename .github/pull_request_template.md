## What changed

## Why

## Checks

- [ ] `swift test` ran, with 0 failures.
- [ ] `swift test --package-path MCPServer` ran, with 0 failures.
- [ ] `xcodegen generate`, then `xcodebuild -project PlateworksDesqueeze.xcodeproj -scheme PlateworksDesqueeze -derivedDataPath build test` ran, with 0 failures.
- [ ] I saw each new behavioral test fail before the code made it pass.
- [ ] No test reaches the real Trash, and no test ran on a real photo folder.
- [ ] The documents are updated: the design when behavior changed, the module map for a new file, `docs/decisions.md` for a decision, `CHANGELOG.md` for a change that a user sees.
- [ ] No rule in the "Invariants" list of `CLAUDE.md` is broken.

## Tests that skipped on my Mac

Say which tests skipped, and why: no `fixtures/`, no exiftool, no dnglab, no
Adobe DNG Converter, or a fixture frame that the match table does not cover.
