/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import SnapKit
import Storage
import ReadingList
import Shared

struct TabTrayControllerUX {
    static let CornerRadius = CGFloat(BraveUX.TabTrayCellCornerRadius)
    static let BackgroundColor = UIConstants.AppBackgroundColor
    static let CellBackgroundColor = UIColor(red:0.95, green:0.95, blue:0.95, alpha:1)
    static let TextBoxHeight = CGFloat(32.0)
    static let FaviconSize = CGFloat(BraveUX.TabTrayCellFaviconSize)
    static let Margin = CGFloat(15)
    static let ToolbarBarTintColor = UIConstants.AppBackgroundColor
    static let ToolbarButtonOffset = CGFloat(10.0)
    static let CloseButtonSize = CGFloat(BraveUX.TabTrayCellCloseButtonSize)
    static let CloseButtonMargin = CGFloat(2.0)
    static let CloseButtonEdgeInset = CGFloat(6)

    static let NumberOfColumnsThin = 1
    static let NumberOfColumnsWide = 3
    static let CompactNumberOfColumnsThin = 2

    // Moved from UIConstants temporarily until animation code is merged
    static var StatusBarHeight: CGFloat {
        if UIScreen.main.traitCollection.verticalSizeClass == .compact {
            return 0
        }
        return 20
    }
}

struct LightTabCellUX {
    static let TabTitleTextColor = UIColor.black
}

struct DarkTabCellUX {
    static let TabTitleTextColor = UIColor.white
}

protocol TabCellDelegate: class {
    func tabCellDidClose(_ cell: TabCell)
}

class TabCell: UICollectionViewCell {
    enum Style {
        case light
        case dark
    }

    static let Identifier = "TabCellIdentifier"

    var style: Style = .light {
        didSet {
            applyStyle(style)
        }
    }

    let backgroundHolder = UIView()
    let background = UIImageViewAligned()
    let titleText: UILabel
    let innerStroke: InnerStrokedView
    let favicon: UIImageView = UIImageView()
    let closeButton: UIButton

    var title: UIVisualEffectView!
    var animator: SwipeAnimator!

    weak var delegate: TabCellDelegate?

    // Changes depending on whether we're full-screen or not.
    var margin = CGFloat(0)

    override init(frame: CGRect) {
        self.backgroundHolder.backgroundColor = UIColor.white
        self.backgroundHolder.layer.cornerRadius = TabTrayControllerUX.CornerRadius
        self.backgroundHolder.clipsToBounds = true
        self.backgroundHolder.backgroundColor = TabTrayControllerUX.CellBackgroundColor

        self.background.contentMode = UIViewContentMode.scaleAspectFill
        self.background.clipsToBounds = true
        self.background.isUserInteractionEnabled = false
        self.background.alignLeft = true
        self.background.alignTop = true

        self.favicon.layer.cornerRadius = 2.0
        self.favicon.layer.masksToBounds = true

        self.titleText = UILabel()
        self.titleText.textAlignment = NSTextAlignment.left
        self.titleText.isUserInteractionEnabled = false
        self.titleText.numberOfLines = 1
        self.titleText.font = DynamicFontHelper.defaultHelper.DefaultSmallFontBold

        self.closeButton = UIButton()
        self.closeButton.setImage(UIImage(named: "stop"), for: UIControlState())
        self.closeButton.tintColor = UIColor.lightGray
       // self.closeButton.imageEdgeInsets = UIEdgeInsetsMake(TabTrayControllerUX.CloseButtonEdgeInset, TabTrayControllerUX.CloseButtonEdgeInset, TabTrayControllerUX.CloseButtonEdgeInset, TabTrayControllerUX.CloseButtonEdgeInset)

        self.innerStroke = InnerStrokedView(frame: self.backgroundHolder.frame)
        self.innerStroke.layer.backgroundColor = UIColor.clear.cgColor

        super.init(frame: frame)

        //self.opaque = true

        self.animator = SwipeAnimator(animatingView: self.backgroundHolder, container: self)
        self.closeButton.addTarget(self, action: #selector(TabCell.SELclose), for: UIControlEvents.touchUpInside)

        contentView.addSubview(backgroundHolder)
        backgroundHolder.addSubview(self.background)
        backgroundHolder.addSubview(innerStroke)

        // Default style is light
        applyStyle(style)

        self.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: NSLocalizedString("Close", comment: "Accessibility label for action denoting closing a tab in tab list (tray)"), target: self.animator, selector: #selector(SELclose))
        ]
    }

