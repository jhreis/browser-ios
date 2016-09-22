/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import SnapKit
import Shared
import XCGLogger

private let log = Logger.browserLogger

@objc
protocol BrowserToolbarProtocol {
    weak var browserToolbarDelegate: BrowserToolbarDelegate? { get set }
    var shareButton: UIButton { get }
    var bookmarkButton: UIButton { get }
    var forwardButton: UIButton { get }
    var backButton: UIButton { get }
    var stopReloadButton: UIButton { get }
    var actionButtons: [UIButton] { get }

    func updateBackStatus(_ canGoBack: Bool)
    func updateForwardStatus(_ canGoForward: Bool)
    func updateReloadStatus(_ isLoading: Bool)
    func updatePageStatus(isWebPage: Bool)
}

@objc
protocol BrowserToolbarDelegate: class {
    func browserToolbarDidPressBack(_ browserToolbar: BrowserToolbarProtocol, button: UIButton)
    func browserToolbarDidPressForward(_ browserToolbar: BrowserToolbarProtocol, button: UIButton)
    func browserToolbarDidLongPressBack(_ browserToolbar: BrowserToolbarProtocol, button: UIButton)
    func browserToolbarDidLongPressForward(_ browserToolbar: BrowserToolbarProtocol, button: UIButton)
    func browserToolbarDidPressReload(_ browserToolbar: BrowserToolbarProtocol, button: UIButton)
    func browserToolbarDidPressStop(_ browserToolbar: BrowserToolbarProtocol, button: UIButton)
    func browserToolbarDidPressBookmark(_ browserToolbar: BrowserToolbarProtocol, button: UIButton)
    func browserToolbarDidLongPressBookmark(_ browserToolbar: BrowserToolbarProtocol, button: UIButton)
    func browserToolbarDidPressShare(_ browserToolbar: BrowserToolbarProtocol, button: UIButton)
}

@objc
open class BrowserToolbarHelper: NSObject {
    let toolbar: BrowserToolbarProtocol

    let ImageReload = UIImage(named: "reload")
    let ImageReloadPressed = UIImage(named: "reloadPressed")
    let ImageStop = UIImage(named: "stop")
    let ImageStopPressed = UIImage(named: "stopPressed")

    var buttonTintColor = BraveUX.ActionButtonTintColor { // TODO see if setting it here can be avoided
        didSet {
            setTintColor(buttonTintColor, forButtons: toolbar.actionButtons)
        }
    }

    var loading: Bool = false {
        didSet {
            if loading {
                toolbar.stopReloadButton.setImage(ImageStop, for: UIControlState())
                toolbar.stopReloadButton.setImage(ImageStopPressed, for: .highlighted)
                toolbar.stopReloadButton.accessibilityLabel = NSLocalizedString("Stop", comment: "Accessibility Label for the browser toolbar Stop button")
            } else {
                toolbar.stopReloadButton.setImage(ImageReload, for: UIControlState())
                toolbar.stopReloadButton.setImage(ImageReloadPressed, for: .highlighted)
                toolbar.stopReloadButton.accessibilityLabel = NSLocalizedString("Reload", comment: "Accessibility Label for the browser toolbar Reload button")
            }
        }
    }

    fileprivate func setTintColor(_ color: UIColor, forButtons buttons: [UIButton]) {
      return
        buttons.forEach { $0.tintColor = color }
    }

