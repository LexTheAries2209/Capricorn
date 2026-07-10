// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI

extension AppLanguage {
    func smartAttributeDisplay(_ attribute: SmartAttribute) -> SmartAttributeDisplay {
        SmartAttributeCatalog.display(for: attribute, language: self)
    }
}
