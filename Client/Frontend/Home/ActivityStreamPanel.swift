/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import UIKit
import Deferred
import Storage
import WebImage
import XCGLogger
import Telemetry

private let log = Logger.browserLogger
private let DefaultSuggestedSitesKey = "topSites.deletedSuggestedSites"

// MARK: -  Lifecycle
struct ASPanelUX {
    static let backgroundColor = UIColor(white: 1.0, alpha: 0.5)
    static let historySize = 10
    static let rowSpacing: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 30 : 20
    static let highlightCellHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 250 : 195

    static let PageControlOffsetSize: CGFloat = 40
    static let SectionInsetsForIpad: CGFloat = 101
    static let SectionInsetsForIphone: CGFloat = 14
    static let CompactWidth: CGFloat = 320
}

class ActivityStreamPanel: UICollectionViewController, HomePanel {
    weak var homePanelDelegate: HomePanelDelegate?
    fileprivate let profile: Profile
    fileprivate let telemetry: ActivityStreamTracker
    fileprivate let flowLayout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()

    fileprivate let topSitesManager = ASHorizontalScrollCellManager()
    fileprivate var pendingCacheUpdate = false
    fileprivate var showHighlightIntro = false
    fileprivate var sessionStart: Timestamp?

    fileprivate lazy var longPressRecognizer: UILongPressGestureRecognizer = {
        return UILongPressGestureRecognizer(target: self, action: #selector(ActivityStreamPanel.longPress(_:)))
    }()

    // Not used for displaying. Only used for calculating layout.
    lazy var topSiteCell: ASHorizontalScrollCell = {
        let customCell = ASHorizontalScrollCell(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 0))
        customCell.delegate = self.topSitesManager
        return customCell
    }()

    var highlights: [Site] = []

    init(profile: Profile, telemetry: ActivityStreamTracker? = nil) {
        self.profile = profile
        self.telemetry = telemetry ?? ActivityStreamTracker(eventsTracker: PingCentre.clientForTopic(.ActivityStreamEvents, clientID: profile.clientID), sessionsTracker: PingCentre.clientForTopic(.ActivityStreamSessions, clientID: profile.clientID))

        super.init(collectionViewLayout: flowLayout)
        self.collectionView?.delegate = self
        self.collectionView?.dataSource = self

        collectionView?.addGestureRecognizer(longPressRecognizer)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didChangeFontSize(notification:)),
                                               name: NotificationDynamicFontChanged,
                                               object: nil)
        
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NotificationDynamicFontChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        Section.allValues.forEach { self.collectionView?.register(Section($0.rawValue).cellType, forCellWithReuseIdentifier: Section($0.rawValue).cellIdentifier) }
        self.collectionView?.register(ASHeaderView.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: "Header")
        self.collectionView?.register(ASFooterView.self, forSupplementaryViewOfKind: UICollectionElementKindSectionFooter, withReuseIdentifier: "Footer")
        collectionView?.backgroundColor = ASPanelUX.backgroundColor
        collectionView?.keyboardDismissMode = .onDrag
        
        self.profile.panelDataObservers.activityStream.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionStart = Date.now()
        reloadAll()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        telemetry.reportSessionStop(Date.now() - (sessionStart ?? 0))
        sessionStart = nil
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: {context in
            self.presentedViewController?.dismiss(animated: true, completion: nil)
            self.collectionViewLayout.invalidateLayout()
            self.collectionView?.reloadData()
        }, completion: nil)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.topSitesManager.currentTraits = self.traitCollection
    }

    func didChangeFontSize(notification: Notification) {
        // Don't need to invalidate the data for a font change. Just reload the UI.
        reloadAll()
    }
}

// MARK: -  Section management
extension ActivityStreamPanel {

    enum Section: Int {
        case topSites
        case highlights
        case highlightIntro

        static let count = 3
        static let allValues = [topSites, highlights, highlightIntro]

