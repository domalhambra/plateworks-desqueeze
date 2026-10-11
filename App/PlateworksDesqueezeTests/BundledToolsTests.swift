import DesqueezeCore
import XCTest

/// The two programs inside the downloaded app: where they are in the bundle,
/// and that the window takes them first (design 15.3 and 15.4). No test
/// here starts a program: each one gives its own answer to "can this file
/// be run".
///
/// The tests of the window's programs call `WindowTools.find`, the one
/// function that `AppModel.live` calls. So a test fails when the window
/// gives the core no place in its bundle, and when a launch hook no longer
/// hides a program (design 15.7).
final class BundledToolsTests: XCTestCase {
    private let perl = ToolLocator.systemPerl
    private let app = "/Applications/Desqueeze.app"
    private var exiftoolInside: String { "\(app)/Contents/Resources/exiftool/exiftool" }
    private var dnglabInside: String { "\(app)/Contents/Helpers/dnglab" }
    private let adobe = ToolLocator.standardConverterApp + ToolLocator.converterBinary

    /// The three programs as the window finds them, on a Mac where only the
    /// files in `present` can be run.
    private func tools(
        bundle: String? = nil, present: Set<String>, arguments: [String: Any] = [:], registered: String? = nil,
        path: String? = nil
    ) -> WindowTools {
        WindowTools.find(
            bundle: URL(fileURLWithPath: bundle ?? app), options: LaunchOptions(arguments: arguments),
            registeredConverterApp: registered.map { URL(fileURLWithPath: $0) }, pathVariable: path,
            isExecutable: { present.contains($0) })
    }

    // MARK: The two places

    // A Mach-O program is in `Contents/Helpers`, and a script is in
    // `Contents/Resources`. The code signature of a bundle needs it so.
    func testTheTwoPlacesAreInsideTheBundle() {
        let inside = BundledTools(bundle: URL(fileURLWithPath: "/Applications/Desqueeze.app"))
        XCTAssertEqual(inside.exiftool.path, "/Applications/Desqueeze.app/Contents/Resources/exiftool/exiftool")
        XCTAssertEqual(inside.dnglab.path, "/Applications/Desqueeze.app/Contents/Helpers/dnglab")
    }

    // The system gives the URL of a bundle with a slash at its end. A
    // person can keep the app in any folder, also one with a space.
    func testTheBundleCanBeAnywhereAndItsURLCanEndWithASlash() {
        let plain = BundledTools(bundle: URL(fileURLWithPath: "/Volumes/My Disk/Apps/Desqueeze.app"))
        let withSlash = BundledTools(
            bundle: URL(fileURLWithPath: "/Volumes/My Disk/Apps/Desqueeze.app/", isDirectory: true))
        XCTAssertEqual(plain, withSlash)
        XCTAssertEqual(plain.exiftool.path, "/Volumes/My Disk/Apps/Desqueeze.app/Contents/Resources/exiftool/exiftool")
        XCTAssertEqual(plain.dnglab.path, "/Volumes/My Disk/Apps/Desqueeze.app/Contents/Helpers/dnglab")
        XCTAssertTrue(plain.exiftool.isFileURL)
        XCTAssertFalse(plain.exiftool.hasDirectoryPath)
        XCTAssertFalse(plain.dnglab.hasDirectoryPath)
    }

    // MARK: The programs of the window

    func testTheWindowTakesTheProgramsOfItsBundleFirst() {
        let found = tools(present: [exiftoolInside, dnglabInside, perl,
                                    "/opt/homebrew/bin/exiftool", "/opt/homebrew/bin/dnglab"])
        XCTAssertEqual(found.exiftool?.path, exiftoolInside)
        XCTAssertEqual(found.dnglab?.path, dnglabInside)
        XCTAssertNil(found.adobe, "Adobe DNG Converter is never inside the app")
    }

    // The exiftool inside is a Perl script. With no Perl of macOS, the
    // window takes the exiftool of the Mac. dnglab needs no Perl.
    func testWithNoPerlOfMacOSTheWindowTakesTheExiftoolOfTheMac() {
        let found = tools(present: [exiftoolInside, dnglabInside, "/opt/homebrew/bin/exiftool"])
        XCTAssertEqual(found.exiftool?.path, "/opt/homebrew/bin/exiftool")
        XCTAssertEqual(found.dnglab?.path, dnglabInside)
        XCTAssertNil(tools(present: [exiftoolInside, dnglabInside]).exiftool)
    }

    // A build from source has no program inside. It looks as before.
    func testABuildFromSourceFindsTheProgramsOfTheMac() {
        let found = tools(bundle: "/Somewhere/build/Desqueeze.app",
                          present: [perl, "/opt/homebrew/bin/exiftool", "/usr/local/bin/dnglab"])
        XCTAssertEqual(found.exiftool?.path, "/opt/homebrew/bin/exiftool")
        XCTAssertEqual(found.dnglab?.path, "/usr/local/bin/dnglab")
        XCTAssertEqual(tools(bundle: "/Somewhere/build/Desqueeze.app", present: [perl]),
                       WindowTools(exiftool: nil, dnglab: nil, adobe: nil))
    }

