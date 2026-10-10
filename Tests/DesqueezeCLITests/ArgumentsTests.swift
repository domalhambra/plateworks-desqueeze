import DesqueezeCore
import XCTest
@testable import DesqueezeCLI

final class ArgumentsTests: XCTestCase {
    let onePointFive = SqueezeFactor(1.5)!

    func parse(_ line: String...) throws -> Invocation { try Arguments.parse(line) }

    func usageError(_ line: String..., file: StaticString = #filePath, line number: UInt = #line) -> String {
        do {
            let invocation = try Arguments.parse(line)
            XCTFail("No usage error. Parsed as \(invocation).", file: file, line: number)
            return ""
        } catch let error as UsageError {
            return error.message
        } catch {
            XCTFail("Not a usage error: \(error)", file: file, line: number)
            return ""
        }
    }

    // MARK: Each command

    func testScan() throws {
        XCTAssertEqual(try parse("scan", "/Volumes/Card/Shoot 1"),
                       Invocation(command: .scan(folder: "/Volumes/Card/Shoot 1")))
    }

    func testRun() throws {
        XCTAssertEqual(try parse("run", "Shoot", "--factor", "1.5"),
                       Invocation(command: .run(folder: "Shoot", factor: onePointFive, convert: true,
                                                trashOriginals: false, dryRun: false)))
    }

    func testRemove() throws {
        XCTAssertEqual(try parse("remove", "Shoot"), Invocation(command: .remove(folder: "Shoot", dryRun: false)))
    }

    func testVersionAndHelp() throws {
        XCTAssertEqual(try parse("--version"), Invocation(command: .version))
        XCTAssertEqual(try parse("--help"), Invocation(command: .help))
        XCTAssertEqual(try parse("-h"), Invocation(command: .help))
    }

    // A person who asks for help gets it, whatever else is on the line.
    func testHelpWinsOverEverythingElseOnTheLine() throws {
        XCTAssertEqual(try parse("run", "--help"), Invocation(command: .help))
        XCTAssertEqual(try parse("frobnicate", "--bogus", "--help"), Invocation(command: .help))
        XCTAssertEqual(try parse("--version", "--help"), Invocation(command: .help))
        XCTAssertEqual(try parse("scan", "Shoot", "--version"), Invocation(command: .version))
    }

    // MARK: Each flag

    func testJSONOnEveryCommand() throws {
        XCTAssertEqual(try parse("scan", "Shoot", "--json"), Invocation(command: .scan(folder: "Shoot"), json: true))
        XCTAssertTrue(try parse("run", "Shoot", "--factor", "2", "--json").json)
        XCTAssertTrue(try parse("remove", "Shoot", "--json").json)
        XCTAssertFalse(try parse("scan", "Shoot").json)
    }

    func testVerboseOnEveryCommand() throws {
        XCTAssertEqual(try parse("scan", "Shoot", "--verbose"),
                       Invocation(command: .scan(folder: "Shoot"), verbose: true))
        XCTAssertTrue(try parse("run", "Shoot", "--factor", "2", "--verbose").verbose)
        XCTAssertTrue(try parse("remove", "Shoot", "--verbose").verbose)
        XCTAssertFalse(try parse("remove", "Shoot").verbose)
    }

    func testDryRunOnRunAndRemove() throws {
        XCTAssertEqual(try parse("run", "Shoot", "--factor", "1.5", "--dry-run").command,
                       .run(folder: "Shoot", factor: onePointFive, convert: true, trashOriginals: false, dryRun: true))
        XCTAssertEqual(try parse("remove", "Shoot", "--dry-run").command, .remove(folder: "Shoot", dryRun: true))
    }

    func testNoConvertOnRun() throws {
        XCTAssertEqual(try parse("run", "Shoot", "--factor", "1.5", "--no-convert").command,
                       .run(folder: "Shoot",
                            factor: onePointFive, convert: false, trashOriginals: false, dryRun: false))
    }