    fileprivate func applyStyle(_ style: Style) {
        self.title?.removeFromSuperview()

        let title: UIVisualEffectView
        switch style {
        case .light:
            title = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
            self.titleText.textColor = LightTabCellUX.TabTitleTextColor
        case .dark:
            title = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            self.titleText.textColor = DarkTabCellUX.TabTitleTextColor
        }

        titleText.backgroundColor = UIColor.clear

        title.layer.shadowColor = UIColor.black.cgColor
        title.layer.shadowOpacity = 0.2
        title.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        title.layer.shadowRadius = 0

        title.addSubview(self.closeButton)
        title.addSubview(self.titleText)
        backgroundHolder.addSubview(self.favicon)

        backgroundHolder.addSubview(title)
        self.title = title
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        closeButton.tintColor = BraveUX.ProgressBarColor

        backgroundHolder.snp_makeConstraints { make in
            make.edges.equalTo(backgroundHolder.superview!)
        }

        background.snp_makeConstraints { make in
            make.bottom.left.right.equalTo(background.superview!)
            make.top.equalTo(background.superview!).offset(TabTrayControllerUX.TextBoxHeight)
        }

        favicon.snp_makeConstraints { make in
            make.bottom.left.equalTo(favicon.superview!)
            make.width.height.equalTo(TabTrayControllerUX.FaviconSize)
        }

        title.snp_makeConstraints { make in
            make.left.top.equalTo(title.superview!)
            make.width.equalTo(title.superview!.snp_width)
            make.height.equalTo(TabTrayControllerUX.TextBoxHeight)
        }

        innerStroke.snp_makeConstraints { make in
            make.edges.equalTo(background)
        }

        titleText.snp_makeConstraints { make in
            make.left.equalTo(closeButton.snp_right)
            make.top.right.bottom.equalTo(titleText.superview!)
        }

        closeButton.snp_makeConstraints { make in
            make.size.equalTo(title.snp_height)
            make.centerY.equalTo(title)
            make.left.equalTo(closeButton.superview!)
        }

        let top = (TabTrayControllerUX.TextBoxHeight - titleText.bounds.height) / 2.0
        titleText.frame.origin = CGPoint(x: titleText.frame.origin.x, y: max(0, top))
    }


    override func prepareForReuse() {
        // Reset any close animations.
        backgroundHolder.transform = CGAffineTransform.identity
        backgroundHolder.alpha = 1
        self.titleText.font = DynamicFontHelper.defaultHelper.DefaultSmallFontBold
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        var right: Bool
        switch direction {
        case .left:
            right = false
        case .right:
            right = true
        default:
            return false
        }
        animator.close(right: right)
        return true
    }

    @objc
    func SELclose() {
        self.animator.SELcloseWithoutGesture()
    }
}

@available(iOS 9, *)
struct PrivateModeStrings {
    static let toggleAccessibilityLabel = NSLocalizedString("Private Mode", tableName: "PrivateBrowsing", comment: "Accessibility label for toggling on/off private mode")
    static let toggleAccessibilityHint = NSLocalizedString("Turns private mode on or off", tableName: "PrivateBrowsing", comment: "Accessiblity hint for toggling on/off private mode")
    static let toggleAccessibilityValueOn = NSLocalizedString("On", tableName: "PrivateBrowsing", comment: "Toggled ON accessibility value")
    static let toggleAccessibilityValueOff = NSLocalizedString("Off", tableName: "PrivateBrowsing", comment: "Toggled OFF accessibility value")
}

protocol TabTrayDelegate: class {
    func tabTrayDidDismiss(_ tabTray: TabTrayController)
    func tabTrayDidAddBookmark(_ tab: Browser)
    func tabTrayDidAddToReadingList(_ tab: Browser) -> ReadingListClientRecord?
    func tabTrayRequestsPresentationOf(viewController: UIViewController)
}

class TabTrayController: UIViewController {
    let tabManager: TabManager
    let profile: Profile
    weak var delegate: TabTrayDelegate?

    var collectionView: UICollectionView!
    var navBar: UIView!
    var addTabButton: UIButton!
    var collectionViewTransitionSnapshot: UIView?

    fileprivate(set) internal var privateMode: Bool = false {
        didSet {
#if !BRAVE_NO_PRIVATE_MODE
            if #available(iOS 9, *) {
                togglePrivateMode.isSelected = privateMode
                togglePrivateMode.accessibilityValue = privateMode ? PrivateModeStrings.toggleAccessibilityValueOn : PrivateModeStrings.toggleAccessibilityValueOff
                tabDataSource.updateData()
                collectionView?.reloadData()
            }
#endif
        }
    }

    fileprivate var tabsToDisplay: [Browser] {
        return tabManager.tabs.displayedTabsForCurrentPrivateMode
    }

