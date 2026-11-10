import Foundation

/// A published version of the app on GitHub.
public struct AppRelease: Equatable, Sendable {
    /// "1.2.0", without the tag's leading "v".
    public let version: String
    /// The DMG attached to the release.
    public let downloadURL: URL

    public init(version: String, downloadURL: URL) {
        self.version = version
        self.downloadURL = downloadURL
    }

    /// Builds a release from where `https://github.com/<repository>/releases/latest` redirects to
    /// (".../releases/tag/v1.2.0"). Nil when the repository has no release (the redirect then has no tag).
    ///
    /// The redirect is used rather than GitHub's API because the API allows 60 anonymous requests an hour
    /// per IP address, which an office sharing one address exhausts.
    public init?(latestReleasePage page: URL, repository: String, asset: String = "Awaker.dmg") {
        let parts = page.pathComponents
        guard let tagIndex = parts.firstIndex(of: "tag"), tagIndex + 1 < parts.count,
              let download = URL(string: "https://github.com/\(repository)/releases/download/\(parts[tagIndex + 1])/\(asset)") else {
            return nil
        }
        let tag = parts[tagIndex + 1]
        self.init(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, downloadURL: download)
    }

    /// True when this release is strictly newer than `current` ("1.10.0" is newer than "1.9.3").
    public func isNewer(than current: String) -> Bool {
        let mine = Self.components(version), theirs = Self.components(current)
        for index in 0..<max(mine.count, theirs.count) {
            let a = index < mine.count ? mine[index] : 0
            let b = index < theirs.count ? theirs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
