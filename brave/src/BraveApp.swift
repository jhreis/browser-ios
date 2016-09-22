/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Deferred

#if !NO_FABRIC
    import Fabric
    import Crashlytics
#endif

#if !DEBUG
    func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif

private let _singleton = BraveApp()

let kAppBootingIncompleteFlag = "kAppBootingIncompleteFlag"
let kDesktopUserAgent = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_11_6) AppleWebKit/537.36 (KHTML, like Gecko) Version/5.0 Safari/537.36"

#if !TEST
    func getApp() -> AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }
#endif

// Any app-level hooks we need from Firefox, just add a call to here
class BraveApp {
    static var isSafeToRestoreTabs = true
    // If app runs for this long, clear the saved pref that indicates it is safe to restore tabs
    static let kDelayBeforeDecidingAppHasBootedOk = (Int64(NSEC_PER_SEC) * 10) // 10 sec

    class var singleton: BraveApp {
        return _singleton
    }

    #if !TEST
    class func getCurrentWebView() -> BraveWebView? {
        return getApp().browserViewController.tabManager.selectedTab?.webView
    }
    #endif

    fileprivate init() {
    }

    class func isIPhoneLandscape() -> Bool {
        return UIDevice.current.userInterfaceIdiom == .phone &&
            UIInterfaceOrientationIsLandscape(UIApplication.shared.statusBarOrientation)
    }

    class func isIPhonePortrait() -> Bool {
        return UIDevice.current.userInterfaceIdiom == .phone &&
            UIInterfaceOrientationIsPortrait(UIApplication.shared.statusBarOrientation)
    }

    class func setupCacheDefaults() {
        URLCache.shared.memoryCapacity = 6 * 1024 * 1024; // 6 MB
        URLCache.shared.diskCapacity = 40 * 1024 * 1024;
    }

    // Be aware: the Prefs object has not been created yet
    class func willFinishLaunching_begin() {
        #if !NO_FABRIC
            Fabric.with([Crashlytics.self])
        #endif
        BraveApp.setupCacheDefaults()
        Foundation.URLProtocol.registerClass(URLProtocol);

        NotificationCenter.default.addObserver(BraveApp.singleton,
             selector: #selector(BraveApp.didEnterBackground(_:)), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)

        NotificationCenter.default.addObserver(BraveApp.singleton,
             selector: #selector(BraveApp.willEnterForeground(_:)), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)

        NotificationCenter.default.addObserver(BraveApp.singleton,
             selector: #selector(BraveApp.memoryWarning(_:)), name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)

        #if !TEST
            //  these quiet the logging from the core of fx ios
            // GCDWebServer.setLogLevel(5)
            Logger.syncLogger.setup(.None)
            Logger.browserLogger.setup(.None)
        #endif

        #if DEBUG
            // desktop UA for testing
            //      let defaults = NSUserDefaults(suiteName: AppInfo.sharedContainerIdentifier())!
            //      defaults.registerDefaults(["UserAgent": kDesktopUserAgent])

        #endif
    }

    // Prefs are created at this point
    class func willFinishLaunching_end() {
        if AppConstants.IsRunningTest {
            print("In test mode, bypass automatic vault registration.")
        } else {
            // TODO hookup VaultManager.userProfileInit()
        }

        BraveApp.isSafeToRestoreTabs = BraveApp.getPrefs()?.stringForKey(kAppBootingIncompleteFlag) == nil
        BraveApp.getPrefs()?.setString("remove me when booted", forKey: kAppBootingIncompleteFlag)

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(BraveApp.kDelayBeforeDecidingAppHasBootedOk) / Double(NSEC_PER_SEC), execute: {
                        BraveApp.getPrefs()?.removeObjectForKey(kAppBootingIncompleteFlag)
        })

        AdBlocker.singleton.networkFileLoader.loadData()
        SafeBrowsing.singleton.networkFileLoader.loadData()
        TrackingProtection.singleton.networkFileLoader.loadData()
        HttpsEverywhere.singleton.networkFileLoader.loadData()

        #if !TEST
            PrivateBrowsing.singleton.startupCheckIfKilledWhileInPBMode()
            CookieSetting.setupOnAppStart()
            ThirdPartyPasswordManagerSetting.setupOnAppStart()
            //BlankTargetLinkHandler.updatedEnabledState()
        #endif

        getApp().profile?.loadBraveShieldsPerBaseDomain().upon() {
            postAsyncToMain(0) { // back to main thread
                if let wv = getCurrentWebView(), let url = wv.URL, let base = url.normalizedHost(), let dbState = BraveShieldState.perNormalizedDomain[base] , wv.braveShieldState.isNotSet() {
                    // on init, the webview's shield state doesn't match the db
                    wv.braveShieldState = dbState
                    wv.reloadFromOrigin()
                }
            }
        }
    }

    // This can only be checked ONCE, the flag is cleared after this.
    // This is because BrowserViewController asks this question after the startup phase,
    // when tabs are being created by user actions. So without more refactoring of the
    // Firefox logic, this is the simplest solution.
    class func shouldRestoreTabs() -> Bool {
        let ok = BraveApp.isSafeToRestoreTabs
        BraveApp.isSafeToRestoreTabs = true
        return ok
    }

    @objc func memoryWarning(_: Notification) {
        URLCache.shared.memoryCapacity = 0
        BraveApp.setupCacheDefaults()
        getApp().tabManager.memoryWarning()
    }

    @objc func didEnterBackground(_: Notification) {
    }

    @objc func willEnterForeground(_ : Notification) {
    }

    class func shouldHandleOpenURL(_ components: URLComponents) -> Bool {
        // TODO look at what x-callback is for
        return components.scheme == "brave" || components.scheme == "brave-x-callback"
    }

    class func getPrefs() -> Prefs? {
        return getApp().profile?.prefs
    }

    static func showErrorAlert(title: String,  error: String) {
        postAsyncToMain(0) { // this utility function can be called from anywhere
            UIAlertView(title: title, message: error, delegate: nil, cancelButtonTitle: "Close").show()
        }
    }

    static func statusBarHeight() -> CGFloat {
        if UIScreen.main.traitCollection.verticalSizeClass == .compact {
            return 0
        }
        return 20
    }

    static var isPasswordManagerInstalled: Bool?

    static func is3rdPartyPasswordManagerInstalled(refreshLookup: Bool) -> Deferred<Bool>  {
        let deferred = Deferred<Bool>()
        if refreshLookup || isPasswordManagerInstalled == nil {
            DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.background).async {
                isPasswordManagerInstalled = OnePasswordExtension.shared().isAppExtensionAvailable()
                deferred.fill(isPasswordManagerInstalled!)
            }
        } else {
            deferred.fill(isPasswordManagerInstalled!)
        }
        return deferred
    }
}