        var title: String? {
            switch self {
            case .highlights: return Strings.ASHighlightsTitle
            case .topSites: return nil
            case .highlightIntro: return nil
            }
        }

        var headerHeight: CGSize {
            switch self {
            case .highlights: return CGSize(width: 50, height: 40)
            case .topSites: return CGSize(width: 0, height: 0)
            case .highlightIntro: return CGSize(width: 50, height: 2)
            }
        }

        var footerHeight: CGSize {
            switch self {
            case .highlights, .highlightIntro: return CGSize.zero
            case .topSites: return CGSize(width: 50, height: 5)
            }
        }

        func cellHeight(_ traits: UITraitCollection, width: CGFloat) -> CGFloat {
            switch self {
            case .highlights: return ASPanelUX.highlightCellHeight
            case .topSites: return 0 //calculated dynamically
            case .highlightIntro: return 200
            }
        }

        func sectionInsets() -> CGFloat {
            switch self {
            case .highlights:
                return UIDevice.current.userInterfaceIdiom == .pad ? ASPanelUX.SectionInsetsForIpad + ASHorizontalScrollCellUX.MinimumInsets : ASPanelUX.SectionInsetsForIphone
            case .topSites:
                return UIDevice.current.userInterfaceIdiom == .pad ? ASPanelUX.SectionInsetsForIpad : 0
            case .highlightIntro:
                return UIDevice.current.userInterfaceIdiom == .pad ? ASPanelUX.SectionInsetsForIpad : 0
            }
        }

        func numberOfItemsForRow() -> CGFloat {
            switch self {
            case .highlights:
                var numItems: CGFloat = 0
                if UIDevice.current.orientation == .landscapeLeft || UIDevice.current.orientation == .landscapeRight {
                    numItems = 4
                } else if UIDevice.current.userInterfaceIdiom == .pad {
                    numItems = 3
                } else {
                    numItems = 2
                }
                return numItems
            case .topSites:
                return 1
            case .highlightIntro:
                return 1
            }
        }

        func cellSize(for traits: UITraitCollection, frameWidth: CGFloat) -> CGSize {
            let height = cellHeight(traits, width: frameWidth)
            let inset = sectionInsets() * 2

            switch self {
            case .highlights:
                let numItems = numberOfItemsForRow()
                return CGSize(width: floor(((frameWidth - inset) - (ASHorizontalScrollCellUX.MinimumInsets * (numItems - 1))) / numItems), height: height)
            case .topSites:
                return CGSize(width: frameWidth - inset, height: height)
            case .highlightIntro:
                return CGSize(width: frameWidth - inset - (ASHorizontalScrollCellUX.MinimumInsets * 2), height: height)
            }
        }

        var headerView: UIView? {
            switch self {
            case .highlights:
                let view = ASHeaderView()
                view.title = title
                return view
            case .topSites:
                return nil
            case .highlightIntro:
                let view = ASHeaderView()
                view.title = title
                return view
            }
        }

        var cellIdentifier: String {
            switch self {
            case .topSites: return "TopSiteCell"
            case .highlights: return "HistoryCell"
            case .highlightIntro: return "HighlightIntroCell"
            }
        }

        var cellType: UICollectionViewCell.Type {
            switch self {
            case .topSites: return ASHorizontalScrollCell.self
            case .highlights: return ActivityStreamHighlightCell.self
            case .highlightIntro: return HighlightIntroCell.self
            }
        }

        init(at indexPath: IndexPath) {
            self.init(rawValue: indexPath.section)!
        }

        init(_ section: Int) {
            self.init(rawValue: section)!
        }
    }
}

