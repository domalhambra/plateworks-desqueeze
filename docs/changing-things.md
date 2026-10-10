# Changing things

One section for each task. Each section names the file to edit, the test
that judges the change, and the design section to read first. "Design" is
`docs/superpowers/specs/2026-10-05-desqueeze-design.md`.

Every command runs from the repo root. Three rules hold for every task:

- Write the test first. A behavioral test counts only after it fails against
  a break.
- Never test on a real photo folder. Use a copy in a temporary folder.
- Before any claim of done, run the three suites (the first section).

## Run the three suites

1. Run the root package: `swift test`. It needs no Xcode project. The docs
   check runs inside it.
2. Run the server package: `swift test --package-path MCPServer`. The first
   run fetches the MCP library, so it needs a network connection.
3. Make the Xcode project: `xcodegen generate`.
4. Run the window's tests:

   ```bash
   xcodebuild -project PlateworksDesqueeze.xcodeproj -scheme PlateworksDesqueeze -derivedDataPath build test
   ```

A test that needs `fixtures/` or a program that is not installed skips. It
does not fail. `docs/architecture.md` lists what skips. The tests on the
real programs start Adobe DNG Converter, so its icon shows in the Dock
during a run.

## Make the fixtures

The tests on the real programs need one ARW and one DNG in `fixtures/`. The
folder is gitignored: the photo is yours and stays on your Mac.

1. Install Adobe DNG Converter in `/Applications`. The script uses it to
   make the DNG.
2. Run the script with one ARW file. The script copies the file and does not
   change it.

   ```bash
   scripts/make_fixtures.sh "/path/to/one file.ARW"
   ```

Any Sony ARW that dnglab and Adobe DNG Converter can read works. A test
takes each value that it expects from the frame itself. The drift check and
the tests of the real dnglab match need a frame that the match table
covers: a Sony A7S III, compressed raw, ISO 50 or 80 to 12800, adapted lens.
With another frame they skip, and the other tests still run. They are in
`Tests/DesqueezeCoreTests/DnglabIntegrationTests.swift`.

## Change a sentence that a front end says

Read design 8 and 13.5 first. A sentence is in sentence case, with no
exclamation mark and no emoji. An error is one plain sentence, with the
tool's own words on a detail line below it.

1. Find where the sentence is made. A sentence that more than one front end
   says is made once, in the core. Never write it a second time in a front
   end.

   | The sentence is about | File | Test |
   |---|---|---|
   | A folder: the counts, the run button, read-only, the advice about the converters | `Sources/DesqueezeCore/FolderText.swift` | `Tests/DesqueezeCoreTests/FolderTextTests.swift` |
   | One file of a run: most notes, the counts line, the Lightroom line | `Sources/DesqueezeCore/RunSummary.swift` | `Tests/DesqueezeCoreTests/RunSummaryTests.swift` |
   | A write that failed, a backup that was restored, a partial DNG | `Sources/DesqueezeCore/DesqueezeJob.swift` | `Tests/DesqueezeCoreTests/DesqueezeJobTests.swift` |
   | Who converts | `Sources/DesqueezeCore/ConverterChoice.swift` | `Tests/DesqueezeCoreTests/ConverterChoiceTests.swift` |
   | A failed conversion, a leftover file | `Sources/DesqueezeCore/RawConverter.swift` | `Tests/DesqueezeCoreTests/RawConverterTests.swift` |
   | A missing exiftool, the dnglab install | `Sources/DesqueezeCore/ToolLocator.swift` | `Tests/DesqueezeCoreTests/ToolLocatorTests.swift` |
   | A wrong factor | `Sources/DesqueezeCore/SqueezeFactor.swift` | `Tests/DesqueezeCoreTests/SqueezeFactorTests.swift` |
   | A path that is no folder | `Sources/DesqueezeCore/FolderChoice.swift` | `Tests/DesqueezeCoreTests/FolderChoiceTests.swift` |
   | The help and the usage errors of the tool | `Sources/DesqueezeCLI/Usage.swift`, `Sources/DesqueezeCLI/Arguments.swift` | `Tests/DesqueezeCLITests/CommandsTests.swift`, `Tests/DesqueezeCLITests/ArgumentsTests.swift` |
   | The layout of the tool's text | `Sources/DesqueezeCLI/TextOutput.swift` | `Tests/DesqueezeCLITests/TextOutputTests.swift` |
   | What a model reads about a tool | `MCPServer/Sources/desqueeze-mcp/Tools.swift` | `MCPServer/Tests/DesqueezeMCPTests/ServerEndToEndTests.swift` |
   | The window alone | `App/PlateworksDesqueeze/AppModel.swift` | `App/PlateworksDesqueezeTests/AppModelTests.swift` |
   | The window alone, in the view | `App/PlateworksDesqueeze/ContentView.swift` | None. Check it by hand. |