#if !BRAVE_NO_PRIVATE_MODE
    @available(iOS 9, *)
    lazy var togglePrivateMode: UIButton = {
        let button = UIButton()
        button.setTitle(NSLocalizedString("Private", comment: "Private button title"), for: UIControlState())
        button.setTitleColor(UIColor.black, for: .selected)
        button.setTitleColor(UIColor(white: 255/255.0, alpha: 1.0), for: UIControlState())
        button.titleLabel!.font = UIFont.systemFont(ofSize: button.titleLabel!.font.pointSize + 2)
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 4 /* left */, 0, 4 /* right */)
        button.addTarget(self, action: #selector(TabTrayController.SELdidTogglePrivateMode), for: .touchUpInside)
        button.accessibilityLabel = PrivateModeStrings.toggleAccessibilityLabel
        button.accessibilityHint = PrivateModeStrings.toggleAccessibilityHint
        button.accessibilityValue = self.privateMode ? PrivateModeStrings.toggleAccessibilityValueOn : PrivateModeStrings.toggleAccessibilityValueOff
        button.accessibilityIdentifier = "TabTrayController.togglePrivateMode"

        if PrivateBrowsing.singleton.isOn {
            button.backgroundColor = UIColor.white
            button.layer.cornerRadius = 4.0
            button.isSelected = true
        }
        return button
    }()

    @available(iOS 9, *)
    fileprivate lazy var emptyPrivateTabsView: EmptyPrivateTabsView = {
        let emptyView = EmptyPrivateTabsView()
        emptyView.learnMoreButton.addTarget(self, action: #selector(TabTrayController.SELdidTapLearnMore), for: UIControlEvents.touchUpInside)
        return emptyView
    }()
#endif
    fileprivate lazy var tabDataSource: TabManagerDataSource = {
        return TabManagerDataSource(cellDelegate: self)
    }()

    fileprivate lazy var tabLayoutDelegate: TabLayoutDelegate = {
        let delegate = TabLayoutDelegate(profile: self.profile, traitCollection: self.traitCollection)
        delegate.tabSelectionDelegate = self
        return delegate
    }()

#if BRAVE
    override func dismissViewControllerAnimated(flag: Bool, completion: (() -> Void)?) {

        super.dismissViewControllerAnimated(flag, completion:completion)

        UIView.animateWithDuration(0.2) {
            let braveTopVC = getApp().rootViewController.topViewController as? BraveTopViewController
            braveTopVC?.view.backgroundColor = BraveUX.TopLevelBackgroundColor
             getApp().browserViewController.view.alpha = 1.0
             getApp().browserViewController.toolbar?.leavingTabTrayMode()
        }

        getApp().browserViewController.updateTabCountUsingTabManager(getApp().tabManager)
    }
#endif

    init(tabManager: TabManager, profile: Profile) {
        self.tabManager = tabManager
        self.profile = profile
        super.init(nibName: nil, bundle: nil)

        tabManager.addDelegate(self)
    }

    convenience init(tabManager: TabManager, profile: Profile, tabTrayDelegate: TabTrayDelegate) {
        self.init(tabManager: tabManager, profile: profile)
        self.delegate = tabTrayDelegate
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NotificationDynamicFontChanged), object: nil)
        self.tabManager.removeDelegate(self)
    }

    func SELDynamicFontChanged(_ notification: Notification) {
        guard notification.name == NotificationDynamicFontChanged else { return }

        self.collectionView.reloadData()
    }

    @objc func onTappedBackground(_ gesture: UITapGestureRecognizer) {
        dismiss(animated: true, completion: nil)
    }

// MARK: View Controller Callbacks
    override func viewDidLoad() {
        super.viewDidLoad()

        view.accessibilityLabel = NSLocalizedString("Tabs Tray", comment: "Accessibility label for the Tabs Tray view.")

        navBar = UIView()
        navBar.backgroundColor = TabTrayControllerUX.BackgroundColor

        addTabButton = UIButton()
        addTabButton.setImage(UIImage(named: "add")?.withRenderingMode(.alwaysTemplate), for: UIControlState())
        addTabButton.addTarget(self, action: #selector(TabTrayController.SELdidClickAddTab), for: .touchUpInside)
        addTabButton.accessibilityLabel = NSLocalizedString("Add Tab", comment: "Accessibility label for the Add Tab button in the Tab Tray.")
        addTabButton.accessibilityIdentifier = "TabTrayController.addTabButton"
        addTabButton.tintColor = UIColor.white // makes it stand out more

        let flowLayout = TabTrayCollectionViewLayout()
        collectionView = UICollectionView(frame: view.frame, collectionViewLayout: flowLayout)

        collectionView.dataSource = tabDataSource
        collectionView.delegate = tabLayoutDelegate

        collectionView.register(TabCell.self, forCellWithReuseIdentifier: TabCell.Identifier)
        collectionView.backgroundColor = UIColor.clear

#if BRAVE
        collectionView.backgroundView = UIView(frame: view.frame)
        collectionView.backgroundView?.snp_makeConstraints() {
            make in
            make.edges.equalTo(collectionView)
        }
        collectionView.backgroundView?.userInteractionEnabled = true
        collectionView.backgroundView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(TabTrayController.onTappedBackground(_:))))
#endif

        view.addSubview(collectionView)
        view.addSubview(navBar)
        view.addSubview(addTabButton)


        makeConstraints()
#if !BRAVE_NO_PRIVATE_MODE
        if #available(iOS 9, *) {
            if profile.prefs.boolForKey(kPrefKeyPrivateBrowsingAlwaysOn) ?? false {
                togglePrivateMode.isHidden = true
            }

            view.addSubview(togglePrivateMode)
            togglePrivateMode.snp_makeConstraints { make in
                make.right.equalTo(addTabButton.snp_left).offset(-10)
                //make.height.equalTo(UIConstants.ToolbarHeight)
                make.centerY.equalTo(self.navBar)
            }

            view.insertSubview(emptyPrivateTabsView, aboveSubview: collectionView)
            emptyPrivateTabsView.alpha = privateTabsAreEmpty() ? 1 : 0
            emptyPrivateTabsView.snp_makeConstraints { make in
                make.edges.equalTo(self.view)
            }

            if let tab = tabManager.selectedTab , tab.isPrivate {
                privateMode = true
            } else if PrivateBrowsing.singleton.isOn {
                privateMode = true
            }

            // register for previewing delegate to enable peek and pop if force touch feature available
