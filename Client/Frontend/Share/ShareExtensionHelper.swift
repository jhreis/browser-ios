/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

private let log = Logger.browserLogger

@objc class URLActivityItemSource : NSObject, UIActivityItemSource {
    var urlString:String
    var item:NSExtensionItem
    init(urlString:String, item:NSExtensionItem) {
        self.urlString = urlString
        self.item = item
        
        
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return self.urlString
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivityType) -> Any? {
        return self.item
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivityType?) -> String {
        
        return "org.appextension.fill-browser-action"
    }
}


class ShareExtensionHelper: NSObject {
    fileprivate weak var selectedTab: Browser?

    fileprivate let selectedURL: URL
    fileprivate var onePasswordExtensionItem: NSExtensionItem!
    var extItem2:NSExtensionItem!
    fileprivate let activities: [UIActivity]
    var pageDetails:NSDictionary!

    init(url: URL, tab: Browser?, activities: [UIActivity]) {
        self.selectedURL = url
        self.selectedTab = tab
        self.activities = activities
    }
    
    func setupExtensionItem(_ completionHandler:@escaping ()->()) {

        let selectedWebView = self.selectedTab?.webView
        
        if selectedWebView == nil {
            NSLog("Nil selected web view, returning nil UIActivityController")
            return
        }

        OnePasswordExtension.shared().createExtensionItem(forWebView: selectedWebView!, completion: {
            [weak self] (extensionItem, error) -> Void in
            if extensionItem == nil {
                log.error("Failed to create the password manager extension item: \(error).")
                return
            }
            
            self?.onePasswordExtensionItem = extensionItem

            completionHandler()

            
        })

    }

    func createActivityViewController(_ completionHandler: @escaping (Bool) -> Void) -> UIActivityViewController? {
        var activityItems = [AnyObject]()

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = selectedTab?.url?.absoluteString ?? selectedURL.absoluteString
        printInfo.outputType = .general
        activityItems.append(printInfo)

        if let tab = selectedTab {
            activityItems.append(BrowserPrintPageRenderer(browser: tab))
        }

        if let title = selectedTab?.title {
            activityItems.append(TitleActivityItemProvider(title: title))
        }
        
        let selectedWebView = self.selectedTab?.webView
        
        if selectedWebView == nil {
            NSLog("Nil selected web view, returning nil UIActivityController")
            return nil
        }

        
        if let url = selectedTab?.webView?.URL {
            if self.onePasswordExtensionItem != nil {
                let act:URLActivityItemSource = URLActivityItemSource(urlString: url.absoluteString!, item: self.onePasswordExtensionItem)
                activityItems.append(act)
            }
        }
        
        
        let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: activities)

        // Hide 'Add to Reading List' which currently uses Safari.
        // We would also hide View Later, if possible, but the exclusion list doesn't currently support
        // third-party activity types (rdar://19430419).
        activityViewController.excludedActivityTypes = [
            UIActivityType.addToReadingList,
        ]
        

        activityViewController.completionWithItemsHandler = {
            activityType, completed, returnedItems, activityError in
            
            defer {
                completionHandler(completed)
            }
            
            if activityType == nil || !completed || returnedItems == nil || returnedItems!.count == 0 {

                return
            }
            
            //'password-find-login-action' is for Keeper, matches 'password'
            if activityType!.contains("com.dashlane")
                || activityType!.contains("lastpass")
                || activityType!.contains("password") {
//                NSLog("obtained \(returnedItems!.count) items")
                let item = returnedItems![0] as? NSExtensionItem
                
                if let itemProvider = item!.attachments?.first as? NSItemProvider {
//                    debugPrint(itemProvider.registeredTypeIdentifiers)
                        let ident = kUTTypePropertyList as String
                        if itemProvider.hasItemConformingToTypeIdentifier(ident) {
                            itemProvider.loadItem(forTypeIdentifier: ident, options: nil) { (dict, error) in
                                if error != nil {
                                    NSLog("Error loading from password extension \(error)")
                                }
                                else if dict != nil {
                                    
                                    OnePasswordExtension.shared().fillReturnedItems(returnedItems, intoWebView: selectedWebView!, completion: { (success, returnedItemsError) -> Void in
                                                        if !success {
                                                            log.error("Failed to fill item into webview: \(returnedItemsError).")
                                                        }
                                                    })

                                }
                            }
                            
                            
                            
                        }

                }
                

            }
        }
        
        return activityViewController
    }
    }
