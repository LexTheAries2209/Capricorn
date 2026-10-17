// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct AppUpdateConfiguration: Equatable, Sendable {
    let feedURL: URL
    let publicKey: String

    init(info: [String: Any], allowsLocalTestFeed: Bool = false) throws {
        guard let value = info["SUFeedURL"] as? String,
              let url = URL(string: value), url.host != nil,
              url.user == nil, url.password == nil,
              url.scheme == "https" || (
                allowsLocalTestFeed && url.scheme == "http"
                    && ["127.0.0.1", "localhost"].contains(url.host ?? "")
              ),
              let publicKey = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: publicKey)?.count == 32 else {
            throw CocoaError(.coderInvalidValue)
        }
        feedURL = url
        self.publicKey = publicKey
    }
}

enum AppUpdateIssue: String, Equatable, Sendable {
    case configuration = "Automatic updates are not configured correctly. Open Releases to download manually."
    case network = "The update server could not be reached. Check your connection and try again."
    case feed = "The update channel is unavailable or invalid. Retry later or open Releases."
    case signature = "The update signature could not be verified. The update was blocked."
    case installation = "The update could not be installed. Check application permissions or download it from Releases."
    case save = "History could not be saved. The update was blocked. Resolve the save error and try again."
}

enum AppUpdaterState: Equatable {
    case idle
    case checking
    case upToDate
    case available(String)
    case downloading
    case extracting
    case readyToInstall
    case installing
    case blocked([AppUpdateConflict])
    case failed(AppUpdateIssue)
}
