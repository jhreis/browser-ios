/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

import Shared
import Storage
import XCGLogger
import Deferred

private let log = Logger.browserLogger

private func getDate(dayOffset: Int) -> Date {
    let calendar = Calendar(identifier: Calendar.Identifier.gregorian)
    let nowComponents = (calendar as NSCalendar).components([NSCalendar.Unit.year, NSCalendar.Unit.month, NSCalendar.Unit.day], from: Date())
    let today = calendar.date(from: nowComponents)!
    return (calendar as NSCalendar).date(byAdding: NSCalendar.Unit.day, value: dayOffset, to: today, options: [])!
}

private typealias SectionNumber = Int
private typealias CategoryNumber = Int
private typealias CategorySpec = (section: SectionNumber?, rows: Int, offset: Int)

private struct HistoryPanelUX {
    static let WelcomeScreenPadding: CGFloat = 15
    static let WelcomeScreenItemTextColor = UIColor.gray
    static let WelcomeScreenItemWidth = 170
}

class HistoryPanel: SiteTableViewController, HomePanel {
    weak var homePanelDelegate: HomePanelDelegate? = nil
    fileprivate lazy var emptyStateOverlayView: UIView = self.createEmptyStateOverview()

    fileprivate let QueryLimit = 100
    fileprivate let NumSections = 4
    fileprivate let Today = getDate(dayOffset: 0)
    fileprivate let Yesterday = getDate(dayOffset: -1)
    fileprivate let ThisWeek = getDate(dayOffset: -7)

    // Category number (index) -> (UI section, row count, cursor offset).
    fileprivate var categories: [CategorySpec] = [CategorySpec]()

    // Reverse lookup from UI section to data category.
    fileprivate var sectionLookup = [SectionNumber: CategoryNumber]()

    var refreshControl: UIRefreshControl?

    init() {
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.defaultCenter().addObserver(self, selector: #selector(HistoryPanel.notificationReceived(_:)), name: NotificationFirefoxAccountChanged, object: nil)
        NotificationCenter.defaultCenter().addObserver(self, selector: #selector(HistoryPanel.notificationReceived(_:)), name: NotificationPrivateDataClearedHistory, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HistoryPanel.notificationReceived(_:)), name: NSNotification.Name(rawValue: NotificationDynamicFontChanged), object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.accessibilityIdentifier = "History List"
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.defaultCenter().removeObserver(self, name: NotificationFirefoxAccountChanged, object: nil)
        NotificationCenter.defaultCenter().removeObserver(self, name: NotificationPrivateDataClearedHistory, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NotificationDynamicFontChanged), object: nil)
    }

    func notificationReceived(_ notification: Notification) {
        switch notification.name {
        case NotificationDynamicFontChanged:
            if emptyStateOverlayView.superview != nil {
                emptyStateOverlayView.removeFromSuperview()
            }
            emptyStateOverlayView = createEmptyStateOverview()
            break
        default:
            // no need to do anything at all
            log.warning("Received unexpected notification \(notification.name)")
            break
        }
    }

    func addRefreshControl() {
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(HistoryPanel.refresh), for: UIControlEvents.valueChanged)
        self.refreshControl = refresh
        self.tableView.addSubview(refresh)
    }

    func removeRefreshControl() {
        self.refreshControl?.removeFromSuperview()
        self.refreshControl = nil
    }

    func endRefreshing() {
        // Always end refreshing, even if we failed!
        self.refreshControl?.endRefreshing()

    }


    /**
    * called by the table view pull to refresh
    **/
    @objc func refresh() {
        self.refreshControl?.beginRefreshing()
    }

    /**
    * fetch from the profile
    **/
    fileprivate func fetchData() -> Deferred<Maybe<Cursor<Site>>> {
        return profile.history.getSitesByLastVisit(QueryLimit)
    }

    fileprivate func setData(_ data: Cursor<Site>) {
        self.data = data
        self.computeSectionOffsets()
    }

    /**
    * Update our view after a data refresh
    **/
    override func reloadData() {
        self.fetchData().uponQueue(DispatchQueue.main) { result in
            if let data = result.successValue {
                self.setData(data)
                self.tableView.reloadData()
                self.updateEmptyPanelState()
            }

            self.endRefreshing()

            // TODO: error handling.
        }
    }

