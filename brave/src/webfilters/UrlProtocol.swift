/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import CoreData

var requestCount = 0
let markerRequestHandled = "request-already-handled"

class URLProtocol: Foundation.URLProtocol {

    var connection: NSURLConnection?
    var disableJavascript = false
    static var testShieldState: BraveShieldState?

    override class func canInit(with request: URLRequest) -> Bool {
        //print("Request #\(requestCount++): URL = \(request.mainDocumentURL?.absoluteString)")
        if let scheme = request.url?.scheme , !scheme.startsWith("http") {
            return false
        }

        if Foundation.URLProtocol.property(forKey: markerRequestHandled, in: request) != nil {
            return false
        }

        guard let url = request.url else { return false }

        let shieldState = testShieldState != nil ? testShieldState! : getShields(request)
        if shieldState.isAllOff() {
            return false
        }
        
        let useCustomUrlProtocol =
            shieldState.isOnScriptBlocking() ?? false ||
            (shieldState.isOnAdBlockAndTp() ?? false && TrackingProtection.singleton.shouldBlock(request)) ||
                (shieldState.isOnAdBlockAndTp() ?? false && AdBlocker.singleton.shouldBlock(request)) ||
                (shieldState.isOnSafeBrowsing() ?? false && SafeBrowsing.singleton.shouldBlock(request)) ||
                (shieldState.isOnHTTPSE() ?? false && HttpsEverywhere.singleton.tryRedirectingUrl(url) != nil)

        return useCustomUrlProtocol
    }

    // Tries to use the UA to match to requesting webview.
    // If it fails use current selected webview
    /*
     - request arrives in protocol
     - protocol maps request to brave web view
     - brave web view has shield state, grab that state, apply it to request
     */
    static func getShields(_ request: URLRequest) -> BraveShieldState {
        let ua = request.allHTTPHeaderFields?["User-Agent"]
        var webViewShield:BraveShieldState? = nil
        let shieldResult = BraveShieldState()

        if let webView = WebViewToUAMapper.userAgentToWebview(ua) {
            webViewShield = webView.braveShieldState
        } else {
            webViewShield = getApp().tabManager.selectedTab?.webView?.braveShieldState
        }

        if let webViewShield = webViewShield , webViewShield.isAllOff() {
            shieldResult.setState(BraveShieldState.kAllOff, on: true)
            return shieldResult
        }

        shieldResult.setStateFromPerPageShield(webViewShield)
        return shieldResult
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    fileprivate class func cloneRequest(_ request: URLRequest) -> NSMutableURLRequest {
        // Reportedly not safe to use built-in cloning methods: http://openradar.appspot.com/11596316
        let newRequest = NSMutableURLRequest(url: request.url!, cachePolicy: request.cachePolicy, timeoutInterval: request.timeoutInterval)
        newRequest.allHTTPHeaderFields = request.allHTTPHeaderFields
        if let m = request.httpMethod {
            newRequest.httpMethod = m
        }
        if let b = request.httpBodyStream {
            newRequest.httpBodyStream = b
        }
        if let b = request.httpBody {
            newRequest.httpBody = b
        }
        newRequest.httpShouldUsePipelining = request.httpShouldUsePipelining
        newRequest.mainDocumentURL = request.mainDocumentURL
        newRequest.networkServiceType = request.networkServiceType
        return newRequest
    }

    func returnEmptyResponse() {
        // To block the load nicely, return an empty result to the client.
        // Nice => UIWebView's isLoading property gets set to false
        // Not nice => isLoading stays true while page waits for blocked items that never arrive

        // IIRC expectedContentLength of 0 is buggy (can't find the reference now).
        guard let url = request.url else { return }
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: 1, textEncodingName: "utf-8")
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    //a special artificial response that includes content that explains why the page was
    //blocked by phishing detection
    func returnBlockedPageResponse() {
        let path = Bundle.main.path(forResource: "SafeBrowsingError", ofType: "html")!
        let src = try! NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) as String
        guard let url = request.url else { return }
        
        let blockedResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1", headerFields: nil)
        client?.urlProtocol(self, didReceive: blockedResponse!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: src.data(using: String.Encoding.utf8)!)
        client?.urlProtocolDidFinishLoading(self)
    }
    

    static var blankPixel: Data? = {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        UIGraphicsBeginImageContext(rect.size)
        let c = UIGraphicsGetCurrentContext()
        c?.setFillColor(UIColor.clear.cgColor)
        c?.fill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return UIImageJPEGRepresentation(image!, 0.4)
    }()

