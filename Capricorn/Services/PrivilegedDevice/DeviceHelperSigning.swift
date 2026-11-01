// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security
import MachO

enum DeviceHelperSigning {
    static func isInternalSnapshotLink(_ entry: URL, snapshot: URL) -> Bool {
        let root = snapshot.resolvingSymlinksInPath().path
        return entry.resolvingSymlinksInPath().path.hasPrefix(root + "/")
    }

    static func containingApp() throws -> URL {
        // launchd may supply a bundle-relative argv[0]. Resolve the loaded
        // image through dyld rather than interpreting it against launchd's cwd.
        var size: UInt32 = 4096
        var path = [CChar](repeating: 0, count: Int(size))
        if _NSGetExecutablePath(&path, &size) != 0 {
            path = [CChar](repeating: 0, count: Int(size))
            guard _NSGetExecutablePath(&path, &size) == 0 else {
                throw DeviceHelperError.rejected("Unable to locate the loaded device service executable.")
            }
        }
        return try containingApp(executableURL: URL(fileURLWithPath: String(cString: path)))
    }

    static func containingApp(executableURL: URL) throws -> URL {
        let executable = executableURL.resolvingSymlinksInPath()
        let directory = executable.deletingLastPathComponent()
        let contents = directory.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard directory.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents",
              app.pathExtension == "app" else {
            throw DeviceHelperError.rejected("The device service must be embedded in a signed application.")
        }
        return app
    }

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
