/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Shared
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


let kNotificationPageUnload = "kNotificationPageUnload"
let kNotificationAllWebViewsDeallocated = "kNotificationAllWebViewsDeallocated"

func convertNavActionToWKType(_ type:UIWebViewNavigationType) -> WKNavigationType {
    return WKNavigationType(rawValue: type.rawValue)!
}

class ContainerWebView : WKWebView {
    weak var legacyWebView: BraveWebView?
}

var globalContainerWebView = ContainerWebView()

protocol WebPageStateDelegate : class {
    func webView(_ webView: UIWebView, progressChanged: Float)
    func webView(_ webView: UIWebView, isLoading: Bool)
    func webView(_ webView: UIWebView, urlChanged: String)
    func webView(_ webView: UIWebView, canGoBack: Bool)
    func webView(_ webView: UIWebView, canGoForward: Bool)
}


@objc class HandleJsWindowOpen : NSObject {
    static func open(_ url: String) {
        postAsyncToMain(0) { // we now know JS callbacks can be off main
            guard let wv = BraveApp.getCurrentWebView() else { return }
            let current = wv.URL
            print("window.open")
            if BraveApp.getPrefs()?.boolForKey("blockPopups") ?? true {
                guard let lastTappedTime = wv.lastTappedTime else { return }
                if fabs(lastTappedTime.timeIntervalSinceNow) > 0.75 { // outside of the 3/4 sec time window and we ignore it
                    print(lastTappedTime.timeIntervalSinceNow)
                    return
                }
            }
            wv.lastTappedTime = nil
            if let _url = URL(string: url, relativeTo: current) {
                getApp().browserViewController.openURLInNewTab(_url)
            }
        }
    }
}

class WebViewToUAMapper {
    static fileprivate let idToWebview = NSMapTable(keyOptions: NSPointerFunctions.Options(), valueOptions: .weakMemory)

    static func setId(_ uniqueId: Int, webView: BraveWebView) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        idToWebview.setObject(webView, forKey: uniqueId)
    }

    static func userAgentToWebview(_ ua: String?) -> BraveWebView? {
        // synchronize code from this point on.
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        guard let ua = ua else { return nil }
        guard let loc = ua.range(of: "_id/") else {
            // the first created webview doesn't have this id set (see webviewBuiltinUserAgent to explain)
            return idToWebview.object(forKey: 1) as? BraveWebView
        }
        
        let keyString = ua.substringWithRange(loc.endIndex..<loc.endIndex.advancedBy(6))
        guard let key = Int(keyString) else { return nil }
        return idToWebview.object(forKey: key) as? BraveWebView
    }
}

struct BraveWebViewConstants {
    static let kNotificationWebViewLoadCompleteOrFailed = "kNotificationWebViewLoadCompleteOrFailed"
    static let kNotificationPageInteractive = "kNotificationPageInteractive"
    static let kContextMenuBlockNavigation = 8675309
}

class BraveWebView: UIWebView {
    class Weak_WebPageStateDelegate {     // We can't use a WeakList here because this is a protocol.
        weak var value : WebPageStateDelegate?
        init (value: WebPageStateDelegate) { self.value = value }
    }
    var delegatesForPageState = [Weak_WebPageStateDelegate]()

    let usingDesktopUserAgent: Bool
    let specialStopLoadUrl = "http://localhost.stop.load"
    weak var navigationDelegate: WKCompatNavigationDelegate?