2. Change the test to the new words, and see it fail.
3. Change the sentence.
4. Run the three suites. The end-to-end tests of the tool and of the server
   also read some sentences.

When you write about the converters, say it the long way: dnglab converts
each photo that it can match, and Adobe DNG Converter converts the others.
"dnglab converts first" is not the rule.

## Add a preset factor

Read design 4.2 and 5 first.

1. Change the expected list in
   `Tests/DesqueezeCoreTests/SqueezeFactorTests.swift`, and see the test
   fail.
2. Add the number to `presets` in `Sources/DesqueezeCore/SqueezeFactor.swift`.
   The window draws one button for each preset.
3. Change the description of the `factor` argument in
   `MCPServer/Sources/desqueeze-mcp/Tools.swift`. It names the common
   factors by hand.
4. Check the window by hand: the row must fit in the fixed width.

## Add a note kind

Read design 12.1 and 13.6 first. A front end reads the `kind` of a note,
never the English sentence.

1. Add the kind to the list in design 12.1, and to the two tests that pin
   every kind: `testEachKindIsWrittenAsItsName` in
   `Tests/DesqueezeCoreTests/ReportsTests.swift`, and the first test of
   `Tests/DesqueezeCoreTests/RunSummaryTests.swift`. See them fail.
2. Add the case to `FileNote.Kind` in
   `Sources/DesqueezeCore/RunSummary.swift`. Add the function that makes the
   note in the same file, with its sentence.
3. Add the note where the run decides it:
   `Sources/DesqueezeCore/DesqueezeJob.swift`, or
   `Sources/DesqueezeCore/RunPlan.swift` for a file that is not written. The
   dry run must give the same note. `Tests/DesqueezeCoreTests/RunSummaryTests.swift`
   and `Tests/DesqueezeCoreTests/PlanTests.swift` judge it.
4. Decide if the kind needs attention. `needsAttention` in
   `Sources/DesqueezeCore/RunSummary.swift` is true only for a failed or a
   blocked file. The exit code in `Sources/DesqueezeCLI/Commands.swift` is 1
   for those, for a stopped run, and for a read-only folder.
   `Tests/DesqueezeCLITests/ExitCodeTests.swift` judges the exit code.
5. Tell the model about the kind in the description of `desqueeze_run`, in
   `MCPServer/Sources/desqueeze-mcp/Tools.swift`.

## Add a field to the JSON

Read design 12.1 and 13.6 first. The tool and the server print the same
report types, so one change reaches both.

1. Add the key to the test of the shape in
   `Tests/DesqueezeCoreTests/ReportsTests.swift`, and see it fail.
2. Add the property to `ScanReport` or `RunReport` in
   `Sources/DesqueezeCore/Reports.swift`. `ScanReport` writes its keys by
   hand in `encode(to:)`, so add the key there. `RunReport` lists its keys in
   `CodingKeys`, so add it there. Write a value that is not known as `null`,
   and do not leave its key out. Two keys are left out on purpose: `steps`
   of a real run, and `converter` of a step that is no conversion.
3. Add the key to the JSON shape in design 12.1.
4. Name the key in the tool description in
   `MCPServer/Sources/desqueeze-mcp/Tools.swift`. A model reads the keys
   there.
5. Run the three suites. `Tests/DesqueezeCLITests/EndToEndTests.swift` and
   `MCPServer/Tests/DesqueezeMCPTests/ServerEndToEndTests.swift` read the
   JSON that the built tool and the built server print.

Never rename or remove a key without a decision row: a script can depend on
it.

## Add an MCP tool

Read design 12.2 first.

1. Put the file work in the core. Add the operation to
   `Sources/DesqueezeCore/Operations.swift`, with its test in
   `Tests/DesqueezeCoreTests/OperationsTests.swift`. The server holds no rule
   about files.
2. Add the name to `toolNames` in
   `MCPServer/Tests/DesqueezeMCPTests/ServerTestCase.swift`, and write the
   test of its schema in
   `MCPServer/Tests/DesqueezeMCPTests/ServerEndToEndTests.swift`. See the
   test of the tool list fail. One test in
   `MCPServer/Tests/DesqueezeMCPTests/ToolErrorTests.swift` pins the count of
   tools: change it too.
