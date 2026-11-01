// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security

enum DeviceHelperSigning {
    static func ownTeam() throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
            throw DeviceHelperError.rejected("The device service requires a certificate-backed application signature.")
        }
        return team
    }

    static func requirement(identifier: String, team: String) -> String {
        #"anchor apple generic and certificate leaf[subject.OU] = "\#(team)" and identifier "\#(identifier)""#
    }

    static func verify(url: URL, identifier: String, team: String, nested: Bool = false) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures
                               | (nested ? kSecCSCheckNestedCode : 0))
        guard SecRequirementCreateWithString(Self.requirement(identifier: identifier, team: team) as CFString,
                                             [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw DeviceHelperError.rejected("The device service rejected an invalid or mismatched code signature.")
        }
    }
}