    lazy var configuration: BraveWebViewConfiguration = { return BraveWebViewConfiguration(webView: self) }()
    lazy var backForwardList: WebViewBackForwardList = { return WebViewBackForwardList(webView: self) } ()
    var progress: WebViewProgress?
    var certificateInvalidConnection:NSURLConnection?
    var braveShieldState = BraveShieldState() {
        didSet {
            if let fpOn = braveShieldState.isOnFingerprintProtection(), let browser = getApp().tabManager.tabForWebView(self) , fpOn {
                if browser.getHelper(FingerprintingProtection.self) == nil {
                    let fp = FingerprintingProtection(browser: browser)
                    browser.addHelper(fp)
                }
            } else {
                let fpOn = BraveApp.getPrefs()?.boolForKey(kPrefKeyFingerprintProtection)
                if fpOn == nil || !fpOn! {
                    getApp().tabManager.tabForWebView(self)?.removeHelper(FingerprintingProtection.self)
                }
            }

            postAsyncToMain(0.2) { // update the UI, wait a bit for loading to have started
                (getApp().browserViewController as! BraveBrowserViewController).updateBraveShieldButtonState(animated: false)
            }
        }
    }
    var blankTargetLinkDetectionOn = true
    var lastTappedTime: Date?
    var removeBvcObserversOnDeinit: ((UIWebView) -> Void)?
    var removeProgressObserversOnDeinit: ((UIWebView) -> Void)?

    var safeBrowsingBlockTriggered:Bool = false
    
    var prevDocumentLocation = ""
    var estimatedProgress: Double = 0
    var title: String = "" {
        didSet {
            if let item = backForwardList.currentItem {
                item.title = title
            }
        }
    }

    fileprivate var _url: (url: Foundation.URL?, isReliableSource: Bool, prevUrl: Foundation.URL?) = (nil, false, nil)

    fileprivate var lastBroadcastedKvoUrl: String = ""
    func setUrl(_ url: Foundation.URL?, reliableSource: Bool) {
        _url.prevUrl = _url.url
        _url.isReliableSource = reliableSource
        if URL?.absoluteString.endsWith("?") ?? false {
            if let noQuery = URL?.absoluteString.components(separatedBy: "?")[0] {
                _url.url = Foundation.URL(string: noQuery)
            }
        } else {
            _url.url = url
        }

        if let url = URL?.absoluteString , url != lastBroadcastedKvoUrl {
            delegatesForPageState.forEach { $0.value?.webView(self, urlChanged: url) }
            lastBroadcastedKvoUrl = url
        }
    }

    func isUrlSourceReliable() -> Bool {
        return _url.isReliableSource
    }

    var previousUrl: Foundation.URL? { get { return _url.prevUrl } }

    var URL: Foundation.URL? {
        get {
            return _url.url
        }
    }

    var uniqueId = -1

    var internalIsLoadingEndedFlag: Bool = false;
    var knownFrameContexts = Set<NSObject>()
    fileprivate static var containerWebViewForCallbacks = { return ContainerWebView() }()
    // From http://stackoverflow.com/questions/14268230/has-anybody-found-a-way-to-load-https-pages-with-an-invalid-server-certificate-u
    var loadingUnvalidatedHTTPSPage: Bool = false

    fileprivate static var webviewBuiltinUserAgent = UserAgent.defaultUserAgent()

    // Needed to identify webview in url protocol
    func generateUniqueUserAgent() {
        // synchronize code from this point on.
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        struct StaticCounter {
            static var counter = 0
        }

        StaticCounter.counter += 1
        let userAgentBase = usingDesktopUserAgent ? kDesktopUserAgent : BraveWebView.webviewBuiltinUserAgent
        let userAgent = userAgentBase + String(format:" _id/%06d", StaticCounter.counter)
        let defaults = UserDefaults(suiteName: AppInfo.sharedContainerIdentifier())!
        defaults.registerDefaults(["UserAgent": userAgent ])
        self.uniqueId = StaticCounter.counter
        WebViewToUAMapper.setId(uniqueId, webView:self)
    }