// MARK: -  Tableview Delegate
extension ActivityStreamPanel: UICollectionViewDelegateFlowLayout {

    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        switch kind {
            case UICollectionElementKindSectionHeader:
                let view = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionElementKindSectionHeader, withReuseIdentifier: "Header", for: indexPath) as! ASHeaderView
                let title = Section(indexPath.section).title
                switch Section(indexPath.section) {
                case .highlights, .highlightIntro:
                    view.title = title
                    return view
                case .topSites:
                    return UICollectionReusableView()
            }
            case UICollectionElementKindSectionFooter:
                let view = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionElementKindSectionFooter, withReuseIdentifier: "Footer", for: indexPath) as! ASFooterView
                switch Section(indexPath.section) {
                case .highlights, .highlightIntro:
                    return UICollectionReusableView()
                case .topSites:
                    return view
            }
            default:
                return UICollectionReusableView()
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        self.longPressRecognizer.isEnabled = false
        selectItemAtIndex(indexPath.item, inSection: Section(indexPath.section))
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let cellSize = Section(indexPath.section).cellSize(for: self.traitCollection, frameWidth: self.view.frame.width)

        switch Section(indexPath.section) {
        case .highlights:
            if highlights.isEmpty {
                return CGSize.zero
            }
            return cellSize
        case .topSites:
            // Create a temporary cell so we can calculate the height.
            let layout = topSiteCell.collectionView.collectionViewLayout as! HorizontalFlowLayout
            let estimatedLayout = layout.calculateLayout(for: CGSize(width: cellSize.width, height: 0))
            return CGSize(width: cellSize.width, height: estimatedLayout.size.height)
        case .highlightIntro:
            return cellSize
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        switch Section(section) {
        case .highlights:
            return highlights.isEmpty ? CGSize.zero : Section(section).headerHeight
        case .highlightIntro:
            return !highlights.isEmpty ? CGSize.zero : Section(section).headerHeight
        case .topSites:
            return Section(section).headerHeight
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        switch Section(section) {
        case .highlights, .highlightIntro:
            return CGSize.zero
        case .topSites:
            return Section(section).footerHeight
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return ASPanelUX.rowSpacing
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let insets = Section(section).sectionInsets()
        return UIEdgeInsets(top: 0, left: insets, bottom: 0, right: insets)
    }

    fileprivate func showSiteWithURLHandler(_ url: URL) {
        let visitType = VisitType.bookmark
        homePanelDelegate?.homePanel(self, didSelectURL: url, visitType: visitType)
    }
}

// MARK: - Tableview Data Source
extension ActivityStreamPanel {

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 3
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch Section(section) {
        case .topSites:
            return topSitesManager.content.isEmpty ? 0 : 1
        case .highlights:
            return self.highlights.count
        case .highlightIntro:
            return self.highlights.isEmpty && showHighlightIntro ? 1 : 0
        }
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let identifier = Section(indexPath.section).cellIdentifier
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath)

        switch Section(indexPath.section) {
        case .topSites:
            return configureTopSitesCell(cell, forIndexPath: indexPath)
        case .highlights:
            return configureHistoryItemCell(cell, forIndexPath: indexPath)
        case .highlightIntro:
            return configureHighlightIntroCell(cell, forIndexPath: indexPath)
        }
    }

    //should all be collectionview
    func configureTopSitesCell(_ cell: UICollectionViewCell, forIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        let topSiteCell = cell as! ASHorizontalScrollCell
        topSiteCell.delegate = self.topSitesManager
        topSiteCell.setNeedsLayout()
        topSiteCell.collectionView.reloadData()
        return cell
    }

    func configureHistoryItemCell(_ cell: UICollectionViewCell, forIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        let site = highlights[indexPath.row]
        let simpleHighlightCell = cell as! ActivityStreamHighlightCell
        simpleHighlightCell.configureWithSite(site)
        return simpleHighlightCell
    }

    func configureHighlightIntroCell(_ cell: UICollectionViewCell, forIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        let introCell = cell as! HighlightIntroCell
        //The cell is configured on creation. No need to configure. But leave this here in case we need it.
        return introCell
    }
}

