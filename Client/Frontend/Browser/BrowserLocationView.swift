/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
import SnapKit
import XCGLogger

private let log = Logger.browserLogger

protocol BrowserLocationViewDelegate {
    func browserLocationViewDidTapLocation(_ browserLocationView: BrowserLocationView)
    func browserLocationViewDidLongPressLocation(_ browserLocationView: BrowserLocationView)
    func browserLocationViewDidTapReaderMode(_ browserLocationView: BrowserLocationView)
    /// - returns: whether the long-press was handled by the delegate; i.e. return `false` when the conditions for even starting handling long-press were not satisfied
    func browserLocationViewDidLongPressReaderMode(_ browserLocationView: BrowserLocationView) -> Bool
    func browserLocationViewLocationAccessibilityActions(_ browserLocationView: BrowserLocationView) -> [UIAccessibilityCustomAction]?
}

struct BrowserLocationViewUX {
    static let HostFontColor = UIColor.black
    static let BaseURLFontColor = UIColor.gray
    static let BaseURLPitch = 0.75
    static let HostPitch = 1.0
    static let LocationContentInset = 8

    static var Themes: [String: Theme] = {
        var themes = [String: Theme]()
        var theme = Theme()
        theme.URLFontColor = UIColor.lightGray
        theme.hostFontColor = UIColor.white
        theme.backgroundColor = UIConstants.PrivateModeLocationBackgroundColor
        themes[Theme.PrivateMode] = theme

        theme = Theme()
        theme.URLFontColor = BaseURLFontColor
        theme.hostFontColor = HostFontColor
        theme.backgroundColor = UIColor.white
        themes[Theme.NormalMode] = theme

        return themes
    }()
}

class BrowserLocationView: UIView {
    var delegate: BrowserLocationViewDelegate?
    var longPressRecognizer: UILongPressGestureRecognizer!
    var tapRecognizer: UITapGestureRecognizer!

    dynamic var baseURLFontColor: UIColor = BrowserLocationViewUX.BaseURLFontColor {
        didSet { updateTextWithURL() }
    }

    dynamic var hostFontColor: UIColor = BrowserLocationViewUX.HostFontColor {
        didSet { updateTextWithURL() }
    }