    var triggeredLocationCheckTimer = Timer()
    // On page load, the contentSize of the webview is updated (**). If the webview has not been notified of a page change (i.e. shouldStartLoadWithRequest was never called) then 'loading' will be false, and we should check the page location using JS.
    // (** Not always updated, particularly on back/forward. For instance load duckduckgo.com, then google.com, and go back. No content size change detected.)
    func contentSizeChangeDetected() {
        if triggeredLocationCheckTimer.isValid {
            return
        }

        // Add a time delay so that multiple calls are aggregated
        triggeredLocationCheckTimer = Timer.scheduledTimer(timeInterval: 0.15, target: self, selector: #selector(timeoutCheckLocation), userInfo: nil, repeats: false)
    }

    // Pushstate navigation may require this case (see brianbondy.com), as well as sites for which simple pushstate detection doesn't work:
    // youtube and yahoo news are examples of this (http://stackoverflow.com/questions/24297929/javascript-to-listen-for-url-changes-in-youtube-html5-player)
    @objc func timeoutCheckLocation() {
        assert(Thread.isMainThread)

        func tryUpdateUrl() {
            guard let location = self.stringByEvaluatingJavaScript(from: "window.location.href"), let currentUrl = URL?.absoluteString else { return }
            if location == currentUrl || location.contains("about:") || location.contains("//localhost") || URL?.host != Foundation.URL(string: location)?.host {
                return
            }

            if isUrlSourceReliable() && location == previousUrl?.absoluteString {
                return
            }

            print("Page change detected by content size change triggered timer: \(location)")

            NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationPageUnload), object: self)
            setUrl(Foundation.URL(string: location), reliableSource: false)

            shieldStatUpdate(.reset)

            progress?.reset()
        }

        tryUpdateUrl()

