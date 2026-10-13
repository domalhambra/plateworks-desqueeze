import Foundation
import XCTest

/// The accent and the icon (design 17).
///
/// The color values are those of design 17.1. They come from the Plateworks
/// color standard, which is kept outside this repo, so these tests are the
/// guard against a value that someone changes by hand. Each test reads files
/// of the repo. No test starts the app.
final class AccentAndIconTests: XCTestCase {
    static let root = DocsCheckTests.root
    static let app = root.appendingPathComponent("App/PlateworksDesqueeze")
    static let assets = app.appendingPathComponent("Assets.xcassets")
    static let theme = root.appendingPathComponent("Sources/DesqueezeCore/DesqueezeCore.docc/theme-settings.json")

    /// The Chalcanthite family of design 17.1, and the two colors of a label
    /// on a fill. The site may use these values and no other.
    static let family: Set<String> = [
        "#00688F", "#65B4DD",   // ink
        "#157BA6", "#4595BC",   // fill
        "#004C6A", "#7DCDF7",   // hover
        "#D7E4EC", "#2F3D44",   // wash
        "#FFFFFF", "#020306",   // on a fill
    ]

    // MARK: The window

    // One value in both appearances: the light fill (design 17.1). The app
    // names `Chalcanthite`, and macOS reads `AccentColor`. The two must be
    // equal, and neither has a second value for the dark appearance.
    func testTheTwoColorAssetsHoldTheLightFillAndNoOtherValue() throws {
        for name in ["Chalcanthite", "AccentColor"] {
            let file = Self.assets.appendingPathComponent("\(name).colorset/Contents.json")
            let colors = try Self.colors(ofColorSet: file)
            XCTAssertEqual(colors.count, 1, "\(name) must have one value, for both appearances")
            XCTAssertEqual(colors.first, AssetColor(space: "srgb", hex: "#157BA6", alpha: 1, appearances: 0),
                           "\(name) must be the Chalcanthite fill of design 17.1")
        }
    }

    // macOS uses `AccentColor` only on a Mac whose accent is Multicolor
    // (design 17.1). So the window sets the tint itself, and no view asks
    // for the accent of the Mac. The tint is in the content view, before
    // `onAppear` (design 17.2): on the view in `DesqueezeApp`, the window
    // opened with the custom factor selected.
    func testTheWindowSetsTheTintAndNoViewAsksForTheAccentOfTheMac() throws {
        let view = try Self.code(Self.app.appendingPathComponent("ContentView.swift"))
        let tint = try XCTUnwrap(view.range(of: ".tint(Color.chalcanthite)"),
                                 "the content view in ContentView.swift must have .tint(Color.chalcanthite)")
        let appear = try XCTUnwrap(view.range(of: ".onAppear"))
        XCTAssertLessThan(tint.lowerBound, appear.lowerBound, "the tint must come before onAppear")
        let entry = try Self.code(Self.app.appendingPathComponent("DesqueezeApp.swift"))
        XCTAssertFalse(entry.contains(".tint("), "the tint is in ContentView.swift, and not in DesqueezeApp.swift")

        let files = try FileManager.default.contentsOfDirectory(at: Self.app, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let code = try Self.code(file)
            XCTAssertFalse(code.contains("accentColor"),
                           "\(file.lastPathComponent) asks for the accent of the Mac. Use Color.chalcanthite.")
        }
    }