//            if traitCollection.forceTouchCapability == .Available {
//                registerForPreviewingWithDelegate(self, sourceView: view)
//            }
        }
#endif

        NotificationCenter.default.addObserver(self, selector: #selector(TabTrayController.SELappWillResignActiveNotification), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabTrayController.SELappDidBecomeActiveNotification), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabTrayController.SELDynamicFontChanged(_:)), name: NSNotification.Name(rawValue: NotificationDynamicFontChanged), object: nil)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // Update the trait collection we reference in our layout delegate
        tabLayoutDelegate.traitCollection = traitCollection
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: nil)
    }

    override var preferredStatusBarStyle : UIStatusBarStyle {
        return UIStatusBarStyle.lightContent
    }

    fileprivate func makeConstraints() {
        navBar.snp_makeConstraints { make in
            make.top.equalTo(snp_topLayoutGuideBottom)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.left.right.equalTo(self.view)
        }

        addTabButton.snp_makeConstraints { make in
            make.trailing.bottom.equalTo(self.navBar)
            make.size.equalTo(UIConstants.ToolbarHeight)
        }

        collectionView.snp_makeConstraints { make in
            make.top.equalTo(navBar.snp_bottom)
            make.left.right.bottom.equalTo(self.view)
        }
    }

// MARK: Selectors

    func SELdidClickAddTab() {
        openNewTab()
    }
  #if !BRAVE_NO_PRIVATE_MODE
    @available(iOS 9, *)
    func SELdidTapLearnMore() {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        if let langID = Locale.preferredLanguages.first {
            let learnMoreRequest = URLRequest(url: "https://support.mozilla.org/1/mobile/\(appVersion)/iOS/\(langID)/private-browsing-ios".asURL!)
            openNewTab(learnMoreRequest)
        }
    }
    
    

    @available(iOS 9, *)
    func SELdidTogglePrivateMode() {
        let scaleDownTransform = CGAffineTransform(scaleX: 0.9, y: 0.9)

        let fromView: UIView
        if privateTabsAreEmpty() {
            fromView = emptyPrivateTabsView
        } else {
            let snapshot = collectionView.snapshotView(afterScreenUpdates: false)
            snapshot?.frame = collectionView.frame
            view.insertSubview(snapshot!, aboveSubview: collectionView)
            fromView = snapshot!
        }

        privateMode = !privateMode
#if BRAVE
        if privateMode {
            PrivateBrowsing.singleton.enter()
            togglePrivateMode.backgroundColor = UIColor.whiteColor()
            togglePrivateMode.layer.cornerRadius = 4.0
        } else {
            self.togglePrivateMode.backgroundColor = UIColor.clearColor()
            view.userInteractionEnabled = false
            view.alpha = 0.5
            let activityView = UIActivityIndicatorView(activityIndicatorStyle: .WhiteLarge)
            activityView.center = view.center
            activityView.startAnimating()
            self.view.addSubview(activityView)

            PrivateBrowsing.singleton.exit().uponQueue(dispatch_get_main_queue()) {
                self.view.userInteractionEnabled = true
                self.view.alpha = 1.0
                activityView.stopAnimating()
            }
        }
        tabDataSource.updateData()
#else
        // If we are exiting private mode and we have the close private tabs option selected, make sure
        // we clear out all of the private tabs
        if !privateMode && profile.prefs.boolForKey("settings.closePrivateTabs") ?? false {
            tabManager.removeAllPrivateTabsAndNotify(false)
        }

        togglePrivateMode.setSelected(privateMode, animated: true)
#endif

        collectionView.layoutSubviews()

        let toView: UIView
        if privateTabsAreEmpty() {
            toView = emptyPrivateTabsView
        } else {
            let newSnapshot = collectionView.snapshotView(afterScreenUpdates: true)
            newSnapshot?.frame = collectionView.frame
            view.insertSubview(newSnapshot!, aboveSubview: fromView)
            collectionView.alpha = 0
            toView = newSnapshot!
        }
        toView.alpha = 0
        toView.transform = scaleDownTransform

        UIView.animate(withDuration: 0.2, delay: 0, options: [], animations: { () -> Void in
            fromView.transform = scaleDownTransform
            fromView.alpha = 0
            toView.transform = CGAffineTransform.identity
            toView.alpha = 1
        }) { finished in
            if fromView != self.emptyPrivateTabsView {
                fromView.removeFromSuperview()
            }
            if toView != self.emptyPrivateTabsView {
                toView.removeFromSuperview()
            }
            self.collectionView.alpha = 1
        }
    }

    @available(iOS 9, *)
    fileprivate func privateTabsAreEmpty() -> Bool {
        return privateMode && tabManager.tabs.privateTabs.count == 0
    }