        if (!isLoading ||
            stringByEvaluatingJavaScript(from: "document.readyState.toLowerCase()") == "complete") && !isUrlSourceReliable()
        {
            updateTitleFromHtml()
            internalIsLoadingEndedFlag = false // need to set this to bypass loadingCompleted() precondition
            loadingCompleted()

            broadcastToPageStateDelegates()
        } else {
            progress?.setProgress(0.3)
            delegatesForPageState.forEach { $0.value?.webView(self, progressChanged: 0.3) }

        }
    }

    func updateTitleFromHtml() {
        if let t = stringByEvaluatingJavaScript(from: "document.title") , !t.isEmpty {
            title = t
        }
    }

    required init(frame: CGRect, useDesktopUserAgent: Bool) {
        self.usingDesktopUserAgent = useDesktopUserAgent
        super.init(frame: frame)
        commonInit()
    }

    static var allocCounter = 0

    fileprivate func commonInit() {
        BraveWebView.allocCounter += 1
        print("webview init  \(BraveWebView.allocCounter)")
        generateUniqueUserAgent()

        progress = WebViewProgress(parent: self)

        delegate = self
        scalesPageToFit = true

        scrollView.showsHorizontalScrollIndicator = false

        #if !TEST
            let rate = UIScrollViewDecelerationRateFast + (UIScrollViewDecelerationRateNormal - UIScrollViewDecelerationRateFast) * 0.5;
            scrollView.setValue(NSValue(cgSize: CGSize(width: rate, height: rate)), forKey: "_decelerationFactor")
        #endif
    }

    var jsBlockedStatLastUrl: String? = nil
    func checkScriptBlockedAndBroadcastStats() {
        if braveShieldState.isOnScriptBlocking() ?? BraveApp.getPrefs()?.boolForKey(kPrefKeyNoScriptOn) ?? false {
            let jsBlocked = Int(stringByEvaluatingJavaScript(from: "document.getElementsByTagName('script').length") ?? "0") ?? 0

            if request?.url?.absoluteString == jsBlockedStatLastUrl && jsBlocked == 0 {
                return
            }
            jsBlockedStatLastUrl = request?.url?.absoluteString

            shieldStatUpdate(.jsSetValue, jsBlocked)
        } else {
            shieldStatUpdate(.broadcastOnly)
        }
    }

    func internalProgressNotification(_ notification: Notification) {
        //print("\(notification.userInfo?["WebProgressEstimatedProgressKey"])")
        if ((notification as NSNotification).userInfo?["WebProgressEstimatedProgressKey"] as? Double ?? 0 > 0.99) {
            delegate?.webViewDidFinishLoad?(self)
        }
    }

    override var isLoading: Bool {
        get {
            if internalIsLoadingEndedFlag {
                // we detected load complete internally –UIWebView sometimes stays in a loading state (i.e. bbc.com)
                return false
            }
            return super.isLoading
        }
    }

    required init?(coder aDecoder: NSCoder) {
        self.usingDesktopUserAgent = false
        super.init(coder: aDecoder)
        commonInit()
    }

    deinit {
        BraveWebView.allocCounter -= 1
        if (BraveWebView.allocCounter == 0) {
            NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationAllWebViewsDeallocated), object: nil)
            print("NO LIVE WEB VIEWS")
        }

        NotificationCenter.default.removeObserver(self)

        _ = Try(withTry: {
            self.removeBvcObserversOnDeinit?(self)
        }) { (exception) -> Void in
            print("Failed remove: \(exception)")
        }

        _ = Try(withTry: {
            self.removeProgressObserversOnDeinit?(self)
        }) { (exception) -> Void in
            print("Failed remove: \(exception)")
        }

        print("webview deinit \(title) ")
    }

    var blankTargetUrl: String?

    func urlBlankTargetTapped(_ url: String) {
        blankTargetUrl = url
    }

    let internalProgressStartedNotification = "WebProgressStartedNotification"
    let internalProgressChangedNotification = "WebProgressEstimateChangedNotification"
    let internalProgressFinishedNotification = "WebProgressFinishedNotification" // Not usable

    override func loadRequest(_ request: URLRequest) {
        guard let internalWebView = value(forKeyPath: "documentView.webView") else { return }
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: internalProgressChangedNotification), object: internalWebView)
        NotificationCenter.default.addObserver(self, selector: #selector(BraveWebView.internalProgressNotification(_:)), name: NSNotification.Name(rawValue: internalProgressChangedNotification), object: internalWebView)

        if let url = request.url, let domain = url.normalizedHost() {
            braveShieldState = BraveShieldState.perNormalizedDomain[domain] ?? BraveShieldState()
        }
        super.loadRequest(request)
    }

    func loadingCompleted() {
        if internalIsLoadingEndedFlag {
            return
        }
        internalIsLoadingEndedFlag = true
        
        if safeBrowsingBlockTriggered {
            return
        }

        // Wait a tiny bit in hopes the page contents are updated. Load completed doesn't mean the UIWebView has done any rendering (or even has the JS engine for the page ready, see the delay() below)
        postAsyncToMain(0.1) {
            [weak self] in
            guard let me = self else { return }
            guard let docLoc = me.stringByEvaluatingJavaScript(from: "document.location.href") else { return }

            if docLoc != me.prevDocumentLocation {
                if !(me.URL?.absoluteString.startsWith(WebServer.sharedInstance.base) ?? false) && !docLoc.startsWith(WebServer.sharedInstance.base) {
                    me.title = me.stringByEvaluatingJavaScript(from: "document.title") ?? Foundation.URL(string: docLoc)?.baseDomain() ?? ""
                }
                #if DEBUG
                print("Adding history, TITLE:\(me.title)")
                #endif
                if let nd = me.navigationDelegate {
                    BraveWebView.containerWebViewForCallbacks.legacyWebView = me
                    nd.webViewDidFinishNavigation(me, url: me.URL)
                }
            }
            me.prevDocumentLocation = docLoc

            me.configuration.userContentController.injectJsIntoPage()
            NotificationCenter.default.post(name: Notification.Name(rawValue: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed), object: me)
            LegacyUserContentController.injectJsIntoAllFrames(me, script: "document.body.style.webkitTouchCallout='none'")

            me.stringByEvaluatingJavaScript(from: "console.log('get favicons'); __firefox__.favicons.getFavicons()")

            me.checkScriptBlockedAndBroadcastStats()
        }
    }

    // URL changes are NOT broadcast here. Have to be selective with those until the receiver code is improved to be more careful about updating
    func broadcastToPageStateDelegates() {
        delegatesForPageState.forEach {
            $0.value?.webView(self, isLoading: isLoading)
            $0.value?.webView(self, canGoBack: canGoBack)
            $0.value?.webView(self, canGoForward: canGoForward)
            $0.value?.webView(self, progressChanged: isLoading ? Float(estimatedProgress) : 1.0)
        }
    }

    func canNavigateBackward() -> Bool {
        return self.canGoBack
    }

    func canNavigateForward() -> Bool {
        return self.canGoForward
    }

    func reloadFromOrigin() {
        self.reload()
    }

    override func reload() {
        shieldStatUpdate(.reset)
        progress?.setProgress(0.3)
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.diskCapacity = 0
        URLCache.shared.memoryCapacity = 0

        if let url = URL, let domain = url.normalizedHost() {
            braveShieldState = BraveShieldState.perNormalizedDomain[domain] ?? BraveShieldState()
            (getApp().browserViewController as! BraveBrowserViewController).updateBraveShieldButtonState(animated: false)
        }
        super.reload()
        
        BraveApp.setupCacheDefaults()
    }

    override func stopLoading() {
        super.stopLoading()
        self.progress?.reset()
    }

    fileprivate func convertStringToDictionary(_ text: String?) -> [String:AnyObject]? {
        if let data = text?.data(using: String.Encoding.utf8) , text?.characters.count > 0 {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:AnyObject]
                return json
            } catch {
                print("Something went wrong")
            }
        }
        return nil
    }

    func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((AnyObject?, NSError?) -> Void)?) {
        postAsyncToMain(0) { // evaluateJavaScript is for compat with WKWebView/Firefox, I didn't vet all the uses, guard by posting to main
            let wrapped = "var result = \(javaScriptString); JSON.stringify(result)"
            let string = self.stringByEvaluatingJavaScript(from: wrapped)
            let dict = self.convertStringToDictionary(string)
            completionHandler?(dict, NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, userInfo: nil))
        }
    }

    func goToBackForwardListItem(_ item: LegacyBackForwardListItem) {
        if let index = backForwardList.backList.index(of: item) {
            let backCount = backForwardList.backList.count - index
            for _ in 0..<backCount {
                goBack()
            }
        } else if let index = backForwardList.forwardList.index(of: item) {
            for _ in 0..<(index + 1) {
                goForward()
            }
        }
    }

    override func goBack() {
        // stop scrolling so the web view will respond faster
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationPageUnload), object: self)
        super.goBack()
    }

    override func goForward() {
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationPageUnload), object: self)
        super.goForward()
    }

    class func isTopFrameRequest(_ request:URLRequest) -> Bool {
        guard let url = request.url, let mainDoc = request.mainDocumentURL else { return false }
        return url.host == mainDoc.host && url.path == mainDoc.path
    }

    // Long press context menu text selection overriding
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return super.canPerformAction(action, withSender: sender)
    }

    func injectCSS(_ css: String) {
        var js = "var script = document.createElement('style');"
        js += "script.type = 'text/css';"
        js += "script.innerHTML = '\(css)';"
        js += "document.head.appendChild(script);"
        LegacyUserContentController.injectJsIntoAllFrames(self, script: js)
    }

    enum ShieldStatUpdate {
        case reset
        case broadcastOnly
        case httpseIncrement
        case abAndTpIncrement
        case jsSetValue
        case fpIncrement
    }

    var shieldStats = ShieldBlockedStats()

    func shieldStatUpdate(_ stat: ShieldStatUpdate, _ value: Int = 1) {

        switch stat {
        case .broadcastOnly:
            break
        case .reset:
            shieldStats = ShieldBlockedStats()
        case .httpseIncrement:
            shieldStats.httpse += value
        case .abAndTpIncrement:
            shieldStats.abAndTp += value
        case .jsSetValue:
            shieldStats.js = value
        case .fpIncrement:
            shieldStats.fp += value
        }

        postAsyncToMain(0.2) { [weak self] in
            if let me = self , BraveApp.getCurrentWebView() === me {
                getApp().braveTopViewController.rightSidePanel.setShieldBlockedStats(me.shieldStats)
            }
        }
    }
}

