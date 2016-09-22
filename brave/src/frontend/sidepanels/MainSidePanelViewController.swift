/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Storage
import SnapKit

class MainSidePanelViewController : SidePanelBaseViewController {

    let bookmarksPanel = BookmarksPanel()
    fileprivate var bookmarksNavController:UINavigationController!
    
    let history = HistoryPanel()

    var bookmarksButton = UIButton()
    var historyButton = UIButton()

    var settingsButton = UIButton()

    let topButtonsView = UIView()
    let addBookmarkButton = UIButton()

    let triangleView = UIImageView()

    let divider = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func setupUIElements() {
        super.setupUIElements()
        
        //change the font used in the navigation controller header
        let font = UIFont.boldSystemFont(ofSize: 14)
        UINavigationBar.appearance().titleTextAttributes = [NSFontAttributeName : font, NSForegroundColorAttributeName : UIColor.black];
        bookmarksNavController = UINavigationController(rootViewController: bookmarksPanel)
        containerView.addSubview(topButtonsView)

        topButtonsView.addSubview(triangleView)
        topButtonsView.addSubview(bookmarksButton)
        topButtonsView.addSubview(historyButton)
        topButtonsView.addSubview(addBookmarkButton)
        topButtonsView.addSubview(settingsButton)
        topButtonsView.addSubview(divider)

        divider.backgroundColor = UIColor.gray

        triangleView.image = UIImage(named: "triangle-nub")
        triangleView.contentMode = UIViewContentMode.center
        triangleView.alpha = 0.9

        settingsButton.setImage(UIImage(named: "settings")?.withRenderingMode(.alwaysTemplate), for: UIControlState())
        settingsButton.addTarget(self, action: #selector(onClickSettingsButton), for: .touchUpInside)
        settingsButton.accessibilityLabel = NSLocalizedString("Settings", comment: "Accessibility label for the Settings button.")

        bookmarksButton.setImage(UIImage(named: "bookmarklist"), for: UIControlState())
        bookmarksButton.addTarget(self, action: #selector(MainSidePanelViewController.showBookmarks), for: .touchUpInside)
        bookmarksButton.accessibilityLabel = NSLocalizedString("Show Bookmarks", comment: "Button to show the bookmarks list")

        historyButton.setImage(UIImage(named: "history"), for: UIControlState())
        historyButton.addTarget(self, action: #selector(MainSidePanelViewController.showHistory), for: .touchUpInside)
        historyButton.accessibilityLabel = NSLocalizedString("Show History", comment: "Button to show the history list")

        addBookmarkButton.addTarget(self, action: #selector(onClickBookmarksButton), for: .touchUpInside)
        addBookmarkButton.setImage(UIImage(named: "bookmark"), for: UIControlState())
        addBookmarkButton.setImage(UIImage(named: "bookmarkMarked"), for: .selected)
        addBookmarkButton.accessibilityLabel = NSLocalizedString("Add Bookmark", comment: "Button to add a bookmark")

        settingsButton.tintColor = BraveUX.ActionButtonTintColor
        bookmarksButton.tintColor = BraveUX.ActionButtonTintColor
        historyButton.tintColor = BraveUX.ActionButtonTintColor
        addBookmarkButton.tintColor = BraveUX.ActionButtonTintColor

        containerView.addSubview(history.view)
        containerView.addSubview(bookmarksNavController.view)
        
        showBookmarks()

        bookmarksNavController.view.isHidden = false

        containerView.bringSubview(toFront: topButtonsView)

        NotificationCenter.defaultCenter().addObserver(self, selector: #selector(historyItemAdded), name: kNotificationSiteAddedToHistory, object: nil)
    }

    @objc func historyItemAdded() {
        if self.view.isHidden {
            return
        }
        postAsyncToMain {
            self.history.refresh()
        }
    }
    
    func willHide() {
        if self.bookmarksPanel.currentBookmarksPanel().tableView.isEditing {
            self.bookmarksPanel.currentBookmarksPanel().disableTableEditingMode()
        }
    }
    
    func onClickSettingsButton() {
        if getApp().profile == nil {
            return
        }

        let settingsTableViewController = BraveSettingsView(style: .grouped)
        settingsTableViewController.profile = getApp().profile

        let controller = SettingsNavigationController(rootViewController: settingsTableViewController)
        controller.modalPresentationStyle = UIModalPresentationStyle.formSheet
        present(controller, animated: true, completion: nil)
    }

    //For this function to be called there *must* be a selected tab and URL
    //since we disable the button when there's no URL
    //see MainSidePanelViewController#updateBookmarkStatus(isBookmarked,url)
    func onClickBookmarksButton() {

        let tab = browserViewController!.tabManager.selectedTab!
        let url = tab.displayURL!.absoluteString
        
        //switch to bookmarks 'tab' in case we're looking at history and tapped the add/remove bookmark button
        self.showBookmarks()

        //TODO -- need to separate the knowledge of whether current site is bookmarked or not from this UI button
        //tracked in https://github.com/brave/browser-ios/issues/375
        if addBookmarkButton.isSelected {
            browserViewController?.removeBookmark(url) {
                self.bookmarksPanel.currentBookmarksPanel().reloadData()
            }
        } else {
            var folderId:String? = nil
            var folderTitle:String? = nil
            if let currentFolder = self.bookmarksPanel.currentBookmarksPanel().bookmarkFolder {
                folderId = currentFolder.guid
                folderTitle = currentFolder.title
            }
            
            let count = self.bookmarksPanel.currentBookmarksPanel().currentItemCount
            browserViewController?.addBookmark(url, title: tab.title, folderId: folderId, folderTitle: folderTitle){
                self.bookmarksPanel.currentBookmarksPanel().reloadData()
                
            }
        }
    }

    override func setupConstraints() {
        super.setupConstraints()
        
        topButtonsView.snp_remakeConstraints {
            make in
            make.top.equalTo(containerView).offset(spaceForStatusBar())
            make.left.right.equalTo(containerView)
            make.height.equalTo(44.0)
        }

        func common(_ make: ConstraintMaker) {
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.width.equalTo(60)
        }

        settingsButton.snp_remakeConstraints {
            make in
            common(make)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(0.25)
        }

        divider.snp_remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView).inset(8.0)
            make.height.equalTo(UIConstants.ToolbarHeight - 18.0)
            make.width.equalTo(2.0)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(0.5)
        }

        historyButton.snp_remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(0.75)
        }

        bookmarksButton.snp_remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(1.25)
        }

        addBookmarkButton.snp_remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(1.75)
        }

        bookmarksNavController.view.snp_remakeConstraints { make in
            make.left.right.bottom.equalTo(containerView)
            make.top.equalTo(topButtonsView.snp_bottom)
        }

        history.view.snp_remakeConstraints { make in
            make.left.right.bottom.equalTo(containerView)
            make.top.equalTo(topButtonsView.snp_bottom)
        }
    }

