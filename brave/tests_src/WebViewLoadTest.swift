/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */
import Foundation
import XCTest
@testable import Client
import Shared


var groupA = ["businessinsider.com", "kotaku.com", "cnn.com"]
var groupB = ["imore.com", "nytimes.com"]

class WebViewLoadTest: XCTestCase {

    /* The following uses XCodes built-in performance measurement XCTest.measureBlock which has no way of handling
     unexpectedly long loads. Ideally if the load takes >15s we would throw out the result.
     I treat >15s as a load failure, but no test result is reported when that happens, and the test must
     be repeated.
     XCTest.measureBlock runs each test 10x.
     */

    fileprivate func doTest(shieldsOn: Bool, group: [String]) {
        WebViewLoadTestUtils.urlProtocolEnabled(shieldsOn)
        measure({
            WebViewLoadTestUtils.loadSites(self, sites: group)
        })
    }

    func testBraveDefaultShieldsOn_A() {
        doTest(shieldsOn: true, group: groupA)
    }

    func testBraveDefaultShieldsOff_A() {
        doTest(shieldsOn: false, group: groupA)
    }

    func testBraveDefaultShieldsOn_B() {
        doTest(shieldsOn: true, group: groupB)
    }

    func testBraveDefaultShieldsOff_B() {
        doTest(shieldsOn: false, group: groupB)
    }

    // End of XCTest measureBlock

    // Uses my own test timing, results aren't as detailed as the XCTest.measureBlock
    func testTopSlowSites() {
        let sites = ["nytimes.com", "macworld.com", "wired.com", "theverge.com",
                     "businessinsider.com", "imore.com", "kotaku.com", "huffingtonpost.com"]
        var dict = [String: (shieldsOn: [Double], shieldsOff: [Double])]()

        for i in 0..<4 {
            let shieldsOn = i % 2 == 0
            WebViewLoadTestUtils.urlProtocolEnabled(shieldsOn)
            //WebViewLoadTestUtils.httpseEnabled(shieldsOn)

            for site in sites {
                let webview = BraveWebView(frame: CGRect(x: 0,y: 0,width: 200,height: 200), useDesktopUserAgent: false)

                print("\(site)")

                // prime it
                //loadSite(site, webview: webview)

                let timeStart = Date.timeIntervalSinceReferenceDate
                let ok = WebViewLoadTestUtils.loadSite(self, site: site, webview: webview)
                if !ok {
                    continue
                }
                let time = Date.timeIntervalSinceReferenceDate - timeStart

                if time < 1 {
                    print("(\(i)) skipping \(site), load too fast \(time)")
                    continue
                }

                if dict[site] == nil {
                    dict[site] = (shieldsOn: [Double](), shieldsOff: [Double]())
                }

                if shieldsOn {
                    dict[site]!.shieldsOn.append(time)
                } else {
                    dict[site]!.shieldsOff.append(time)
                }
            }
        }


        var countSitesWithFasterLoad = 0
        var averages = [String: (on: Double, off: Double)]()
        for (site, arrays) in dict {
            func average(_ isOn: Bool, arr: [Double]) {
                let average = arr.reduce(0.0) { return ($0 + $1) } / Double(arr.count)
                print("Shields On:\(isOn) \(site) \(average)")
                if averages[site] == nil {
                    averages[site] = (on: 0.0, off: 0.0)
                }
                if isOn {
                    averages[site]!.on = average
                } else {
                    averages[site]!.off = average
                }

                if (averages[site]!.on > 0 && averages[site]!.off > 0 && averages[site]!.on < averages[site]!.off) {
                    countSitesWithFasterLoad += 1
                }
            }
            average(true, arr: arrays.shieldsOn)
            average(false, arr: arrays.shieldsOff)
        }

        XCTAssert(countSitesWithFasterLoad == sites.count, "Expected all sites to load faster with ad block")
    }


    #if TEST_ALEXA500
    // If you have an hour+ to wait, this will run through a huge list of sites.
    // It is very useful to stress the app, you can watch memory, or just see if there are any major errors
    // in the console.
    func testStressUsingAlexa500() {
        let w = BraveWebView(frame: CGRectMake(0,0,200,200))
        var count = 0
        for site in sites500 {
            print("Site: \(count += 1) \(site)")
            WebViewLoadTestUtils.loadSite(self, site: site, webview: w)
        }
    }
    #endif
    
    func testOpenUrlUsingBraveSchema() {
        expectationForNotification(BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        let site = "google.ca"
        let ok = UIApplication.shared.openURL(
            URL(string: "brave://open-url?url=https%253A%252F%252F" + site)!)
        waitForExpectations(timeout: 10, handler: nil)
        XCTAssert(ok, "open url failed for site: \(site)")
    }
}
