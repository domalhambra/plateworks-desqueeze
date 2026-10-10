import DesqueezeCore
import XCTest

/// The built server with the real exiftool and the real converter (design
/// 12.4). Each test speaks MCP to it over its pipes. A test that needs a
/// fixture or a tool skips when it is absent.
final class ServerEndToEndTests: ServerTestCase {
    /// Words that would tell a model where the option that moves the
    /// originals is: the window's box, and the flag of the command line
    /// tool (design 14.7). No text that the server gives a model has one.
    static let placesOfTheOption = ["the window", "command line", "trash-originals", "checkbox"]

    // MARK: The session

    func testInitializeGivesTheNameTheVersionAndTheToolsCapability() throws {
        let server = try launch()

        let result = try initialize(server)

        let info = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(info["name"] as? String, "desqueeze-mcp")
        XCTAssertEqual(info["version"] as? String, DesqueezeVersion.current)
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(capabilities["tools"], "the server says that it has tools")
        XCTAssertNil(capabilities["resources"])
        XCTAssertNil(capabilities["prompts"])
        XCTAssertEqual((result["instructions"] as? String)?.contains("desqueeze_scan"), true)
        // Design 14.1: the first thing that a model reads says it too.
        let instructions = try XCTUnwrap(result["instructions"] as? String)
        XCTAssertTrue(instructions.contains(
            "This server never moves an original ARW file to the Trash, and it has no argument for that. "
                + "Only the user can ask for it."))
        // Design 14.7: the text does not tell a model where the option is.
        XCTAssertTrue(instructions.hasSuffix("Only the user can ask for it."), instructions)
        for place in Self.placesOfTheOption {
            XCTAssertFalse(instructions.contains(place), "the instructions name a place of the option: \(place)")
        }
        XCTAssertTrue(try server.result(of: "ping").isEmpty, "a ping gets an empty result")
    }

