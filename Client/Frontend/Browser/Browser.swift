/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import Shared

import XCGLogger

private let log = Logger.browserLogger

protocol BrowserHelper {
    static func scriptMessageHandlerName() -> String?
    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage)
}


protocol BrowserDelegate {
    func browser(_ browser: Browser, didAddSnackbar bar: SnackBar)
    func browser(_ browser: Browser, didRemoveSnackbar bar: SnackBar)
    func browser(_ browser: Browser, didSelectFindInPageForSelection selection: String)
    func browser(_ browser: Browser, didCreateWebView webView: BraveWebView)
    func browser(_ browser: Browser, willDeleteWebView webView: BraveWebView)
}

struct DangerousReturnWKNavigation {
    static let emptyNav = WKNavigation()
}

class UIImageWithNotify {
    struct WeakImageView {
        weak var view : UIImageView?
        init(_ i: UIImageView?) {
            self.view = i
        }
    }
    var image: UIImage? {
        didSet {
            // notify listeners, and remove dead ones
            listenerImages = listenerImages.filter {
                $0.view?.image = image
                return $0.view != nil
            }
        }
    }
    var listenerImages = [WeakImageView]()
}

class Browser: NSObject, BrowserWebViewDelegate {
    fileprivate var _isPrivate: Bool = false
    internal fileprivate(set) var isPrivate: Bool {
        get {
            if #available(iOS 9, *) {
                return _isPrivate
            } else {
                return false
            }
        }
        set {
            if newValue {
                PrivateBrowsing.singleton.enter()
            }
            else {
                PrivateBrowsing.singleton.exit()
            }
            _isPrivate = newValue
        }
    }

    var webView: BraveWebView?
    var browserDelegate: BrowserDelegate?
    var bars = [SnackBar]()
    var favicons = [String:Favicon]() // map baseDomain() to favicon
    var lastExecutedTime: Timestamp?
    var sessionData: SessionData?
    var lastRequest: URLRequest? = nil
    var restoring: Bool = false
    var pendingScreenshot = false

    /// The last title shown by this tab. Used by the tab tray to show titles for zombie tabs.
    var lastTitle: String?

    /// Whether or not the desktop site was requested with the last request, reload or navigation. Note that this property needs to
    /// be managed by the web view's navigation delegate.
    var desktopSite: Bool = false

    fileprivate(set) var screenshot = UIImageWithNotify()
    var screenshotUUID: UUID?

    fileprivate var helperManager: HelperManager? = nil
    fileprivate var configuration: WKWebViewConfiguration? = nil

    /// Any time a browser tries to make requests to display a Javascript Alert and we are not the active
    /// browser instance, queue it for later until we become foregrounded.
    fileprivate var alertQueue = [JSAlertInfo]()

    init(configuration: WKWebViewConfiguration, isPrivate: Bool) {
        self.configuration = configuration
        super.init()
        self.isPrivate = isPrivate
    }

#if BRAVE && IMAGE_SWIPE_ON
    let screenshotsForHistory = ScreenshotsForHistory()

    func screenshotForBackHistory() -> UIImage? {
        webView?.backForwardList.update()
        guard let prevLoc = webView?.backForwardList.backItem?.URL.absoluteString else { return nil }
        return screenshotsForHistory.get(prevLoc)
    }

    func screenshotForForwardHistory() -> UIImage? {
        webView?.backForwardList.update()
        guard let next = webView?.backForwardList.forwardItem?.URL.absoluteString else { return nil }
        return screenshotsForHistory.get(next)
    }
