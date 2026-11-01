// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

// Compile outside the app and sign with a DIFFERENT identifier. A successful
// version reply is a test failure; this probe never sends a device request.
@objc protocol DeviceHelperXPC {
    func version(reply: @escaping (Int) -> Void)
}

let connection = NSXPCConnection(machServiceName: "lex.Capricorn.DeviceHelper", options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: DeviceHelperXPC.self)
connection.invalidationHandler = {
    print("DEVICE_HELPER_UNTRUSTED rejected: XPC connection invalidated")
    exit(0)
}
connection.interruptionHandler = {
    print("DEVICE_HELPER_UNTRUSTED rejected: XPC connection interrupted")
    exit(0)
}
connection.activate()
let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    print("DEVICE_HELPER_UNTRUSTED rejected: \(error.localizedDescription)")
    exit(0)
} as! DeviceHelperXPC
proxy.version { version in
    print("DEVICE_HELPER_UNTRUSTED FAILURE: unauthorized client received version \(version)")
    exit(1)
}
DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
    print("DEVICE_HELPER_UNTRUSTED inconclusive: no explicit rejection received")
    exit(2)
}
RunLoop.current.run()