    func testToolsListHasThreeToolsWithTheirSchemasAndAnnotations() throws {
        let server = try start()

        let tools = try XCTUnwrap(try server.result(of: "tools/list")["tools"] as? [[String: Any]])

        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, Self.toolNames)
        let required = ["desqueeze_scan": ["folder"], "desqueeze_run": ["folder", "factor"],
                        "desqueeze_remove": ["folder"]]
        let types = [
            "desqueeze_scan": ["folder": "string"],
            "desqueeze_run": ["folder": "string", "factor": "number", "convert": "boolean", "dry_run": "boolean"],
            "desqueeze_remove": ["folder": "string", "dry_run": "boolean"],
        ]
        for tool in tools {
            let name = try XCTUnwrap(tool["name"] as? String)
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any], name)
            XCTAssertEqual(schema["type"] as? String, "object", name)
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false, name)
            XCTAssertEqual(schema["required"] as? [String], required[name], name)
            let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]], name)
            XCTAssertEqual(properties.mapValues { $0["type"] as? String ?? "" }, types[name], name)
            for (argument, property) in properties {
                XCTAssertFalse((property["description"] as? String ?? "").isEmpty, "\(name) \(argument)")
            }

            // Design 12.2: what a description must tell the model.
            let description = try XCTUnwrap(tool["description"] as? String, name)
            XCTAssertTrue(description.contains("top level"), "\(name): the top level of the folder only")
            if name == "desqueeze_scan" {
                XCTAssertTrue(description.contains("Changes no file"), name)
                XCTAssertTrue(description.contains("Call this first"), name)
            } else {
                XCTAssertTrue(description.contains("call desqueeze_scan first"), "\(name): scan first")
                XCTAssertTrue(description.contains("reversible"), name)
                XCTAssertTrue(description.contains("ARW files are never changed"), name)
                XCTAssertTrue(description.contains("dry_run"), name)
                // Design 12.2 and 14.1: the server never moves an original.
                XCTAssertTrue(description.contains(
                    "This server never moves an original ARW file to the Trash, and it has no argument for that. "
                        + "Only the user can ask for it."), name)
            }
            // Design 14.7: no text of the server tells a model where the
            // option is.
            for place in Self.placesOfTheOption {
                XCTAssertFalse(description.contains(place), "\(name) names a place of the option: \(place)")
            }
        }
        let run = try XCTUnwrap(tools[1]["inputSchema"] as? [String: Any])["properties"] as? [String: [String: Any]]
        XCTAssertEqual(run?["convert"]?["default"] as? Bool, true)
        XCTAssertEqual(run?["dry_run"]?["default"] as? Bool, false)
        XCTAssertEqual(run?["factor"]?["minimum"] as? Int, 1)
        XCTAssertEqual(run?["factor"]?["maximum"] as? Int, 4)
        XCTAssertEqual((run?["factor"]?["description"] as? String)?.contains(SqueezeFactor.ruleText), true)
        XCTAssertTrue(try XCTUnwrap(tools[1]["description"] as? String).contains("desqueeze_remove"),
                      "run names the tool that reverses it")

        // Design 13.5: "dnglab converts first" is short for the table, and
        // is not the rule. Each description says it the long way, with the
        // core's sentence, and says what is true now.
        let scanText = try XCTUnwrap(tools[0]["description"] as? String)
        for phrase in [
            "\"exiftool\", \"dnglab\" and \"dngConverter\": where the three programs are.",
            "\"dngConverter\" is the path of Adobe DNG Converter.",
            "ARW files are converted when \"dnglab\" or \"dngConverter\" has a path.",
            "dnglab converts each photo that it can match. "
                + "Adobe DNG Converter, when it is installed, converts the others.",
            "When both are null, ARW files stay as they are, and desqueeze_run still sets the stretch of "
                + "the DNG files.",
            "To make the ARW files convert, tell the user: Install dnglab with: brew install dnglab",
        ] {
            XCTAssertTrue(scanText.contains(phrase), "scan: \(phrase)")
        }
        XCTAssertTrue(scanText.contains(ConverterText.whoConverts), "scan: the core's sentence")
        let runText = try XCTUnwrap(tools[1]["description"] as? String)
        for phrase in [
            "dnglab converts each photo that it can match. "
                + "Adobe DNG Converter, when it is installed, converts the others.",
            "Each DNG that dnglab makes gets the values that Adobe DNG Converter writes, "
                + "so Lightroom shows the same photo.",
            "When neither is installed, ARW files stay as they are. To make them convert, tell the user: "
                + "Install dnglab with: brew install dnglab",
            "tell the user this line: Photos already in Lightroom: Metadata › Read Metadata from File.",
            "\"convertedByDnglab\" and \"convertedByAdobe\"",
            "Their sum is \"converted\".",
            "A note of the kind \"convertedUnmatched\" is no failure:",
            "the note says what the DNG lacks",
        ] {
            XCTAssertTrue(runText.contains(phrase), "run: \(phrase)")
        }
        for sentence in [ConverterText.whoConverts, ConverterText.matchedValues, ToolLocator.dnglabInstallLine,
                         RunSummary.lightroomHint] {
            XCTAssertTrue(runText.contains(sentence), "run: the core's sentence \(sentence)")
        }
        // Design 4.4: the Lightroom line is for a run that set at least one
        // photo, and never for a dry run. The server prints JSON only, so
        // the description gives the model that rule, for run and for remove.
        let lightroomRule = "When \"set\" is above 0 and dry_run was false, tell the user this line: "
            + "Photos already in Lightroom: Metadata › Read Metadata from File. "
            + "Do not say it after a dry run, or when \"set\" is 0."
        let removeText = try XCTUnwrap(tools[2]["description"] as? String)
        // Design 13.9: a run and a remove on a volume that gives no folder
        // lock go on, and the result has a note. The model must not take
        // it for a failure.
        let noLock = "A note of the kind \"noFolderLock\" is no failure: the volume gives no lock for a folder, "
            + "so nothing kept a second run out of the folder while this run worked."
        for (name, text) in [("run", runText), ("remove", removeText)] {
            XCTAssertTrue(text.contains(noLock), "\(name): \(text)")
            XCTAssertTrue(text.contains(lightroomRule), "\(name): \(text)")
            XCTAssertFalse(text.contains("When photos are in Lightroom already"), "\(name): the rule before 4.4")
        }
        for (name, text) in [("scan", scanText), ("run", runText)] {
            XCTAssertFalse(text.contains("converts first"), "\(name): the short form is not the rule")
            XCTAssertFalse(text.contains("converts the ARW files"), name)
        }
        XCTAssertTrue(runText.contains("\"trashOriginals\" is always false and \"originalsInTrash\" is always 0 "
            + "in a result of this server."), runText)
        // No tool has an argument that could ask for the originals.
        for tool in tools {
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            XCTAssertEqual(properties.keys.filter { $0.lowercased().contains("trash")
                || $0.lowercased().contains("original") }, [], "\(tool["name"] ?? "")")
        }
        XCTAssertEqual((run?["dry_run"]?["description"] as? String)?.contains(
            "A \"convert\" step names its converter in \"converter\": \"dnglab\" or \"adobe\"."), true)
        // What was true with one converter, and is false now.
        for tool in tools {
            let text = try XCTUnwrap(tool["description"] as? String)
            for phrase in ["the two programs", "with Adobe DNG Converter.",
                           "Adobe DNG Converter is not installed, and ARW files stay as they are"] {
                XCTAssertFalse(text.contains(phrase), "\(tool["name"] ?? ""): \(phrase)")
            }
        }

        // Scan is read-only. Run and remove change files, destroy nothing,
        // and a second call with the same arguments changes nothing more.
        let scan = try XCTUnwrap(tools[0]["annotations"] as? [String: Any])
        XCTAssertEqual(scan["readOnlyHint"] as? Bool, true)
        for tool in tools.dropFirst() {
            let annotations = try XCTUnwrap(tool["annotations"] as? [String: Any])
            XCTAssertEqual(annotations["readOnlyHint"] as? Bool, false)
            XCTAssertEqual(annotations["destructiveHint"] as? Bool, false)
            XCTAssertEqual(annotations["idempotentHint"] as? Bool, true)
        }
    }

    func testAnUnknownToolIsAnErrorOfTheProtocolAndTheServerGoesOn() throws {
        let server = try start()

        let id = try server.send("tools/call", toolCall("desqueeze_delete", ["folder": folder.path]))
        let answer = try server.answer(to: id).answer

        let error = try XCTUnwrap(answer["error"] as? [String: Any], "\(answer)")
        XCTAssertEqual(error["code"] as? Int, -32602)
        XCTAssertEqual((error["message"] as? String)?.contains("desqueeze_delete"), true)
        XCTAssertTrue(try server.result(of: "ping").isEmpty)
    }

    // The library reads `params` as any JSON value and hands it to the
    // server, so the server says what is wrong in its own words.
    func testMalformedParametersOfAToolCallGetAPlainSentence() throws {
        let server = try start()
        let wrong = [
            "",
            #","params":null"#,
            #","params":{}"#,
            #","params":"desqueeze_scan""#,
            #","params":["desqueeze_scan"]"#,
            #","params":{"arguments":{"folder":"/tmp"}}"#,
            #","params":{"name":5,"arguments":{"folder":"/tmp"}}"#,
            #","params":{"name":"desqueeze_scan","arguments":"/tmp"}"#,
            #","params":{"name":"desqueeze_scan","arguments":["/tmp"]}"#,
        ]
        for (number, params) in wrong.enumerated() {
            let id = 100 + number
            try server.write(#"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call"\#(params)}"# + "\n")
            let answer = try server.answer(to: id).answer

            let error = try XCTUnwrap(answer["error"] as? [String: Any], "\(params): \(answer)")
            XCTAssertEqual(error["code"] as? Int, -32602, "invalid params: \(params)")
            XCTAssertEqual(error["message"] as? String,
                           "Invalid params: tools/call needs a tool name and an arguments object.", params)
        }
        XCTAssertTrue(try server.result(of: "ping").isEmpty, "the server goes on")
    }

    // MARK: desqueeze_scan

    // The comparison is with `DesqueezeOperations` and `ReportJSON.text` in
    // the test process. Those two are all that `desqueeze scan --json`
    // prints, so the server and the command line tool give the same bytes.
    func testScanGivesTheJSONOfTheCommandLineTool() throws {
        try requireFixturesAndTools()
        try makeShoot()
        let before = try state(of: folder)
        let server = try start()

        let result = try call(server, "desqueeze_scan", ["folder": folder.path])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(result.progress.count, 0, "a scan has no progress")
        XCTAssertEqual(result.text, try ReportJSON.text(try operations().scan(folder)))
        let json = try result.json()
        XCTAssertEqual(Set(json.keys),
                       ["folder", "writable", "exiftool", "dnglab", "dngConverter", "dngs", "pendingARWs",
                        "orphanBackups"])
        XCTAssertEqual(json["folder"] as? String, folder.path)
        XCTAssertEqual(json["writable"] as? Bool, true)
        XCTAssertEqual(json["exiftool"] as? String, ToolLocator().exiftool()?.path)
        XCTAssertEqual(json["dnglab"] as? String, ToolLocator().dnglab()?.path, "the path, or null")
        XCTAssertEqual(json["dngConverter"] as? String, ToolLocator().dngConverter()?.path)
        XCTAssertEqual(json["dngs"] as? [NSDictionary], [[
            "name": "already here.dng", "scale": "1 1", "originalRawFileName": "sample.ARW", "hasBackup": false,
        ]])
        XCTAssertEqual(json["pendingARWs"] as? [String], ["frame.ARW"])
        XCTAssertEqual(json["orphanBackups"] as? [String], [])
        XCTAssertEqual(try state(of: folder), before)
    }

    func testALinkToAFolderIsThatFolder() throws {
        try requireFixturesAndTools()
        try makeShoot()
        let link = base.appendingPathComponent("Link to shoot")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let server = try start()

        let result = try call(server, "desqueeze_scan", ["folder": link.path])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try result.json()["folder"] as? String, folder.path, "the folder, not the link")
    }

    // MARK: desqueeze_run and desqueeze_remove

    func testADryRunChangesNoFile() throws {
        try requireFixturesAndTools()
        try makeShoot()
        let before = try state(of: folder)
        let server = try start()

        let run = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.5, "dry_run": true],
                           progressToken: "dry")
        let remove = try call(server, "desqueeze_remove", ["folder": folder.path, "dry_run": true])

        XCTAssertFalse(run.isError, run.text)
        let json = try run.json()
        XCTAssertEqual(json["dryRun"] as? Bool, true)
        XCTAssertEqual(json["factor"] as? String, "1.5")
        XCTAssertEqual(counts(json), [1, 2, 0, 0, 0, 0], "the counts of the run it plans")
        XCTAssertEqual(json["steps"] as? [NSDictionary], [
            // dnglab gets a frame with a full match, when it is installed.
            ["name": "frame.ARW", "action": "convert", "converter": dnglabConvertsTheFixture() ? "dnglab" : "adobe"],
            ["name": "already here.dng", "action": "write"],
            ["name": "frame.dng", "action": "write"],
        ])
        XCTAssertEqual(run.progress.count, 0, "a dry run has no steps in work")
        XCTAssertFalse(remove.isError, remove.text)
        XCTAssertEqual(try remove.json()["dryRun"] as? Bool, true)
        XCTAssertEqual(counts(try remove.json()), [0, 0, 1, 0, 0, 0], "the DNG has no stretch already")

        XCTAssertEqual(try state(of: folder), before, "no size, no date and no byte changed")
        XCTAssertEqual(try names(in: folder), ["already here.dng", "frame.ARW"], "no _original file, and no new DNG")
        XCTAssertEqual(try names(in: discard), [])
    }

    func testRunThenScanThenRunAgainThenRemoveThenScan() throws {
        try requireFixturesAndTools()
        try makeShoot()
        let arwBefore = try Data(contentsOf: folder.appendingPathComponent("frame.ARW"))
        let server = try start()

        // No progress token, so no progress message: `call` reads the answer
        // and fails when another message comes first.
        let run = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.5])
        XCTAssertFalse(run.isError, run.text)
        XCTAssertEqual(run.progress.count, 0)
        let json = try run.json()
        XCTAssertEqual(Set(json.keys), ["folder", "factor", "dryRun", "converted", "convertedByDnglab",
                                        "convertedByAdobe", "set", "skipped", "blocked", "failed", "stopped",
                                        "unconvertedARWs", "trashOriginals", "originalsInTrash", "notes"])
        // The server never moves an original (design 14.1).
        XCTAssertEqual(json["trashOriginals"] as? Bool, false)
        XCTAssertEqual(json["originalsInTrash"] as? Int, 0)
        XCTAssertEqual([json["convertedByDnglab"], json["convertedByAdobe"]] as? [Int],
                       dnglabConvertsTheFixture() ? [1, 0] : [0, 1])
        XCTAssertEqual(json["folder"] as? String, folder.path)
        XCTAssertEqual(json["factor"] as? String, "1.5")
        XCTAssertEqual(json["dryRun"] as? Bool, false)
        XCTAssertEqual(json["stopped"] as? Bool, false)
        XCTAssertEqual(counts(json), [1, 2, 0, 0, 0, 0])
        XCTAssertEqual(json["notes"] as? [NSDictionary], [])

        func scanned() throws -> [String: String] {
            let scan = try call(server, "desqueeze_scan", ["folder": folder.path])
            var scales: [String: String] = [:]
            for dng in try XCTUnwrap(try scan.json()["dngs"] as? [[String: Any]]) {
                scales[try XCTUnwrap(dng["name"] as? String)] = dng["scale"] as? String ?? "unknown"
            }
            return scales
        }
        XCTAssertEqual(try scanned(), ["already here.dng": "1.5 1", "frame.dng": "1.5 1"])
        XCTAssertEqual(try names(in: folder), ["already here.dng", "frame.ARW", "frame.dng"], "no backup is left")
        XCTAssertEqual(try names(in: discard), ["already here.dng_original", "frame.dng_original"],
                       "the backups went to the test folder, not to the Trash")

        let again = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.5])
        XCTAssertEqual(counts(try again.json()), [0, 0, 2, 0, 0, 0], "all skipped")

        let remove = try call(server, "desqueeze_remove", ["folder": folder.path])
        XCTAssertFalse(remove.isError, remove.text)
        XCTAssertEqual(try remove.json()["factor"] as? String, "1")
        XCTAssertEqual(counts(try remove.json()), [0, 2, 0, 0, 0, 0])
        XCTAssertEqual(try scanned(), ["already here.dng": "1 1", "frame.dng": "1 1"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("frame.ARW")), arwBefore,
                       "the ARW is never changed")
    }

    // The server has no argument for the originals (design 14.1). A call
    // that carries one is refused by the rule for an argument that the tool
    // does not have: it is a tool error, no step runs, and no ARW moves.
    // The folder holds a real photo that would convert, so a server that
    // took the argument would move it.
    func testACallThatAsksToMoveTheOriginalsIsRefusedAndMovesNoARW() throws {
        try requireFixturesAndTools()
        try makeShoot()
        let before = try state(of: folder)
        let server = try start()

        for name in ["trash_originals", "trashOriginals", "trash-originals"] {
            let run = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.5, name: true],
                               progressToken: name)
            XCTAssertTrue(run.isError, "\(name): \(run.text)")
            XCTAssertEqual(run.text, "desqueeze_run has no argument \"\(name)\". "
                + "Its arguments are: folder, factor, convert, dry_run.")
            XCTAssertEqual(run.progress.count, 0, "no step was done")
            XCTAssertEqual(try names(in: folder), ["already here.dng", "frame.ARW"], "the ARW is where it was")
            XCTAssertEqual(try state(of: folder), before, "no file changed")
            XCTAssertEqual(try names(in: discard), [], "nothing was moved")
        }
        // A dry run and a remove with the argument are refused too.
        let dry = try call(server, "desqueeze_run",
                           ["folder": folder.path, "factor": 1.5, "dry_run": true, "trash_originals": true])
        XCTAssertTrue(dry.isError, dry.text)
        let remove = try call(server, "desqueeze_remove", ["folder": folder.path, "trash_originals": true])
        XCTAssertTrue(remove.isError, remove.text)
        XCTAssertEqual(try state(of: folder), before)

        // The same call with no such argument runs, and the ARW stays.
        let run = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.5, "dry_run": true])
        XCTAssertFalse(run.isError, run.text)
        XCTAssertEqual(try run.json()["trashOriginals"] as? Bool, false)
        XCTAssertEqual((try run.json()["steps"] as? [NSDictionary])?.map { $0["action"] as? String },
                       ["convert", "write", "write"])
    }

    // `convert` false leaves the ARW, and the report counts it.
    func testConvertFalseLeavesTheARW() throws {
        try requireFixturesAndTools()
        try makeShoot()
        let server = try start()

        let run = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 2, "convert": false])

        XCTAssertFalse(run.isError, run.text)
        XCTAssertEqual(try run.json()["factor"] as? String, "2")
        XCTAssertEqual(counts(try run.json()), [0, 1, 0, 0, 0, 1])
        XCTAssertEqual(try names(in: folder), ["already here.dng", "frame.ARW"])
        XCTAssertEqual(try scales(), ["already here.dng": "2 1"])
    }

    // A JSON number has no decimal places of its own: 1.33 arrives as the
    // nearest binary number. The factor must still be 1.33, as typed.
    func testAFactorWithDecimalPlacesHasNoNoise() throws {
        try requireFixturesAndTools()
        try copyFixture("sample.dng", as: "a.dng")
        let server = try start()

        for (factor, label) in [(1.33, "1.33"), (1.8, "1.8"), (1.3333, "1.3333"), (2.0, "2"), (4.0, "4")] {
            let plan = try call(server, "desqueeze_run", ["folder": folder.path, "factor": factor, "dry_run": true])
            XCTAssertFalse(plan.isError, plan.text)
            XCTAssertEqual(try plan.json()["factor"] as? String, label)
        }
        // The same numbers, written as a client can write them.
        for (text, label) in [("1.50", "1.5"), ("2", "2"), ("1.0", "1"), ("1.33e0", "1.33")] {
            let request = server.request("tools/call", ["name": "desqueeze_run", "arguments": [String: Any]()])
            let line = try ServerProcess.line(request.message).replacingOccurrences(
                of: #""arguments":{}"#, with: #""arguments":{"folder":"\#(folder.path)","factor":\#(text),"dry_run":true}"#)
            try server.write(line + "\n")
            let plan = try toolResult(server, id: request.id)
            XCTAssertFalse(plan.isError, plan.text)
            XCTAssertEqual(try plan.json()["factor"] as? String, label, text)
        }

        let run = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.33])
        XCTAssertEqual(try run.json()["factor"] as? String, "1.33")
        XCTAssertEqual(try scales(), ["a.dng": "1.33 1"])
    }

    // A file that fails is in the JSON. The call itself did not fail.
    func testAFileThatFailsIsStillASuccessfulCall() throws {
        try requireFixturesAndTools()
        try copyFixture("sample.dng", as: "good.dng")
        try Data("not a photo".utf8).write(to: folder.appendingPathComponent("junk.dng"))
        try copyFixture("sample.dng", as: "held.dng")
        try Data("an older backup".utf8).write(to: folder.appendingPathComponent("held.dng_original"))
        let server = try start()

        let run = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.5])

        XCTAssertFalse(run.isError, "isError is false: the JSON carries the failures")
        let json = try run.json()
        XCTAssertEqual(counts(json), [0, 1, 0, 1, 1, 0])
        let kinds = try XCTUnwrap(json["notes"] as? [[String: Any]]).compactMap { $0["kind"] as? String }
        XCTAssertEqual(Set(kinds), ["failed", "blockedByBackup"])
    }

    // MARK: Progress

    func testARunWithAProgressTokenSendsOneMessageForEachStep() throws {
        try requireFixturesAndTools()
        try makeShoot()
        let server = try start()

        let run = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.5], progressToken: "run-1")

        XCTAssertEqual(counts(try run.json()), [1, 2, 0, 0, 0, 0])
        // `call` has checked that each one came before the result.
        XCTAssertEqual(run.progress as [NSDictionary], [
            ["progressToken": "run-1", "progress": 1, "total": 3, "message": "frame.ARW"],
            ["progressToken": "run-1", "progress": 2, "total": 3, "message": "already here.dng"],
            ["progressToken": "run-1", "progress": 3, "total": 3, "message": "frame.dng"],
        ])

        // The token can be a number. Remove has steps too.
        let id = try server.send("tools/call", [
            "name": "desqueeze_remove", "arguments": ["folder": folder.path], "_meta": ["progressToken": 7],
        ])
        let remove = try toolResult(server, id: id)
        XCTAssertEqual(remove.progress as [NSDictionary], [
            ["progressToken": 7, "progress": 1, "total": 2, "message": "already here.dng"],
            ["progressToken": 7, "progress": 2, "total": 2, "message": "frame.dng"],
        ])
    }

    // MARK: One call at a time

    // The brief's case: two runs on one folder, sent in one write. Side by
    // side, both would scan before either wrote, and the second writer would
    // meet the backup of the first: a false "blocked" or "failed".
    func testTwoRunsSentAtOnceGiveTwoValidReports() throws {
        try requireFixturesAndTools()
        try makeDNGs(4)
        let server = try start()

        let first = server.request("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5]))
        let second = server.request("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5]))
        try server.write(try ServerProcess.line(first.message) + "\n" + ServerProcess.line(second.message) + "\n")

        // The answers can come in either order: the library writes each one
        // from a task of its own. The reports say which call ran first.
        var reports: [Int: [String: Any]] = [:]
        while reports.count < 2 {
            let message = try server.nextMessage(timeout: ServerProcess.longWait)
            let id = try XCTUnwrap(message["id"] as? Int, "\(message)")
            reports[id] = try toolResult(message, earlier: []).json()
        }
        XCTAssertEqual(Set(reports.keys), [first.id, second.id])
        let inOrder = reports.values.sorted { ($0["set"] as? Int ?? 0) > ($1["set"] as? Int ?? 0) }
        XCTAssertEqual(counts(inOrder[0]), [0, 4, 0, 0, 0, 0], "the call that ran first set all four")
        XCTAssertEqual(counts(inOrder[1]), [0, 0, 4, 0, 0, 0], "the call that waited found all four set")
        for report in inOrder { XCTAssertEqual(report["notes"] as? [NSDictionary], [], "no false note") }
        XCTAssertEqual(try names(in: folder), ["1.dng", "2.dng", "3.dng", "4.dng"], "no backup is left")
    }

    // A call that arrives while a run is in work waits for it. The scan is
    // sent after the first progress message, so the run is in work then, with
    // five files to go. A scan takes less time than one of them: beside the
    // run, it would answer first and show files with no stretch.
    func testACallThatArrivesDuringARunWaitsForIt() throws {
        try requireFixturesAndTools()
        try makeDNGs(6)
        let server = try start()

        let run = try server.send("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5],
                                                         progressToken: "wait"))
        let firstStep = try server.nextMessage(timeout: ServerProcess.longWait)
        XCTAssertEqual(firstStep["method"] as? String, "notifications/progress", "\(firstStep)")
        let scan = try server.send("tools/call", toolCall("desqueeze_scan", ["folder": folder.path]))
        let ping = try server.send("ping")

        // The ping is not a tool call. It does not wait.
        var order: [Int] = []
        var results: [Int: [String: Any]] = [:]
        while order.count < 3 {
            let message = try server.nextMessage(timeout: ServerProcess.longWait)
            guard message["method"] == nil, let id = message["id"] as? Int else { continue }
            order.append(id)
            results[id] = message
        }
        XCTAssertEqual(order.first, ping, "the ping is answered at once, during the run")
        XCTAssertEqual(Set(order), [ping, run, scan])
        let report = try toolResult(try XCTUnwrap(results[run]), earlier: []).json()
        XCTAssertEqual(counts(report), [0, 6, 0, 0, 0, 0])
        let scanned = try toolResult(try XCTUnwrap(results[scan]), earlier: []).json()
        let scales = try XCTUnwrap(scanned["dngs"] as? [[String: Any]]).map { $0["scale"] as? String }
        XCTAssertEqual(scales, Array(repeating: "1.5 1", count: 6), "the scan saw the folder after the whole run")
    }

    // MARK: Cancel

    // The library turns `notifications/cancelled` into a cancelled task. The
    // server sets the run's flag: the run stops after the file in work, and
    // its report says `stopped`.
    func testACancelStopsTheRunAfterTheFileInWork() throws {
        try requireFixturesAndTools()
        try makeDNGs(6)
        let server = try start()

        let run = try server.send("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5],
                                                         progressToken: "stop"))
        _ = try server.nextMessage(timeout: ServerProcess.longWait)
        try server.notify("notifications/cancelled", ["requestId": run, "reason": "The test stops the run."])

        let result = try toolResult(server, id: run)
        XCTAssertFalse(result.isError, result.text)
        let json = try result.json()
        XCTAssertEqual(json["stopped"] as? Bool, true)
        let set = try XCTUnwrap(json["set"] as? Int)
        XCTAssertTrue((1..<6).contains(set), "\(set) files were set before the stop")
        let scales = try scales()
        XCTAssertEqual(scales.values.filter { $0 == "1.5 1" }.count, set, "each file is whole: set, or not started")
        XCTAssertEqual(scales.values.filter { $0 == "1 1" }.count, 6 - set)
        XCTAssertEqual(try names(in: folder).filter { $0.hasSuffix("_original") }, [], "no backup is left")
        XCTAssertTrue(try server.result(of: "ping").isEmpty, "the server goes on")
    }

    // A call that is cancelled while it waits does no work and gets no
    // answer, as the protocol says for a cancelled request.
    func testACallCancelledWhileItWaitsDoesNoWork() throws {
        try requireFixturesAndTools()
        try makeDNGs(4)
        let server = try start()

        let run = try server.send("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5],
                                                         progressToken: "first"))
        _ = try server.nextMessage(timeout: ServerProcess.longWait)
        let remove = try server.send("tools/call", toolCall("desqueeze_remove", ["folder": folder.path]))
        // The library takes each request in a task of its own, and a cancel
        // that comes before that task has started is lost. The answer to a
        // ping that was sent after the call shows that the call has started.
        let ping = try server.send("ping")
        var steps = 0
        while try server.nextMessage(timeout: ServerProcess.longWait)["id"] as? Int != ping { steps += 1 }
        try server.notify("notifications/cancelled", ["requestId": remove])

        let report = try toolResult(server, id: run)
        XCTAssertEqual(counts(try report.json()), [0, 4, 0, 0, 0, 0])
        XCTAssertEqual(steps + report.progress.count, 3, "the three steps after the first")
        // A scan waits behind every call before it. Its answer is the next
        // one, so the remove gave none, and it changed no file.
        let scan = try server.send("tools/call", toolCall("desqueeze_scan", ["folder": folder.path]))
        let (answer, earlier) = try server.answer(to: scan, timeout: ServerProcess.longWait)
        XCTAssertEqual(earlier.count, 0, "no answer to the cancelled call: \(earlier)")
        let scales = try XCTUnwrap(try toolResult(answer, earlier: []).json()["dngs"] as? [[String: Any]])
        XCTAssertEqual(scales.map { $0["scale"] as? String }, Array(repeating: "1.5 1", count: 4))
    }

    // MARK: Standard input closes

    func testClosingStandardInputEndsTheServerWithZero() throws {
        let server = try start()
        XCTAssertNil(server.waitForExit(timeout: 0.5), "the server waits for its client")

        server.closeInput()

        XCTAssertEqual(server.waitForExit(), 0)
    }

    // The client goes away during a run. The run completes, its answer is
    // written, and then the server ends with 0.
    func testClosingStandardInputDuringARunLetsTheRunComplete() throws {
        try requireFixturesAndTools()
        try makeDNGs(4)
        let server = try start()

        let run = try server.send("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5],
                                                         progressToken: "close"))
        _ = try server.nextMessage(timeout: ServerProcess.longWait)
        server.closeInput()

        let result = try toolResult(server, id: run)
        XCTAssertEqual(result.progress.count, 3, "the three steps after the first")
        XCTAssertEqual(counts(try result.json()), [0, 4, 0, 0, 0, 0])
        XCTAssertEqual(try result.json()["stopped"] as? Bool, false)
        XCTAssertEqual(server.waitForExit(), 0)
        XCTAssertEqual(try scales().values.sorted(), Array(repeating: "1.5 1", count: 4))
        XCTAssertEqual(try names(in: folder), ["1.dng", "2.dng", "3.dng", "4.dng"], "no backup is left")
    }

    // Standard input closes right behind the requests, as it does for
    // `desqueeze-mcp < requests.txt`. A request that needs no queue is
    // answered. Of the tool calls, at most the one in work runs: the client
    // has gone, and a call that changes files must not start for nobody.
    func testAtTheEndOfInputAtMostTheToolCallInWorkRuns() throws {
        try requireFixturesAndTools()
        try makeDNGs(2)
        let server = try launch()
        let hello = server.request("initialize", [
            "protocolVersion": "2025-06-18", "capabilities": [String: Any](),
            "clientInfo": ["name": "desqueeze-mcp-tests", "version": "1"],
        ])
        let list = server.request("tools/list")
        let ping = server.request("ping")
        let first = server.request("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 2]))
        let second = server.request("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5]))

        try server.write(try [hello, list, ping, first, second].map { try ServerProcess.line($0.message) + "\n" }
            .joined())
        server.closeInput()

        XCTAssertEqual(server.waitForExit(timeout: ServerProcess.longWait), 0)
        XCTAssertTrue(server.waitForEndOfOutput())
        XCTAssertEqual(server.unfinishedOutput, "")
        var answered: Set<Int> = []
        for _ in server.outputLines { answered.insert(try XCTUnwrap(try server.nextMessage()["id"] as? Int)) }
        XCTAssertTrue(answered.isSuperset(of: [hello.id, list.id, ping.id]), "\(answered)")
        let calls = answered.subtracting([hello.id, list.id, ping.id])
        XCTAssertLessThanOrEqual(calls.count, 1, "at most the call in work ran: \(calls)")
        // The folder shows which call ran, and that no other did.
        let expected = calls == [first.id] ? "2 1" : calls == [second.id] ? "1.5 1" : "1 1"
        XCTAssertEqual(try scales(), ["1.dng": expected, "2.dng": expected])
        XCTAssertEqual(try names(in: folder), ["1.dng", "2.dng"], "no backup is left")
    }

    // Two calls, and the client goes away during the first. The run in work
    // completes and is answered. The call that waited for it does not
    // start: its folder is as it was, to the byte and to the date. A server
    // that closes its queue only when no call is in work runs the second
    // call for nobody: this test fails against that (seen 2026-10-10).
    func testAtTheEndOfInputACallThatWaitsForTheRunInWorkDoesNotStart() throws {
        try requireFixturesAndTools()
        try makeDNGs(4)
        let second = base.appendingPathComponent("Second shoot")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        for name in ["1.dng", "2.dng"] {
            try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent("sample.dng"),
                                             to: second.appendingPathComponent(name))
        }
        let before = try state(of: second)
        let server = try start()

        let run = try server.send("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5],
                                                         progressToken: "first"))
        // The first step is complete, so the run is in work, with three
        // files to go.
        let firstStep = try server.nextMessage(timeout: ServerProcess.longWait)
        XCTAssertEqual(firstStep["method"] as? String, "notifications/progress", "\(firstStep)")
        let waiting = try server.send("tools/call", toolCall("desqueeze_run", ["folder": second.path, "factor": 2]))
        server.closeInput()

        let result = try toolResult(server, id: run)
        XCTAssertEqual(counts(try result.json()), [0, 4, 0, 0, 0, 0], "the run in work completes")
        XCTAssertEqual(server.waitForExit(timeout: ServerProcess.longWait), 0)
        XCTAssertTrue(server.waitForEndOfOutput())
        let answered = try server.outputLines.compactMap { line -> Int? in
            (try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int
        }
        XCTAssertFalse(answered.contains(waiting), "the call that waited got an answer: \(server.outputLines)")
        XCTAssertEqual(try state(of: second), before, "the call that waited changed its folder")
        XCTAssertEqual(try names(in: second), ["1.dng", "2.dng"])
        XCTAssertEqual(try scales().values.sorted(), Array(repeating: "1.5 1", count: 4))
    }

    // The idle rule, with the real server. The client goes away during a
    // run that lasts longer than the 2 seconds for which the server waits
    // for an answer that no call is working on. The answer still arrives
    // whole, and then the server ends with 0.
    //
    // The number of files comes from this Mac's own speed. A fixed number
    // that lasts 2 seconds on one Mac does not on a faster one.
    func testAtTheEndOfInputARunThatLastsLongerThanThePatienceIsAnswered() throws {
        try requireFixturesAndTools()
        try makeDNGs(2)
        let server = try start()

        // A run of 2 files, timed from the progress message of the first
        // file to the answer: the time of one file, without the scan.
        let timed = try server.send("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 2],
                                                           progressToken: "timed"))
        _ = try server.nextMessage(timeout: ServerProcess.longWait)
        let firstFileDone = Date()
        XCTAssertEqual(counts(try toolResult(server, id: timed).json()), [0, 2, 0, 0, 0, 0])
        let perFile = max(Date().timeIntervalSince(firstFileDone), 0.001)
        // Enough files for 3 seconds of work after the first file.
        let copies = max(14, Int(3 / perFile) + 2)
        // Each copy is a whole DNG: about 12 MB for a frame of the Sony
        // A7S III, and more for a larger sensor. A timing near the floor
        // would make thousands of them and fill the disk. Past this limit
        // the Mac is too fast for the test, and the in-process twin pins
        // the rule.
        let mostCopies = 60
        if copies > mostCopies {
            let size = try FileManager.default.attributesOfItem(
                atPath: Self.fixtures.appendingPathComponent("sample.dng").path)[.size] as? Int ?? 0
            let megabytes = String(format: "%.1f", Double(size) / 1_000_000)
            throw XCTSkip("This Mac is too fast for this test: \(copies) files of \(megabytes) MB would be needed "
                + "(\(perFile) seconds a file; the limit is \(mostCopies)). The in-process twin, "
                + "AnsweringTransportTests.testTheStreamStaysOpenWhileACallIsInWorkLongerThanThePatience, "
                + "pins the rule.")
        }
        for number in 3...copies { try copyFixture("sample.dng", as: "\(number).dng") }

        let run = try server.send("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5],
                                                         progressToken: "long"))
        _ = try server.nextMessage(timeout: ServerProcess.longWait)
        let closed = Date()
        server.closeInput()

        let result = try toolResult(server, id: run)
        XCTAssertGreaterThan(Date().timeIntervalSince(closed), 2,
                             "the run must last longer than the 2 seconds, or this test pins nothing: "
                                 + "\(copies) files at \(perFile) seconds a file")
        XCTAssertEqual(counts(try result.json()), [0, copies, 0, 0, 0, 0])
        XCTAssertEqual(try result.json()["stopped"] as? Bool, false)
        XCTAssertEqual(server.waitForExit(), 0)
        XCTAssertTrue(server.waitForEndOfOutput())
        XCTAssertEqual(server.unfinishedOutput, "", "the answer is whole")
        XCTAssertEqual(try names(in: folder).filter { $0.hasSuffix("_original") }, [], "no backup is left")
    }

    // A run that was cancelled stops after its current file and gives its
    // report. With the end of input right behind the cancel, the report is
    // still written before the server ends.
    func testARunCancelledJustBeforeTheEndOfInputStillGivesItsReport() throws {
        try requireFixturesAndTools()
        try makeDNGs(6)
        let server = try start()

        let run = try server.send("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5],
                                                         progressToken: "stop"))
        _ = try server.nextMessage(timeout: ServerProcess.longWait)
        try server.notify("notifications/cancelled", ["requestId": run])
        server.closeInput()

        let json = try toolResult(server, id: run).json()
        XCTAssertEqual(json["stopped"] as? Bool, true)
        let set = try XCTUnwrap(json["set"] as? Int)
        XCTAssertEqual(server.waitForExit(), 0)
        XCTAssertTrue(server.waitForEndOfOutput())
        XCTAssertEqual(server.unfinishedOutput, "")
        XCTAssertEqual(try scales().values.filter { $0 == "1.5 1" }.count, set, "each file is whole")
        XCTAssertEqual(try names(in: folder).filter { $0.hasSuffix("_original") }, [], "no backup is left")
    }

    // A request that the library never answers must not hold the server
    // open. The library takes a request whose id is not a whole number or a
    // string for a notification, and sends nothing. The server waits a short
    // time, says so on standard error, and ends.
    func testARequestThatGetsNoAnswerDoesNotHoldTheServerOpen() throws {
        let server = try start()

        try server.write(#"{"jsonrpc":"2.0","id":1.5,"method":"ping"}"# + "\n")
        server.closeInput()

        XCTAssertEqual(server.waitForExit(timeout: 10), 0)
        XCTAssertTrue(server.waitForEndOfOutput())
        XCTAssertTrue(server.errorText.contains("No answer came for: [\"1.5\"]"), server.errorText)
    }

    // MARK: A signal

    // An MCP client stops a server with SIGTERM. The server does not end at
    // once: exiftool would complete the file in work, and nobody would check
    // it or discard its backup. The run stops after the file in work, its
    // report is written, the call that waits does not start, and the server
    // ends with 0. The signal goes to the server's process only.
    func testASignalDuringARunStopsItAfterTheFileInWorkAndEndsTheServerWithZero() throws {
        try requireFixturesAndTools()
        let count = 10
        try makeDNGs(count)
        let server = try start()

        let run = try server.send("tools/call", toolCall("desqueeze_run", ["folder": folder.path, "factor": 1.5],
                                                         progressToken: "signal"))
        _ = try server.nextMessage(timeout: ServerProcess.longWait)
        // A second call, which waits behind the run. The answer to a ping
        // that was sent after it shows that the library has started it.
        let remove = try server.send("tools/call", toolCall("desqueeze_remove", ["folder": folder.path]))
        let ping = try server.send("ping")
        while try server.nextMessage(timeout: ServerProcess.longWait)["id"] as? Int != ping {}
        server.send(signal: SIGTERM)

        XCTAssertEqual(server.waitForExit(timeout: ServerProcess.longWait), 0, "the server ends by itself, with 0")
        XCTAssertTrue(server.waitForEndOfOutput())
        XCTAssertEqual(server.unfinishedOutput, "", "the output ends with a line end")
        let messages = try server.outputLines.map {
            try XCTUnwrap(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any], $0)
        }
        let answers = messages.filter { $0["method"] == nil }
        XCTAssertFalse(answers.contains { $0["id"] as? Int == remove }, "the call that waited gets no answer")
        let answer = try XCTUnwrap(answers.first { $0["id"] as? Int == run }, "the run gives its report")
        let json = try toolResult(answer, earlier: []).json()
        XCTAssertEqual(json["stopped"] as? Bool, true)
        let set = try XCTUnwrap(json["set"] as? Int)
        XCTAssertGreaterThanOrEqual(set, 1)
        XCTAssertLessThan(set, count, "the run must stop before the last file")

        // exiftool does not get the signal: it goes to the server only. As
        // for the command line tool, one outcome is allowed all the same: a
        // program that was just starting got it. That one file is `failed`,
        // its detail names signal 15, and it is left as it was.
        let notes = try XCTUnwrap(json["notes"] as? [[String: Any]])
        XCTAssertEqual(json["failed"] as? Int, notes.count, "every note is a failed file: \(notes)")
        XCTAssertLessThanOrEqual(notes.count, 1, "at most one program was just starting: \(notes)")
        for note in notes {
            XCTAssertEqual(note["kind"] as? String, "failed")
            let detail = try XCTUnwrap(note["detail"] as? String)
            XCTAssertTrue(detail.contains("signal 15."), "the only allowed failure is signal 15: \(detail)")
        }

        // Each file is whole: set and checked with its backup gone, or as
        // it was. The remove did not run: the files that were set are set.
        XCTAssertEqual(try names(in: folder), (1...count).map { "\($0).dng" }.sorted(),
                       "no backup and no exiftool work file stays in the folder")
        XCTAssertEqual(try names(in: discard).count, set, "one backup for each file that was set")
        let scales = try scales()
        XCTAssertEqual(scales.values.filter { $0 == "1.5 1" }.count, set)
        XCTAssertEqual(scales.values.filter { $0 == "1 1" }.count, count - set)
        for note in notes {
            XCTAssertEqual(scales[try XCTUnwrap(note["name"] as? String)], "1 1",
                           "the file that the signal reached is unchanged")
        }
    }

    // With no call in work there is nothing to complete.
    func testASignalWithNoCallInWorkEndsTheServerAtOnceWithZero() throws {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            let server = try start()

            server.send(signal: number)

            XCTAssertEqual(server.waitForExit(timeout: 5), 0, "signal \(number)")
            XCTAssertTrue(server.waitForEndOfOutput())
        }
    }

    // MARK: Standard output is the protocol

    // A whole session, with a run, an error of each kind, and lines that are
    // not MCP. Every line of standard output is one JSON-RPC message, and
    // there is nothing else: no log line, no blank line, no unfinished line.
    func testNothingButJSONRPCLinesOnStandardOutput() throws {
        try requireFixturesAndTools()
        try makeShoot()
        try Data("not a photo".utf8).write(to: folder.appendingPathComponent("junk.dng"))
        let server = try start()

        _ = try server.result(of: "tools/list")
        _ = try call(server, "desqueeze_scan", ["folder": folder.path])
        _ = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.5, "dry_run": true])
        _ = try call(server, "desqueeze_run", ["folder": folder.path, "factor": 1.5], progressToken: "all")
        _ = try call(server, "desqueeze_remove", ["folder": folder.path])
        XCTAssertTrue(try call(server, "desqueeze_run", ["folder": folder.path]).isError)
        XCTAssertTrue(try call(server, "desqueeze_scan", ["folder": "/no/such/folder"]).isError)
        let unknown = try server.send("no/such/method")
        XCTAssertNotNil(try server.answer(to: unknown).answer["error"])
        try server.write("this line is not JSON\n")
        XCTAssertNotNil(try server.nextMessage()["error"], "a parse error, as a JSON-RPC message")
        try server.write("\n")
        _ = try server.result(of: "ping")
        server.closeInput()

        XCTAssertEqual(server.waitForExit(), 0)
        XCTAssertTrue(server.waitForEndOfOutput())
        XCTAssertEqual(server.unfinishedOutput, "", "the output ends with a line end")
        XCTAssertGreaterThanOrEqual(server.outputLines.count, 14)
        for line in server.outputLines { XCTAssertTrue(Self.isJSONRPC(line), "not a JSON-RPC line: \(line)") }
        XCTAssertTrue(server.errorText.contains(
                          "Test mode: every file that would go to the Trash goes to \(discard.path)."),
                      "the notice is on standard error: \(server.errorText)")
    }
}
