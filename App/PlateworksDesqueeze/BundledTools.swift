import DesqueezeCore
import Foundation

/// Where exiftool and dnglab are inside the app's bundle (design 15.3).
///
/// The downloaded app has the two programs at these places.
/// `scripts/make_release.sh` puts them there. A build from source has no
/// file there, and the window then finds the programs on the Mac, as
/// before. `WindowTools.find` gives the two places to `ToolLocator`, so the
/// core holds no path of the bundle.
///
/// A value type with no file work, so a unit test can check the places.
struct BundledTools: Equatable {
    /// `Contents/Resources/exiftool/exiftool`. exiftool is a script, and its
    /// `lib` folder is beside it. A script goes in `Contents/Resources`.
    let exiftool: URL
    /// `Contents/Helpers/dnglab`. dnglab is a Mach-O program. The code
    /// signature of a bundle needs such a program in `Contents/Helpers`.
    let dnglab: URL

    /// - Parameter bundle: the URL of the app, `Bundle.main.bundleURL`.
    init(bundle: URL) {
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        exiftool = contents.appendingPathComponent("Resources/exiftool/exiftool", isDirectory: false)
        dnglab = contents.appendingPathComponent("Helpers/dnglab", isDirectory: false)
    }
}

/// The three programs as the window uses them. Each one is nil when the
/// window cannot use it: it is not there, or a launch hook hides it.
struct WindowTools: Equatable {
    let exiftool: URL?
    let dnglab: URL?
    let adobe: URL?

    /// Finds the three programs for the window. This is the one way from
    /// the URL of the bundle and the launch options to the three programs:
    /// `AppModel.live` calls it, and so do the tests. Nothing has a
    /// default, so no caller leaves the bundle or a hook out.
    ///
    /// exiftool and dnglab come from inside the bundle first, because the
    /// versions there are the tested ones (design 15.4). An app that is
    /// built from source has no file at the two places, so it finds the
    /// programs on the Mac. A launch hook hides a program wherever it is,
    /// also a copy inside the bundle.
    ///
    /// - Parameters:
    ///   - bundle: the URL of the app, `Bundle.main.bundleURL`.
    ///   - options: the launch hooks.
    ///   - registeredConverterApp: the app that Launch Services names for
    ///     Adobe DNG Converter. Nil when it names none.
    ///   - pathVariable: the value of `PATH`.
    ///   - isExecutable: true when the file at a path can be run.
    static func find(
        bundle: URL, options: LaunchOptions, registeredConverterApp: URL?, pathVariable: String?,
        isExecutable: @escaping @Sendable (String) -> Bool
    ) -> WindowTools {
        let inside = BundledTools(bundle: bundle)
        let locator = ToolLocator(
            pathVariable: pathVariable, registeredConverterApp: registeredConverterApp,
            bundledExiftool: inside.exiftool, bundledDnglab: inside.dnglab, isExecutable: isExecutable)
        return WindowTools(
            exiftool: options.hidesExiftool ? nil : locator.exiftool(),
            dnglab: options.hidesDnglab ? nil : locator.dnglab(),
            adobe: options.hidesAdobe ? nil : locator.dngConverter())
    }
}