extension BraveWebView: UIWebViewDelegate {

    class LegacyNavigationAction : WKNavigationAction {
        var writableRequest: URLRequest
        var writableType: WKNavigationType

        init(type: WKNavigationType, request: URLRequest) {
            writableType = type
            writableRequest = request
            super.init()
        }

        override var request: URLRequest { get { return writableRequest} }
        override var navigationType: WKNavigationType { get { return writableType } }
        override var sourceFrame: WKFrameInfo {
            get { return WKFrameInfo() }
        }
    }

    func webView(_ webView: UIWebView,shouldStartLoadWith request: URLRequest, navigationType: UIWebViewNavigationType ) -> Bool {
        guard let url = request.url else { return false }

        if let contextMenu = window?.rootViewController?.presentedViewController
            , contextMenu.view.tag == BraveWebViewConstants.kContextMenuBlockNavigation {
            // When showing a context menu, the webview will often still navigate (ex. news.google.com)
            // We need to block navigation using this tag.
            return false
        }
        
        if url.absoluteString == blankTargetUrl {
            blankTargetUrl = nil
            print(url)
            getApp().browserViewController.openURLInNewTab(url)
            return false
        }
        blankTargetUrl = nil

        if url.scheme == "mailto" {
            UIApplication.shared.openURL(url)
            return false
        }

        #if DEBUG
            var printedUrl = url.absoluteString
            let maxLen = 100
            if printedUrl.characters.count > maxLen {
                printedUrl =  printedUrl.substringToIndex(printedUrl.startIndex.advancedBy(maxLen)) + "..."
            }
            //print("webview load: " + printedUrl)
        #endif

        if AboutUtils.isAboutHomeURL(url) {
            setUrl(url, reliableSource: true)
            progress?.completeProgress()
            return true
        }

        if url.absoluteString.contains(specialStopLoadUrl) {
            progress?.completeProgress()
            return false
        }

        if loadingUnvalidatedHTTPSPage {
            certificateInvalidConnection = NSURLConnection(request: request, delegate: self)
            certificateInvalidConnection?.start()
            return false
        }

        if let progressCheck = progress?.shouldStartLoadWithRequest(request, navigationType: navigationType) , !progressCheck {
            return false
        }

        if let nd = navigationDelegate {
            var shouldLoad = true
            nd.webViewDecidePolicyForNavigationAction(self, url: url, shouldLoad: &shouldLoad)
            if !shouldLoad {
                return false
            }
        }

        if url.scheme.startsWith("itms") || url.host == "itunes.apple.com" {
            progress?.completeProgress()
            return false
        }

        let locationChanged = BraveWebView.isTopFrameRequest(request) && url.absoluteString != URL?.absoluteString
        if locationChanged {
            blankTargetLinkDetectionOn = true
            // TODO Maybe separate page unload from link clicked.
            NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationPageUnload), object: self)
            setUrl(url, reliableSource: true)
            #if DEBUG
                print("Page changed by shouldStartLoad: \(URL?.absoluteString ?? "")")
            #endif

