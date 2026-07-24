import Foundation
import Testing
@testable import HeyCodex

@Suite("App version comparison")
struct AppVersionTests {
    @Test func newerCoreVersionsWin() {
        #expect(AppVersion.isNewer("v0.2.0", than: "0.1.0"))
        #expect(AppVersion.isNewer("1.0.0", than: "0.9.9"))
        #expect(!AppVersion.isNewer("0.1.0", than: "0.1.0"))
        #expect(!AppVersion.isNewer("0.1.0", than: "0.2.0"))
    }

    @Test func releaseBeatsItsOwnPrerelease() {
        #expect(AppVersion.isNewer("0.1.0", than: "0.1.0-test.2"))
        #expect(!AppVersion.isNewer("0.1.0-test.2", than: "0.1.0"))
    }

    @Test func prereleaseNumbersCompareNumerically() {
        #expect(AppVersion.isNewer("0.1.0-test.10", than: "0.1.0-test.2"))
        #expect(!AppVersion.isNewer("0.1.0-test.2", than: "0.1.0-test.10"))
    }

    @Test func leadingTagPrefixAndWhitespaceAreIgnored() {
        #expect(AppVersion.isNewer(" v0.1.1 ", than: "v0.1.0"))
    }
}

@Suite("Latest release picking")
struct LatestReleasePickerTests {
    @Test func picksTheHighestVersionIncludingPrereleases() {
        let releases = [
            ReleaseSummary(tagName: "v0.1.0-test.9", draft: false, prerelease: true),
            ReleaseSummary(tagName: "v0.1.0-test.10", draft: false, prerelease: true),
            ReleaseSummary(tagName: "v0.1.0-test.8", draft: false, prerelease: true),
        ]
        #expect(
            LatestReleasePicker.pick(from: releases, includePrereleases: true)
                == "v0.1.0-test.10"
        )
    }

    @Test func ignoresDraftReleases() {
        let releases = [
            ReleaseSummary(tagName: "v9.9.9", draft: true, prerelease: false),
            ReleaseSummary(tagName: "v0.1.0-test.10", draft: false, prerelease: true),
        ]
        #expect(
            LatestReleasePicker.pick(from: releases, includePrereleases: true)
                == "v0.1.0-test.10"
        )
    }

    @Test func stableChannelIgnoresPrereleases() {
        let releases = [
            ReleaseSummary(tagName: "v1.1.0-test.1", draft: false, prerelease: true),
            ReleaseSummary(tagName: "v1.0.1", draft: false, prerelease: false),
        ]
        #expect(LatestReleasePicker.pick(from: releases) == "v1.0.1")
    }

    @Test func returnsNilWhenThereIsNothingToPick() {
        #expect(LatestReleasePicker.pick(from: []) == nil)
    }

    @Test func decodesTheGitHubListPayload() throws {
        let json = Data("""
        [{"tag_name": "v0.1.0-test.10", "draft": false, "prerelease": true, "name": "x"}]
        """.utf8)
        let releases = try JSONDecoder().decode([ReleaseSummary].self, from: json)
        #expect(releases == [
            ReleaseSummary(tagName: "v0.1.0-test.10", draft: false, prerelease: true)
        ])
    }
}