// MARK: - Data Management
extension ActivityStreamPanel: DataObserverDelegate {
    fileprivate func reportMissingData(sites: [Site], source: ASPingSource) {
        let missingImagePings: [[String: Any]] = sites.flatMap { site in
            if site.metadata?.mediaURL == nil {
                return self.telemetry.pingFor(badState: .MissingMetadataImage, source: source)
            }
            return nil
        }

        let missingFaviconPings: [[String: Any]] = sites.flatMap { site in
            if site.icon == nil {
                return self.telemetry.pingFor(badState: .MissingFavicon, source: source)
            }
            return nil
        }

        let badPings = missingImagePings + missingFaviconPings
        self.telemetry.eventsTracker.sendBatch(badPings, validate: true)
    }

    // Reloads both highlights and top sites data from their respective caches. Does not invalidate the cache.
    // See ActivityStreamDataObserver for invalidation logic.
    func reloadAll() {
        accumulate([self.getHighlights, self.getTopSites]).uponQueue(.main) { _ in
            // If there is no pending cache update and highlights are empty. Show the onboarding screen
            self.showHighlightIntro = self.highlights.isEmpty && !self.pendingCacheUpdate
            self.collectionView?.reloadData()
        }
    }

    func getHighlights() -> Success {
        let num = Int(Section.highlights.numberOfItemsForRow())
        return self.profile.recommendations.getHighlights().both(self.profile.recommendations.getRecentBookmarks(num)).bindQueue(.main) { (highlights, bookmarks) in
            guard let highlights = highlights.successValue?.asArray(), let bookmarks = bookmarks.successValue?.asArray() else {
                return succeed()
            }
            let sites = bookmarks + highlights
            // Scan through the fetched highlights and report on anything that might be missing.
            self.reportMissingData(sites: sites, source: .Highlights)
            self.highlights = sites
            return succeed()
        }
    }

    func getTopSites() -> Success {
        return self.profile.history.getTopSitesWithLimit(16).both(self.profile.history.getPinnedTopSites()).bindQueue(.main) { (topsites, pinnedSites) in
            guard let mySites = topsites.successValue?.asArray(), let pinnedSites = pinnedSites.successValue?.asArray(), !self.pendingCacheUpdate else {
                return succeed()
            }

            let usersSites = pinnedSites.map({ PinnedSite(site:$0) }) + mySites
            let defaultSites = self.defaultTopSites()

            // Merge default topsites with a user's topsites.
            let mergedSites = usersSites.union(defaultSites, f: { (site) -> String in
                return URL(string: site.url)?.hostSLD ?? ""
            })

            // Favour topsites from defaultSites as they have better favicons.
            let newSites = mergedSites.map { site -> Site in
                let domain = URL(string: site.url)?.hostSLD
                return defaultSites.find { $0.title.lowercased() == domain } ?? site
            }

            // Don't report bad states for default sites we provide
            self.reportMissingData(sites: usersSites, source: .TopSites)

            self.topSitesManager.currentTraits = self.view.traitCollection

            if newSites.count > Int(ActivityStreamTopSiteCacheSize) {
                self.topSitesManager.content = Array(newSites[0..<Int(ActivityStreamTopSiteCacheSize)])
            } else {
                self.topSitesManager.content = newSites
            }

            self.topSitesManager.urlPressedHandler = { [unowned self] url, indexPath in
                self.longPressRecognizer.isEnabled = false
                self.telemetry.reportEvent(.Click, source: .TopSites, position: indexPath.item)
                self.showSiteWithURLHandler(url as URL)
            }

            return succeed()
        }
    }

    func willInvalidateDataSources() {
        self.pendingCacheUpdate = true
    }

    // Invoked by the ActivityStreamDataObserver when highlights/top sites invalidation is complete.
    func didInvalidateDataSources() {
        self.pendingCacheUpdate = false
        reloadAll()
    }

