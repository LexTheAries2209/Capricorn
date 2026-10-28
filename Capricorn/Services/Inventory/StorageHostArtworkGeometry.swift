// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

/// Apple's keyboard views share the 2021/2023 chassis. Keep artwork placement
/// and socket projection together so graph wires cannot drift from the markers.
enum StorageHostTopView {
    case macBookPro14, macBookPro16

    init?(identifier: String) {
        switch identifier {
        case "MacBookPro18,3", "MacBookPro18,4", "Mac14,5", "Mac14,9":
            self = .macBookPro14
        case "MacBookPro18,1", "MacBookPro18,2", "Mac14,6", "Mac14,10":
            self = .macBookPro16
        default:
            return nil
        }
    }

    var assetName: String {
        self == .macBookPro14 ? "MacBookPro14Top2023" : "MacBookPro16Top2023"
    }

    private var sourceBounds: CGRect {
        self == .macBookPro14
            ? CGRect(x: 96, y: 225, width: 809, height: 479)
            : CGRect(x: 54, y: 196, width: 893, height: 535)
    }

    private var chassis: CGRect {
        self == .macBookPro14
            ? CGRect(x: 171, y: 238, width: 658, height: 466)
            : CGRect(x: 127, y: 209, width: 747, height: 522)
    }

    func anchor(_ port: StorageHostPort) -> CGPoint? {
        guard (1...3).contains(port.number) else { return nil }
        // On the 2021 chassis, sockets 1 and 3 share the keyboard number row;
        // socket 2 aligns with QWER. Use one Y value for both rear sockets.
        let numberRowY: CGFloat = self == .macBookPro14 ? 336 : 324
        let qwertyRowY: CGFloat = self == .macBookPro14 ? 376 : 364
        let source = CGPoint(x: port.number == 3 ? chassis.maxX : chassis.minX,
                             y: port.number == 2 ? qwertyRowY : numberRowY)
        let frame = StorageHostArtworkGeometry.imageFrame
        let scale = min(frame.width / sourceBounds.width, frame.height / sourceBounds.height)
        let inset = CGPoint(x: (frame.width - sourceBounds.width * scale) / 2,
                            y: (frame.height - sourceBounds.height * scale) / 2)
        return CGPoint(x: frame.minX + inset.x + (source.x - sourceBounds.minX) * scale,
                       y: frame.minY + inset.y + (source.y - sourceBounds.minY) * scale)
    }
}

enum StorageHostArtworkGeometry {
    static let size = CGSize(width: 340, height: 280)
    static let imageFrame = CGRect(x: 10, y: 0, width: 320, height: 205)
    static let unresolvedAnchor = CGPoint(x: 170, y: 258)

    static func assetName(for model: StorageHostModel) -> String? {
        model.desktopPortLayout?.assetName
    }

    static func anchor(_ port: StorageHostPort, model: StorageHostModel) -> CGPoint? {
        if model.hasVerifiedPortLayout, let topView = StorageHostTopView(identifier: model.identifier) {
            return topView.anchor(port)
        }
        return model.desktopPortLayout?.anchor(port)
    }
}