    var url: URL? {
        didSet {
            let wasHidden = lockImageView.isHidden
            lockImageView.isHidden = url?.scheme != "https"
            if wasHidden != lockImageView.isHidden {
                UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil)
            }
            updateTextWithURL()
            setNeedsUpdateConstraints()
        }
    }

    var readerModeState: ReaderModeState {
        get {
            return readerModeButton.readerModeState
        }
        set (newReaderModeState) {
            if newReaderModeState != self.readerModeButton.readerModeState {
                let wasHidden = readerModeButton.isHidden
                self.readerModeButton.readerModeState = newReaderModeState
                readerModeButton.isHidden = (newReaderModeState == ReaderModeState.Unavailable)
                if wasHidden != readerModeButton.isHidden {
                    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil)
                }
                UIView.animate(withDuration: 0.1, animations: { () -> Void in
                    if newReaderModeState == ReaderModeState.Unavailable {
                        self.readerModeButton.alpha = 0.0
                    } else {
                        self.readerModeButton.alpha = 1.0
                    }
                    self.setNeedsUpdateConstraints()
                    self.layoutIfNeeded()
                })
            }
        }
    }

    lazy var placeholder: NSAttributedString = {
        let placeholderText = NSLocalizedString("Search or enter address", comment: "The text shown in the URL bar on about:home")
        return NSAttributedString(string: placeholderText, attributes: [NSForegroundColorAttributeName: UIColor.white])
    }()

    lazy var urlTextField: UITextField = {
        let urlTextField = DisplayTextField()

        self.longPressRecognizer.delegate = self
        urlTextField.addGestureRecognizer(self.longPressRecognizer)
        self.tapRecognizer.delegate = self
        urlTextField.addGestureRecognizer(self.tapRecognizer)

        urlTextField.attributedPlaceholder = self.placeholder
        urlTextField.accessibilityIdentifier = "url"
        urlTextField.accessibilityActionsSource = self
        urlTextField.font = UIConstants.DefaultChromeFont
        return urlTextField
    }()

    fileprivate lazy var lockImageView: UIImageView = {
        let lockImageView = UIImageView(image: UIImage(named: "lock_verified"))
        lockImageView.isHidden = true
        lockImageView.isAccessibilityElement = true
        lockImageView.contentMode = UIViewContentMode.center
        lockImageView.accessibilityLabel = NSLocalizedString("Secure connection", comment: "Accessibility label for the lock icon, which is only present if the connection is secure")
        return lockImageView
    }()

    fileprivate lazy var privateBrowsingIconView: UIImageView = {
        let icon = UIImageView(image: UIImage(named: "privateBrowsingGlasses")!.withRenderingMode(.alwaysTemplate))
        icon.tintColor = BraveUX.BraveOrange
        icon.alpha = 0
        icon.isAccessibilityElement = true
        icon.contentMode = UIViewContentMode.scaleAspectFit
        icon.accessibilityLabel = NSLocalizedString("Private mode icon", comment: "Private mode icon next to location string")
        return icon
    }()

    fileprivate lazy var readerModeButton: ReaderModeButton = {
        let readerModeButton = ReaderModeButton(frame: CGRect.zero)
        readerModeButton.isHidden = true
        readerModeButton.addTarget(self, action: #selector(BrowserLocationView.SELtapReaderModeButton), for: .touchUpInside)
        readerModeButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(BrowserLocationView.SELlongPressReaderModeButton(_:))))
        readerModeButton.isAccessibilityElement = true
        readerModeButton.accessibilityLabel = NSLocalizedString("Reader View", comment: "Accessibility label for the Reader View button")
        readerModeButton.accessibilityCustomActions = [UIAccessibilityCustomAction(name: NSLocalizedString("Add to Reading List", comment: "Accessibility label for action adding current page to reading list."), target: self, selector: #selector(BrowserLocationView.SELreaderModeCustomAction))]
        return readerModeButton
    }()

    // Prefixing with brave to distinguish from progress view that firefox has (which we hide)
    var braveProgressView: UIView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat(URLBarViewUX.LocationHeight)))

    override init(frame: CGRect) {
        super.init(frame: frame)

        longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(BrowserLocationView.SELlongPressLocation(_:)))
        tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(BrowserLocationView.SELtapLocation(_:)))

        addSubview(urlTextField)
        addSubview(privateBrowsingIconView)
        addSubview(lockImageView)
        addSubview(readerModeButton)

        braveProgressView.accessibilityLabel = "braveProgressView"
        braveProgressView.backgroundColor = BraveUX.ProgressBarColor
        braveProgressView.layer.cornerRadius = CGFloat(BraveUX.TextFieldCornerRadius)
        braveProgressView.layer.masksToBounds = true
        self.addSubview(braveProgressView)
        self.sendSubview(toBack: braveProgressView)
    }

    override var accessibilityElements: [AnyObject]! {
        get {
            return [privateBrowsingIconView, lockImageView, urlTextField, readerModeButton].filter { !$0.isHidden }
        }
        set {
            super.accessibilityElements = newValue
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConstraints() {
        privateBrowsingIconLayout()

        lockImageView.snp_makeConstraints { make in
            make.centerY.equalTo(self)
            make.left.equalTo(self.privateBrowsingIconView.snp_right).offset(BrowserLocationViewUX.LocationContentInset)
            make.width.equalTo(self.lockImageView.intrinsicContentSize.width)
        }

        readerModeButton.snp_makeConstraints { make in
            make.right.centerY.equalTo(self)
            make.width.equalTo(self.readerModeButton.intrinsicContentSize.width)
        }
        

        urlTextField.snp_remakeConstraints { make in
            make.top.bottom.equalTo(self)

            if lockImageView.isHidden {
                make.left.equalTo(self.privateBrowsingIconView.snp_right).offset(BrowserLocationViewUX.LocationContentInset)
            } else {
                make.left.equalTo(self.lockImageView.snp_right).offset(BrowserLocationViewUX.LocationContentInset)
            }

            if readerModeButton.isHidden {
                make.right.equalTo(self).inset(BrowserLocationViewUX.LocationContentInset
                    + 20) // BRAVE added to make space for stopReloadButton
            } else {
                make.right.equalTo(self.readerModeButton.snp_left)
            }
        }

        super.updateConstraints()
    }

    func showPrivateBrowsingIcon(_ enabled: Bool) {
        privateBrowsingIconView.alpha = enabled ? 1.0 : 0.0
        setNeedsUpdateConstraints()
    }

    fileprivate func privateBrowsingIconLayout() {
        privateBrowsingIconView.snp_remakeConstraints() { make in
            make.centerY.equalTo(self)

            if self.privateBrowsingIconView.alpha > 0 {
                make.width.equalTo(16)
                make.left.equalTo(self).offset(BrowserLocationViewUX.LocationContentInset)
            } else {
                make.left.equalTo(self)
                make.width.equalTo(0)
            }
        }
    }

    func SELtapReaderModeButton() {
        delegate?.browserLocationViewDidTapReaderMode(self)
    }

    func SELlongPressReaderModeButton(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == UIGestureRecognizerState.began {
            delegate?.browserLocationViewDidLongPressReaderMode(self)
        }
    }

    func SELlongPressLocation(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == UIGestureRecognizerState.began {
            delegate?.browserLocationViewDidLongPressLocation(self)
        }
    }

    func SELtapLocation(_ recognizer: UITapGestureRecognizer) {
        delegate?.browserLocationViewDidTapLocation(self)
    }

    func SELreaderModeCustomAction() -> Bool {
        return delegate?.browserLocationViewDidLongPressReaderMode(self) ?? false
    }

    fileprivate func updateTextWithURL() {
        if url == nil {
            urlTextField.text = ""
            return
        }

        if let httplessURL = url?.absoluteDisplayString(), let baseDomain = url?.baseDomain() {
            // Highlight the base domain of the current URL.
            let attributedString = NSMutableAttributedString(string: httplessURL)
            let nsRange = NSMakeRange(0, httplessURL.characters.count)
            attributedString.addAttribute(NSForegroundColorAttributeName, value: baseURLFontColor, range: nsRange)
            attributedString.colorSubstring(baseDomain, withColor: hostFontColor)
            attributedString.addAttribute(UIAccessibilitySpeechAttributePitch, value: NSNumber(double: BrowserLocationViewUX.BaseURLPitch), range: nsRange)
            attributedString.pitchSubstring(baseDomain, withPitch: BrowserLocationViewUX.HostPitch)
            urlTextField.attributedText = attributedString
        } else {
            // If we're unable to highlight the domain, just use the URL as is.
            urlTextField.text = url?.absoluteString
        }
        postAsyncToMain(0.1) {
            self.urlTextField.textColor = UIColor.white
        }
    }
}

extension BrowserLocationView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // If the longPressRecognizer is active, fail all other recognizers to avoid conflicts.
        return gestureRecognizer == longPressRecognizer
    }
}

