import Foundation
import Testing
@testable import AwakerCore

@Suite struct AppReleaseTests {
    @Test func readsTheVersionFromWhereTheLatestReleasePageLands() throws {
        let page = try #require(URL(string: "https://github.com/o/r/releases/tag/v1.2.0"))
        let release = try #require(AppRelease(latestReleasePage: page, repository: "o/r"))

        #expect(release.version == "1.2.0")
        #expect(release.downloadURL.absoluteString == "https://github.com/o/r/releases/download/v1.2.0/Awaker.dmg")
        #expect(release.pageURL == page)
    }

    @Test func aRepositoryWithoutReleaseGivesNothing() throws {
        let page = try #require(URL(string: "https://github.com/o/r/releases"))
        #expect(AppRelease(latestReleasePage: page, repository: "o/r") == nil)
    }

    @Test func comparesVersionsNumerically() {
        func release(_ version: String) -> AppRelease {
            AppRelease(version: version, downloadURL: URL(string: "https://example.com/a.dmg")!)
        }

        #expect(release("1.10.0").isNewer(than: "1.9.3"))
        #expect(release("2.0").isNewer(than: "1.9.9"))
        #expect(release("1.0.1").isNewer(than: "1.0"))
        #expect(!release("1.0.0").isNewer(than: "1.0.0"))
        #expect(!release("1.0.0").isNewer(than: "1.0.1"))
    }
}
