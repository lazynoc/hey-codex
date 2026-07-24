import Foundation
import Observation

enum AppVersion {
    static func isNewer(_ remote: String, than current: String) -> Bool {
        compare(parse(remote), parse(current)) == .orderedDescending
    }

    private struct Parsed {
        var core: [Int]
        var prerelease: [String]
    }

    private static func parse(_ version: String) -> Parsed {
        var cleaned = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned = String(cleaned.dropFirst())
        }

        let parts = cleaned.split(separator: "-", maxSplits: 1)
        let core = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        let prerelease = parts.count > 1
            ? parts[1].split(separator: ".").map(String.init)
            : []
        return Parsed(core: core, prerelease: prerelease)
    }

    private static func compare(_ lhs: Parsed, _ rhs: Parsed) -> ComparisonResult {
        for index in 0..<max(lhs.core.count, rhs.core.count) {
            let left = index < lhs.core.count ? lhs.core[index] : 0
            let right = index < rhs.core.count ? rhs.core[index] : 0
            if left != right {
                return left > right ? .orderedDescending : .orderedAscending
            }
        }

        // Equal cores: a release outranks any of its prereleases.
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): break
        }

        for index in 0..<max(lhs.prerelease.count, rhs.prerelease.count) {
            guard index < lhs.prerelease.count else { return .orderedAscending }
            guard index < rhs.prerelease.count else { return .orderedDescending }
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }
            if let leftNumber = Int(left), let rightNumber = Int(right) {
                return leftNumber > rightNumber ? .orderedDescending : .orderedAscending
            }
            return left > right ? .orderedDescending : .orderedAscending
        }
        return .orderedSame
    }
}

@MainActor
@Observable
final class UpdateModel {
    enum Status: Equatable {
        case unknown
        case checking
        case upToDate
        case available(String)
        case failed
    }

    private(set) var status: Status = .unknown

    // The list endpoint lets prerelease builds follow newer test builds
    // while stable builds remain on the stable release channel.
    static let releaseURL = URL(
        string: "https://api.github.com/repos/lazynoc/hey-codex/releases?per_page=20"
    )!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func check() async {
        status = .checking

        var request = URLRequest(url: Self.releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let statusCode = (response as? HTTPURLResponse)?.statusCode
        else {
            status = .failed
            return
        }

        guard statusCode == 200,
              let releases = try? JSONDecoder().decode([ReleaseSummary].self, from: data),
              let newest = LatestReleasePicker.pick(
                  from: releases,
                  includePrereleases: currentVersion.contains("-")
              )
        else {
            status = .failed
            return
        }

        status = AppVersion.isNewer(newest, than: currentVersion)
            ? .available(newest)
            : .upToDate
    }
}

struct ReleaseSummary: Decodable, Equatable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
    }
}

enum LatestReleasePicker {
    nonisolated static func pick(
        from releases: [ReleaseSummary],
        includePrereleases: Bool = false
    ) -> String? {
        releases
            .filter { !$0.draft && (includePrereleases || !$0.prerelease) }
            .map(\.tagName)
            .max { AppVersion.isNewer($1, than: $0) }
    }
}