    fileprivate func updateEmptyPanelState() {
        if data.count == 0 {
            if self.emptyStateOverlayView.superview == nil {
                self.tableView.addSubview(self.emptyStateOverlayView)
                self.emptyStateOverlayView.snp_makeConstraints { make -> Void in
                    make.edges.equalTo(self.tableView)
                    make.size.equalTo(self.view)
                }
            }
        } else {
            self.emptyStateOverlayView.removeFromSuperview()
        }
    }

    fileprivate func createEmptyStateOverview() -> UIView {
        let overlayView = UIView()
        overlayView.backgroundColor = UIColor.white

        return overlayView
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        let category = self.categories[(indexPath as NSIndexPath).section]
        if let site = data[indexPath.row + category.offset] {
            if let cell = cell as? TwoLineTableViewCell {
                cell.setLines(site.title, detailText: site.url)
                if let siteId = site.id, let icon = iconForSiteId[siteId] {
                    cell.imageView?.setIcon(icon, withPlaceholder: FaviconFetcher.defaultFavicon)
                } else {
                    cell.imageView?.setIcon(nil, withPlaceholder: FaviconFetcher.defaultFavicon)

                    profile.favicons.getFavicon(forSite: site) >>== { cursor in
                        if cursor.count < 1 {
                            return
                        }
                        let favicons = cursor.asArray().flatMap{ $0 } // remove optionals
                        guard let best = getBestFavicon(favicons) else { return }
                        if let id = site.id {
                            self.iconForSiteId[id] = best
                        }
                        cell.imageView?.setIcon(best, withPlaceholder: FaviconFetcher.defaultFavicon)
                    }
                }
            }
        }


#if BRAVE
        cell.backgroundColor = UIColor.clearColor()
#endif
        return cell
    }

    fileprivate func siteForIndexPath(_ indexPath: NSIndexPath) -> Site? {
        let offset = self.categories[sectionLookup[indexPath.section]!].offset
        return data[indexPath.row + offset]
    }

    func tableView(_ tableView: UITableView, didSelectRowAtIndexPath indexPath: IndexPath) {
        if let site = self.siteForIndexPath(indexPath),
           let url = URL(string: site.url) {
            let visitType = VisitType.Typed    // Means History, too.
            homePanelDelegate?.homePanel(self, didSelectURL: url, visitType: visitType)
            return
        }
        log.warning("No site or no URL when selecting row.")
    }

    // Functions that deal with showing header rows.
    func numberOfSectionsInTableView(_ tableView: UITableView) -> Int {
        var count = 0
        for category in self.categories {
            if category.rows > 0 {
                count += 1
            }
        }
        return count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        var title = String()
        switch sectionLookup[section]! {
        case 0: title = NSLocalizedString("Today", comment: "History tableview section header")
        case 1: title = NSLocalizedString("Yesterday", comment: "History tableview section header")
        case 2: title = NSLocalizedString("Last week", comment: "History tableview section header")
        case 3: title = NSLocalizedString("Last month", comment: "History tableview section header")
        default:
            assertionFailure("Invalid history section \(section)")
        }
        return title
    }

    func categoryForDate(_ date: MicrosecondTimestamp) -> Int {
        let date = Double(date)
        if date > (1000000 * Today.timeIntervalSince1970) {
            return 0
        }
        if date > (1000000 * Yesterday.timeIntervalSince1970) {
            return 1
        }
        if date > (1000000 * ThisWeek.timeIntervalSince1970) {
            return 2
        }
        return 3
    }

    fileprivate func isInCategory(_ date: MicrosecondTimestamp, category: Int) -> Bool {
        return self.categoryForDate(date) == category
    }

    func computeSectionOffsets() {
        var counts = [Int](repeating: 0, count: NumSections)

        // Loop over all the data. Record the start of each "section" of our list.
        for i in 0..<data.count {
            if let site = data[i] {
                counts[categoryForDate(site.latestVisit!.date)] += 1
            }
        }

        var section = 0
        var offset = 0
        self.categories = [CategorySpec]()
        for i in 0..<NumSections {
            let count = counts[i]
            if count > 0 {
                log.debug("Category \(i) has \(count) rows, and thus is section \(section).")
                self.categories.append((section: section, rows: count, offset: offset))
                sectionLookup[section] = i
                offset += count
                section += 1
            } else {
                log.debug("Category \(i) has 0 rows, and thus has no section.")
                self.categories.append((section: nil, rows: 0, offset: offset))
            }
        }
    }