    func testTheProjectNamesTheAccentAndTheIcon() throws {
        let project = try String(contentsOf: Self.root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor"))
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))
    }

    // MARK: The site

    // The theme file of the site holds colors only (design 17.1). A font or
    // an address in it would make the site load a file, and the privacy
    // page says that it loads none from another host.
    func testTheThemeOfTheSiteHoldsColorsOfTheFamilyOnly() throws {
        let data = try Data(contentsOf: Self.theme)
        let findings = try Self.findings(inTheme: data)
        XCTAssertEqual(findings, [], "theme-settings.json: \(findings.joined(separator: "; "))")
    }

    // The reader itself, against one break of each kind.
    func testTheThemeReaderFailsForAFontAnAddressAndAForeignColor() throws {
        func findings(_ json: String) throws -> [String] { try Self.findings(inTheme: Data(json.utf8)) }

        XCTAssertEqual(try findings(##"{"theme":{"color":{"link":{"light":"#00688F","dark":"#65B4DD"}}}}"##), [])
        XCTAssertEqual(try findings(##"{"theme":{"color":{"button-text":"#FFFFFF"}}}"##), [])

        XCTAssertFalse(try findings(##"{"theme":{"typography":{"html-font":"serif"}}}"##).isEmpty, "a font")
        XCTAssertFalse(try findings(##"{"theme":{"color":{"link":"#00688F"},"typography":{}}}"##).isEmpty, "a font key with no value")
        XCTAssertFalse(try findings(##"{"theme":{"color":{"html-font":"#00688F"}}}"##).isEmpty, "a key that names a font")
        XCTAssertFalse(try findings(##"{"theme":{"color":{"link":"url(https://example.com/a.png)"}}}"##).isEmpty, "an address")
        XCTAssertFalse(try findings(##"{"theme":{"color":{"link":"//example.com"}}}"##).isEmpty, "an address with no scheme")
        XCTAssertFalse(try findings(##"{"theme":{"color":{"link":"#0066FF"}}}"##).isEmpty, "a color of another family")
        XCTAssertFalse(try findings(##"{"theme":{"color":{"link":"#00688f"}}}"##).isEmpty, "small letters")
        XCTAssertFalse(try findings(##"{"theme":{"color":{"link":{"light":"#00688F","sepia":"#65B4DD"}}}}"##).isEmpty, "a third appearance")
        XCTAssertFalse(try findings(##"{"theme":{"color":{}}}"##).isEmpty, "no color")
        XCTAssertFalse(try findings(##"{"meta":{},"theme":{"color":{"link":"#00688F"}}}"##).isEmpty, "a second key at the top")
        XCTAssertFalse(try findings(##"{"theme":{"color":{"link":7}}}"##).isEmpty, "a number")
    }

    // MARK: The icon

    // Each slot of the icon set has its file, at its size in pixels (design
    // 17.3). `scripts/make_app_icon.py` writes them.
    func testEachSlotOfTheIconSetHasAFileOfItsSize() throws {
        let set = Self.assets.appendingPathComponent("AppIcon.appiconset")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: set.appendingPathComponent("Contents.json")))
        let images = try XCTUnwrap((json as? [String: Any])?["images"] as? [[String: String]])

        var slots = Set<String>()
        for image in images {
            let size = try XCTUnwrap(image["size"]), scale = try XCTUnwrap(image["scale"])
            let name = try XCTUnwrap(image["filename"], "the slot \(size) \(scale) has no file")
            XCTAssertEqual(image["idiom"], "mac")
            slots.insert("\(size) \(scale)")

            let points = try XCTUnwrap(Int(size.components(separatedBy: "x")[0]))
            let factor = try XCTUnwrap(Int(scale.dropLast()))
            let png = try Data(contentsOf: set.appendingPathComponent(name))
            let pixels = try XCTUnwrap(Self.pixelSize(ofPNG: png), "\(name) is no PNG")
            XCTAssertEqual(pixels.width, points * factor, "the width of \(name)")
            XCTAssertEqual(pixels.height, points * factor, "the height of \(name)")
        }
        let expected = Set([16, 32, 128, 256, 512].flatMap { ["\($0)x\($0) 1x", "\($0)x\($0) 2x"] })
        XCTAssertEqual(slots, expected)
        XCTAssertEqual(images.count, expected.count, "a slot is there two times")
    }

    func testThePNGReaderGivesTheSizeAndRefusesOtherData() {
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
        png.append(contentsOf: Array("IHDR".utf8))
        png.append(contentsOf: [0, 0, 4, 0, 0, 0, 2, 0, 8, 6, 0, 0, 0])
        XCTAssertEqual(Self.pixelSize(ofPNG: png)?.width, 1024)
        XCTAssertEqual(Self.pixelSize(ofPNG: png)?.height, 512)
        XCTAssertNil(Self.pixelSize(ofPNG: Data("<svg/>".utf8)))
        XCTAssertNil(Self.pixelSize(ofPNG: Data()))
    }

    // MARK: Readers

    struct AssetColor: Equatable {
        let space: String
        let hex: String
        let alpha: Double
        /// The count of appearance rules of the entry. An entry for the dark
        /// appearance has one.
        let appearances: Int
    }

    static func colors(ofColorSet file: URL) throws -> [AssetColor] {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let entries = try XCTUnwrap(json?["colors"] as? [[String: Any]])
        return try entries.map { entry in
            let color = try XCTUnwrap(entry["color"] as? [String: Any])
            let parts = try XCTUnwrap(color["components"] as? [String: String])
            func byte(_ key: String) throws -> String {
                let value = try XCTUnwrap(parts[key])
                XCTAssertTrue(value.hasPrefix("0x") && value.count == 4, "\(key) must be a byte in the form 0x15")
                return String(value.dropFirst(2)).uppercased()
            }
            return AssetColor(space: try XCTUnwrap(color["color-space"] as? String),
                              hex: "#" + (try byte("red")) + (try byte("green")) + (try byte("blue")),
                              alpha: try XCTUnwrap(Double(try XCTUnwrap(parts["alpha"]))),
                              appearances: (entry["appearances"] as? [Any])?.count ?? 0)
        }
    }

    /// A Swift file with no line comments, so a comment can name a thing
    /// that the code must not use.
    static func code(_ file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
            .components(separatedBy: "\n")
            .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line }
            .joined(separator: "\n")
    }

    /// What is wrong with a theme file. An empty list is a pass.
    static func findings(inTheme data: Data) throws -> [String] {
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ["it is no object"] }
        var findings: [String] = []
        if Set(top.keys) != ["theme"] { findings.append("the top must hold the key theme only, and it holds \(top.keys.sorted())") }
        guard let theme = top["theme"] as? [String: Any] else { return findings + ["it has no theme"] }
        if Set(theme.keys) != ["color"] { findings.append("the theme must hold the key color only, and it holds \(theme.keys.sorted())") }
        guard let colors = theme["color"] as? [String: Any], !colors.isEmpty else { return findings + ["it has no color"] }

        func judge(_ value: Any, at key: String) {
            guard let text = value as? String else { findings.append("\(key) is no text"); return }
            if !family.contains(text) { findings.append("\(key) is \(text), which is no value of design 17.1") }
        }
        for (key, value) in colors.sorted(by: { $0.key < $1.key }) {
            if key.contains("font") || key.contains("url") { findings.append("the key \(key) names a font or an address") }
            if let pair = value as? [String: Any] {
                if Set(pair.keys) != ["light", "dark"] { findings.append("\(key) must hold light and dark, and it holds \(pair.keys.sorted())") }
                for (mode, inner) in pair.sorted(by: { $0.key < $1.key }) { judge(inner, at: "\(key).\(mode)") }
            } else {
                judge(value, at: key)
            }
        }
        return findings
    }

    /// The width and the height that the header of a PNG states.
    static func pixelSize(ofPNG data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 24, Array(bytes[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
              Array(bytes[12..<16]) == Array("IHDR".utf8) else { return nil }
        func number(_ start: Int) -> Int { bytes[start..<start + 4].reduce(0) { $0 << 8 | Int($1) } }
        return (number(16), number(20))
    }
}
