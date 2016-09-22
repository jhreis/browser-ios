/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// This is bottom toolbar

import SnapKit

extension UIImage{

    func alpha(_ value:CGFloat)->UIImage
    {
        UIGraphicsBeginImageContextWithOptions(self.size, false, 0.0)

        let ctx = UIGraphicsGetCurrentContext();
        let area = CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height);

        ctx?.scaleBy(x: 1, y: -1);
        ctx?.translateBy(x: 0, y: -area.size.height);
        ctx?.setBlendMode(.multiply);
        ctx?.setAlpha(value);
        ctx?.draw(self.cgImage!, in: area);

        let newImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        return newImage!;
    }
}

class BraveBrowserBottomToolbar : BrowserToolbar {
    static var tabsCount = 1

    lazy var tabsButton: TabsButton = {
        let tabsButton = TabsButton()
        tabsButton.titleLabel.text = "\(tabsCount)"
        tabsButton.addTarget(self, action: #selector(BraveBrowserBottomToolbar.onClickShowTabs), for: UIControlEvents.touchUpInside)
        tabsButton.accessibilityLabel = NSLocalizedString("Show Tabs",
                                                          comment: "Accessibility Label for the tabs button in the browser toolbar")
        return tabsButton
    }()

    lazy var addTabButton: UIButton = {
        let button = UIButton()
        let image = UIImage(named: "add")
        button.accessibilityLabel = NSLocalizedString("Add Tab", comment: "Accessibility label for the bottom toolbar add tab button")
        button.addTarget(self, action: #selector(BraveBrowserBottomToolbar.onClickAddTab), for: UIControlEvents.touchUpInside)

        // Button is grey without upping the brightness
        // TODO remove this when the icon changes
        func hackToMakeWhite(_ image: UIImage) -> UIImage {
            let brightnessFilter = CIFilter(name: "CIColorControls")!
            brightnessFilter.setValue(1.0, forKey: "inputBrightness")
            brightnessFilter.setValue(CIImage(image: image), forKey: kCIInputImageKey)
            return UIImage(cgImage: CIContext(options:nil).createCGImage(brightnessFilter.outputImage!, from:brightnessFilter.outputImage!.extent)!, scale: image.scale, orientation: .up)
        }

        button.setImage(hackToMakeWhite(image!), for: UIControlState())
        return button
    }()

    var leftSpacer = UIView()
    var rightSpacer = UIView()

    fileprivate weak var clonedTabsButton: TabsButton?
    var tabsContainer = UIView()

    fileprivate static weak var currentInstance: BraveBrowserBottomToolbar?

    //let backForwardUnderlay = UIImageView(image: UIImage(named: "backForwardUnderlay"))

    override init(frame: CGRect) {

        super.init(frame: frame)

        BraveBrowserBottomToolbar.currentInstance = self

        bookmarkButton.isHidden = true
        stopReloadButton.isHidden = true

        tabsContainer.addSubview(tabsButton)
        addSubview(tabsContainer)
        //addSubview(backForwardUnderlay)

        //backForwardUnderlay.alpha = BraveUX.BackForwardEnabledButtonAlpha

        bringSubview(toFront: backButton)
        bringSubview(toFront: forwardButton)

        addSubview(addTabButton)

        addSubview(leftSpacer)
        addSubview(rightSpacer)
        rightSpacer.isUserInteractionEnabled = false
        leftSpacer.isUserInteractionEnabled = false

        if let img = forwardButton.imageView?.image {
            forwardButton.setImage(img.alpha(BraveUX.BackForwardDisabledButtonAlpha), for: .disabled)
        }
        if let img = backButton.imageView?.image {
            backButton.setImage(img.alpha(BraveUX.BackForwardDisabledButtonAlpha), for: .disabled)
        }

        var theme = Theme()
        theme.buttonTintColor = BraveUX.ActionButtonTintColor
        theme.backgroundColor = UIColor.clear
        BrowserToolbar.Themes[Theme.NormalMode] = theme
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func applyTheme(_ themeName: String) {
        super.applyTheme(themeName)
        tabsButton.applyTheme(themeName)
    }

    class func updateTabCountDuplicatedButton(_ count: Int, animated: Bool) {
        guard let instance = BraveBrowserBottomToolbar.currentInstance else { return }
        tabsCount = count
        URLBarView.updateTabCount(instance.tabsButton,
                                  clonedTabsButton: &instance.clonedTabsButton, count: count, animated: animated)
    }

    func onClickAddTab() {
        let app = UIApplication.shared.delegate as! AppDelegate
        let isPrivate = PrivateBrowsing.singleton.isOn
        if isPrivate {
            if #available(iOS 9, *) {
                app.tabManager.addTabAndSelect(nil, configuration: nil, isPrivate: true)
            }
        } else {
            app.tabManager.addTabAndSelect()
        }
        app.browserViewController.urlBar.browserLocationViewDidTapLocation(app.browserViewController.urlBar.locationView)
    }

    func setAlphaOnAllExceptTabButton(_ alpha: CGFloat) {
        for item in [addTabButton, backButton, forwardButton, shareButton] {
            item.alpha = alpha
        }
    }

    func onClickShowTabs() {
        setAlphaOnAllExceptTabButton(0)
        BraveURLBarView.tabButtonPressed()
    }

    func leavingTabTrayMode() {
        setAlphaOnAllExceptTabButton(1.0)
    }

    // TODO find a way to do this properly with themes.
    func styleHacks() {
        tabsButton.labelBackground.backgroundColor = BraveUX.ActionButtonTintColor
    }

    override func updateConstraints() {
        super.updateConstraints()

        styleHacks()

        stopReloadButton.isHidden = true

        func common(_ make: ConstraintMaker, bottomInset: Int = 0) {
            make.top.equalTo(self)
            make.bottom.equalTo(self).inset(bottomInset)
            make.width.equalTo(self).dividedBy(5)
        }

        backButton.snp_remakeConstraints { make in
            common(make)
            make.left.equalTo(self)
        }

        forwardButton.snp_remakeConstraints { make in
            common(make)
            make.left.equalTo(backButton.snp_right)
        }

        shareButton.snp_remakeConstraints { make in
            common(make)
            make.centerX.equalTo(self)
        }

        addTabButton.snp_remakeConstraints { make in
            common(make)
            make.left.equalTo(shareButton.snp_right)
        }

        tabsContainer.snp_remakeConstraints { make in
            common(make)
            make.right.equalTo(self)
        }

        tabsButton.snp_remakeConstraints { make in
            make.center.equalTo(tabsContainer)
            make.top.equalTo(tabsContainer)
            make.bottom.equalTo(tabsContainer)
            make.width.equalTo(tabsButton.snp_height)
        }
    }

    override func updatePageStatus(isWebPage: Bool) {
        super.updatePageStatus(isWebPage: isWebPage)
        
        let isPrivate = getApp().browserViewController.tabManager.selectedTab?.isPrivate ?? false
        if isPrivate {
            postAsyncToMain(0) {
                // ensure theme is applied after inital styling
                self.applyTheme(Theme.PrivateMode)
            }
        }
    }
}