            if let url = request.url, let domain = url.normalizedHost() {
                braveShieldState = BraveShieldState.perNormalizedDomain[domain] ?? BraveShieldState()
            }

            shieldStatUpdate(.reset)
        }

        broadcastToPageStateDelegates()

        return true
    }


    func webViewDidStartLoad(_ webView: UIWebView) {
        backForwardList.update()
        
        if let nd = navigationDelegate {
            // this triggers the network activity spinner
            globalContainerWebView.legacyWebView = self
            nd.webViewDidStartProvisionalNavigation(self, url: URL)
        }
        progress?.webViewDidStartLoad()

        delegatesForPageState.forEach { $0.value?.webView(self, isLoading: true) }

        #if !TEST
            HideEmptyImages.runJsInWebView(self)
        #endif

        configuration.userContentController.injectFingerprintProtection()
    }

    func webViewDidFinishLoad(_ webView: UIWebView) {
        assert(Thread.isMainThread)

        // browserleaks canvas requires injection at this point
        configuration.userContentController.injectFingerprintProtection()

        guard let pageInfo = stringByEvaluatingJavaScript(from: "document.readyState.toLowerCase() + '|' + document.title") else {
            return
        }
        
        if let isSafeBrowsingBlock = stringByEvaluatingJavaScript(from: "document['BraveSafeBrowsingPageResult']") {
            safeBrowsingBlockTriggered = (isSafeBrowsingBlock as NSString).boolValue
        }

        let pageInfoArray = pageInfo.components(separatedBy: "|")

        let readyState = pageInfoArray.first // ;print("readyState:\(readyState)")
        if let t = pageInfoArray.last , !t.isEmpty {
            title = t
        }
        progress?.webViewDidFinishLoad(documentReadyState: readyState)

        backForwardList.update()
        broadcastToPageStateDelegates()
    }

    func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
        if (error.code == NSURLErrorCancelled) {
            return
        }
        print("didFailLoadWithError: \(error)")

        if (error.domain == NSURLErrorDomain) {
            if (error.code == NSURLErrorServerCertificateHasBadDate      ||
                error?.code == NSURLErrorServerCertificateUntrusted         ||
                error?.code == NSURLErrorServerCertificateHasUnknownRoot    ||
                error?.code == NSURLErrorServerCertificateNotYetValid)
            {
                guard let errorUrl = error.userInfo[NSURLErrorFailingURLErrorKey] as? Foundation.URL else { return }

                if errorUrl.absoluteString.regexReplacePattern("^.+://", with: "") != URL?.absoluteString.regexReplacePattern("^.+://", with: "") {
                    print("only show cert error for top-level page")
                    return
                }

                let alert = UIAlertController(title: "Certificate Error", message: "The identity of \(errorUrl.absoluteString) can't be verified", preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.default) {
                    handler in
                    self.stopLoading()
                    webView.loadRequest(URLRequest(url: Foundation.URL(string: self.specialStopLoadUrl)!))

                    // The current displayed url is wrong, so easiest hack is:
                    if (self.canGoBack) { // I don't think the !canGoBack case needs handling
                        self.goBack()
                        self.goForward()
                    }
                    })
                alert.addAction(UIAlertAction(title: "Continue", style: UIAlertActionStyle.default) {
                    handler in
                    self.loadingUnvalidatedHTTPSPage = true;
                    self.loadRequest(URLRequest(url: errorUrl))
                    })

                #if !TEST
                    window?.rootViewController?.present(alert, animated: true, completion: nil)
                #endif
                return
            }
        }

        NotificationCenter.default
            .post(name: Notification.Name(rawValue: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed), object: self)

        // The error may not be the main document that failed to load. Check if the failing URL matches the URL being loaded

        if let error = error, let errorUrl = error.userInfo[NSURLErrorFailingURLErrorKey] as? Foundation.URL {
            var handled = false
            if error.code == -1009 /*kCFURLErrorNotConnectedToInternet*/ {
                let cache = URLCache.shared.cachedResponse(for: URLRequest(url: errorUrl))
                if let html = cache?.data.utf8EncodedString , html.characters.count > 100 {
                    loadHTMLString(html, baseURL: errorUrl)
                    handled = true
                }
            }

            let kPluginIsHandlingLoad = 204 // mp3 for instance, returns an error to webview that a plugin is taking over, which is correct
            if !handled && URL?.absoluteString == errorUrl.absoluteString && error.code != kPluginIsHandlingLoad {
                if let nd = navigationDelegate {
                    globalContainerWebView.legacyWebView = self
                    nd.webViewDidFailNavigation(self, withError: error ?? NSError.init(domain: "", code: 0, userInfo: nil))
                }
            }
        }
        progress?.didFailLoadWithError()
        broadcastToPageStateDelegates()
    }
}

extension BraveWebView : NSURLConnectionDelegate, NSURLConnectionDataDelegate {
    func connection(_ connection: NSURLConnection, willSendRequestFor challenge: URLAuthenticationChallenge) {
        guard let trust = challenge.protectionSpace.serverTrust else { return }
        let cred = URLCredential(trust: trust)
        challenge.sender?.use(cred, for: challenge)
        challenge.sender?.continueWithoutCredential(for: challenge)
        loadingUnvalidatedHTTPSPage = false
    }

    func connection(_ connection: NSURLConnection, didReceive response: URLResponse) {
        guard let url = URL else { return }
        loadingUnvalidatedHTTPSPage = false
        loadRequest(URLRequest(url: url))
        certificateInvalidConnection?.cancel()
    }    
}
