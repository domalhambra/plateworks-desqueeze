import XCTest
@testable import DesqueezeCore

/// What counts as a folder when a person drops, chooses, or names one
/// (design, section 5). Each test builds its own temporary folder.
final class FolderChoiceTests: XCTestCase {
    var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderChoiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: base) }

    func makeFolder(_ name: String) throws -> URL {
        let url = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeLink(_ name: String, to target: URL) throws -> URL {
        let url = base.appendingPathComponent(name)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        return url
    }

    /// The path with every link in it resolved, as `realpath` gives it.
    func realPath(_ url: URL?) -> String? {
        guard let url, let pointer = realpath(url.path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    func testAFolderIsThatFolder() throws {
        let shoot = try makeFolder("Shoot 1")
        let folder = FolderChoice.folder(at: shoot)
        XCTAssertEqual(realPath(folder), realPath(shoot))
        XCTAssertEqual(folder?.lastPathComponent, "Shoot 1")
    }

    func testALinkToAFolderIsThatFolder() throws {
        let shoot = try makeFolder("Shoot 1")
        let link = try makeLink("Link", to: shoot)
        let folder = FolderChoice.folder(at: link)
        XCTAssertEqual(realPath(folder), realPath(shoot))
        XCTAssertEqual(folder?.lastPathComponent, "Shoot 1", "the window shows the name of the folder, not of the link")
    }

    func testAFileIsNotAFolder() throws {
        let file = base.appendingPathComponent("a.dng")
        try Data().write(to: file)
        XCTAssertNil(FolderChoice.folder(at: file))
        XCTAssertNil(FolderChoice.folder(at: try makeLink("Link", to: file)))
    }

    func testAPathWithNothingAtItIsNotAFolder() throws {
        XCTAssertNil(FolderChoice.folder(at: base.appendingPathComponent("gone")))
        XCTAssertNil(FolderChoice.folder(at: try makeLink("Link", to: base.appendingPathComponent("gone"))))
    }

    func testAPackageIsNotAFolder() throws {
        XCTAssertNil(FolderChoice.folder(at: try makeFolder("Thing.app")))
        XCTAssertNil(FolderChoice.folder(at: try makeFolder("Photos Library.photoslibrary")))
    }

    func testALinkToAPackageIsNotAFolder() throws {
        let app = try makeFolder("Thing.app")
        XCTAssertNil(FolderChoice.folder(at: try makeLink("Link", to: app)))
    }

    // Why a path names no folder: one sentence, the same in every front end.
    func testTheReasonForAPathThatIsNotAFolder() throws {
        let gone = base.appendingPathComponent("gone")
        XCTAssertEqual(FolderChoice.whyNotAFolder(gone), "Nothing is at this path.")
        XCTAssertEqual(FolderChoice.whyNotAFolder(try makeLink("Link to gone", to: gone)), "Nothing is at this path.")

        let file = base.appendingPathComponent("a.dng")
        try Data().write(to: file)
        XCTAssertEqual(FolderChoice.whyNotAFolder(file), "It is a file, not a folder.")
        XCTAssertEqual(FolderChoice.whyNotAFolder(try makeLink("Link to file", to: file)), "It is a file, not a folder.")

        let package = try makeFolder("Thing.app")
        let sentence = "It is a package, such as an app or a photo library, and not a folder of photos."
        XCTAssertEqual(FolderChoice.whyNotAFolder(package), sentence)
        XCTAssertEqual(FolderChoice.whyNotAFolder(try makeLink("Link to package", to: package)), sentence)
    }
}
