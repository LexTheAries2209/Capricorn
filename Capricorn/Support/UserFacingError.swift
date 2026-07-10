// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum UserFacingError {
    static func message(_ prefix: String, error: Error) -> String {
        let error = error as NSError
        return "\(prefix) (\(error.domain) \(error.code))"
    }
}
