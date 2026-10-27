// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Capricorn

final class StorageHostArtworkTests: XCTestCase {
    @MainActor
    func testSystemArtworkCoversCommonMacFamilies() throws {
        let models = [
            ("MacBookPro18,2", "macbookpro"),
            ("MacBookAir10,1", "macbookair"),
            ("iMac21,1", "imac"),
            ("Macmini9,1", "macmini"),
            ("Mac13,1", "macstudio"),
            ("MacPro7,1", "macpro")
        ]
        for (identifier, family) in models {
            let type = try XCTUnwrap(StorageHostArtwork.contentType(for: identifier), identifier)
            XCTAssertTrue(type.identifier.contains(family), type.identifier)
            let image = try XCTUnwrap(StorageHostArtwork.shared.image(for: identifier), identifier)
            XCTAssertTrue(image.isValid)
            XCTAssertGreaterThan(image.size.width, 100)
            XCTAssertGreaterThan(image.size.height, 100)
            XCTAssertNotNil(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
    }

    @MainActor
    func testOfficialMacBookImageIsCroppedAndCached() throws {
        let first = try XCTUnwrap(StorageHostArtwork.shared.image(for: "MacBookPro18,2"))
        let second = try XCTUnwrap(StorageHostArtwork.shared.image(for: "MacBookPro18,2"))
        XCTAssertTrue(first === second)
        XCTAssertGreaterThan(first.size.width / first.size.height, 1.4, "Transparent icon padding should not shrink the laptop.")
    }

    @MainActor
    func testUnknownModelDoesNotSubstituteAnotherMachineArtwork() {
        XCTAssertNil(StorageHostArtwork.contentType(for: "CapricornUnknownMac999,1"))
        XCTAssertNil(StorageHostArtwork.shared.image(for: "CapricornUnknownMac999,1"))
    }

    @MainActor
    func testBothKeyboardViewsAreBundledForMatchingChassis() throws {
        for (identifier, size) in [("Mac14,5", NSSize(width: 809, height: 479)),
                                   ("Mac14,6", NSSize(width: 893, height: 535))] {
            let profile = try XCTUnwrap(StorageHostTopView(identifier: identifier))
            let asset = try XCTUnwrap(NSImage(named: profile.assetName))
            XCTAssertEqual(asset.size, size)
            XCTAssertTrue(StorageHostArtwork.shared.image(for: identifier) === asset)
        }
        XCTAssertNil(StorageHostTopView(identifier: "MacBookAir10,1"))
        XCTAssertNil(StorageHostTopView(identifier: "Macmini9,1"))
    }

    func testKeyboardSocketProjectionFollowsChassisSidesAndRearSpacing() throws {
        for identifier in ["MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4",
                           "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10"] {
            let profile = try XCTUnwrap(StorageHostTopView(identifier: identifier))
            let rear = try XCTUnwrap(profile.anchor(.init(number: 1)))
            let front = try XCTUnwrap(profile.anchor(.init(number: 2)))
            let right = try XCTUnwrap(profile.anchor(.init(number: 3)))
            XCTAssertEqual(rear.x, front.x)
            XCTAssertLessThan(rear.x, 50)
            XCTAssertGreaterThan(right.x, 290)
            XCTAssertLessThan(rear.y, front.y)
            XCTAssertLessThan(front.y, 90, "Both left sockets belong near the hinge, not the palm rest.")
            XCTAssertEqual(rear.y, right.y, "Sockets 1 and 3 must be exactly parallel.")
            let is14Inch = profile.assetName == "MacBookPro14Top2023"
            XCTAssertEqual(rear.y, is14Inch ? 51.67 : 52.51, accuracy: 0.1, "Align to the keyboard number row.")
            XCTAssertEqual(front.y, is14Inch ? 67.49 : 66.84, accuracy: 0.1, "Align socket 2 to the QWER row.")
            XCTAssertTrue(StorageHostArtworkGeometry.imageFrame.contains(rear))
            XCTAssertTrue(StorageHostArtworkGeometry.imageFrame.contains(front))
            XCTAssertTrue(StorageHostArtworkGeometry.imageFrame.contains(right))
            XCTAssertNil(profile.anchor(.init(number: 4)))
        }
    }
}
