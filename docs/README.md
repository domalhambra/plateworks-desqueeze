# Documentation index

Every document in this folder, and when to read it. The docs check
(`scripts/docs_check.py`, run by `swift test`) reports eight kinds of
finding. Four of them can occur in a repo that has its files:

- A Markdown file here has no row below.
- `README.md`, `CLAUDE.md`, `AGENTS.md`, this file or a document at the top
  of this folder quotes a path that does not exist.
- `CLAUDE.md` reaches 2,000 tokens, at four characters for each token.
- `CLAUDE.md` stops naming a working document.

The other four occur only when a required file is missing or is a starter
file.

## Working documents

| Document | Read when |
|---|---|
| `architecture.md` | You are new here, or you want to know which file owns a behavior and which test covers it. The shape, the two packages, the module map, one run step by step with its safety rules, delivery, and the test suites. |
| `changing-things.md` | You are about to change something. One section for each task: the suites, the fixtures, a sentence, a preset factor, a note kind, a JSON field, an MCP tool, a camera, a converter rule, the MCP library pin, a version, a release, a program inside the download, a hand check of the window, a document, a decision. |
| `decisions.md` | Something looks like a past decision, and you want the reason before you change it. Dated, with a table of rejected and deferred items at the end. |
| `build-history.md` | You want to know how version 1 was built: the method, the order of the work, what changed on the way, and what the reviews found. It is history. |

## Specifications

| Document | Read when |
|---|---|
| `superpowers/specs/2026-10-05-desqueeze-design.md` | You change any behavior. It is the contract: the scan, the factor, the run, the window, the errors, the command line tool, the MCP server, the converters, the option that moves the originals to the Trash, and the download. Sections 12 to 15 are the newest, and they win where they differ from an earlier section. Section 2.1 records what was tested by hand. |

One file in that folder is not Markdown:

- `superpowers/specs/2026-10-09-ilce-7sm3-adobe-values.json` is the data file
  of the match table: the values that Adobe DNG Converter wrote for the Sony
  A7S III at 23 ISO settings. The table in
  `Sources/DesqueezeCore/AdobeMatch.swift` is a copy of it, and a unit test
  fails when the two differ.

New specs go in `superpowers/specs/`. Give each one a row here. When a spec
governs behavior, give it a row in `CLAUDE.md` too.

## Documents at the repo root

| Document | Read when |
|---|---|
| `README.md` | You want to know what the tool does, what it needs, what the download holds, and how to build and run it. |
| `CLAUDE.md` | You are about to change code. The rules that must not break, and the one document to read for each kind of change. |
| `AGENTS.md` | You are a coding agent. It points to `CLAUDE.md`. |
| `CONTRIBUTING.md` | You want to send a change, or add a camera to the match table. |
| `PROJECT_CHARTER.md` | You want the purpose, the status and the milestones. |
| `CHANGELOG.md` | You want to know what a version holds. |
| `SECURITY.md` | You found a problem that can harm a person's files, or you want to check a download. |
| `THIRD_PARTY_NOTICES.md` | You want the license of each program that the app starts, of the two programs inside the download, and of each library that the server links. |
| `LICENSE` | The MIT license of this repo. |

## The documentation site

The source of the site is not in this folder. It is a DocC catalog beside
the code, `Sources/DesqueezeCore/DesqueezeCore.docc`: one Markdown file for
each article, and the API reference from the documentation comments of the
core. `scripts/build_docs.sh` builds it, and `changing-things.md` has the
steps. The docs check does not read the catalog.
`Tests/DesqueezeCoreTests/DocsSiteTests.swift` does.

## Standards that this repo follows

Both are kept outside the repo. No file here depends on them at build time.

| Standard | Used for |
|---|---|
| The Plateworks documentation standard | Which documents a repo carries and what each one holds. This repo is at its Medium tier, with a charter and the files of an open-source repo. |
| Simplified Technical English (ASD-STE100) | The writing standard for these documents: short sentences, the active voice, one word for one thing, instructions in the imperative. |

`scripts/docs_check.py` is a copy of the check that the documentation
standard defines. Its header comment differs, and it has no skip rule for
paths outside the repo. Its checks are not edited here.
`Tests/DesqueezeCoreTests/DocsCheckTests.swift` runs it.
