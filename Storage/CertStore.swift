/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import UIKit
import Deferred

/// In-memory certificate store.
open class CertStore {
    fileprivate var keys = Set<String>()

    public init() {}

    open func addCertificate(_ cert: SecCertificate) {
        let data: Data = SecCertificateCopyData(cert) as Data
        let key = keyForData(data)
        keys.insert(key)
    }

    open func containsCertificate(_ cert: SecCertificate) -> Bool {
        let data: Data = SecCertificateCopyData(cert) as Data
        let key = keyForData(data)
        return keys.contains(key)
    }

    fileprivate func keyForData(_ data: Data) -> String {
        return data.sha256.hexEncodedString
    }
}
