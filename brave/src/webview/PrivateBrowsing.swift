import Shared
import Deferred
import Crashlytics

private let _singleton = PrivateBrowsing()

class PrivateBrowsing {
    class var singleton: PrivateBrowsing {
        return _singleton
    }

    fileprivate(set) var isOn = false

    var nonprivateCookies = [HTTPCookie: Bool]()

    // On startup we are no longer in private mode, if there is a .public cookies file, it means app was killed in private mode, so restore the cookies file
    func startupCheckIfKilledWhileInPBMode() {
        webkitDirLocker(lock: false)
        cookiesFileDiskOperation(.restore)
    }

    enum MoveCookies {
        case savePublicBackup
        case restore
        case deletePublicBackup
    }

    // GeolocationSites.plist cannot be blocked any other way than locking the filesystem so that webkit can't write it out
    // TODO: after unlocking, verify that sites from PB are not in the written out GeolocationSites.plist, based on manual testing this
    // doesn't seem to be the case, but more rigourous test cases are needed
    fileprivate func webkitDirLocker(lock: Bool) {
        let fm = FileManager.default
        let baseDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)[0]
        let webkitDir = baseDir + "/WebKit"
        do {
            try fm.setAttributes([FileAttributeKey.posixPermissions: (lock ? NSNumber(value: 0 as Int16) : NSNumber(value: 0o755 as Int16))], ofItemAtPath: webkitDir)
        } catch {
            print(error)
        }
    }

    fileprivate func cookiesFileDiskOperation(_ type: MoveCookies) {
        let fm = FileManager.default
        let baseDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)[0]
        let cookiesDir = baseDir + "/Cookies"
        let originSuffix = type == .savePublicBackup ? "cookies" : ".public"

        do {
            let contents = try fm.contentsOfDirectory(atPath: cookiesDir)
            for item in contents {
                if item.hasSuffix(originSuffix) {
                    if type == .deletePublicBackup {
                        try fm.removeItem(atPath: cookiesDir + "/" + item)
                    } else {
                        var toPath = cookiesDir + "/"
                        if type == .restore {
                            toPath += NSString(string: item).deletingPathExtension
                        } else {
                            toPath += item + ".public"
                        }
                        if fm.fileExists(atPath: toPath) {
                            do { try fm.removeItem(atPath: toPath) } catch {}
                        }
                        try fm.moveItem(atPath: cookiesDir + "/" + item, toPath: toPath)
                    }
                }
            }
        } catch {
            print(error)
        }
    }

    func enter() {
        if isOn {
            return
        }

        isOn = true

        getApp().tabManager.enterPrivateBrowsingMode(self)

        cookiesFileDiskOperation(.savePublicBackup)

        URLCache.shared.memoryCapacity = 0;
        URLCache.shared.diskCapacity = 0;

        let storage = HTTPCookieStorage.shared
        if let cookies = storage.cookies {
            for cookie in cookies {
                nonprivateCookies[cookie] = true
                storage.deleteCookie(cookie)
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(PrivateBrowsing.cookiesChanged(_:)), name: NSNotification.Name.NSHTTPCookieManagerCookiesChanged, object: nil)

        webkitDirLocker(lock: true)

        UserDefaults.standard.set(true, forKey: "WebKitPrivateBrowsingEnabled")
    }

    fileprivate var exitDeferred = Deferred<()>()
    func exit() -> Deferred<()> {
        let isAlwaysPrivate = getApp().profile?.prefs.boolForKey(kPrefKeyPrivateBrowsingAlwaysOn) ?? false

        exitDeferred = Deferred<()>()
        if isAlwaysPrivate || !isOn {
            exitDeferred.fill(())
            return exitDeferred
        }

        isOn = false
        UserDefaults.standard.set(false, forKey: "WebKitPrivateBrowsingEnabled")
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(allWebViewsKilled), name: NSNotification.Name(rawValue: kNotificationAllWebViewsDeallocated), object: nil)

        getApp().tabManager.removeAllPrivateTabsAndNotify(false)
        postAsyncToMain(2) {
#if !NO_FABRIC
            Answers.logCustomEvent(withName: "PrivateBrowsing exit failed", customAttributes: nil)
#endif
            self.allWebViewsKilled()
        }

        return exitDeferred
    }

    @objc func allWebViewsKilled() {
        struct ReentrantGuard {
            static var inFunc = false
        }

        if ReentrantGuard.inFunc {
            return
        }
        ReentrantGuard.inFunc = true

        NotificationCenter.default.removeObserver(self)
        postAsyncToMain(0.25) { // even after all webviews killed, an added delay is needed before the webview state is fully cleared, this is horrible. Fortunately, I have only seen this behaviour on the simulator.

            self.webkitDirLocker(lock: false)
            BraveApp.setupCacheDefaults()

            getApp().profile?.loadBraveShieldsPerBaseDomain().upon() { _ in // clears PB in-memory-only shield data, loads from disk
                let clear: [Clearable] = [CacheClearable(), CookiesClearable()]
                ClearPrivateDataTableViewController.clearPrivateData(clear).uponQueue(DispatchQueue.main) { _ in
                    self.cookiesFileDiskOperation(.deletePublicBackup)
                    let storage = HTTPCookieStorage.shared
                    for cookie in self.nonprivateCookies {
                        storage.setCookie(cookie.0)
                    }
                    self.nonprivateCookies = [HTTPCookie: Bool]()

                    getApp().tabManager.exitPrivateBrowsingMode(self)

                    self.exitDeferred.fillIfUnfilled(())
                    ReentrantGuard.inFunc = false
                }
            }
        }
    }

    @objc func cookiesChanged(_ info: Notification) {
        NotificationCenter.default.removeObserver(self)
        let storage = HTTPCookieStorage.shared
        var newCookies = [HTTPCookie]()
        if let cookies = storage.cookies {
            for cookie in cookies {
                if let readOnlyProps = cookie.properties {
                    var props = readOnlyProps as [String: AnyObject]
                    let discard = props[HTTPCookiePropertyKey.discard] as? String
                    if discard == nil || discard! != "TRUE" {
                        props.removeValue(forKey: HTTPCookiePropertyKey.expires)
                        props[HTTPCookiePropertyKey.discard] = "TRUE"
                        storage.deleteCookie(cookie)
                        if let newCookie = HTTPCookie(properties: props) {
                            newCookies.append(newCookie)
                        }
                    }
                }
            }
        }
        for c in newCookies {
            storage.setCookie(c)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(PrivateBrowsing.cookiesChanged(_:)), name: NSNotification.Name.NSHTTPCookieManagerCookiesChanged, object: nil)
    }
}
