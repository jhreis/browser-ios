/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import SwiftKeychainWrapper
import LocalAuthentication
import Storage

class AppAuthenticator {
    static func presentAuthenticationUsingInfo(_ authenticationInfo: AuthenticationKeychainInfo, touchIDReason: String, success: (() -> Void)?, fallback: (() -> Void)?) {
        if authenticationInfo.useTouchID {
            let localAuthContext = LAContext()
            localAuthContext.localizedFallbackTitle = AuthenticationStrings.enterPasscode
            localAuthContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: touchIDReason) { didSucceed, error in
                if didSucceed {
                    // Update our authentication info's last validation timestamp so we don't ask again based
                    // on the set required interval
                    authenticationInfo.recordValidation()
                    KeychainWrapper.setAuthenticationInfo(authenticationInfo)

                    DispatchQueue.main.async {
                        success?()
                    }
                } else if let authError = error , authError.code == LAError.Code.userFallback.rawValue {
                    DispatchQueue.main.async {
                        fallback?()
                    }
                }
            }
        } else {
            fallback?()
        }
    }

    static func presentPasscodeAuthentication(_ presentingNavController: UINavigationController?, delegate: PasscodeEntryDelegate) {
        let passcodeVC = PasscodeEntryViewController()
        passcodeVC.delegate = delegate
        let navController = UINavigationController(rootViewController: passcodeVC)
        navController.modalPresentationStyle = .formSheet
        presentingNavController?.present(navController, animated: true, completion: nil)
    }
}