    func returnBlankPixel() {
        guard let url = request.url, let pixel = URLProtocol.blankPixel else { return }
        let response = URLResponse(url: url, mimeType: "image/jpeg", expectedContentLength: pixel.count, textEncodingName: nil)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: pixel)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func startLoading() {
        let newRequest = URLProtocol.cloneRequest(request)
        Foundation.URLProtocol.setProperty(true, forKey: markerRequestHandled, in: newRequest)

        let shieldState = URLProtocol.getShields(request)
        let ua = request.allHTTPHeaderFields?["User-Agent"]

        // HttpsEverywhere re-checking is O(1) due to internal cache,
        if let url = request.url, let redirectedUrl = shieldState.isOnHTTPSE() ?? false ? HttpsEverywhere.singleton.tryRedirectingUrl(url) : nil {
            // TODO handle https redirect loop
            newRequest.url = redirectedUrl
            #if DEBUG
                //print(url.absoluteString + " [HTTPE to] " + redirectedUrl.absoluteString)
            #endif

            if url == request.mainDocumentURL {
                returnEmptyResponse()
                postAsyncToMain(0) {
                    WebViewToUAMapper.userAgentToWebview(ua)?.loadRequest(newRequest)
                }
            } else {
                connection = NSURLConnection(request: newRequest as URLRequest, delegate: self)
                postAsyncToMain(0.1) {
                    WebViewToUAMapper.userAgentToWebview(ua)?.shieldStatUpdate(.httpseIncrement)
                }
            }
            return
        } else if shieldState.isOnSafeBrowsing() ?? false && SafeBrowsing.singleton.shouldBlock(request) {
            
            returnBlockedPageResponse()

            return
        } else if shieldState.isOnAdBlockAndTp() ?? false && (TrackingProtection.singleton.shouldBlock(request) || AdBlocker.singleton.shouldBlock(request)) {
            if request.url?.host?.contains("pcworldcommunication.d2.sc.omtrdc.net") ?? false || request.URL?.host?.contains("b.scorecardresearch.com") ?? false {
                // sites such as macworld.com need this, or links are not clickable
                returnBlankPixel()
            } else {
                returnEmptyResponse()
            }
            postAsyncToMain(0.1) {
                WebViewToUAMapper.userAgentToWebview(ua)?.shieldStatUpdate(.abAndTpIncrement)
            }
            return
        }

        disableJavascript = shieldState.isOnScriptBlocking() ?? false

        if let url = request.url?.absoluteString , disableJavascript && (url.contains(".js?") || url.contains(".js#") || url.endsWith(".js")) {
            returnEmptyResponse()
            return
        }

        self.connection = NSURLConnection(request: newRequest as URLRequest, delegate: self)
    }

    override func stopLoading() {
        connection?.cancel()
        self.connection = nil
    }

    // MARK: NSURLConnection
    func connection(_ connection: NSURLConnection!, didReceiveResponse response: URLResponse!) {
        var returnedResponse: URLResponse = response
        if let response = response as? HTTPURLResponse,
            let url = response.url
            , disableJavascript && !AboutUtils.isAboutURL(url)
        {
            var fields = response.allHeaderFields as? [String : String] ?? [String : String]()
            fields["X-WebKit-CSP"] = "script-src none"
            returnedResponse = HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: "HTTP/1.1" /*not used*/, headerFields: fields)!
        }
        self.client!.urlProtocol(self, didReceive: returnedResponse, cacheStoragePolicy: .allowed)
    }

    func connection(_ connection: NSURLConnection, willSendRequest request: URLRequest, redirectResponse response: URLResponse?) -> URLRequest?
    {
        if let response = response {
            client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
        }
        return request
    }

    func connection(_ connection: NSURLConnection!, didReceiveData data: Data!) {
        self.client!.urlProtocol(self, didLoad: data)
        //self.mutableData.appendData(data)
    }

    func connectionDidFinishLoading(_ connection: NSURLConnection!) {
        self.client!.urlProtocolDidFinishLoading(self)
    }

    func connection(_ connection: NSURLConnection!, didFailWithError error: NSError!) {
        self.client!.urlProtocol(self, didFailWithError: error)
        print("* Error url: \(self.request.URLString)\n* Details: \(error)")
    }
}
