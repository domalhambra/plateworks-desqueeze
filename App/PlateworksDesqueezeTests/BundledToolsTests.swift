import DesqueezeCore
import XCTest

/// The two programs inside the downloaded app: where they are in the bundle,
/// and that the window takes them first (design 15.3 and 15.4). No test
/// here starts a program: each one asks a locator with its own answer to
/// "can this file be run".
final class BundledToolsTests: XCTestCase {
    private let perl = ToolLocator.systemPerl

    /// The locator as `AppModel.live` makes it for `bundle`, on a Mac where
    /// only the files in `present` can be run.
    private func locator(bundle: String, present: Set<String>) -> ToolLocator {
        let inside = BundledTools(bundle: URL(fileURLWithPath: bundle))
        return ToolLocator(pathVariable: nil, bundledExiftool: inside.exiftool, bundledDnglab: inside.dnglab,
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

    // MARK: The window's locator

    func testTheWindowTakesTheProgramsOfItsBundleFirst() {
        let app = "/Applications/Desqueeze.app"
        let found = locator(bundle: app, present: [
            "\(app)/Contents/Resources/exiftool/exiftool", "\(app)/Contents/Helpers/dnglab", perl,
            "/opt/homebrew/bin/exiftool", "/opt/homebrew/bin/dnglab",
        ])
        XCTAssertEqual(found.exiftool()?.path, "\(app)/Contents/Resources/exiftool/exiftool")
        XCTAssertEqual(found.dnglab()?.path, "\(app)/Contents/Helpers/dnglab")
    }

    // A build from source has no program inside. It looks as before.
    func testABuildFromSourceFindsTheProgramsOfTheMac() {
        let found = locator(bundle: "/Somewhere/build/Desqueeze.app", present: [
            perl, "/opt/homebrew/bin/exiftool", "/usr/local/bin/dnglab",
        ])
        XCTAssertEqual(found.exiftool()?.path, "/opt/homebrew/bin/exiftool")
        XCTAssertEqual(found.dnglab()?.path, "/usr/local/bin/dnglab")
    }

    // MARK: The launch hooks (design, section 9)

    // A hook hides a program wherever it is, also inside the bundle.
    func testALaunchHookHidesAProgramOfTheBundleToo() {
        let app = "/Applications/Desqueeze.app"
        let adobe = ToolLocator.standardConverterApp + ToolLocator.converterBinary
        let found = locator(bundle: app, present: [
            "\(app)/Contents/Resources/exiftool/exiftool", "\(app)/Contents/Helpers/dnglab", perl, adobe,
        ])

        let none = LaunchOptions(arguments: [:])
        XCTAssertEqual(none.exiftool(in: found)?.path, "\(app)/Contents/Resources/exiftool/exiftool")
        XCTAssertEqual(none.dnglab(in: found)?.path, "\(app)/Contents/Helpers/dnglab")
        XCTAssertEqual(none.adobe(in: found)?.path, adobe)

        let noTools = LaunchOptions(arguments: ["simulateMissingTools": "YES"])
        XCTAssertNil(noTools.exiftool(in: found))
        XCTAssertNil(noTools.dnglab(in: found))
        XCTAssertNil(noTools.adobe(in: found))

        let noDnglab = LaunchOptions(arguments: ["simulateMissingDnglab": "YES"])
        XCTAssertNotNil(noDnglab.exiftool(in: found))
        XCTAssertNil(noDnglab.dnglab(in: found))
        XCTAssertNotNil(noDnglab.adobe(in: found))

        let noAdobe = LaunchOptions(arguments: ["simulateMissingAdobe": "YES"])
        XCTAssertNotNil(noAdobe.exiftool(in: found))
        XCTAssertNotNil(noAdobe.dnglab(in: found))
        XCTAssertNil(noAdobe.adobe(in: found))
    }
}
