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
}
