/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Storage

struct SiteTableViewControllerUX {
    static let HeaderHeight = CGFloat(25)
    static let RowHeight = CGFloat(58)
    static let HeaderBorderColor = UIColor(rgb: 0xCFD5D9).colorWithAlphaComponent(0.8)
    static let HeaderTextColor = UIAccessibilityDarkerSystemColorsEnabled() ? UIColor.black : UIColor(rgb: 0x232323)
    static let HeaderBackgroundColor = UIColor(rgb: 0xECF0F3).colorWithAlphaComponent(0.3)
    static let HeaderFont = UIFont.systemFont(ofSize: 12, weight: UIFontWeightMedium)
    static let HeaderTextMargin = CGFloat(10)
}

class SiteTableViewHeader : UITableViewHeaderFooterView {
    // I can't get drawRect to play nicely with the glass background. As a fallback
    // we just use views for the top and bottom borders.
    let topBorder = UIView()
    let bottomBorder = UIView()
    let titleLabel = UILabel()

    override var textLabel: UILabel? {
        return titleLabel
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        topBorder.backgroundColor = UIColor.white
        bottomBorder.backgroundColor = SiteTableViewControllerUX.HeaderBorderColor
        contentView.backgroundColor = UIColor.white

        titleLabel.font = DynamicFontHelper.defaultHelper.DeviceFontSmallLight
        titleLabel.textColor = SiteTableViewControllerUX.HeaderTextColor
        titleLabel.textAlignment = .left

        addSubview(topBorder)
        addSubview(bottomBorder)
        contentView.addSubview(titleLabel)

        topBorder.snp_makeConstraints { make in
            make.left.right.equalTo(self)
            make.top.equalTo(self).offset(-0.5)
            make.height.equalTo(0.5)
        }

        bottomBorder.snp_makeConstraints { make in
            make.left.right.bottom.equalTo(self)
            make.height.equalTo(0.5)
        }

        // A table view will initialize the header with CGSizeZero before applying the actual size. Hence, the label's constraints
        // must not impose a minimum width on the content view.
        titleLabel.snp_makeConstraints { make in
            make.left.equalTo(contentView).offset(SiteTableViewControllerUX.HeaderTextMargin).priority(999)
            make.right.equalTo(contentView).offset(-SiteTableViewControllerUX.HeaderTextMargin).priority(999)
            make.centerY.equalTo(contentView)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/**
 * Provides base shared functionality for site rows and headers.
 */
class SiteTableViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    fileprivate let CellIdentifier = "CellIdentifier"
    fileprivate let HeaderIdentifier = "HeaderIdentifier"
    var profile: Profile! {
        didSet {
            reloadData()
        }
    }
    
    var iconForSiteId = [Int : Favicon]()
    var data: Cursor<Site> = Cursor<Site>(status: .Success, msg: "No data set")
    var tableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(tableView)
        tableView.snp_makeConstraints { make in
            make.edges.equalTo(self.view)
            return
        }

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(HistoryTableViewCell.self, forCellReuseIdentifier: CellIdentifier)
        tableView.register(SiteTableViewHeader.self, forHeaderFooterViewReuseIdentifier: HeaderIdentifier)
        tableView.layoutMargins = UIEdgeInsets.zero
        tableView.keyboardDismissMode = UIScrollViewKeyboardDismissMode.onDrag
        tableView.backgroundColor = UIConstants.PanelBackgroundColor
        tableView.separatorColor = UIConstants.SeparatorColor
        tableView.accessibilityIdentifier = "SiteTable"

        if #available(iOS 9, *) {
            tableView.cellLayoutMarginsFollowReadableWidth = false
        }

        // Set an empty footer to prevent empty cells from appearing in the list.
        tableView.tableFooterView = UIView()
    }

    deinit {
        // The view might outlive this view controller thanks to animations;
        // explicitly nil out its references to us to avoid crashes. Bug 1218826.
        tableView.dataSource = nil
        tableView.delegate = nil
    }

    func reloadData() {
        if data.status != .Success {
            print("Err: \(data.statusMessage)", terminator: "\n")
        } else {
            debugNoteIfNotMainThread() // Guard against misuse
            postAsyncToMain { // TODO remove this, see comment below
                // By bad design, when self.profile is set, this func is called, profile usage (possibly assignment) is not restricted to main thread.
                self.tableView.reloadData()
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return data.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier, for: indexPath)
        if self.tableView(tableView, hasFullWidthSeparatorForRowAtIndexPath: indexPath) {
            cell.separatorInset = UIEdgeInsets.zero
        }
        
        cell.gestureRecognizers?.forEach { cell.removeGestureRecognizer($0) }
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPressOnCell))
        cell.addGestureRecognizer(lp)

        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return tableView.dequeueReusableHeaderFooterView(withIdentifier: HeaderIdentifier)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SiteTableViewControllerUX.HeaderHeight
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return SiteTableViewControllerUX.RowHeight
    }

    func tableView(_ tableView: UITableView, hasFullWidthSeparatorForRowAtIndexPath indexPath: IndexPath) -> Bool {
        return false
    }

    @objc func longPressOnCell(_ gesture: UILongPressGestureRecognizer) {
        if tableView.isEditing { //disable context menu on editing mode
            return
        }
        
        if gesture.state != .began {
            return
        }
        
        guard let cell = gesture.view as? UITableViewCell else { return }
        var url:URL? = nil

        if let bookmarks = self as? BookmarksPanel,
            let source = bookmarks.source,
            let indexPath = tableView.indexPath(for: cell) {
            let bookmark = source.current[indexPath.row]
            if let b = bookmark as? BookmarkItem {
                url = URL(string: b.url)
            }

        } else if let path = cell.detailTextLabel?.text {
            url = URL(string: path)
        }

        guard let _ = url else { return }

        let tappedElement = ContextMenuHelper.Elements(link: url, image: nil)
        var p = getApp().window!.convert(cell.center, from:cell.superview!)
        p.x += cell.frame.width * 0.33
        getApp().browserViewController.showContextMenu(elements: tappedElement, touchPoint: p)
    }
}