    init(toolbar: BrowserToolbarProtocol) {
        self.toolbar = toolbar
        super.init()

        toolbar.backButton.setImage(UIImage(named: "back"), for: UIControlState())
        //toolbar.backButton.setImage(UIImage(named: "backPressed"), forState: .Highlighted)
        toolbar.backButton.accessibilityLabel = NSLocalizedString("Back", comment: "Accessibility Label for the browser toolbar Back button")
        //toolbar.backButton.accessibilityHint = NSLocalizedString("Double tap and hold to open history", comment: "")
        let longPressGestureBackButton = UILongPressGestureRecognizer(target: self, action: #selector(BrowserToolbarHelper.SELdidLongPressBack(_:)))
        toolbar.backButton.addGestureRecognizer(longPressGestureBackButton)
        toolbar.backButton.addTarget(self, action: #selector(BrowserToolbarHelper.SELdidClickBack), for: UIControlEvents.touchUpInside)

        toolbar.forwardButton.setImage(UIImage(named: "forward"), for: UIControlState())
        //toolbar.forwardButton.setImage(UIImage(named: "forwardPressed"), forState: .Highlighted)
        toolbar.forwardButton.accessibilityLabel = NSLocalizedString("Forward", comment: "Accessibility Label for the browser toolbar Forward button")
        //toolbar.forwardButton.accessibilityHint = NSLocalizedString("Double tap and hold to open history", comment: "")
        let longPressGestureForwardButton = UILongPressGestureRecognizer(target: self, action: #selector(BrowserToolbarHelper.SELdidLongPressForward(_:)))
        toolbar.forwardButton.addGestureRecognizer(longPressGestureForwardButton)
        toolbar.forwardButton.addTarget(self, action: #selector(BrowserToolbarHelper.SELdidClickForward), for: UIControlEvents.touchUpInside)

        toolbar.stopReloadButton.setImage(UIImage(named: "reload"), for: UIControlState())
        toolbar.stopReloadButton.setImage(UIImage(named: "reloadPressed"), for: .highlighted)
        toolbar.stopReloadButton.accessibilityLabel = NSLocalizedString("Reload", comment: "Accessibility Label for the browser toolbar Reload button")
        let longPressGestureStopReloadButton = UILongPressGestureRecognizer(target: self, action: #selector(BrowserToolbarHelper.SELdidLongPressStopReload(_:)))
        toolbar.stopReloadButton.addGestureRecognizer(longPressGestureStopReloadButton)
        toolbar.stopReloadButton.addTarget(self, action: #selector(BrowserToolbarHelper.SELdidClickStopReload), for: UIControlEvents.touchUpInside)

        toolbar.shareButton.setImage(UIImage(named: "send"), for: UIControlState())
#if !BRAVE // we use the default press state for now. 
        toolbar.shareButton.setImage(UIImage(named: "sendPressed"), for: .highlighted)
#endif
        toolbar.shareButton.accessibilityLabel = NSLocalizedString("Share", comment: "Accessibility Label for the browser toolbar Share button")
        toolbar.shareButton.addTarget(self, action: #selector(BrowserToolbarHelper.SELdidClickShare), for: UIControlEvents.touchUpInside)
        toolbar.bookmarkButton.contentMode = UIViewContentMode.center

        toolbar.bookmarkButton.setImage(UIImage(named: "bookmark"), for: UIControlState())
        toolbar.bookmarkButton.setImage(UIImage(named: "bookmarked"), for: UIControlState.selected)
        toolbar.bookmarkButton.setImage(UIImage(named: "bookmarkHighlighted"), for: UIControlState.highlighted)
        toolbar.bookmarkButton.accessibilityLabel = NSLocalizedString("Bookmark", comment: "Accessibility Label for the browser toolbar Bookmark button")
        let longPressGestureBookmarkButton = UILongPressGestureRecognizer(target: self, action: #selector(BrowserToolbarHelper.SELdidLongPressBookmark(_:)))
        toolbar.bookmarkButton.addGestureRecognizer(longPressGestureBookmarkButton)
        toolbar.bookmarkButton.addTarget(self, action: #selector(BrowserToolbarHelper.SELdidClickBookmark), for: UIControlEvents.touchUpInside)

        setTintColor(buttonTintColor, forButtons: toolbar.actionButtons)
    }

    func SELdidClickBack() {
        toolbar.browserToolbarDelegate?.browserToolbarDidPressBack(toolbar, button: toolbar.backButton)
    }

    func SELdidLongPressBack(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == UIGestureRecognizerState.began {
            toolbar.browserToolbarDelegate?.browserToolbarDidLongPressBack(toolbar, button: toolbar.backButton)
        }
    }

    func SELdidClickShare() {
        toolbar.browserToolbarDelegate?.browserToolbarDidPressShare(toolbar, button: toolbar.shareButton)
    }

    func SELdidClickForward() {
        toolbar.browserToolbarDelegate?.browserToolbarDidPressForward(toolbar, button: toolbar.forwardButton)
    }

    func SELdidLongPressForward(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == UIGestureRecognizerState.began {
            toolbar.browserToolbarDelegate?.browserToolbarDidLongPressForward(toolbar, button: toolbar.forwardButton)
        }
    }

    func SELdidClickBookmark() {
        toolbar.browserToolbarDelegate?.browserToolbarDidPressBookmark(toolbar, button: toolbar.bookmarkButton)
    }

    func SELdidLongPressBookmark(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == UIGestureRecognizerState.began {
            toolbar.browserToolbarDelegate?.browserToolbarDidLongPressBookmark(toolbar, button: toolbar.bookmarkButton)
        }
    }



    func SELdidClickStopReload() {
        if loading {
            toolbar.browserToolbarDelegate?.browserToolbarDidPressStop(toolbar, button: toolbar.stopReloadButton)
            loading = false
        } else {
            toolbar.browserToolbarDelegate?.browserToolbarDidPressReload(toolbar, button: toolbar.stopReloadButton)
        }
    }

    func SELdidLongPressStopReload(_ recognizer: UILongPressGestureRecognizer) {

    }

    func updateReloadStatus(_ isLoading: Bool) {
        loading = isLoading
    }
}


class BrowserToolbar: Toolbar, BrowserToolbarProtocol {
    weak var browserToolbarDelegate: BrowserToolbarDelegate?

    let shareButton: UIButton
    let bookmarkButton: UIButton
    let forwardButton: UIButton
    let backButton: UIButton
    let stopReloadButton: UIButton
    let actionButtons: [UIButton]

    var helper: BrowserToolbarHelper?

    static var Themes: [String: Theme] = {
        var themes = [String: Theme]()
        var theme = Theme()
        theme.buttonTintColor = UIConstants.PrivateModeActionButtonTintColor
        themes[Theme.PrivateMode] = theme

        theme = Theme()
        theme.buttonTintColor = UIColor.darkGray
        themes[Theme.NormalMode] = theme

        return themes
    }()

    // This has to be here since init() calls it
    override init(frame: CGRect) {
        // And these have to be initialized in here or the compiler will get angry
        backButton = UIButton()
        backButton.accessibilityIdentifier = "BrowserToolbar.backButton"
        forwardButton = UIButton()
        forwardButton.accessibilityIdentifier = "BrowserToolbar.forwardButton"
        stopReloadButton = UIButton()
        stopReloadButton.accessibilityIdentifier = "BrowserToolbar.stopReloadButton"
        shareButton = UIButton()
        shareButton.accessibilityIdentifier = "BrowserToolbar.shareButton"
        bookmarkButton = UIButton()
        bookmarkButton.accessibilityIdentifier = "BrowserToolbar.bookmarkButton"
        actionButtons = [backButton, forwardButton, stopReloadButton, shareButton, bookmarkButton]

        super.init(frame: frame)

        self.helper = BrowserToolbarHelper(toolbar: self)

        addButtons(backButton, forwardButton, stopReloadButton, shareButton, bookmarkButton)

        accessibilityNavigationStyle = .combined
        accessibilityLabel = NSLocalizedString("Navigation Toolbar", comment: "Accessibility label for the navigation toolbar displayed at the bottom of the screen.")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateBackStatus(_ canGoBack: Bool) {
        backButton.isEnabled = canGoBack
    }

    func updateForwardStatus(_ canGoForward: Bool) {
        forwardButton.isEnabled = canGoForward
    }

    func updateReloadStatus(_ isLoading: Bool) {
        helper?.updateReloadStatus(isLoading)
    }

    func updatePageStatus(isWebPage: Bool) {
        bookmarkButton.isEnabled = isWebPage
        stopReloadButton.isEnabled = isWebPage
        shareButton.isEnabled = isWebPage
    }

    override func draw(_ rect: CGRect) {
        if let context = UIGraphicsGetCurrentContext() {
            drawLine(context, start: CGPoint(x: 0, y: 0), end: CGPoint(x: frame.width, y: 0))
        }
    }

    fileprivate func drawLine(_ context: CGContext, start: CGPoint, end: CGPoint) {
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.05).cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: start.x, y: start.y))
        context.addLine(to: CGPoint(x: end.x, y: end.y))
        context.strokePath()
    }
}

// MARK: UIAppearance
extension BrowserToolbar {
    dynamic var actionButtonTintColor: UIColor? {
        get { return helper?.buttonTintColor }
        set {
            guard let value = newValue else { return }
            helper?.buttonTintColor = value
        }
    }
}

extension BrowserToolbar: Themeable {
    func applyTheme(_ themeName: String) {
        guard let theme = BrowserToolbar.Themes[themeName] else {
            log.error("Unable to apply unknown theme \(themeName)")
            return
        }
        actionButtonTintColor = theme.buttonTintColor!
    }
}