3. Add a `ToolDefinition` in `MCPServer/Sources/desqueeze-mcp/Tools.swift`,
   and add it to `ToolCatalog.all`. The description says what the tool
   changes, that `desqueeze_remove` reverses a run, and to call
   `desqueeze_scan` first. Set the annotations: a tool that changes no file
   is marked read-only.
4. Add the case and its argument checks to
   `MCPServer/Sources/desqueeze-mcp/ToolCall.swift`.
   `MCPServer/Tests/DesqueezeMCPTests/ToolErrorTests.swift` judges each
   refusal.
5. Call the operation in
   `MCPServer/Sources/desqueeze-mcp/ToolEnvironment.swift`.
6. Add the tool to the help text in
   `MCPServer/Sources/desqueeze-mcp/Program.swift`, and to the table in
   design 12.2.

## Add a camera to the match table

Read design 13.2, 13.4 and 13.9 first. The steps are in `CONTRIBUTING.md`,
under "Add a camera to the match table". This task needs Adobe DNG Converter
and one frame from that camera at each ISO setting.

The files to change:

- A new data file beside
  `docs/superpowers/specs/2026-10-09-ilce-7sm3-adobe-values.json`, in the
  same shape.
- `Sources/DesqueezeCore/AdobeMatch.swift`: a new `Camera` value, added to
  `cameras`.
- `Tests/DesqueezeCoreTests/AdobeMatchTests.swift`:
  `testTheTableIsTheDataFile` pins one camera today. Extend it to the new
  data file first, and see it fail.
- The design, 13.4 and 13.9, and `README.md`: both say that the table has one
  camera.

The drift check judges the row against the real Adobe DNG Converter:
`swift test --filter AdobeDriftTests`.

## Change a converter rule

Read design 4.3 step 1, 13.3 and 13.4 first. Then read the rules in
`CLAUDE.md`. These rules protect the user's files.

| Rule | File | Test |
|---|---|---|
| A rule for every converter: the checks before the start, the leftovers of an earlier run, the work file, what counts as a partial output | `ConverterRules` in `Sources/DesqueezeCore/RawConverter.swift` | `Tests/DesqueezeCoreTests/RawConverterTests.swift` |
| The command line of Adobe DNG Converter | `AdobeConverter` in `Sources/DesqueezeCore/RawConverter.swift` | `Tests/DesqueezeCoreTests/RawConverterTests.swift` |
| The dnglab steps: its command, the tags, the read-back | `Sources/DesqueezeCore/DnglabConverter.swift` | `Tests/DesqueezeCoreTests/DnglabConverterTests.swift` |
| The rename that never replaces | `Sources/DesqueezeCore/ExclusiveRename.swift` | `Tests/DesqueezeCoreTests/ExclusiveRenameTests.swift` |
| Which converter gets an ARW | `Sources/DesqueezeCore/ConverterChoice.swift` | `Tests/DesqueezeCoreTests/ConverterChoiceTests.swift` |
| What the run does after a failed conversion | `Sources/DesqueezeCore/DesqueezeJob.swift` | `Tests/DesqueezeCoreTests/DesqueezeJobTests.swift` |

1. Change the design first. The design is the contract.
2. Write the test on fakes, and see it fail.
3. Change the code.
4. Run `swift test` with the fixtures and both converters installed, so the
   tests on the real programs and the drift check run.

Never pass `-f` to dnglab. Never pass `-h` to Adobe DNG Converter.

## Update the MCP library pin

Read design 12.2 first. The library is not yet at 1.0, and its API changes
between minor versions.

1. Change the version in `MCPServer/Package.swift`. Keep `.upToNextMinor`.
2. Resolve the packages: `swift package resolve --package-path MCPServer`.
   This writes `MCPServer/Package.resolved`. Commit that file.
3. Run `swift test --package-path MCPServer`. The end-to-end tests check the
   bytes on the wire, so they find a change in the protocol.
4. Read the header of
   `MCPServer/Sources/desqueeze-mcp/AnsweringTransport.swift`. It says what
   the library does not do at the pinned version, and what a later version
   can make simpler.
5. Update `THIRD_PARTY_NOTICES.md`: each version from
   `MCPServer/Package.resolved`, and each license from the package's own
   license file.

## Cut a version

The version is in three places: the core, `project.yml`, and the changelog.
Tests keep them equal.