    func testEveryFlagOfRunTogetherInAnyOrder() throws {
        let expected = Invocation(command: .run(folder: "Shoot", factor: onePointFive, convert: false,
                                                trashOriginals: false, dryRun: true),
                                  json: true, verbose: true)
        XCTAssertEqual(try parse("run", "Shoot", "--factor", "1.5", "--no-convert", "--dry-run", "--json", "--verbose"),
                       expected)
        XCTAssertEqual(try parse("--verbose", "--json", "run", "--dry-run", "--factor", "1.5", "--no-convert", "Shoot"),
                       expected)
    }

    // MARK: The factor

    func testTheFactorTakesTheValuesOfTheWindow() throws {
        func factor(_ text: String) throws -> SqueezeFactor? {
            guard case .run(_, let factor, _, _, _) = try parse("run", "Shoot", "--factor", text).command else {
                return nil
            }
            return factor
        }
        XCTAssertEqual(try factor("1.33"), SqueezeFactor(1.33))
        XCTAssertEqual(try factor("2"), SqueezeFactor(2))
        XCTAssertEqual(try factor("1"), .noStretch)
        XCTAssertEqual(try factor("4"), SqueezeFactor(4))
        XCTAssertEqual(try factor("1.3333"), SqueezeFactor(1.3333))
    }

    func testTheFactorCanFollowAnEqualsSign() throws {
        XCTAssertEqual(try parse("run", "Shoot", "--factor=1.5").command,
                       .run(folder: "Shoot", factor: onePointFive, convert: true, trashOriginals: false, dryRun: false))
    }

    func testRunWithNoFactorIsAUsageErrorBecauseThereIsNoDefault() {
        XCTAssertEqual(usageError("run", "Shoot"), "run needs --factor <number>. There is no default.")
        XCTAssertEqual(usageError("run", "Shoot", "--dry-run", "--json"),
                       "run needs --factor <number>. There is no default.")
    }

    func testAFactorWithNoValueIsAUsageError() {
        XCTAssertEqual(usageError("run", "Shoot", "--factor"), "--factor needs a number.")
        XCTAssertEqual(usageError("run", "Shoot", "--factor", "--json"), "--factor needs a number.")
        XCTAssertEqual(usageError("run", "Shoot", "--factor="), "--factor needs a number.")
    }

    func testAFactorOutOfRangeOrNotANumberIsAUsageError() {
        for bad in ["0.99", "4.0001", "0", "5", "abc", "1.33333", "1.5x", "-1.5", "1e0", " ", "inf", "nan"] {
            XCTAssertEqual(usageError("run", "Shoot", "--factor", bad),
                           "The factor must be a number from 1 to 4, with at most four decimal places. "
                               + "It was \"\(bad)\".",
                           bad)
        }
    }

    // The rule alone does not say what is wrong with a comma. The core adds
    // the words, so the window and the MCP server say them too.
    func testAFactorWithACommaIsAUsageErrorThatSaysToUseAPeriod() {
        let rule = "The factor must be a number from 1 to 4, with at most four decimal places."
        XCTAssertEqual(usageError("run", "Shoot", "--factor", "1,5"),
                       "\(rule) It was \"1,5\". Use a period for the decimal point.")
        XCTAssertEqual(usageError("run", "Shoot", "--factor=1,33"),
                       "\(rule) It was \"1,33\". Use a period for the decimal point.")
        // The sentence reads correctly for text that ends with a comma.
        XCTAssertEqual(usageError("run", "Shoot", "--factor", "1.5,"),
                       "\(rule) It was \"1.5,\". Use a period for the decimal point.")
    }

    func testAFactorGivenTwiceIsAUsageError() {
        XCTAssertEqual(usageError("run", "Shoot", "--factor", "1.5", "--factor", "2"),
                       "--factor was given more than once.")
        XCTAssertEqual(usageError("run", "Shoot", "--factor=1.5", "--factor=1.5"),
                       "--factor was given more than once.")
    }

    // MARK: The folder

    func testACommandWithNoFolderIsAUsageError() {
        XCTAssertEqual(usageError("scan"), "scan needs a folder.")
        XCTAssertEqual(usageError("run", "--factor", "1.5"), "run needs a folder.")
        XCTAssertEqual(usageError("remove", "--json"), "remove needs a folder.")
        XCTAssertEqual(usageError("scan", ""), "scan needs a folder.")
    }

