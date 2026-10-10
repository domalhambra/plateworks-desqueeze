import XCTest
@testable import DesqueezeCore

/// The rename that never replaces (design 13.3, step 5), on injected system
/// calls and on the disk of the temporary folder.
final class ExclusiveRenameTests: XCTestCase {
    let work = URL(fileURLWithPath: "/tmp/Shoot 1/.a.desqueeze-work.dng")
    let dng = URL(fileURLWithPath: "/tmp/Shoot 1/a.dng")

    /// A rename on three scripted calls. `log` gets each call that was made.
    func rename(exclusive: Int32, exists: Bool = false, plain: Int32 = 0, log: CallLog) -> ExclusiveRename {
        ExclusiveRename(
            renameExclusive: { log.entries.append("exclusive \($0) \($1)"); return exclusive },
            exists: { log.entries.append("check \($0)"); return exists },
            rename: { log.entries.append("rename \($0) \($1)"); return plain })
    }

    func testTheExclusiveCallAloneMovesTheFileWhenTheVolumeHasIt() {
        let log = CallLog()
        XCTAssertEqual(rename(exclusive: 0, log: log).move(work, to: dng), .moved)
        XCTAssertEqual(log.entries, ["exclusive \(work.path) \(dng.path)"], "no second rename")
    }

    func testANameThatTheExclusiveCallFindsTakenIsNotRenamedOnTheOtherPath() {
        let log = CallLog()
        XCTAssertEqual(rename(exclusive: EEXIST, log: log).move(work, to: dng), .nameTaken)
        XCTAssertEqual(log.entries, ["exclusive \(work.path) \(dng.path)"], "a plain rename would replace the file")
    }

    // The volume does not have the call: check the name, then rename.
    func testWithoutTheCallAFreeNameIsCheckedAndThenRenamed() {
        let log = CallLog()
        XCTAssertEqual(rename(exclusive: ENOTSUP, exists: false, log: log).move(work, to: dng), .moved)
        XCTAssertEqual(log.entries, [
            "exclusive \(work.path) \(dng.path)", "check \(dng.path)", "rename \(work.path) \(dng.path)",
        ])
    }

    func testWithoutTheCallATakenNameIsNeverRenamedOnto() {
        let log = CallLog()
        XCTAssertEqual(rename(exclusive: ENOTSUP, exists: true, log: log).move(work, to: dng), .nameTaken)
        XCTAssertEqual(log.entries, ["exclusive \(work.path) \(dng.path)", "check \(dng.path)"],
                       "a plain rename would replace the file")
    }

    func testWithoutTheCallAPlainRenameThatFailsGivesItsErrorNumber() {
        let log = CallLog()
        XCTAssertEqual(rename(exclusive: ENOTSUP, plain: EROFS, log: log).move(work, to: dng), .failed(EROFS))
    }

    // Any other refusal is not "the volume does not have the call": the
    // other path is not tried.
    func testAnotherErrorOfTheExclusiveCallFailsWithItsNumberAndTriesNothingElse() {
        for code in [EACCES, ENOENT, EROFS, EINVAL, EOPNOTSUPP] {
            let log = CallLog()
            XCTAssertEqual(rename(exclusive: code, log: log).move(work, to: dng), .failed(code))
            XCTAssertEqual(log.entries.count, 1, "\(code)")
        }
        XCTAssertEqual(ExclusiveRename.Outcome.words(for: EACCES), "Permission denied")
    }

    // MARK: The real calls

    func testOnTheRealDiskAFreeNameGetsTheFileWithItsBytes() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let work = folder.appendingPathComponent(".frame 1.desqueeze-work.dng")
        let dng = folder.appendingPathComponent("frame 1.dng")
        try Data("the new DNG".utf8).write(to: work)

