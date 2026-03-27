import Darwin
import Foundation
import Libbox

public enum GitHubUpdateChecker {
    private static let releasesURL = "https://api.github.com/repos/SagerNet/sing-box/releases"
    private static let releasesPerPage = 100
    private static let minimumSemver = "0.0.0-0"

    public static func checkAsync(track: UpdateTrack, force: Bool = false) async throws -> UpdateInfo? {
        try await BlockingIO.run {
            try check(track: track, force: force)
        }
    }

    public static func check(track: UpdateTrack, force: Bool = false) throws -> UpdateInfo? {
        let client = HTTPClient()
        guard let releases = try fetchReleases(client: client, track: track) else {
            return nil
        }
        let currentVersion = Bundle.main.version

        var bestRelease: GitHubRelease?
        var bestVersion: String?
        var bestAsset: GitHubAsset?

        for release in releases {
            if release.draft { continue }
            if track == .stable, release.prerelease { continue }
            guard let pkgAsset = findPKGAsset(in: release.assets) else { continue }

            let version = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            guard shouldIncludeRelease(
                version: version,
                currentVersion: currentVersion,
                track: track,
                force: force
            ) else { continue }

            if let best = bestVersion {
                guard LibboxCompareSemver(version, best) else { continue }
            }

            bestRelease = release
            bestVersion = version
            bestAsset = pkgAsset
        }

        guard let release = bestRelease,
              let version = bestVersion,
              let pkgAsset = bestAsset
        else {
            return nil
        }

        return UpdateInfo(
            versionName: version,
            releaseURL: release.htmlURL,
            downloadURL: pkgAsset.browserDownloadURL,
            releaseNotes: release.body,
            isPrerelease: release.prerelease,
            fileSize: pkgAsset.size
        )
    }

    private static func findPKGAsset(in assets: [GitHubAsset]) -> GitHubAsset? {
        let pkgAssets = assets.filter { $0.name.hasSuffix(".pkg") }

        let preferred = preferredPKGVariant()

        if let match = pkgAssets.first(where: { $0.name.contains(preferred) }) {
            return match
        }
        if let universal = pkgAssets.first(where: { $0.name.contains("Universal") }) {
            return universal
        }
        return pkgAssets.first
    }

    private static func preferredPKGVariant() -> String {
        if let hostSupportsArm64 = hostSupportsArm64() {
            return hostSupportsArm64 ? "Apple" : "Intel"
        }

        #if arch(arm64)
            return "Apple"
        #else
            return "Intel"
        #endif
    }

    private static func hostSupportsArm64() -> Bool? {
        var value: Int32 = 0
        var size = MemoryLayout.size(ofValue: value)
        let result = withUnsafeMutablePointer(to: &value) {
            sysctlbyname("hw.optional.arm64", $0, &size, nil, 0)
        }
        guard result == 0 else {
            return nil
        }
        return value != 0
    }

    private static func shouldIncludeRelease(
        version: String,
        currentVersion: String,
        track: UpdateTrack,
        force: Bool
    ) -> Bool {
        guard isValidSemver(version) else {
            return false
        }
        if force || LibboxCompareSemver(version, currentVersion) {
            return true
        }
        return track == .stable && isValidPrereleaseSemver(currentVersion)
    }

    private static func isValidSemver(_ version: String) -> Bool {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedVersion == minimumSemver || LibboxCompareSemver(trimmedVersion, minimumSemver)
    }

    private static func isValidPrereleaseSemver(_ version: String) -> Bool {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedVersion.contains("-") && isValidSemver(trimmedVersion)
    }

    private static func fetchReleases(client: HTTPClient, track: UpdateTrack) throws -> [GitHubRelease]? {
        var allReleases: [GitHubRelease] = []
        var page = 1

        while true {
            let releasesJSON = try client.getString("\(releasesURL)?per_page=\(releasesPerPage)&page=\(page)")
            guard let data = releasesJSON.data(using: .utf8) else {
                return nil
            }

            let pageReleases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            allReleases.append(contentsOf: pageReleases)

            if track != .stable || pageReleases.count < releasesPerPage {
                return allReleases
            }
            page += 1
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let size: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}
