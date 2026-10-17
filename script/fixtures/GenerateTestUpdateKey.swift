// SPDX-License-Identifier: GPL-3.0-only
import CryptoKit
import Foundation

let path = CommandLine.arguments[1]
let key = Curve25519.Signing.PrivateKey()
FileManager.default.createFile(
    atPath: path, contents: nil,
    attributes: [.posixPermissions: 0o600]
)
try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: URL(fileURLWithPath: path))
print(key.publicKey.rawRepresentation.base64EncodedString())