    // The folders of `PATH` come after the two Homebrew folders.
    func testTheWindowLooksInTheFoldersOfThePathToo() {
        let found = tools(present: ["/opt/tools/exiftool", "/opt/tools/dnglab", "/usr/local/bin/dnglab"],
                          path: "/usr/bin:/opt/tools")
        XCTAssertEqual(found.exiftool?.path, "/opt/tools/exiftool")
        XCTAssertEqual(found.dnglab?.path, "/usr/local/bin/dnglab")
        XCTAssertNil(tools(present: ["/opt/tools/exiftool"], path: nil).exiftool)
    }

    // The window asks macOS where Adobe DNG Converter is, and gives the
    // answer here. That app comes before the one in the Applications folder.
    func testTheWindowFindsAdobeDNGConverterWhereMacOSSaysItIs() {
        let registered = "/Somewhere/Apps/Adobe DNG Converter.app"
        let binary = registered + ToolLocator.converterBinary
        XCTAssertEqual(tools(present: [binary, adobe], registered: registered).adobe?.path, binary)
        XCTAssertEqual(tools(present: [adobe], registered: registered).adobe?.path, adobe)
        XCTAssertEqual(tools(present: [adobe]).adobe?.path, adobe)
        XCTAssertNil(tools(present: [binary]).adobe, "macOS named no app, and the Applications folder has none")
    }

    // MARK: The launch hooks (design, section 9)

    // A hook hides a program wherever it is, also inside the bundle.
    func testALaunchHookHidesAProgramOfTheBundleToo() {
        let present: Set<String> = [exiftoolInside, dnglabInside, perl, adobe]
        func found(_ arguments: [String: Any]) -> WindowTools { tools(present: present, arguments: arguments) }
        func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

        XCTAssertEqual(found([:]),
                       WindowTools(exiftool: url(exiftoolInside), dnglab: url(dnglabInside), adobe: url(adobe)))
        XCTAssertEqual(found(["simulateMissingTools": "YES"]), WindowTools(exiftool: nil, dnglab: nil, adobe: nil))
        XCTAssertEqual(found(["simulateMissingDnglab": "YES"]),
                       WindowTools(exiftool: url(exiftoolInside), dnglab: nil, adobe: url(adobe)))
        XCTAssertEqual(found(["simulateMissingAdobe": "YES"]),
                       WindowTools(exiftool: url(exiftoolInside), dnglab: url(dnglabInside), adobe: nil))
        XCTAssertEqual(found(["simulateMissingDnglab": "YES", "simulateMissingAdobe": "YES"]),
                       WindowTools(exiftool: url(exiftoolInside), dnglab: nil, adobe: nil))
    }

    // A hook hides a program of the Mac as it did before.
    func testALaunchHookHidesAProgramOfTheMac() {
        let present: Set<String> = ["/opt/homebrew/bin/exiftool", "/opt/homebrew/bin/dnglab", adobe]
        XCTAssertEqual(tools(bundle: "/Somewhere/build/Desqueeze.app", present: present,
                             arguments: ["simulateMissingTools": "YES"]),
                       WindowTools(exiftool: nil, dnglab: nil, adobe: nil))
        XCTAssertNotNil(tools(bundle: "/Somewhere/build/Desqueeze.app", present: present).exiftool)
    }

    // MARK: The release script

    // `scripts/make_release.sh` puts the two programs into the bundle, and
    // it holds the two places a second time. They must be the places of
    // this type. With another place in the script, the downloaded app
    // does not find its own programs, and nothing says so: it takes the
    // programs of the Mac, or it says that exiftool is not installed.
    func testTheReleaseScriptPutsTheProgramsAtTheSameTwoPlaces() throws {
        // App/PlateworksDesqueezeTests/BundledToolsTests.swift -> repo root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/make_release.sh"), encoding: .utf8)
        let lines = script.split(separator: "\n").map(String.init)

        let app = "/Applications/Desqueeze.app"
        let inside = BundledTools(bundle: URL(fileURLWithPath: app))
        let exiftool = String(inside.exiftool.path.dropFirst(app.count + 1))
        let dnglab = String(inside.dnglab.path.dropFirst(app.count + 1))
        XCTAssertEqual(lines.filter { $0.hasPrefix("exiftool_place=") }, ["exiftool_place=\"\(exiftool)\""])
        XCTAssertEqual(lines.filter { $0.hasPrefix("dnglab_place=") }, ["dnglab_place=\"\(dnglab)\""])
        // The script builds each path in the bundle from its variable.
        XCTAssertTrue(script.contains("exiftool_inside=\"$app/$exiftool_place\""))
        XCTAssertTrue(script.contains("dnglab_inside=\"$app/$dnglab_place\""))
    }
}