#endif

    class func toTab(_ browser: Browser) -> RemoteTab? {
        if let displayURL = browser.displayURL {
            let hl = browser.historyList;
            let history = Array(hl.filter(RemoteTab.shouldIncludeURL).reverse())
            return RemoteTab(clientGUID: nil,
                URL: displayURL,
                title: browser.displayTitle,
                history: history,
                lastUsed: NSDate.now(),
                icon: nil)
        } else if let sessionData = browser.sessionData , !sessionData.urls.isEmpty {
            let history = Array(sessionData.urls.filter(RemoteTab.shouldIncludeURL).reverse())
            if let displayURL = history.first {
                return RemoteTab(clientGUID: nil,
                    URL: displayURL,
                    title: browser.displayTitle,
                    history: history,
                    lastUsed: sessionData.lastUsedTime,
                    icon: nil)
            }
        }

        return nil
    }

    weak var navigationDelegate: WKCompatNavigationDelegate? {
        didSet {
            if let webView = webView {
                webView.navigationDelegate = navigationDelegate
            }
        }
    }

    func createWebview(useDesktopUserAgent:Bool = false) {
        assert(Thread.isMainThread)
        if !Thread.isMainThread {
            return
        }

        if webView == nil {
#if !BRAVE
            assert(configuration != nil, "Create webview can only be called once")
            configuration!.userContentController = WKUserContentController()
            configuration!.preferences = WKPreferences()
            configuration!.preferences.javaScriptCanOpenWindowsAutomatically = false
#endif
            let webView = BraveWebView(frame: CGRect.zero, useDesktopUserAgent: useDesktopUserAgent)
            configuration = nil

            webView.accessibilityLabel = NSLocalizedString("Web content", comment: "Accessibility label for the main web content view")
#if !BRAVE
            webView.allowsBackForwardNavigationGestures = true
#endif
            webView.backgroundColor = UIColor.lightGray

            // Turning off masking allows the web content to flow outside of the scrollView's frame
            // which allows the content appear beneath the toolbars in the BrowserViewController
            webView.scrollView.layer.masksToBounds = false
            webView.navigationDelegate = navigationDelegate
            helperManager = HelperManager(webView: webView)

            restore(webView)

            self.webView = webView
            browserDelegate?.browser(self, didCreateWebView: self.webView!)

#if !BRAVE
            // lastTitle is used only when showing zombie tabs after a session restore.
            // Since we now have a web view, lastTitle is no longer useful.
            lastTitle = nil
#endif
            lastExecutedTime = Date.now()
        }
    }

    func restore(_ webView: BraveWebView) {
        // Pulls restored session data from a previous SavedTab to load into the Browser. If it's nil, a session restore
        // has already been triggered via custom URL, so we use the last request to trigger it again; otherwise,
        // we extract the information needed to restore the tabs and create a NSURLRequest with the custom session restore URL
        // to trigger the session restore via custom handlers
        if let sessionData = self.sessionData {
            #if !BRAVE // no idea why restoring is needed, but it causes the displayed url not to update, which is bad
                restoring = true
            #endif
            lastTitle = sessionData.currentTitle
            if let title = lastTitle {
                webView.title = title
            }
            var updatedURLs = [String]()
            for url in sessionData.urls {
                let updatedURL = WebServer.sharedInstance.updateLocalURL(url)!.absoluteString
                updatedURLs.append(updatedURL)
            }
            let currentPage = sessionData.currentPage
            self.sessionData = nil
            var jsonDict = [String: AnyObject]()
            jsonDict["history"] = updatedURLs as AnyObject?
            jsonDict["currentPage"] = currentPage as AnyObject?
            let escapedJSON = JSON.stringify(jsonDict, pretty: false).stringByAddingPercentEncodingWithAllowedCharacters(CharacterSet.URLQueryAllowedCharacterSet())!
            let restoreURL = URL(string: "\(WebServer.sharedInstance.base)/about/sessionrestore?history=\(escapedJSON)")
            lastRequest = URLRequest(URL: restoreURL!)
            webView.loadRequest(lastRequest!)
        } else if let request = lastRequest {
            webView.loadRequest(request)
        } else {
            log.error("creating webview with no lastRequest and no session data: \(self.url)")
        }
    }

    func deleteWebView(isTabDeleted: Bool) {
        assert(Thread.isMainThread) // to find and remove these cases in debug
        guard let wv = webView else { return }

        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).sync {
            if !isTabDeleted {
                self.lastTitle = self.title
                let currentItem: LegacyBackForwardListItem! = wv.backForwardList.currentItem
                // Freshly created web views won't have any history entries at all.
                // If we have no history, abort.
                if currentItem != nil {
                    let backList = wv.backForwardList.backList ?? []
                    let forwardList = wv.backForwardList.forwardList ?? []
                    let urls = (backList + [currentItem] + forwardList).map { $0.URL }
                    let currentPage = -forwardList.count
                    self.sessionData = SessionData(currentPage: currentPage, currentTitle: self.title, urls: urls, lastUsedTime: self.lastExecutedTime ?? Date.now())
                }
            }
            self.browserDelegate?.browser(self, willDeleteWebView: wv)
            self.webView = nil
        }
    }

    deinit {
        deleteWebView(isTabDeleted: true)
    }

    var loading: Bool {
        return webView?.isLoading ?? false
    }

    var estimatedProgress: Double {
        return webView?.estimatedProgress ?? 0
    }

    var backList: [LegacyBackForwardListItem]? {
        return webView?.backForwardList.backList
    }

    var forwardList: [LegacyBackForwardListItem]? {
        return webView?.backForwardList.forwardList
    }

    var historyList: [URL] {
        func listToUrl(_ item: LegacyBackForwardListItem) -> URL { return item.URL as URL }
        var tabs = self.backList?.map(listToUrl) ?? [URL]()
        tabs.append(self.url!)
        return tabs
    }

    var title: String? {
        return webView?.title
    }

    var displayTitle: String {
        if let title = webView?.title , !title.isEmpty {
            return title
        }

        guard let lastTitle = lastTitle , !lastTitle.isEmpty else {
            return displayURL?.absoluteString ??  ""
        }

        return lastTitle
    }

    var currentInitialURL: URL? {
        get {
            let initalURL = self.webView?.backForwardList.currentItem?.initialURL
            return initalURL as URL?
        }
    }

    var displayFavicon: Favicon? {
        assert(Thread.isMainThread)
        var width = 0
        var largest: Favicon?
        for icon in favicons {
            if icon.0 != webView?.URL?.baseDomain() {
                continue
            }
            if icon.1.width > width {
                width = icon.1.width!
                largest = icon.1
            }
        }
        return largest
    }

    var url: URL? {
        guard let resolvedURL = webView?.URL ?? lastRequest?.url else {
            guard let sessionData = sessionData else { return nil }
            return sessionData.urls.last as URL?
        }
        return resolvedURL
    }

    var displayURL: URL? {
        if let url = url {
            if ReaderModeUtils.isReaderModeURL(url) {
                return ReaderModeUtils.decodeURL(url)
            }

            if ErrorPageHelper.isErrorPageURL(url) {
                let decodedURL = ErrorPageHelper.originalURLFromQuery(url)
                if !AboutUtils.isAboutURL(decodedURL) {
                    return decodedURL
                } else {
                    return nil
                }
            }

            if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) , (urlComponents.user != nil) || (urlComponents.password != nil) {
                urlComponents.user = nil
                urlComponents.password = nil
                return urlComponents.url
            }

            if !AboutUtils.isAboutURL(url) && !url.absoluteString.contains(WebServer.sharedInstance.base) {
                return url
            }
        }
        return nil
    }

    var canGoBack: Bool {
        return webView?.canGoBack ?? false
    }

    var canGoForward: Bool {
        return webView?.canGoForward ?? false
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func goToBackForwardListItem(_ item: LegacyBackForwardListItem) {
        webView?.goToBackForwardListItem(item)
    }

    func loadRequest(_ request: URLRequest) -> WKNavigation? {
        if let webView = webView {
            lastRequest = request
#if !BRAVE
            return webView.loadRequest(request)
#else
            webView.loadRequest(request); return DangerousReturnWKNavigation.emptyNav;
#endif
          }
        return nil
    }

    func stop() {
        webView?.stopLoading()
    }

    func reload() {
        webView?.reloadFromOrigin()
    }

    func addHelper(_ helper: BrowserHelper) {
        helperManager!.addHelper(helper)
    }

    func getHelper<T>(_ classType: T.Type) -> T? {
        return helperManager?.getHelper(classType)
    }

    func removeHelper<T>(_ classType: T.Type) {
        helperManager?.removeHelper(classType)
    }

    func hideContent(_ animated: Bool = false) {
        webView?.isUserInteractionEnabled = false
        if animated {
            UIView.animate(withDuration: 0.25, animations: { () -> Void in
                self.webView?.alpha = 0.0
            })
        } else {
            webView?.alpha = 0.0
        }
    }

    func showContent(_ animated: Bool = false) {
        webView?.isUserInteractionEnabled = true
        if animated {
            UIView.animate(withDuration: 0.25, animations: { () -> Void in
                self.webView?.alpha = 1.0
            })
        } else {
            webView?.alpha = 1.0
        }
    }

    func addSnackbar(_ bar: SnackBar) {
        bars.append(bar)
        browserDelegate?.browser(self, didAddSnackbar: bar)
    }

    func removeSnackbar(_ bar: SnackBar) {
        if let index = bars.index(of: bar) {
            bars.remove(at: index)
            browserDelegate?.browser(self, didRemoveSnackbar: bar)
        }
    }

    func removeAllSnackbars() {
        // Enumerate backwards here because we'll remove items from the list as we go.
        for i in (0..<bars.count).reversed() {
            let bar = bars[i]
            removeSnackbar(bar)
        }
    }

    func expireSnackbars() {
        // Enumerate backwards here because we may remove items from the list as we go.
        for i in (0..<bars.count).reversed() {
            let bar = bars[i]
            if !bar.shouldPersist(self) {
                removeSnackbar(bar)
            }
        }
    }


    func setScreenshot(_ screenshot: UIImage?, revUUID: Bool = true) {
#if IMAGE_SWIPE_ON
        if let loc = webView?.URL?.absoluteString, let screenshot = screenshot {
            screenshotsForHistory.addForLocation(loc, image: screenshot)
        }
#endif
        guard let screenshot = screenshot else { return }

        self.screenshot.image = screenshot
        if revUUID {
            self.screenshotUUID = UUID()
        }
    }

//    func toggleDesktopSite() {
//        desktopSite = !desktopSite
//        reload()
//    }

    func queueJavascriptAlertPrompt(_ alert: JSAlertInfo) {
        alertQueue.append(alert)
    }

    func dequeueJavascriptAlertPrompt() -> JSAlertInfo? {
        guard !alertQueue.isEmpty else {
            return nil
        }
        return alertQueue.removeFirst()
    }

    func cancelQueuedAlerts() {
        alertQueue.forEach { alert in
            alert.cancel()
        }
    }

    fileprivate func browserWebView(_ browserWebView: BrowserWebView, didSelectFindInPageForSelection selection: String) {
        browserDelegate?.browser(self, didSelectFindInPageForSelection: selection)
    }
}

