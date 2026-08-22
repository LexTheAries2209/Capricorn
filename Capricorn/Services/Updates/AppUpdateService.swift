// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation

struct AppVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    init(_ value: String) {
        let numbers = value
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        components = numbers.isEmpty ? [0] : numbers
    }

    init(marketingVersion: String, build: String?) {
        let marketingComponents = marketingVersion
            .split(separator: ".")
            .compactMap { Int($0) }
        let buildComponents = build?.split(separator: ".").compactMap { Int($0) } ?? []
        let resolvedComponents = marketingComponents + buildComponents
        components = resolvedComponents.isEmpty ? [0] : resolvedComponents
    }

    static var current: AppVersion {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return AppVersion(marketingVersion: marketing, build: build)
    }

    var displayValue: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

struct AppUpdateRelease: Equatable, Sendable {
    var tagName: String
    var name: String
    var version: AppVersion
    var htmlURL: URL
    var body: String
}

enum AppUpdateCheckState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case updateAvailable(AppUpdateRelease)
    case failed
}

protocol AppUpdateReleaseFetching: Sendable {
    func latestRelease() async throws -> AppUpdateRelease
}

struct GitHubReleaseService: AppUpdateReleaseFetching, Sendable {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/LexTheAries2209/Capricorn/releases/latest")!
    static let releasesURL = URL(string: "https://github.com/LexTheAries2209/Capricorn/releases")!

    private let session: URLSession
    private let endpoint: URL

    init(session: URLSession = .shared, endpoint: URL = GitHubReleaseService.latestReleaseURL) {
        self.session = session
        self.endpoint = endpoint
    }

    func latestRelease() async throws -> AppUpdateRelease {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Capricorn", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.parseRelease(data: data)
    }

    static func parseRelease(data: Data) throws -> AppUpdateRelease {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard !payload.draft, !payload.prerelease else {
            throw URLError(.resourceUnavailable)
        }
        return AppUpdateRelease(
            tagName: payload.tagName,
            name: payload.name?.isEmpty == false ? payload.name! : payload.tagName,
            version: AppVersion(payload.tagName),
            htmlURL: payload.htmlURL,
            body: payload.body ?? ""
        )
    }

    private struct Payload: Decodable {
        var tagName: String
        var name: String?
        var htmlURL: URL
        var body: String?
        var draft: Bool
        var prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case body
            case draft
            case prerelease
        }
    }
}

@MainActor
@Observable
final class AppUpdateChecker {
    var state: AppUpdateCheckState = .idle
    var lastCheckedAt: Date?

    let currentVersion: AppVersion
    private let fetchLatest: @Sendable () async throws -> AppUpdateRelease
    private var hasAttemptedLaunchCheck = false

    init(
        currentVersion: AppVersion = .current,
        fetchLatest: @escaping @Sendable () async throws -> AppUpdateRelease = {
            try await GitHubReleaseService().latestRelease()
        }
    ) {
        self.currentVersion = currentVersion
        self.fetchLatest = fetchLatest
    }

    func checkNow() async {
        state = .checking
        do {
            let release = try await fetchLatest()
            guard !Task.isCancelled else { return }
            lastCheckedAt = Date()
            state = release.version > currentVersion ? .updateAvailable(release) : .upToDate
        } catch {
            guard !Task.isCancelled else { return }
            lastCheckedAt = Date()
            state = .failed
        }
    }

    func checkQuietlyAtLaunch() async {
        guard !hasAttemptedLaunchCheck else { return }
        hasAttemptedLaunchCheck = true
        await checkNow()
    }
}