    func hideURLFromTopSites(_ site: Site) {
        guard let host = site.tileURL.normalizedHost else {
            return
        }
        let url = site.tileURL.absoluteString
        // if the default top sites contains the siteurl. also wipe it from default suggested sites.
        if defaultTopSites().filter({$0.url == url}).isEmpty == false {
            deleteTileForSuggestedSite(url)
        }
        profile.history.removeHostFromTopSites(host).uponQueue(.main) { result in
            guard result.isSuccess else { return }
            self.profile.panelDataObservers.activityStream.invalidate(highlights: false)
        }
    }

    func pinTopSite(_ site: Site) {
        profile.history.addPinnedTopSite(site).uponQueue(.main) { result in
            guard result.isSuccess else { return }
            self.profile.panelDataObservers.activityStream.invalidate(highlights: false)
        }
    }

    func removePinTopSite(_ site: Site) {
        profile.history.removeFromPinnedTopSites(site).uponQueue(.main) { result in
            guard result.isSuccess else { return }
            self.profile.panelDataObservers.activityStream.invalidate(highlights: false)
        }
    }

    func hideFromHighlights(_ site: Site) {
        profile.recommendations.removeHighlightForURL(site.url).uponQueue(.main) { result in
            guard result.isSuccess else { return }
            self.profile.panelDataObservers.activityStream.invalidate(highlights: true)
        }
    }

    fileprivate func deleteTileForSuggestedSite(_ siteURL: String) {
        var deletedSuggestedSites = profile.prefs.arrayForKey(DefaultSuggestedSitesKey) as? [String] ?? []
        deletedSuggestedSites.append(siteURL)
        profile.prefs.setObject(deletedSuggestedSites, forKey: DefaultSuggestedSitesKey)
    }

    func defaultTopSites() -> [Site] {
        let suggested = SuggestedSites.asArray()
        let deleted = profile.prefs.arrayForKey(DefaultSuggestedSitesKey) as? [String] ?? []
        return suggested.filter({deleted.index(of: $0.url) == .none})
    }

    @objc fileprivate func longPress(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        guard longPressGestureRecognizer.state == UIGestureRecognizerState.began else { return }

        let point = longPressGestureRecognizer.location(in: self.collectionView)
        guard let indexPath = self.collectionView?.indexPathForItem(at: point) else { return }

        switch Section(indexPath.section) {
        case .highlights:
            presentContextMenu(for: indexPath)
        case .topSites:
            let topSiteCell = self.collectionView?.cellForItem(at: indexPath) as! ASHorizontalScrollCell
            let pointInTopSite = longPressGestureRecognizer.location(in: topSiteCell.collectionView)
            guard let topSiteIndexPath = topSiteCell.collectionView.indexPathForItem(at: pointInTopSite) else { return }
            presentContextMenu(for: topSiteIndexPath)
        case .highlightIntro:
            break
        }
    }

    fileprivate func fetchBookmarkStatusThenPresentContextMenu(for site: Site, with indexPath: IndexPath, forSection section: Section, completionHandler: @escaping () -> ActionOverlayTableViewController?) {
        profile.bookmarks.modelFactory >>== {
            $0.isBookmarked(site.url).uponQueue(.main) { result in
                guard let isBookmarked = result.successValue else {
                    log.error("Error getting bookmark status: \(result.failureValue ??? "nil").")
                    return
                }
                site.setBookmarked(isBookmarked)
                self.presentContextMenu(for: site, with: indexPath, completionHandler: completionHandler)
            }
        }
    }

    func selectItemAtIndex(_ index: Int, inSection section: Section) {
        let site: Site?
        switch section {
        case .highlights:
            site = self.highlights[index]
        case .topSites, .highlightIntro:
            return
        }
        if let site = site {
            telemetry.reportEvent(.Click, source: .Highlights, position: index)
            showSiteWithURLHandler(URL(string:site.url)!)
        }
    }
}

