#!/usr/bin/env swift
// SPDX-License-Identifier: GPL-3.0-only
import Foundation

final class UpdateNetworkProbe: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for transaction in metrics.transactionMetrics {
            let host = transaction.request.url?.host ?? "unknown"
            print("  host=\(host) proxy=\(transaction.isProxyConnection)")
        }
    }
}

let arguments = CommandLine.arguments.dropFirst()
let urls = arguments.compactMap { value -> URL? in
    guard let url = URL(string: value), url.host != nil,
          ["https", "http"].contains(url.scheme ?? ""),
          url.user == nil, url.password == nil else { return nil }
    return url
}
guard !urls.isEmpty, urls.count == arguments.count else {
    print("Usage: xcrun swift scripts/diagnose-update-network.swift <http(s)-url> [...]")
    exit(2)
}

Task {
    var failed = false
    for url in urls {
        print("Checking \(url.host ?? "unknown") with macOS system proxy settings")
        // Match Sparkle's session configuration. A nil proxy dictionary uses system policy.
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: UpdateNetworkProbe(), delegateQueue: nil)
        do {
            let (_, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("  HTTP \(status)")
            if !(200..<300).contains(status) { failed = true }
        } catch {
            let error = error as NSError
            print("  error=\(error.domain) code=\(error.code)")
            failed = true
        }
        session.finishTasksAndInvalidate()
    }
    exit(failed ? 1 : 0)
}
dispatchMain()