#endif

    @available(iOS 9, *)
    func changePrivacyMode(_ isPrivate: Bool) {
#if !BRAVE_NO_PRIVATE_MODE
        if isPrivate != privateMode {
            guard let _ = collectionView else {
                privateMode = isPrivate
                return
            }
            SELdidTogglePrivateMode()
        }
#endif
    }

    fileprivate func openNewTab(_ request: URLRequest? = nil) {
#if !BRAVE_NO_PRIVATE_MODE
        if #available(iOS 9, *) {
            if privateMode {
                emptyPrivateTabsView.isHidden = true
            }
        }
#endif
        // We're only doing one update here, but using a batch update lets us delay selecting the tab
        // until after its insert animation finishes.
        self.collectionView.performBatchUpdates({ _ in
            var tab: Browser?
#if !BRAVE_NO_PRIVATE_MODE
            if #available(iOS 9, *) {
                tab = self.tabManager.addTab(request, isPrivate: self.privateMode)
            } else {
              tab = self.tabManager.addTab(request)
            }
#else
            tab = self.tabManager.addTab(request)
#endif
            if let tab = tab {
                self.tabManager.selectTab(tab)
            }
        }, completion: { finished in
            if finished {
                #if BRAVE
                    self.dismissViewControllerAnimated(true, completion: nil)
                #else
                    self.navigationController?.popViewController(animated: true)
                #endif
            }
        })
    }
}

// MARK: - App Notifications
extension TabTrayController {
    func SELappWillResignActiveNotification() {
        if privateMode {
            collectionView.alpha = 0
        }
    }

    func SELappDidBecomeActiveNotification() {
        // Re-show any components that might have been hidden because they were being displayed
        // as part of a private mode tab
        UIView.animate(withDuration: 0.2, delay: 0, options: UIViewAnimationOptions(), animations: {
            self.collectionView.alpha = 1
        },
        completion: nil)
    }
}

extension TabTrayController: TabSelectionDelegate {
    func didSelectTabAtIndex(_ index: Int) {
        let tab = tabsToDisplay[index]
        tabManager.selectTab(tab)
        #if BRAVE
            self.dismissViewControllerAnimated(true, completion: nil)
        #else
            self.navigationController?.popViewController(animated: true)
        #endif
    }
}

extension TabTrayController: PresentingModalViewControllerDelegate {
    func dismissPresentedModalViewController(_ modalViewController: UIViewController, animated: Bool) {
        dismiss(animated: animated, completion: { self.collectionView.reloadData() })
    }
}

extension TabTrayController: TabManagerDelegate {
    func tabManager(_ tabManager: TabManager, didSelectedTabChange selected: Browser?) {
    }

    func tabManager(_ tabManager: TabManager, didCreateWebView tab: Browser, url: URL?) {
    }

    func tabManager(_ tabManager: TabManager, didAddTab tab: Browser) {
        // Get the index of the added tab from it's set (private or normal)
        guard let index = tabsToDisplay.index(of: tab) else { return }

        tabDataSource.updateData()

        self.collectionView?.performBatchUpdates({ _ in
            self.collectionView.insertItems(at: [IndexPath(item: index, section: 0)])
        }, completion: { finished in
            if finished {
                tabManager.selectTab(tab)
                // don't pop the tab tray view controller if it is not in the foreground
                if self.presentedViewController == nil {
                    #if BRAVE
                        self.dismissViewControllerAnimated(true, completion: nil)
                    #else
                        self.navigationController?.popViewController(animated: true)
                    #endif
                }
            }
        })
    }

    func tabManager(_ tabManager: TabManager, didRemoveTab tab: Browser) {
        var removedIndex = -1
        for i in 0..<tabDataSource.tabList.count() {
            let tabRef = tabDataSource.tabList.at(i)
            if tabRef == nil || getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.indexOf(tabRef!) == nil {
                removedIndex = i
                break
            }
        }

        tabDataSource.updateData()
        if (removedIndex < 0) {
            return
        }

        self.collectionView.deleteItems(at: [IndexPath(item: removedIndex, section: 0)])

        // Workaround: On iOS 8.* devices, cells don't get reloaded during the deletion but after the
        // animation has finished which causes cells that animate from above to suddenly 'appear'. This
        // is fixed on iOS 9 but for iOS 8 we force a reload on non-visible cells during the animation.
        if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_8_3) {
            let visibleCount = collectionView.indexPathsForVisibleItems.count
            var offscreenIndexPaths = [IndexPath]()
            for i in 0..<(tabsToDisplay.count - visibleCount) {
                offscreenIndexPaths.append(IndexPath(item: i, section: 0))
            }
            self.collectionView.reloadItems(at: offscreenIndexPaths)
        }
#if !BRAVE_NO_PRIVATE_MODE
        if #available(iOS 9, *) {
            if privateTabsAreEmpty() {
                emptyPrivateTabsView.alpha = 1
            }
        }
#endif
    }

    func tabManagerDidAddTabs(_ tabManager: TabManager) {
    }

    func tabManagerDidRestoreTabs(_ tabManager: TabManager) {
    }
}