        XCTAssertEqual(ExclusiveRename.system.move(work, to: dng), .moved)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["frame 1.dng"])
        XCTAssertEqual(try Data(contentsOf: dng), Data("the new DNG".utf8))
    }

    /// Plants each kind of thing at the name `frame <n>.dng`, with a work
    /// file beside it, and asks `rename` to move the work file there. The
    /// answer must be "the name is taken", and the thing at the name must be
    /// the one that was planted: a file, a folder, a link, and a link that
    /// points at nothing.
    func assertAnythingAtTheNameStaysAsItWas(_ rename: ExclusiveRename, file: StaticString = #filePath,
                                             line: UInt = #line) throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        let files = FileManager.default
        let target = folder.appendingPathComponent("elsewhere.bin")
        try Data("a file of the person".utf8).write(to: target)
        let plant: [(String, (URL) throws -> Void)] = [
            ("a file", { try Data("another program's DNG".utf8).write(to: $0) }),
            ("an empty file", { try Data().write(to: $0) }),
            ("a folder", { try files.createDirectory(at: $0, withIntermediateDirectories: false) }),
            ("a link to a file", { try files.createSymbolicLink(at: $0, withDestinationURL: target) }),
            ("a link to a folder", { try files.createSymbolicLink(at: $0, withDestinationURL: folder) }),
            ("a dangling link", {
                try files.createSymbolicLink(atPath: $0.path, withDestinationPath: folder.path + "/no such file")
            }),
        ]
        for (number, (what, make)) in plant.enumerated() {
            let work = folder.appendingPathComponent(".frame \(number).desqueeze-work.dng")
            let dng = folder.appendingPathComponent("frame \(number).dng")
            try Data("the new DNG".utf8).write(to: work)
            try make(dng)
            let before = try files.attributesOfItem(atPath: dng.path)

            XCTAssertEqual(rename.move(work, to: dng), .nameTaken, what, file: file, line: line)

            XCTAssertEqual(try? Data(contentsOf: work), Data("the new DNG".utf8), "\(what): the work file stays",
                           file: file, line: line)
            // `attributesOfItem` does not follow a link, so these are the
            // type and the number of the thing at the name itself.
            let after = try files.attributesOfItem(atPath: dng.path)
            XCTAssertEqual(after[.type] as? FileAttributeType, before[.type] as? FileAttributeType, what,
                           file: file, line: line)
            XCTAssertEqual(after[.systemFileNumber] as? Int, before[.systemFileNumber] as? Int,
                           "\(what): the thing at the name was replaced", file: file, line: line)
        }
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("frame 0.dng")),
                       Data("another program's DNG".utf8), file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: target), Data("a file of the person".utf8),
                       "nothing was written through a link", file: file, line: line)
    }

    // Anything at the name stops the rename, and stays as it was.
    func testOnTheRealDiskAnythingAtTheNameStaysAsItWas() throws {
        try assertAnythingAtTheNameStaysAsItWas(.system)
    }

    // The other path, for a volume that does not have the exclusive call:
    // the system's own check of the name, and the system's own plain rename.
    // The check must not follow a link. `FileManager.fileExists` follows
    // one, says that a dangling link is not there, and the plain rename then
    // replaces the link.
    func testOnTheRealDiskTheCheckOfTheOtherPathDoesNotFollowALink() throws {
        let system = ExclusiveRename.system
        try assertAnythingAtTheNameStaysAsItWas(
            ExclusiveRename(renameExclusive: { _, _ in ENOTSUP }, exists: system.exists, rename: system.rename))
    }

    func testOnTheRealDiskAFileThatIsNotThereFailsWithTheSystemsNumber() throws {
        let folder = try makeTemporaryFolder()
        defer { removeTemporaryFolder(folder) }
        XCTAssertEqual(ExclusiveRename.system.move(folder.appendingPathComponent("no such file"),
                                                   to: folder.appendingPathComponent("a.dng")), .failed(ENOENT))
    }
}

/// Both paths of `ExclusiveRename` on real volumes: two small disk images,
/// one APFS and one ExFAT, in a temporary folder.
///
/// Each image is attached with `-nobrowse`, at a mount point inside the
/// temporary folder, and detached in `tearDown`. The test touches no other
/// volume. It skips when `hdiutil` cannot make or attach an image.
///
/// What macOS 27 did on 2026-10-09, and what the test pins:
///
/// | Volume | The name is taken | The name is free |
/// |---|---|---|
/// | APFS | `renamex_np` answers `EEXIST` | `renamex_np` renames |
/// | ExFAT | `renamex_np` answers `EEXIST` | `renamex_np` answers `ENOTSUP`, then the check and a plain `rename` |
final class ExclusiveRenameVolumeTests: XCTestCase {
    static let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")

    var base: URL!
    /// The mount point of each image that this test attached.
    var mounted: [URL] = []

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("desqueeze-volumes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() {
        var left: [URL] = []
        for volume in mounted where !detach(volume) { left.append(volume) }
        mounted = left
        XCTAssertEqual(left, [], "a disk image of this test is still attached")
        // The images go with the folder. With a volume still attached, the
        // folder stays: removing it would reach into the volume.
        if left.isEmpty, let base, base.lastPathComponent.hasPrefix("desqueeze-volumes-") {
            try? FileManager.default.removeItem(at: base)
        }
    }