extension ActivityStreamPanel: HomePanelContextMenu {
    func presentContextMenu(for site: Site, with indexPath: IndexPath, completionHandler: @escaping () -> ActionOverlayTableViewController?) {
        guard let _ = site.bookmarked else {
            fetchBookmarkStatusThenPresentContextMenu(for: site, with: indexPath, forSection: Section(indexPath.section), completionHandler: completionHandler)
            return
        }
        guard let contextMenu = completionHandler() else { return }
        self.present(contextMenu, animated: true, completion: nil)
    }

    func getSiteDetails(for indexPath: IndexPath) -> Site? {
        let site: Site

        switch Section(indexPath.section) {
        case .highlights:
            site = highlights[indexPath.row]
        case .topSites:
            site = topSitesManager.content[indexPath.item]
        case .highlightIntro:
            return nil
        }

        return site
    }

    func getContextMenuActions(for site: Site, with indexPath: IndexPath) -> [ActionOverlayTableViewAction]? {
        guard let siteURL = URL(string: site.url) else { return nil }

        let pingSource: ASPingSource
        let index: Int
        var sourceView: UIView?
        
        switch Section(indexPath.section) {
        case .topSites:
            pingSource = .TopSites
            index = indexPath.item
            if let topSiteCell = self.collectionView?.cellForItem(at: IndexPath(row: 0, section: 0)) as? ASHorizontalScrollCell {
                sourceView = topSiteCell.collectionView.cellForItem(at: indexPath)
            }
        case .highlights:
            pingSource = .Highlights
            index = indexPath.row
            sourceView = self.collectionView?.cellForItem(at: indexPath)
        case .highlightIntro:
            return nil
        }

        let openInNewTabAction = ActionOverlayTableViewAction(title: Strings.OpenInNewTabContextMenuTitle, iconString: "") { action in
            self.homePanelDelegate?.homePanelDidRequestToOpenInNewTab(siteURL, isPrivate: false)
            self.telemetry.reportEvent(.NewTab, source: pingSource, position: index)
            LeanplumIntegration.sharedInstance.track(eventName: .openedNewTab, withParameters: ["Source":"Activity Stream Long Press Context Menu" as AnyObject])
        }

        let openInNewPrivateTabAction = ActionOverlayTableViewAction(title: Strings.OpenInNewPrivateTabContextMenuTitle, iconString: "") { action in
            self.homePanelDelegate?.homePanelDidRequestToOpenInNewTab(siteURL, isPrivate: true)
        }
        
        let bookmarkAction: ActionOverlayTableViewAction
        if site.bookmarked ?? false {
            bookmarkAction = ActionOverlayTableViewAction(title: Strings.RemoveBookmarkContextMenuTitle, iconString: "action_bookmark_remove", handler: { action in
                self.profile.bookmarks.modelFactory >>== {
                    $0.removeByURL(siteURL.absoluteString)
                    site.setBookmarked(false)
                }
                self.profile.panelDataObservers.activityStream.invalidate(highlights: false)
                self.telemetry.reportEvent(.RemoveBookmark, source: pingSource, position: index)

            })
        } else {
            bookmarkAction = ActionOverlayTableViewAction(title: Strings.BookmarkContextMenuTitle, iconString: "action_bookmark", handler: { action in
                let shareItem = ShareItem(url: site.url, title: site.title, favicon: site.icon)
                self.profile.bookmarks.shareItem(shareItem)
                var userData = [QuickActions.TabURLKey: shareItem.url]
                if let title = shareItem.title {
                    userData[QuickActions.TabTitleKey] = title
                }
                QuickActions.sharedInstance.addDynamicApplicationShortcutItemOfType(.openLastBookmark,
                                                                                    withUserData: userData,
                                                                                    toApplication: UIApplication.shared)
                site.setBookmarked(true)
                self.telemetry.reportEvent(.AddBookmark, source: pingSource, position: index)
            })
        }

        let deleteFromHistoryAction = ActionOverlayTableViewAction(title: Strings.DeleteFromHistoryContextMenuTitle, iconString: "action_delete", handler: { action in
            self.telemetry.reportEvent(.Delete, source: pingSource, position: index)
            self.profile.history.removeHistoryForURL(site.url).uponQueue(.main) { result in
                guard result.isSuccess else { return }
                self.profile.panelDataObservers.activityStream.invalidate(highlights: true)
            }
        })

        let shareAction = ActionOverlayTableViewAction(title: Strings.ShareContextMenuTitle, iconString: "action_share", handler: { action in
            let helper = ShareExtensionHelper(url: siteURL, tab: nil, activities: [])
            let controller = helper.createActivityViewController { completed, activityType in
                self.telemetry.reportEvent(.Share, source: pingSource, position: index, shareProvider: activityType)
            }
            if UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.pad, let popoverController = controller.popoverPresentationController {
                let cellRect = sourceView?.frame ?? CGRect.zero
                let cellFrameInSuperview = self.collectionView?.convert(cellRect, to: self.collectionView) ?? CGRect.zero

                popoverController.sourceView = sourceView
                popoverController.sourceRect = CGRect(origin: CGPoint(x: cellFrameInSuperview.size.width/2, y: cellFrameInSuperview.height/2), size: .zero)
                popoverController.permittedArrowDirections = [.up, .down, .left]
                popoverController.delegate = self
            }
            self.present(controller, animated: true, completion: nil)
        })

        let removeTopSiteAction = ActionOverlayTableViewAction(title: Strings.RemoveContextMenuTitle, iconString: "action_remove", handler: { action in
            self.telemetry.reportEvent(.Remove, source: pingSource, position: index)
            self.hideURLFromTopSites(site)
        })

        let dismissHighlightAction = ActionOverlayTableViewAction(title: Strings.RemoveContextMenuTitle, iconString: "action_remove", handler: { action in
            self.telemetry.reportEvent(.Dismiss, source: pingSource, position: index)
            self.hideFromHighlights(site)
        })

        let pinTopSite = ActionOverlayTableViewAction(title: Strings.PinTopsiteActionTitle, iconString: "action_pin", handler: { action in
            self.pinTopSite(site)
        })

        let removePinTopSite = ActionOverlayTableViewAction(title: Strings.RemovePinTopsiteActionTitle, iconString: "action_unpin", handler: { action in
            self.removePinTopSite(site)
        })

        let topSiteActions: [ActionOverlayTableViewAction]
        if let _ = site as? PinnedSite {
            topSiteActions = [removePinTopSite]
        } else {
            topSiteActions = [pinTopSite, removeTopSiteAction]
        }

        var actions = [openInNewTabAction, openInNewPrivateTabAction, bookmarkAction, shareAction]

        switch Section(indexPath.section) {
            case .highlights: actions.append(contentsOf: [dismissHighlightAction, deleteFromHistoryAction])
            case .topSites: actions.append(contentsOf: topSiteActions)
            case .highlightIntro: break
        }
        return actions
    }
}