extension TabTrayController: UIScrollViewAccessibilityDelegate {
    func accessibilityScrollStatus(for scrollView: UIScrollView) -> String? {
        var visibleCells = collectionView.visibleCells as! [TabCell]
        var bounds = collectionView.bounds
        bounds = bounds.offsetBy(dx: collectionView.contentInset.left, dy: collectionView.contentInset.top)
        bounds.size.width -= collectionView.contentInset.left + collectionView.contentInset.right
        bounds.size.height -= collectionView.contentInset.top + collectionView.contentInset.bottom
        // visible cells do sometimes return also not visible cells when attempting to go past the last cell with VoiceOver right-flick gesture; so make sure we have only visible cells (yeah...)
        visibleCells = visibleCells.filter { !$0.frame.intersection(bounds).isEmpty }

        let cells = visibleCells.map { self.collectionView.indexPath(for: $0)! }
        let indexPaths = cells.sorted { (a: IndexPath, b: IndexPath) -> Bool in
            return (a as NSIndexPath).section < (b as NSIndexPath).section || ((a as NSIndexPath).section == (b as NSIndexPath).section && (a as NSIndexPath).row < (b as NSIndexPath).row)
        }

        if indexPaths.count == 0 {
            return NSLocalizedString("No tabs", comment: "Message spoken by VoiceOver to indicate that there are no tabs in the Tabs Tray")
        }

        let firstTab = (indexPaths.first! as NSIndexPath).row + 1
        let lastTab = (indexPaths.last! as NSIndexPath).row + 1
        let tabCount = collectionView.numberOfItems(inSection: 0)

        if (firstTab == lastTab) {
            let format = NSLocalizedString("Tab %@ of %@", comment: "Message spoken by VoiceOver saying the position of the single currently visible tab in Tabs Tray, along with the total number of tabs. E.g. \"Tab 2 of 5\" says that tab 2 is visible (and is the only visible tab), out of 5 tabs total.")
            return String(format: format, NSNumber(value: firstTab as Int), NSNumber(value: tabCount as Int))
        } else {
            let format = NSLocalizedString("Tabs %@ to %@ of %@", comment: "Message spoken by VoiceOver saying the range of tabs that are currently visible in Tabs Tray, along with the total number of tabs. E.g. \"Tabs 8 to 10 of 15\" says tabs 8, 9 and 10 are visible, out of 15 tabs total.")
            return String(format: format, NSNumber(value: firstTab as Int), NSNumber(value: lastTab as Int), NSNumber(value: tabCount as Int))
        }
    }
}

private func removeTabUtil(_ tabManager: TabManager, tab: Browser) {
    let isAlwaysPrivate = getApp().profile?.prefs.boolForKey(kPrefKeyPrivateBrowsingAlwaysOn) ?? false
    let createIfNone =  isAlwaysPrivate ? true : !PrivateBrowsing.singleton.isOn
    tabManager.removeTab(tab, createTabIfNoneLeft: createIfNone)
}

extension TabTrayController: SwipeAnimatorDelegate {
    func swipeAnimator(_ animator: SwipeAnimator, viewWillExitContainerBounds: UIView) {
        let tabCell = animator.container as! TabCell
        if let indexPath = collectionView.indexPath(for: tabCell) {
            let tab = tabsToDisplay[(indexPath as NSIndexPath).item]
            removeTabUtil(tabManager, tab: tab)
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NSLocalizedString("Closing tab", comment: ""))
        }
    }
}

extension TabTrayController: TabCellDelegate {
    func tabCellDidClose(_ cell: TabCell) {
        let indexPath = collectionView.indexPath(for: cell)!
        let tab = tabsToDisplay[(indexPath as NSIndexPath).item]
        removeTabUtil(tabManager, tab: tab)
    }
}

extension TabTrayController: SettingsDelegate {
    func settingsOpenURLInNewTab(_ url: URL) {
        let request = URLRequest(url: url)
        openNewTab(request)
    }
}

private class TabManagerDataSource: NSObject, UICollectionViewDataSource {
    unowned var cellDelegate: TabCellDelegate & SwipeAnimatorDelegate

    fileprivate var tabList = WeakList<Browser>()

    init(cellDelegate: TabCellDelegate & SwipeAnimatorDelegate) {
        self.cellDelegate = cellDelegate
        super.init()

        getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.forEach {
            tabList.insert($0)
        }
    }

    func updateData() {
        tabList = WeakList<Browser>()
        getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.forEach {
            tabList.insert($0)
        }
    }

    @objc func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let tabCell = collectionView.dequeueReusableCell(withReuseIdentifier: TabCell.Identifier, for: indexPath) as! TabCell
        tabCell.animator.delegate = cellDelegate
        tabCell.delegate = cellDelegate

        guard let tab = tabList.at(indexPath.item) else {
            assert(false)
            return tabCell
        }
        tabCell.style = tab.isPrivate ? .Dark : .Light
        tabCell.titleText.text = tab.displayTitle

