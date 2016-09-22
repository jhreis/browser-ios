import Foundation

import Shared
import Storage
import Deferred

var iPadOffscreenView = UIView(frame: CGRect(x: 3000,y: 0,width: 1,height: 1))
let tagFor1PwSnackbar = 8675309
var noPopupOnSites: [String] = []

let kPrefName3rdPartyPasswordShortcutEnabled = "thirdPartyPasswordShortcutEnabled"


struct ThirdPartyPasswordManagers {
    static let UseBuiltInInstead = (displayName: "Don't use", cellLabel: "", prefId: 0)
    static let OnePassword = (displayName: "1Password", cellLabel: "1Password", prefId: 1)
    static let LastPass = (displayName: "LastPass", cellLabel: "LastPass", prefId: 2)
}

extension LoginsHelper {
    func thirdPartyPasswordRegisterPageListeners() {
        guard let wv = browser?.webView else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(LoginsHelper.hideOnPageChange(_:)), name: NSNotification.Name(rawValue: kNotificationPageUnload), object: wv)
        NotificationCenter.default.addObserver(self, selector: #selector(LoginsHelper.checkOnPageLoaded(_:)), name: NSNotification.Name(rawValue: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed), object: wv)
    }

    func thirdPartyPasswordSnackbar() {
        let isEnabled = ThirdPartyPasswordManagerSetting.currentSetting?.prefId ?? 0 > 0
        if !isEnabled {
            return
        }

        guard let url = browser?.webView?.URL else { return }

        BraveApp.is3rdPartyPasswordManagerInstalled(refreshLookup: false).upon {
            [weak self]
            result in
            if !result {
                return
            }

            self?.isInNoShowList(url).upon {
                [weak self]
                result in
                if result {
                    return
                }

                postAsyncToMain(0) {
                    [weak self] in
                    guard let safeSelf = self else { return }
                    if let snackBar = safeSelf.snackBar {
                        if safeSelf.browser?.bars.map({ $0.tag }).index(of: tagFor1PwSnackbar) != nil {
                            return // already have a 1PW snackbar active for this tab
                        }

                        safeSelf.browser?.removeSnackbar(snackBar)
                    }

                    let managerName = ThirdPartyPasswordManagerSetting.currentSetting?.displayName ?? "your password manager"

                    safeSelf.snackBar = SnackBar(attrText: NSAttributedString(string: "Sign in with \(managerName)"), img: UIImage(named: "key"), buttons: [])
                    safeSelf.snackBar!.tag = tagFor1PwSnackbar
                    let button = UIButton()
                    button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    safeSelf.snackBar!.addSubview(button)
                    button.addTarget(self, action: #selector(LoginsHelper.onExecuteTapped), for: .touchUpInside)

                    let close = UIButton(frame: CGRect(x: safeSelf.snackBar!.frame.width - 40, y: 0, width: 40, height: 40))
                    close.setImage(UIImage(named: "stop")!, for: UIControlState())
                    close.addTarget(self, action: #selector(LoginsHelper.onCloseTapped), for: .touchUpInside)
                    close.tintColor = UIColor.black
                    close.autoresizingMask = [.flexibleLeftMargin]
                    safeSelf.snackBar!.addSubview(close)

                    safeSelf.browser?.addSnackbar(safeSelf.snackBar!)
                }
            }
        }
    }

    @objc func onCloseTapped() {
        if let s = snackBar {
            self.browser?.removeSnackbar(s)

            guard let host = browser?.webView?.URL?.hostWithGenericSubdomainPrefixRemoved() else { return }
            noPopupOnSites.append(host)
            #if PW_DB
                getApp().profile!.db.write("INSERT INTO \(TableOnePasswordNoPopup) (domain) VALUES (?)", withArgs: [host])
            #endif
        }
    }

    @objc func checkOnPageLoaded(_ notification: Notification) {
        if notification.object !== browser?.webView {
            return
        }
        postAsyncToMain(0.1) {
            [weak self] in
            let result = self?.browser?.webView?.stringByEvaluatingJavaScript(from: "document.querySelectorAll(\"input[type='password']\").length !== 0")
            if let ok = result , ok == "true" {
                self?.thirdPartyPasswordSnackbar()
            }
        }
    }

    @objc func hideOnPageChange(_ notification: Notification) {
        if let snackBar = snackBar , snackBar.tag == tagFor1PwSnackbar {
            browser?.removeSnackbar(snackBar)
        }
    }

    @objc func onExecuteTapped() {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        if !isIPad {
            UIView.animate(withDuration: 0.2, animations: {
                // Hiding shows user feedback to the tap, don't remove, as snackbar should not show again until page change
                // We don't hide on iPad, because if the autodetection of the cell to click fails, a popup is shown for the
                // user to select their PW manager, and iPad needs a UIView to anchor the popup bubble
                self.snackBar?.alpha = 0
            }) 
            UIAlertController.hackyHide(on: true)
        }

        let sender:UIView =  snackBar!

        if isIPad && iPadOffscreenView.superview == nil {
            getApp().browserViewController.view.addSubview(iPadOffscreenView)
        }

        OnePasswordExtension.shared().fillItem(intoWebView: browser!.webView!, for: getApp().browserViewController, sender: sender, showOnlyLogins: true) { (success, error) -> Void in
            if isIPad {
                iPadOffscreenView.removeFromSuperview()
                self.browser?.removeSnackbar(self.snackBar!)
            } else {
                UIAlertController.hackyHide(on: false)
            }

            if success == false {
                print("Failed to fill into webview: <\(error)>")
            }
        }

        var found = false

        // recurse through items until the 1pw share item is found
        func selectShareItem(_ view: UIView, shareItemName: String) {
            if found {
                return
            }

            for subview in view.subviews {
                if subview.description.contains("UICollectionViewControllerWrapperView") && (subview.subviews.first?.subviews.count)! > 1 {
                    let wrapperCell = subview.subviews.first?.subviews[1] as? UICollectionViewCell
                    if let collectionView = wrapperCell?.subviews.first?.subviews.first?.subviews.first as? UICollectionView {

                        // As a safe upper bound, just look at 10 items max
                        for i in 0..<10 {
                            let indexPath = IndexPath(item: i, section: 0)
                            let suspectCell = collectionView.cellForItem(at: indexPath)
                            if suspectCell == nil {
                                break;
                            }
                            if suspectCell?.subviews.first?.subviews.last?.description.contains(shareItemName) ?? false {
                                collectionView.delegate?.collectionView?(collectionView, didSelectItemAt:indexPath)
                                found = true
                            }
                        }

                        return
                    }
                }
                selectShareItem(subview, shareItemName: shareItemName)
            }
        }

        // The event loop needs to run for the share screen to reliably be showing, a delay of zero also works.
        postAsyncToMain(0.2) {
            guard let itemToLookFor = ThirdPartyPasswordManagerSetting.currentSetting?.cellLabel else { return }
            selectShareItem(getApp().window!, shareItemName: itemToLookFor)

            if !found {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    UIActivityViewController.hackyDismissal()
                    iPadOffscreenView.removeFromSuperview()
                    BraveApp.getPrefs()?.setInt(0, forKey: kPrefName3rdPartyPasswordShortcutEnabled)
                    BraveApp.showErrorAlert(title: "Password shortcut error", error: "Can't find item named \(itemToLookFor)")
                } else {
                    // Just show the regular share screen, this isn't a fatal problem on iPhone
                    UIAlertController.hackyHide(on: false)
                }
            }
        }
    }

    // Using a DB-backed storage for this is under consideration.
    // Use a similar Deferred-style so switching to the DB method is seamless
    func isInNoShowList(_ url: URL)  -> Deferred<Bool>  {
        let deferred = Deferred<Bool>()
        var result = false
        if let host = url.hostWithGenericSubdomainPrefixRemoved() {
            result = noPopupOnSites.contains(host)
        }
        deferred.fill(result)
        return deferred
    }
}
