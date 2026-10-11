import Foundation

/// Where exiftool and dnglab are inside the app's bundle (design 15.3).
///
/// The downloaded app has the two programs at these places.
/// `scripts/make_release.sh` puts them there. A build from source has no
/// file there, and the window then finds the programs on the Mac, as
/// before. `AppModel.live` gives the two places to `ToolLocator`, so the
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
