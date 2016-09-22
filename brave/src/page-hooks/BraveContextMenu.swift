/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Using suggestions from: http://www.icab.de/blog/2010/07/11/customize-the-contextual-menu-of-uiwebview/

let kNotificationMainWindowTapAndHold = "kNotificationMainWindowTapAndHold"

class BraveContextMenu {
    var tapLocation: CGPoint = CGPoint.zero
    var tappedElement: ContextMenuHelper.Elements?

    var timer1_cancelDefaultMenu: Timer = Timer()
    var timer2_showMenuIfStillPressed: Timer = Timer()

    static let initialDelayToCancelBuiltinMenu = 0.25 // seconds, must be <0.3 or built-in menu can't be cancelled
    static let totalDelayToShowContextMenu = 0.85 - initialDelayToCancelBuiltinMenu // 850 is copied from Safari

    fileprivate func resetTimer() {
        if (!timer1_cancelDefaultMenu.isValid && !timer2_showMenuIfStillPressed.isValid) {
            return
        }

        if let url = tappedElement?.link {
            BraveApp.getCurrentWebView()?.loadRequest(URLRequest(url: url as URL))
        }

        [timer1_cancelDefaultMenu, timer2_showMenuIfStillPressed].forEach { $0.invalidate() }
        tappedElement = nil
    }

    fileprivate func isBrowserTopmostAndNoPanelsOpen() ->  Bool {
        guard let top = getApp().rootViewController.visibleViewController as? BraveTopViewController else {
            return false
        }

        return top.mainSidePanel.view.isHidden && top.rightSidePanel.view.isHidden
    }

    func sendEvent(_ event: UIEvent, window: UIWindow) {
        if !isBrowserTopmostAndNoPanelsOpen() {
            resetTimer()
            return
        }

        guard let braveWebView = BraveApp.getCurrentWebView() else { return }

        if let touches = event.touches(for: window), let touch = touches.first , touches.count == 1 {
            braveWebView.lastTappedTime = Date()
            switch touch.phase {
            case .began:  // A finger touched the screen
                guard let touchView = event.allTouches?.first?.view , touchView.isDescendant(of: braveWebView) else {
                    resetTimer()
                    return
                }

                tapLocation = touch.location(in: window)
                resetTimer()
                timer1_cancelDefaultMenu = Timer.scheduledTimer(timeInterval: BraveContextMenu.initialDelayToCancelBuiltinMenu, target: self, selector: #selector(BraveContextMenu.cancelDefaultMenuAndFindTappedItem), userInfo: nil, repeats: false)
                break
            case .moved, .stationary:
                let p1 = touch.location(in: window)
                let p2 = touch.previousLocation(in: window)
                let distance =  hypotf(Float(p1.x) - Float(p2.x), Float(p1.y) - Float(p2.y))
                if distance > 10.0 { // my test for this: tap with edge of finger, then roll to opposite edge while holding finger down, is 5-10 px of movement; don't want this to be a move
                    resetTimer()
                }
                break
            case .ended, .cancelled:
                resetTimer()
                break
            }
        } else {
            resetTimer()
        }
    }

    @objc func showContextMenu() {
        func showContextMenuForElement(_ tappedElement:  ContextMenuHelper.Elements) {
            let info = ["point": NSValue(cgPoint: tapLocation)]
            NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationMainWindowTapAndHold), object: self, userInfo: info)
            guard let bvc = getApp().browserViewController else { return }
            if bvc.urlBar.inOverlayMode {
                return
            }
            bvc.showContextMenu(elements: tappedElement, touchPoint: tapLocation)
            resetTimer()
            return
        }


        if let tappedElement = tappedElement {
            showContextMenuForElement(tappedElement)
        }
    }

    // This is called 2x, once at .25 seconds to ensure the native context menu is cancelled,
    // then again at .5 seconds to show our context menu. (This code was borne of frustration, not ideal flow)
    @objc func cancelDefaultMenuAndFindTappedItem() {
        if !isBrowserTopmostAndNoPanelsOpen() {
            resetTimer()
            return
        }

        guard let hit = ElementAtPoint().getHit(tapLocation) else {
            // No link or image found, not for this class to handle
            resetTimer()
            return
        }

        tappedElement = ContextMenuHelper.Elements(link: hit.url != nil ? URL(string: hit.url!) : nil, image: hit.image != nil ? URL(string: hit.image!) : nil)

        func blockOtherGestures(_ views: [UIView]?) {
            guard let views = views else { return }
            for view in views {
                if let gestures = view.gestureRecognizers as [UIGestureRecognizer]! {
                    for gesture in gestures {
                        if gesture is UILongPressGestureRecognizer {
                            // toggling gets the gesture to ignore this long press
                            gesture.isEnabled = false
                            gesture.isEnabled = true
                        }
                    }
                }
            }
        }
        
        blockOtherGestures(BraveApp.getCurrentWebView()?.scrollView.subviews)

        timer2_showMenuIfStillPressed = Timer.scheduledTimer(timeInterval: BraveContextMenu.totalDelayToShowContextMenu, target: self, selector: #selector(BraveContextMenu.showContextMenu), userInfo: nil, repeats: false)
    }
}