extension ActivityStreamPanel: UIPopoverPresentationControllerDelegate {

    // Dismiss the popover if the device is being rotated.
    // This is used by the Share UIActivityViewController action sheet on iPad
    func popoverPresentationController(_ popoverPresentationController: UIPopoverPresentationController, willRepositionPopoverTo rect: UnsafeMutablePointer<CGRect>, in view: AutoreleasingUnsafeMutablePointer<UIView>) {
        popoverPresentationController.presentedViewController.dismiss(animated: false, completion: nil)
    }
}

// MARK: Telemetry

enum ASPingEvent: String {
    case Click = "CLICK"
    case Delete = "DELETE"
    case Dismiss = "DISMISS"
    case Share = "SHARE"
    case NewTab = "NEW_TAB"
    case AddBookmark = "ADD_BOOKMARK"
    case RemoveBookmark = "REMOVE_BOOKMARK"
    case Remove = "REMOVE"
}

enum ASPingBadStateEvent: String {
    case MissingMetadataImage = "MISSING_METADATA_IMAGE"
    case MissingFavicon = "MISSING_FAVICON"
}

enum ASPingSource: String {
    case Highlights = "HIGHLIGHTS"
    case TopSites = "TOP_SITES"
    case HighlightsIntro = "HIGHLIGHTS_INTRO"
}