extension BrowserLocationView: AccessibilityActionsSource {
    func accessibilityCustomActionsForView(_ view: UIView) -> [UIAccessibilityCustomAction]? {
        if view === urlTextField {
            return delegate?.browserLocationViewLocationAccessibilityActions(self)
        }
        return nil
    }
}

extension BrowserLocationView: Themeable {
    func applyTheme(_ themeName: String) {
        guard let theme = BrowserLocationViewUX.Themes[themeName] else {
            log.error("Unable to apply unknown theme \(themeName)")
            return
        }
        baseURLFontColor = theme.URLFontColor!
        hostFontColor = theme.hostFontColor!
        backgroundColor = theme.backgroundColor
    }
}

private class ReaderModeButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setImage(UIImage(named: "reader.png"), for: UIControlState())
        setImage(UIImage(named: "reader_active.png"), for: UIControlState.selected)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var _readerModeState: ReaderModeState = ReaderModeState.Unavailable
    
    var readerModeState: ReaderModeState {
        get {
            return _readerModeState;
        }
        set (newReaderModeState) {
            _readerModeState = newReaderModeState
            switch _readerModeState {
            case .Available:
                self.isEnabled = true
                self.isSelected = false
            case .Unavailable:
                self.isEnabled = false
                self.isSelected = false
            case .Active:
                self.isEnabled = true
                self.isSelected = true
            }
        }
    }
}

private class DisplayTextField: UITextField {
    weak var accessibilityActionsSource: AccessibilityActionsSource?

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            return accessibilityActionsSource?.accessibilityCustomActionsForView(self)
        }
        set {
            super.accessibilityCustomActions = newValue
        }
    }

    fileprivate override var canBecomeFirstResponder : Bool {
        return false
    }
}