1. Change the number in the three tests that pin it, and see them fail:
   `VersionTests` in `Tests/DesqueezeCoreTests/BackupTestFolderTests.swift`,
   `testVersionPrintsTheNameAndTheNumber` in
   `Tests/DesqueezeCLITests/CommandsTests.swift`, and `testVersionAndHelp`
   in `Tests/DesqueezeCLITests/EndToEndTests.swift`.
2. Change `current` in `Sources/DesqueezeCore/Version.swift`. The tool and
   the server print this number.
3. Change `MARKETING_VERSION` in `project.yml` to the same number, and
   increase `CURRENT_PROJECT_VERSION`. `VersionTests` fails when the two
   numbers differ.
4. Add the entry to `CHANGELOG.md`, as the newest one:
   `## [1.2.3] - 2027-01-31`. The changelog test in
   `Tests/DesqueezeCoreTests/DocsCheckTests.swift` fails when the newest
   entry is not the current version.
5. Run `xcodegen generate`, then the three suites.

## Check the window by hand

The view has no test. Build the app (`README.md`), then start it with launch
arguments. Each argument is read from the command line only, never from the
saved settings.

| Argument | Shows |
|---|---|
| `-openFolder <path>` | The folder, loaded at launch. Use a copy of a shoot folder. |
| `-simulateMissingTools YES` | The window on a Mac with no exiftool and no converter |
| `-simulateMissingDnglab YES` | The window with no dnglab |
| `-simulateMissingAdobe YES` | The window with no Adobe DNG Converter |
| The last two together | The window with exiftool and with neither converter |

The arguments are in `LaunchOptions`, at the end of
`App/PlateworksDesqueeze/AppModel.swift`. Design 9 has the full acceptance
pass. The window uses the real Trash, so the backups of a hand check go
there.

## Add or change a document

1. Put a new document under `docs/`, and add its row to `docs/README.md`.
   The docs check fails for a Markdown file with no row.
2. Quote a repo path in backticks, from the repo root. The docs check reads
   `README.md`, `CLAUDE.md`, `AGENTS.md` and each document at the top of
   `docs/`. It fails for a quoted path that does not exist. It does not read
   the other documents at the repo root, so check their paths yourself.
3. When a document governs a kind of change, add a row to the table in
   `CLAUDE.md`. That file must stay under 2,000 tokens, so trim it when you
   add to it.
4. When you add a source file, add its row to the module map in
   `docs/architecture.md`.
5. Run the check alone:

   ```bash
   python3 scripts/docs_check.py . --require docs/decisions.md --require docs/architecture.md --require docs/changing-things.md --known-absent fixtures/
   ```

`scripts/docs_check.py` is a copy of the check that the documentation
standard defines. Its header comment differs, and it has no skip rule for
paths outside the repo. Do not edit its checks here.

## Change the documentation site

The site is a DocC catalog, `Sources/DesqueezeCore/DesqueezeCore.docc`. It
has a first page, `DesqueezeCore.md`, and one Markdown file for each
article. The API reference comes from the documentation comments in
`Sources/DesqueezeCore/`. The package has no dependency for the site: the
build uses the `docc` of Xcode.

1. Change the article, or the documentation comment. For a new article, add
   its file to the catalog, and add its `<doc:Name>` line under "Topics" on
   the first page. For a new public type, add it to a group under "Topics"
   too.
2. Hold to the rules of the site. It is for a public reader: no path on one
   Mac, and no private repo. Every command in an article was run. A fact
   that a repo document also states must agree with it. Numbers that change,
   such as test counts and timings, stay out.
3. Run the site test: `swift test --filter DocsSiteTests`. It fails when the
   first page names an article that does not exist, when an article is not
   on the first page, when a `<doc:…>` link points to no article, and when
   an article quotes a test or a repo path that does not exist.
4. Build the site: `scripts/build_docs.sh`. It writes the site to the folder
   docs inside build, which git ignores. A warning of docc is an error
   there: an unresolved link or symbol stops the build. Fix it.
5. Look at the site. The script prints the command for a web server on this
   Mac, and the command for a preview that follows each change to an
   article.

When you change a sentence, an option, a note kind, a JSON key or the match
table, change the article that describes it in the same change.

`.github/workflows/docs.yml` publishes the site to GitHub Pages on a push to
the main branch. It has not run yet: the repo is not on GitHub. Its header
lists what to check on the first run.

## Record a decision

Add a row to `docs/decisions.md` under the date of the decision: what was
decided, why, and the design section or the file that carries it. Never
delete a row. When a decision is reversed, mark the old row superseded and
add the new one.