struct ActivityStreamTracker {
    let eventsTracker: PingCentreClient
    let sessionsTracker: PingCentreClient

    private var baseASPing: [String: Any] {
        return [
            "app_version": AppInfo.appVersion,
            "build": AppInfo.buildNumber,
            "locale": Locale.current.identifier,
            "release_channel": AppConstants.BuildChannel.rawValue
        ]
    }

    func pingFor(badState: ASPingBadStateEvent, source: ASPingSource) -> [String: Any] {
        var eventPing: [String: Any] = [
            "event": badState.rawValue,
            "page": "NEW_TAB",
            "source": source.rawValue,
        ]
        eventPing.merge(with: baseASPing)
        return eventPing
    }

    func reportEvent(_ event: ASPingEvent, source: ASPingSource, position: Int, shareProvider: String? = nil) {
        var eventPing: [String: Any] = [
            "event": event.rawValue,
            "page": "NEW_TAB",
            "source": source.rawValue,
            "action_position": position,
        ]

        if let provider = shareProvider {
            eventPing["share_provider"] = provider
        }

        eventPing.merge(with: baseASPing)
        eventsTracker.sendPing(eventPing as [String : AnyObject], validate: true)
    }

    func reportSessionStop(_ duration: UInt64) {
        sessionsTracker.sendPing([
            "session_duration": NSNumber(value: duration),
            "app_version": AppInfo.appVersion,
            "build": AppInfo.buildNumber,
            "locale": Locale.current.identifier,
            "release_channel": AppConstants.BuildChannel.rawValue
            ] as [String: Any], validate: true)
    }
}

// MARK: - Section Header View
struct ASHeaderViewUX {
    static let SeperatorColor =  UIColor(rgb: 0xedecea)
    static let TextFont = DynamicFontHelper.defaultHelper.DefaultMediumBoldFont
    static let SeperatorHeight = 1
    static let Insets: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? ASPanelUX.SectionInsetsForIpad : ASPanelUX.SectionInsetsForIphone
    static let TitleTopInset: CGFloat = 5
}

class ASFooterView: UICollectionReusableView {

    override init(frame: CGRect) {
        super.init(frame: frame)

        let seperatorLine = UIView()
        seperatorLine.backgroundColor = ASHeaderViewUX.SeperatorColor
        self.backgroundColor = UIColor.clear
        addSubview(seperatorLine)
        seperatorLine.snp.makeConstraints { make in
            make.height.equalTo(ASHeaderViewUX.SeperatorHeight)
            make.leading.equalTo(self.snp.leading)
            make.trailing.equalTo(self.snp.trailing)
            make.top.equalTo(self.snp.top)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class ASHeaderView: UICollectionReusableView {
    lazy fileprivate var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.text = self.title
        titleLabel.textColor = UIColor.gray
        titleLabel.font = ASHeaderViewUX.TextFont
        return titleLabel
    }()

    var title: String? {
        willSet(newTitle) {
            titleLabel.text = newTitle
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(titleLabel)
        let leftInset = UIDevice.current.userInterfaceIdiom == .pad ? ASHorizontalScrollCellUX.MinimumInsets : 0
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(self).inset(ASHeaderViewUX.Insets + leftInset)
            make.trailing.equalTo(self).inset(-ASHeaderViewUX.Insets)
            make.top.equalTo(self).inset(ASHeaderViewUX.TitleTopInset)
            make.bottom.equalTo(self)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

open class PinnedSite: Site {
    let isPinnedSite = true

    init(site: Site) {
        super.init(url: site.url, title: site.title, bookmarked: site.bookmarked)
        self.icon = site.icon
        self.metadata = site.metadata
    }

}
