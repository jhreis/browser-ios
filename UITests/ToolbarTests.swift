/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import UIKit
import EarlGrey

class ToolbarTests: KIFTestCase, UITextFieldDelegate {
    fileprivate var webRoot: String!

    override func setUp() {
        webRoot = SimplePageServer.start()
        BrowserUtils.dismissFirstRunUI(tester())
    }

    func testURLEntry() {
        let textField = tester().waitForView(withAccessibilityIdentifier: "url") as! UITextField
        tester().tapView(withAccessibilityIdentifier: "url")
        tester().enterText(intoCurrentFirstResponder: "foobar")
        tester().tapView(withAccessibilityIdentifier: "goBack")
        XCTAssertNotEqual(textField.text, "foobar", "Verify that the URL bar text clears on about:home")

        // 127.0.0.1 doesn't cause http:// to be hidden. localhost does. Both will work.
        let localhostURL = webRoot.replacingOccurrences(of: "127.0.0.1", with: "localhost", options: NSString.CompareOptions(), range: nil)
        let url = "\(localhostURL)/numberedPage.html?page=1"

        // URL without "http://".
        let displayURL = "\(localhostURL)/numberedPage.html?page=1".substring(from: url.characters.index(url.startIndex, offsetBy: "http://".characters.count))

        EarlGrey.select(elementWithMatcher: grey_accessibilityID("url")).perform(grey_tap())
        EarlGrey.select(elementWithMatcher: grey_accessibilityID("address")).perform(grey_replaceText(url))
        EarlGrey.select(elementWithMatcher: grey_accessibilityID("address")).perform(grey_typeText("\n"))
        tester().waitForAnimationsToFinish()
        XCTAssertEqual(textField.text, displayURL, "URL matches page URL")

        tester().tapView(withAccessibilityIdentifier: "url")
        tester().enterText(intoCurrentFirstResponder: "foobar")
        tester().tapView(withAccessibilityIdentifier: "goBack")
        XCTAssertEqual(textField.text, displayURL, "Verify that text reverts to page URL after entering text")

        tester().tapView(withAccessibilityIdentifier: "url")
        tester().clearTextFromFirstResponder()
        tester().tapView(withAccessibilityIdentifier: "goBack")
        XCTAssertEqual(textField.text, displayURL, "Verify that text reverts to page URL after clearing text")
    }

    func testUserInfoRemovedFromURL() {
        let hostWithUsername = webRoot.replacingOccurrences(of: "127.0.0.1", with: "username:password@127.0.0.1", options: NSString.CompareOptions(), range: nil)
        let urlWithUserInfo = "\(hostWithUsername)/numberedPage.html?page=1"
        let url = "\(webRoot!)/numberedPage.html?page=1"

        let urlFieldAppeared = GREYCondition(name: "Wait for URL field", block: { _ in
            var errorOrNil: NSError?
            EarlGrey.select(elementWithMatcher: grey_accessibilityID("url"))
                .assert(grey_notNil(), error: &errorOrNil)
            return errorOrNil == nil
        }).wait(withTimeout: 10)
        GREYAssertTrue(urlFieldAppeared, reason: "Failed to display URL field")

        EarlGrey.select(elementWithMatcher: grey_accessibilityID("url")).perform(grey_tap())
        EarlGrey.select(elementWithMatcher: grey_accessibilityID("address")).perform(grey_replaceText(urlWithUserInfo))
        EarlGrey.select(elementWithMatcher: grey_accessibilityID("address")).perform(grey_typeText("\n"))
        tester().waitForAnimationsToFinish()

        let urlField = tester().waitForView(withAccessibilityIdentifier: "url") as! UITextField
        XCTAssertEqual("http://" + urlField.text!, url)
    }

    override func tearDown() {
        let previousOrientation = UIDevice.current.value(forKey: "orientation") as! Int
        if previousOrientation == UIInterfaceOrientation.landscapeLeft.rawValue {
            // Rotate back to portrait
            let value = UIInterfaceOrientation.portrait.rawValue
            UIDevice.current.setValue(value, forKey: "orientation")
        }
        BrowserUtils.resetToAboutHome(tester())
        BrowserUtils.clearPrivateData(tester: tester())
    }
}