    /// Detaches a volume that this test attached. `-force` is the fallback.
    func detach(_ volume: URL) -> Bool {
        for arguments in [["detach", volume.path, "-quiet"], ["detach", volume.path, "-force", "-quiet"]] {
            if let result = try? SystemProcessRunner().run(Self.hdiutil, arguments), result.exitCode == 0 { return true }
        }
        return false
    }

    /// Makes an image of 20 MB with this file system, and attaches it.
    /// The volume name is short: ExFAT takes 11 characters.
    ///
    /// - Returns: a new folder on the volume.
    func volume(_ fileSystem: String, named name: String) throws -> URL {
        let files = FileManager.default
        let image = base.appendingPathComponent("\(name).dmg")
        let mounts = base.appendingPathComponent("\(name) mounts")
        try files.createDirectory(at: mounts, withIntermediateDirectories: false)
        let runner = SystemProcessRunner()
        guard let made = try? runner.run(Self.hdiutil, [
            "create", "-size", "20m", "-fs", fileSystem, "-volname", "DQ\(name.uppercased())", "-quiet", image.path,
        ]), made.exitCode == 0 else {
            throw XCTSkip("hdiutil could not make a \(fileSystem) image.")
        }
        let attached = try? runner.run(Self.hdiutil, [
            "attach", image.path, "-nobrowse", "-mountrandom", mounts.path, "-quiet",
        ])
        // The mount point is the one thing in the folder. It is noted before
        // anything else, so `tearDown` detaches it whatever happens next.
        let points = (try? files.contentsOfDirectory(at: mounts, includingPropertiesForKeys: nil)) ?? []
        mounted += points
        guard attached?.exitCode == 0, points.count == 1 else {
            throw XCTSkip("hdiutil could not attach the \(fileSystem) image.")
        }
        let shoot = points[0].appendingPathComponent("Shoot 1")
        try files.createDirectory(at: shoot, withIntermediateDirectories: false)
        return shoot
    }

    /// The real calls, with a record of each one and of what it answered.
    func recording(_ log: CallLog) -> ExclusiveRename {
        let system = ExclusiveRename.system
        return ExclusiveRename(
            renameExclusive: {
                let code = system.renameExclusive($0, $1)
                log.entries.append("renamex_np \(code)")
                return code
            },
            exists: {
                log.entries.append("check")
                return system.exists($0)
            },
            rename: {
                let code = system.rename($0, $1)
                log.entries.append("rename \(code)")
                return code
            })
    }

    /// A taken name and a free name on one volume.
    ///
    /// - Returns: the calls that each rename made.
    func renameOnce(in shoot: URL) throws -> (taken: [String], free: [String]) {
        let others = Data("another program's DNG".utf8)
        let ours = Data("the new DNG".utf8)

        // The name is taken.
        var work = shoot.appendingPathComponent(".frame 1.desqueeze-work.dng")
        var dng = shoot.appendingPathComponent("frame 1.dng")
        try ours.write(to: work)
        try others.write(to: dng)
        let taken = CallLog()
        XCTAssertEqual(recording(taken).move(work, to: dng), .nameTaken)
        XCTAssertEqual(try Data(contentsOf: dng), others, "the DNG of the other program must not change")
        XCTAssertEqual(try Data(contentsOf: work), ours, "the work file stays")

        // The name is free.
        work = shoot.appendingPathComponent(".frame 2.desqueeze-work.dng")
        dng = shoot.appendingPathComponent("frame 2.dng")
        try ours.write(to: work)
        let free = CallLog()
        XCTAssertEqual(recording(free).move(work, to: dng), .moved)
        XCTAssertEqual(try Data(contentsOf: dng), ours)
        XCTAssertFalse(ConverterOutput.exists(atPath: work.path), "the work file has the new name, and is not a copy")
        return (taken.entries, free.entries)
    }

    func testOnAPFSTheSystemChecksAndRenamesInOneStep() throws {
        let shoot = try volume("APFS", named: "apfs")
        let calls = try renameOnce(in: shoot)
        XCTAssertEqual(calls.taken, ["renamex_np \(EEXIST)"])
        XCTAssertEqual(calls.free, ["renamex_np 0"])
    }

    func testOnExFATAFreeNameTakesTheCheckAndThenAPlainRename() throws {
        let shoot = try volume("ExFAT", named: "exfat")
        let calls = try renameOnce(in: shoot)
        XCTAssertEqual(calls.taken, ["renamex_np \(EEXIST)"])
        XCTAssertEqual(calls.free, ["renamex_np \(ENOTSUP)", "check", "rename 0"])
    }
}