    func showBookmarks() {
        history.view.isHidden = true
        bookmarksNavController.view.isHidden = false
        moveTabIndicator(bookmarksButton)
    }

    func showHistory() {
        bookmarksNavController.view.isHidden = true
        history.view.isHidden = false
        moveTabIndicator(historyButton)
    }

    func moveTabIndicator(_ button: UIButton) {
        triangleView.snp_remakeConstraints {
            make in
            make.width.equalTo(button)
            make.height.equalTo(6)
            make.left.equalTo(button)
            make.top.equalTo(button.snp_bottom)
        }
    }

    override func setHomePanelDelegate(_ delegate: HomePanelDelegate?) {
        bookmarksPanel.profile = getApp().profile
        history.profile = getApp().profile
        bookmarksPanel.homePanelDelegate = delegate
        history.homePanelDelegate = delegate
        
        if (delegate != nil) {
            bookmarksPanel.reloadData()
            history.reloadData()
        }
    }

    
    func updateBookmarkStatus(_ isBookmarked: Bool, url: URL?) {
        //URL will be passed as nil by updateBookmarkStatus from BraveTopViewController
        if url == nil {
            //disable button for homescreen/empty url
            addBookmarkButton.isSelected = false
            addBookmarkButton.isEnabled = false
        }
        else {
            addBookmarkButton.isEnabled = true
            addBookmarkButton.isSelected = isBookmarked
        }
    }
}


