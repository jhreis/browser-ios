/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

private let _singleton = AdBlocker()

class AdBlocker {
    static let prefKey = "braveBlockAdsAndTracking"
    static let prefKeyDefaultValue = true
    static let dataVersion = "1"

    lazy var abpFilterLibWrapper: ABPFilterLibWrapper = { return ABPFilterLibWrapper() }()

    lazy var networkFileLoader: NetworkDataFileLoader = {
        let dataUrl = URL(string: "https://s3.amazonaws.com/adblock-data/\(dataVersion)/ABPFilterParserData.dat")!
        let dataFile = "abp-data-\(dataVersion).dat"
        let loader = NetworkDataFileLoader(url: dataUrl, file: dataFile, localDirName: "abp-data")
        loader.delegate = self
        return loader
    }()

    var fifoCacheOfUrlsChecked = FifoDict()
    var isNSPrefEnabled = true

    fileprivate init() {
        NotificationCenter.default.addObserver(self, selector: #selector(AdBlocker.prefsChanged(_:)), name: UserDefaults.didChangeNotification, object: nil)
        updateEnabledState()
    }

    class var singleton: AdBlocker {
        return _singleton
    }

    func updateEnabledState() {
        isNSPrefEnabled = BraveApp.getPrefs()?.boolForKey(AdBlocker.prefKey) ?? AdBlocker.prefKeyDefaultValue
    }

    @objc func prefsChanged(_ info: Notification) {
        updateEnabledState()
    }

    // We can add whitelisting logic here for puzzling adblock problems
    fileprivate func isWhitelistedUrl(_ url: String, forMainDocDomain domain: String) -> Bool {
        // https://github.com/brave/browser-ios/issues/89
        if domain.contains("yahoo") && url.contains("s.yimg.com/zz/combo") {
            return true
        }
        return false
    }

    func setForbesCookie() {
        let cookieName = "forbes bypass"
        let storage = HTTPCookieStorage.shared
        let existing = storage.cookies(for: URL(string: "http://www.forbes.com")!)
        if let existing = existing {
            for c in existing {
                if c.name == cookieName {
                    return
                }
            }
        }

        var dict: [String:AnyObject] = [:]
        dict[HTTPCookiePropertyKey.path] = "/"
        dict[HTTPCookiePropertyKey.name] = cookieName
        dict[HTTPCookiePropertyKey.value] = "forbes_ab=true; welcomeAd=true; adblock_session=Off; dailyWelcomeCookie=true"
        dict[HTTPCookiePropertyKey.domain] = "www.forbes.com"

        let components: DateComponents = DateComponents()
        (components as NSDateComponents).setValue(1, forComponent: NSCalendar.Unit.month);
        dict[HTTPCookiePropertyKey.expires] = (Calendar.current as NSCalendar).date(byAdding: components, to: Date(), options: NSCalendar.Options(rawValue: 0))

        let newCookie = HTTPCookie(properties: dict as! [HTTPCookiePropertyKey : Any])
        if let c = newCookie {
            storage.setCookie(c)
        }
    }

    class RedirectLoopGuard {
        let timeWindow: TimeInterval // seconds
        let maxRedirects: Int
        var startTime = Date()
        var redirects = 0

        init(timeWindow: TimeInterval, maxRedirects: Int) {
            self.timeWindow = timeWindow
            self.maxRedirects = maxRedirects
        }

        func isLooping() -> Bool {
            return redirects > maxRedirects
        }

        func increment() {
            let time = Date()
            if time.timeIntervalSince(startTime) > timeWindow {
                startTime = time
                redirects = 0
            }
            redirects += 1
        }
    }

    // In the valid case, 4-5x we see 'forbes/welcome' page in succession (URLProtocol can call more than once for an URL, this is well documented)
    // Set the window as 10x in 10sec, after that stop forwarding the page.
    var forbesRedirectGuard = RedirectLoopGuard(timeWindow: 10.0, maxRedirects: 10)

    func shouldBlock(_ request: URLRequest) -> Bool {
        // synchronize code from this point on.
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        guard let url = request.url else {
                return false
        }

        if url.host?.contains("forbes.com") ?? false {
            setForbesCookie()

            if url.absoluteString.contains("/forbes/welcome") {
                forbesRedirectGuard.increment()
                if !forbesRedirectGuard.isLooping() {
                    postAsyncToMain(0.5) {
                        /* For some reason, even with the cookie set, I can't get past the welcome page, until I manually load a page on forbes. So if a do a google search for a subpage on forbes, I can click on that and get to forbes, and from that point on, I no longer see the welcome page. This hack seems to work perfectly for duplicating that behaviour. */
                        BraveApp.getCurrentWebView()?.loadRequest(URLRequest(url: URL(string: "http://www.forbes.com")!))
                    }
                }
            }
        }


        if request.mainDocumentURL?.absoluteString.startsWith(WebServer.sharedInstance.base) ?? false {
            return false
        }

        var mainDocDomain = request.mainDocumentURL?.host ?? ""
        mainDocDomain = stripLocalhostWebServer(mainDocDomain)

        if isWhitelistedUrl(url.absoluteString, forMainDocDomain: mainDocDomain) {
            return false
        }

        if !mainDocDomain.isEmpty && url.absoluteString.contains(mainDocDomain) {
            return false // ignore top level doc
        }

        // A cache entry is like: fifoOfCachedUrlChunks[0]["www.microsoft.com_http://some.url"] = true/false for blocking
        let key = "\(mainDocDomain)_" + stripLocalhostWebServer(url.absoluteString)

        if let checkedItem = fifoCacheOfUrlsChecked.getItem(key) {
            if checkedItem === NSNull() {
                return false
            } else {
                return checkedItem as! Bool
            }
        }

        let isBlocked = abpFilterLibWrapper.isBlockedConsideringType(url.absoluteString,
                                                                     mainDocumentUrl: mainDocDomain,
                                                                     acceptHTTPHeader:request.value(forHTTPHeaderField: "Accept"))

        fifoCacheOfUrlsChecked.addItem(key, value: isBlocked)

        #if LOG_AD_BLOCK
            if isBlocked {
                print("blocked \(url.absoluteString)")
            }
        #endif

        return isBlocked
    }
}

extension AdBlocker: NetworkDataFileLoaderDelegate {
    
    func fileLoader(_: NetworkDataFileLoader, setDataFile data: Data?) {
        abpFilterLibWrapper.setDataFile(data)
    }
    
    func fileLoaderHasDataFile(_: NetworkDataFileLoader) -> Bool {
        return abpFilterLibWrapper.hasDataFile()
    }

    func fileLoaderDelegateWillHandleInitialRead(_: NetworkDataFileLoader) -> Bool {
        return false
    }
}