    func testASecondFolderIsAUsageError() {
        XCTAssertEqual(usageError("scan", "One", "Two"), "Too many arguments: Two. Give one folder.")
        XCTAssertEqual(usageError("remove", "One", "Two", "Three"), "Too many arguments: Two Three. Give one folder.")
    }

    // A folder path with spaces arrives as one argument. Nothing splits it.
    func testAFolderNameIsTakenAsItIs() throws {
        XCTAssertEqual(try parse("scan", "My Shoot  2026/Day 1").command, .scan(folder: "My Shoot  2026/Day 1"))
        XCTAssertEqual(try parse("scan", "./rel/../Shoot").command, .scan(folder: "./rel/../Shoot"))
    }

    // Two dashes end the options, so a folder whose name starts with a dash
    // can be given.
    func testTwoDashesEndTheOptions() throws {
        XCTAssertEqual(try parse("scan", "--json", "--", "--help"),
                       Invocation(command: .scan(folder: "--help"), json: true))
        XCTAssertEqual(try parse("run", "--factor", "2", "--", "-odd folder").command,
                       .run(folder: "-odd folder",
                            factor: SqueezeFactor(2)!, convert: true, trashOriginals: false, dryRun: false))
        XCTAssertEqual(usageError("scan", "--", "One", "--json"), "Too many arguments: --json. Give one folder.")
    }

    // MARK: The other usage errors

    func testNoArgumentIsAUsageError() {
        XCTAssertEqual(usageError(), "No command was given.")
        XCTAssertEqual(usageError("--json"), "No command was given.")
    }

    func testAnUnknownCommandIsAUsageError() {
        XCTAssertEqual(usageError("desqueeze", "Shoot"),
                       "Unknown command: desqueeze. The commands are scan, run and remove.")
        XCTAssertEqual(usageError("Scan", "Shoot"), "Unknown command: Scan. The commands are scan, run and remove.")
    }

    func testAnUnknownOptionIsAUsageError() {
        XCTAssertEqual(usageError("scan", "Shoot", "--frob"), "Unknown option: --frob")
        XCTAssertEqual(usageError("run", "Shoot", "--factor", "1.5", "-n"), "Unknown option: -n")
        XCTAssertEqual(usageError("scan", "Shoot", "--json=yes"), "Unknown option: --json=yes")
        XCTAssertEqual(usageError("scan", "Shoot", "--JSON"), "Unknown option: --JSON")
        XCTAssertEqual(usageError("--frob"), "Unknown option: --frob")
    }

    func testAnOptionOnACommandThatDoesNotTakeItIsAUsageError() {
        XCTAssertEqual(usageError("scan", "Shoot", "--factor", "1.5"), "--factor does not go with scan.")
        XCTAssertEqual(usageError("scan", "Shoot", "--dry-run"), "--dry-run does not go with scan.")
        XCTAssertEqual(usageError("scan", "Shoot", "--no-convert"), "--no-convert does not go with scan.")
        XCTAssertEqual(usageError("remove", "Shoot", "--factor", "2"),
                       "--factor does not go with remove. Remove always sets no stretch.")
        XCTAssertEqual(usageError("remove", "Shoot", "--no-convert"),
                       "--no-convert does not go with remove. Remove never converts.")
    }

    // No usage error may run a command. Each message is plain: a sentence
    // that starts with a capital or an option, and has no exclamation mark.
    func testEveryUsageMessageIsPlain() {
        let lines: [[String]] = [
            [], ["frob"], ["scan"], ["scan", "a", "b"], ["scan", "a", "--frob"], ["run", "a"],
            ["run", "a", "--factor"], ["run", "a", "--factor", "9"], ["run", "a", "--factor", "1", "--factor", "2"],
            ["scan", "a", "--dry-run"], ["remove", "a", "--factor", "2"], ["remove", "a", "--no-convert"],
        ]
        for line in lines {
            XCTAssertThrowsError(try Arguments.parse(line), "\(line)") { error in
                let message = (error as? UsageError)?.message ?? ""
                XCTAssertFalse(message.isEmpty, "\(line)")
                XCTAssertFalse(message.contains("!"), message)
                XCTAssertNotEqual(message, "Not written.")
            }
        }
    }
}
