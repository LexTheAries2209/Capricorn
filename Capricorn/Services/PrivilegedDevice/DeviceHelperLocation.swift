// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum DeviceHelperLocation {
    static let unsuitableMessage = "Move Capricorn to a permanent folder on a local writable disk before enabling the device service."

    static func validate(_ app: URL) throws {
        let canonical = app.resolvingSymlinksInPath()
        let volume = try canonical.resourceValues(forKeys: [
            .volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeIsRemovableKey, .volumeIsEjectableKey
        ])
        try validate(path: canonical.path, isLocal: volume.volumeIsLocal == true,
                     isReadOnly: volume.volumeIsReadOnly != false,
                     isRemovable: volume.volumeIsRemovable != false || volume.volumeIsEjectable != false)
    }

    static func validate(path: String, isLocal: Bool, isReadOnly: Bool, isRemovable: Bool) throws {
        let temporaryRoots = ["/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp",
                              "/var/folders", "/private/var/folders"]
        let isTemporary = temporaryRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
        guard isLocal, !isReadOnly, !isRemovable, !isTemporary,
              !path.split(separator: "/").contains("AppTranslocation"),
              URL(fileURLWithPath: path).pathExtension == "app" else {
            throw DeviceHelperError.rejected(unsuitableMessage)
        }
    }
}