        if !tab.displayTitle.isEmpty {
            tabCell.accessibilityLabel = tab.displayTitle
        } else {
            tabCell.accessibilityLabel = AboutUtils.getAboutComponent(tab.url)
        }

        tabCell.isAccessibilityElement = true
        tabCell.accessibilityHint = NSLocalizedString("Swipe right or left with three fingers to close the tab.", comment: "Accessibility hint for tab tray's displayed tab.")

        if let favIcon = tab.displayFavicon {
            tabCell.favicon.sd_setImageWithURL(URL(string: favIcon.url)!)
            tabCell.favicon.backgroundColor = BraveUX.TabTrayCellBackgroundColor
        } else {
            tabCell.favicon.image = nil
        }
        
        tabCell.background.image = tab.screenshot.image
        tab.screenshot.listenerImages.append(UIImageWithNotify.WeakImageView(tabCell.background))
        
        return tabCell
    }

    @objc func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabList.count()
    }
}

@objc protocol TabSelectionDelegate: class {
    func didSelectTabAtIndex(_ index :Int)
}

private class TabLayoutDelegate: NSObject, UICollectionViewDelegateFlowLayout {
    weak var tabSelectionDelegate: TabSelectionDelegate?

    fileprivate var traitCollection: UITraitCollection
    fileprivate var profile: Profile
    fileprivate var numberOfColumns: Int {
        let compactLayout = profile.prefs.boolForKey("CompactTabLayout") ?? true

        // iPhone 4-6+ portrait
        if traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .regular {
            return compactLayout ? TabTrayControllerUX.CompactNumberOfColumnsThin : TabTrayControllerUX.NumberOfColumnsThin
        } else {
            return TabTrayControllerUX.NumberOfColumnsWide
        }
    }

    init(profile: Profile, traitCollection: UITraitCollection) {
        self.profile = profile
        self.traitCollection = traitCollection
        super.init()
    }

    fileprivate func cellHeightForCurrentDevice() -> CGFloat {
        let compactLayout = profile.prefs.boolForKey("CompactTabLayout") ?? true
        let shortHeight = (compactLayout ? TabTrayControllerUX.TextBoxHeight * 6 : TabTrayControllerUX.TextBoxHeight * 5)

        if self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClass.compact {
            return shortHeight
        } else if self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClass.compact {
            return shortHeight
        } else {
            return TabTrayControllerUX.TextBoxHeight * 8
        }
    }

    @objc func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return TabTrayControllerUX.Margin
    }

    @objc func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let cellWidth = floor((collectionView.bounds.width - TabTrayControllerUX.Margin * CGFloat(numberOfColumns + 1)) / CGFloat(numberOfColumns))
        return CGSize(width: cellWidth, height: self.cellHeightForCurrentDevice())
    }

    @objc func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsetsMake(TabTrayControllerUX.Margin, TabTrayControllerUX.Margin, TabTrayControllerUX.Margin, TabTrayControllerUX.Margin)
    }

    @objc func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return TabTrayControllerUX.Margin
    }

    @objc func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        tabSelectionDelegate?.didSelectTabAtIndex((indexPath as NSIndexPath).row)
    }
}

// There seems to be a bug with UIKit where when the UICollectionView changes its contentSize
// from > frame.size to <= frame.size: the contentSet animation doesn't properly happen and 'jumps' to the
// final state.
// This workaround forces the contentSize to always be larger than the frame size so the animation happens more
// smoothly. This also makes the tabs be able to 'bounce' when there are not enough to fill the screen, which I
// think is fine, but if needed we can disable user scrolling in this case.
private class TabTrayCollectionViewLayout: UICollectionViewFlowLayout {
    fileprivate override var collectionViewContentSize : CGSize {
        var calculatedSize = super.collectionViewContentSize
        let collectionViewHeight = collectionView?.bounds.size.height ?? 0
        if calculatedSize.height < collectionViewHeight && collectionViewHeight > 0 {
            calculatedSize.height = collectionViewHeight + 1
        }
        return calculatedSize
    }
}

struct EmptyPrivateTabsViewUX {
    static let TitleColor = UIColor.white
    static let TitleFont = UIFont.systemFont(ofSize: 22, weight: UIFontWeightMedium)
    static let DescriptionColor = UIColor.white
    static let DescriptionFont = UIFont.systemFont(ofSize: 17)
    static let LearnMoreFont = UIFont.systemFont(ofSize: 15, weight: UIFontWeightMedium)
    static let TextMargin: CGFloat = 18
    static let LearnMoreMargin: CGFloat = 30
    static let MaxDescriptionWidth: CGFloat = 250
}