    // UI sections disappear as categories empty. We need to translate back and forth.
    fileprivate func uiSectionToCategory(_ section: SectionNumber) -> CategoryNumber {
        for i in 0..<self.categories.count {
            if let s = self.categories[i].section , s == section {
                return i
            }
        }
        return 0
    }

    fileprivate func categoryToUISection(_ category: CategoryNumber) -> SectionNumber? {
        return self.categories[category].section
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.categories[uiSectionToCategory(section)].rows
    }

    func tableView(_ tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: IndexPath) {
        // Intentionally blank. Required to use UITableViewRowActions
    }

    func tableView(_ tableView: UITableView, editActionsForRowAtIndexPath indexPath: IndexPath) -> [AnyObject]? {
        let title = NSLocalizedString("Remove", tableName: "HistoryPanel", comment: "Action button for deleting history entries in the history panel.")

        let delete = UITableViewRowAction(style: UITableViewRowActionStyle.default, title: title, handler: { (action, indexPath) in
            if let site = self.siteForIndexPath(indexPath) {
                // Why the dispatches? Because we call success and failure on the DB
                // queue, and so calling anything else that calls through to the DB will
                // deadlock. This problem will go away when the history API switches to
                // Deferred instead of using callbacks.
                self.profile.history.removeHistoryForURL(site.url)
                    .upon { res in
                        self.fetchData().uponQueue(DispatchQueue.main) { result in
                            // If a section will be empty after removal, we must remove the section itself.
                            if let data = result.successValue {

                                let oldCategories = self.categories
                                self.data = data
                                self.computeSectionOffsets()

                                let sectionsToDelete = NSMutableIndexSet()
                                var rowsToDelete = [NSIndexPath]()
                                let sectionsToAdd = NSMutableIndexSet()
                                var rowsToAdd = [NSIndexPath]()

                                for (index, category) in self.categories.enumerate() {
                                    let oldCategory = oldCategories[index]

                                    // don't bother if we're not displaying this category
                                    if oldCategory.section == nil && category.section == nil {
                                        continue
                                    }

                                    // 1. add a new section if the section didn't previously exist
                                    if oldCategory.section == nil && category.section != oldCategory.section {
                                        log.debug("adding section \(category.section)")
                                        sectionsToAdd.addIndex(category.section!)
                                    }

                                    // 2. add a new row if there are more rows now than there were before
                                    if oldCategory.rows < category.rows {
                                        log.debug("adding row to \(category.section) at \(category.rows-1)")
                                        rowsToAdd.append(NSIndexPath(forRow: category.rows-1, inSection: category.section!))
                                    }

                                    // if we're dealing with the section where the row was deleted:
                                    // 1. if the category no longer has a section, then we need to delete the entire section
                                    // 2. delete a row if the number of rows has been reduced
                                    // 3. delete the selected row and add a new one on the bottom of the section if the number of rows has stayed the same
                                    if oldCategory.section == indexPath.section {
                                        if category.section == nil {
                                            log.debug("deleting section \(indexPath.section)")
                                            sectionsToDelete.addIndex(indexPath.section)
                                        } else if oldCategory.section == category.section {
                                            if oldCategory.rows > category.rows {
                                                log.debug("deleting row from \(category.section) at \(indexPath.row)")
                                                rowsToDelete.append(indexPath)
                                            } else if category.rows == oldCategory.rows {
                                                log.debug("in section \(category.section), removing row at \(indexPath.row) and inserting row at \(category.rows-1)")
                                                rowsToDelete.append(indexPath)
                                                rowsToAdd.append(NSIndexPath(forRow: category.rows-1, inSection: indexPath.section))
                                            }
                                        }
                                    }
                                }

                                tableView.beginUpdates()
                                if sectionsToAdd.count > 0 {
                                    tableView.insertSections(sectionsToAdd, withRowAnimation: UITableViewRowAnimation.Left)
                                }
                                if sectionsToDelete.count > 0 {
                                    tableView.deleteSections(sectionsToDelete, withRowAnimation: UITableViewRowAnimation.Right)
                                }
                                if !rowsToDelete.isEmpty {
                                    tableView.deleteRowsAtIndexPaths(rowsToDelete, withRowAnimation: UITableViewRowAnimation.Right)
                                }

                                if !rowsToAdd.isEmpty {
                                    tableView.insertRowsAtIndexPaths(rowsToAdd, withRowAnimation: UITableViewRowAnimation.Right)
                                }

                                tableView.endUpdates()
                                self.updateEmptyPanelState()
                            }
                        }
                }
            }
        })
        return [delete]
    }
}