private class HelperManager: NSObject, WKScriptMessageHandler {
    fileprivate var helpers = [String: BrowserHelper]()
    fileprivate weak var webView: BraveWebView?

    init(webView: BraveWebView) {
        self.webView = webView
    }

    @objc func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        for helper in helpers.values {
            if let scriptMessageHandlerName = type(of: helper).scriptMessageHandlerName() {
                if scriptMessageHandlerName == message.name {
                    helper.userContentController(userContentController, didReceiveScriptMessage: message)
                    return
                }
            }
        }
    }

    func addHelper(_ helper: BrowserHelper) {
        if let _ = helpers["\(type(of: helper))"] {
            assertionFailure("Duplicate helper added: \(type(of: helper))")
        }

        helpers["\(type(of: helper))"] = helper

        // If this helper handles script messages, then get the handler name and register it. The Browser
        // receives all messages and then dispatches them to the right BrowserHelper.
        if let scriptMessageHandlerName = type(of: helper).scriptMessageHandlerName() {
            webView?.configuration.userContentController.addScriptMessageHandler(self, name: scriptMessageHandlerName)
        }
    }

    func getHelper<T>(_ classType: T.Type) -> T? {
        return helpers["\(classType)"] as? T
    }

    func removeHelper<T>(_ classType: T.Type) {
        if let t = T.self as? BrowserHelper.Type, let name = t.scriptMessageHandlerName() {
            webView?.configuration.userContentController.removeScriptMessageHandler(name: name)
        }
        helpers.removeValue(forKey: "\(classType)")
    }
}

private protocol BrowserWebViewDelegate: class {
    func browserWebView(_ browserWebView: BrowserWebView, didSelectFindInPageForSelection selection: String)
}

private class BrowserWebView: WKWebView, MenuHelperInterface {
    fileprivate weak var delegate: BrowserWebViewDelegate?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return action == MenuHelper.SelectorFindInPage
    }

    @objc func menuHelperFindInPage(_ sender: Notification) {
        evaluateJavaScript("getSelection().toString()") { result, _ in
            let selection = result as? String ?? ""
            self.delegate?.browserWebView(self, didSelectFindInPageForSelection: selection)
        }
    }

    fileprivate override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The find-in-page selection menu only appears if the webview is the first responder.
        becomeFirstResponder()

        return super.hitTest(point, with: event)
    }
}