// View we display when there are no private tabs created
private class EmptyPrivateTabsView: UIView {
    fileprivate lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = EmptyPrivateTabsViewUX.TitleColor
        label.font = EmptyPrivateTabsViewUX.TitleFont
        label.textAlignment = NSTextAlignment.center
        return label
    }()

    fileprivate var descriptionLabel: UILabel = {
        let label = UILabel()
        label.textColor = EmptyPrivateTabsViewUX.DescriptionColor
        label.font = EmptyPrivateTabsViewUX.DescriptionFont
        label.textAlignment = NSTextAlignment.center
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = EmptyPrivateTabsViewUX.MaxDescriptionWidth
        return label
    }()

    fileprivate var learnMoreButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(
            NSLocalizedString("Learn More", tableName: "PrivateBrowsing", comment: "Text button displayed when there are no tabs open while in private mode"),
            for: UIControlState())
        button.setTitleColor(UIConstants.PrivateModeTextHighlightColor, for: UIControlState())
        button.titleLabel?.font = EmptyPrivateTabsViewUX.LearnMoreFont
        return button
    }()

#if !BRAVE
    fileprivate var iconImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "largePrivateMask"))
        return imageView
    }()
#endif
    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.black.withAlphaComponent(0.6)

        titleLabel.text =  NSLocalizedString("Private Browsing",
            tableName: "PrivateBrowsing", comment: "Title displayed for when there are no open tabs while in private mode")
        descriptionLabel.text = NSLocalizedString("Brave won't remember any of your history or cookies, but new bookmarks will be saved.",
            tableName: "PrivateBrowsing", comment: "Description text displayed when there are no open tabs while in private mode")

        addSubview(titleLabel)
        addSubview(descriptionLabel)
#if !BRAVE
        addSubview(iconImageView)
        addSubview(learnMoreButton)
#endif
        titleLabel.snp_makeConstraints { make in
            make.center.equalTo(self)
        }

        descriptionLabel.snp_makeConstraints { make in
            make.top.equalTo(titleLabel.snp_bottom).offset(EmptyPrivateTabsViewUX.TextMargin)
            make.centerX.equalTo(self)
        }

#if !BRAVE
        iconImageView.snp_makeConstraints { make in
            make.bottom.equalTo(titleLabel.snp_top).offset(-EmptyPrivateTabsViewUX.TextMargin)
            make.centerX.equalTo(self)
        }

        learnMoreButton.snp_makeConstraints { (make) -> Void in
            make.top.equalTo(descriptionLabel.snp_bottom).offset(EmptyPrivateTabsViewUX.LearnMoreMargin)
            make.centerX.equalTo(self)
        }
#endif
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

//@available(iOS 9.0, *)
//extension TabTrayController: TabPeekDelegate {
//
//    func tabPeekDidAddBookmark(tab: Browser) {
//        delegate?.tabTrayDidAddBookmark(tab)
//    }
//
//    func tabPeekDidAddToReadingList(tab: Browser) -> ReadingListClientRecord? {
//        return delegate?.tabTrayDidAddToReadingList(tab)
//    }
//
//    func tabPeekDidCloseTab(tab: Browser) {
//        if let index = self.tabDataSource.tabs.indexOf(tab),
//            let cell = self.collectionView?.cellForItemAtIndexPath(NSIndexPath(forItem: index, inSection: 0)) as? TabCell {
//            cell.SELclose()
//        }
//    }
//
//    func tabPeekRequestsPresentationOf(viewController viewController: UIViewController) {
//        delegate?.tabTrayRequestsPresentationOf(viewController: viewController)
//    }
//}

//@available(iOS 9.0, *)
//extension TabTrayController: UIViewControllerPreviewingDelegate {
//
//    func previewingContext(previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
//
//        guard let collectionView = collectionView else { return nil }
//        let convertedLocation = self.view.convertPoint(location, toView: collectionView)
//
//        guard let indexPath = collectionView.indexPathForItemAtPoint(convertedLocation),
//            let cell = collectionView.cellForItemAtIndexPath(indexPath) else { return nil }
//
//        let tab = tabDataSource.tabs[indexPath.row]
//        let tabVC = TabPeekViewController(tab: tab, delegate: self)
//        if let browserProfile = profile as? BrowserProfile {
//            tabVC.setState(withProfile: browserProfile, clientPickerDelegate: self)
//        }
//        previewingContext.sourceRect = self.view.convertRect(cell.frame, fromView: collectionView)
//
//        return tabVC
//    }
//
//    func previewingContext(previewingContext: UIViewControllerPreviewing, commitViewController viewControllerToCommit: UIViewController) {
//        guard let tpvc = viewControllerToCommit as? TabPeekViewController else { return }
//        tabManager.selectTab(tpvc.tab)
//
//        #if BRAVE
//            self.dismissViewControllerAnimated(true, completion: nil)
//        #else
//            self.navigationController?.popViewControllerAnimated(true)
//        #endif
//
//        delegate?.tabTrayDidDismiss(self)
//
//    }
//}

//extension TabTrayController: ClientPickerViewControllerDelegate {
//
//    func clientPickerViewController(clientPickerViewController: ClientPickerViewController, didPickClients clients: [RemoteClient]) {
//        if let item = clientPickerViewController.shareItem {
//            self.profile.sendItems([item], toClients: clients)
//        }
//        clientPickerViewController.dismissViewControllerAnimated(true, completion: nil)
//    }
//
//    func clientPickerViewControllerDidCancel(clientPickerViewController: ClientPickerViewController) {
//        clientPickerViewController.dismissViewControllerAnimated(true, completion: nil)
//    }
//}
