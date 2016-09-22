/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

class SettingsNavigationController: UINavigationController {
    var popoverDelegate: PresentingModalViewControllerDelegate?

    func SELdone() {
        if let delegate = popoverDelegate {
            delegate.dismissPresentedModalViewController(self, animated: true)
            getApp().browserViewController.view.alpha = CGFloat(BraveUX.BrowserViewAlphaWhenShowingTabTray)
        } else {
            self.dismiss(animated: true, completion: {
                getApp().browserViewController.view.alpha = CGFloat(1.0)
            })
        }
        
        getApp().browserViewController.urlBar.setNeedsLayout()
        getApp().browserViewController.urlBar.setNeedsUpdateConstraints()
    }
}

protocol PresentingModalViewControllerDelegate {
    func dismissPresentedModalViewController(_ modalViewController: UIViewController, animated: Bool)
}
