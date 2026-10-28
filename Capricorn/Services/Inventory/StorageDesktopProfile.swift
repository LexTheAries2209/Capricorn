// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

struct StorageDesktopSocket: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let side: StorageHostPortPosition
    let normalizedPoint: CGPoint

    var port: StorageHostPort { .init(number: 0, socketID: id) }
}

/// Visual socket identities are deliberately separate from macOS built-in port
/// numbers. A user-confirmed association never guesses a registry numbering order.
struct StorageDesktopProfile: Equatable, Sendable {
    enum Family: Sendable { case mini, studio, iMac }
    let family: Family
    let assetName: String
    let artworkFrame: CGRect
    let sockets: [StorageDesktopSocket]

    init?(model: StorageHostModel) {
        let id = model.identifier
        let name = model.productName?.lowercased() ?? ""
        let newMini = ["Mac16,10", "Mac16,11", "Mac17,16", "Mac18,5"].contains(id)
        let oldMini = ["Macmini9,1", "Mac14,3"].contains(id)
        let studio = ["Mac13,1", "Mac13,2", "Mac14,13", "Mac14,14", "Mac15,14", "Mac16,9"].contains(id)
        let iMac = ["iMac21,1", "iMac21,2", "Mac15,4", "Mac15,5", "Mac16,2", "Mac16,3"].contains(id)
        var sockets: [StorageDesktopSocket] = []
        func add(_ socketID: String, _ title: String, _ side: StorageHostPortPosition,
                 _ x: CGFloat, _ y: CGFloat) {
            sockets.append(.init(id: socketID, title: title, side: side,
                                 normalizedPoint: CGPoint(x: x, y: y)))
        }
        if newMini || oldMini {
            family = .mini
            assetName = newMini ? "MacMiniTop" : "MacMiniClassicTop"
            artworkFrame = CGRect(x: 70, y: 4, width: 200, height: 200)
            if newMini {
                // Rear photographs face the opposite direction to a top view:
                // mirror the source X coordinates, keeping the front at the bottom.
                for (index, x) in [1 - 635.0 / 774, 1 - 582.0 / 774, 1 - 529.0 / 774].enumerated() {
                    add("rear-c-\(index)", "后部 USB-C · \(index + 1)", .back, x, 0)
                }
                for (index, x) in [161.0 / 772, 252.0 / 772].enumerated() {
                    add("front-c-\(index)", "前部 USB-C · \(index + 1)", .front, x, 1)
                }
            } else {
                let rearC = [1 - (900.0 - 622) / 574, 1 - (856.0 - 622) / 574]
                for (index, x) in rearC.enumerated() {
                    add("rear-c-\(index)", "后部 USB-C · \(index + 1)", .back, x, 0)
                }
                for (index, x) in [1 - (1112.0 - 622) / 574, 1 - (1059.0 - 622) / 574].enumerated() {
                    add("rear-a-\(index)", "后部 USB-A · \(index + 1)", .back, x, 0)
                }
            }
        } else if studio {
            family = .studio
            assetName = "MacStudioTop"
            artworkFrame = CGRect(x: 70, y: 4, width: 200, height: 200)
            for (index, x) in [274.0, 230, 186, 142].enumerated() {
                add("rear-c-\(index)", "后部 USB-C · \(index + 1)", .back, 1 - x / 904, 0)
            }
            for (index, x) in [605.0, 548].enumerated() {
                add("rear-a-\(index)", "后部 USB-A · \(index + 1)", .back, 1 - x / 904, 0)
            }
            for (index, x) in [149.0, 217].enumerated() {
                add("front-c-\(index)", "前部 USB-C · \(index + 1)", .front, x / 904, 1)
            }
        } else if iMac || name.contains("imac") && name.contains("m6") {
            family = .iMac
            let twoPorts = ["iMac21,2", "Mac15,4", "Mac16,2"].contains(id)
            assetName = twoPorts ? "iMacBackTwoPorts" : "iMacBack"
            artworkFrame = CGRect(x: 48, y: 4, width: 244, height: 205)
            let xs: [CGFloat] = twoPorts ? [64, 73] : [47, 56, 64, 73]
            for (index, x) in xs.enumerated() {
                add("rear-c-\(index)", "后部 USB-C · \(index + 1)", .back, x / 314, 199 / 265)
            }
        } else {
            return nil
        }
        self.sockets = sockets
    }

    func socket(for port: StorageHostPort) -> StorageDesktopSocket? {
        guard let socketID = port.socketID else { return nil }
        return sockets.first { $0.id == socketID }
    }

    func anchor(_ port: StorageHostPort) -> CGPoint? {
        guard let socket = socket(for: port) else { return nil }
        return CGPoint(x: artworkFrame.minX + socket.normalizedPoint.x * artworkFrame.width,
                       y: artworkFrame.minY + socket.normalizedPoint.y * artworkFrame.height)
    }
}
