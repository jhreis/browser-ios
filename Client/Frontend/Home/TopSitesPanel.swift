/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import XCGLogger
import Storage
import WebImage
import Deferred

private let log = Logger.browserLogger

private let ThumbnailIdentifier = "Thumbnail"

extension CGSize {
    public func widthLargerOrEqualThanHalfIPad() -> Bool {
        let halfIPadSize: CGFloat = 507
        return width >= halfIPadSize
    }
}

struct TopSitesPanelUX {
    fileprivate static let EmptyStateTitleTextColor = UIColor.darkGray
    fileprivate static let EmptyStateTopPaddingInBetweenItems: CGFloat = 15
    fileprivate static let WelcomeScreenPadding: CGFloat = 15
    fileprivate static let WelcomeScreenItemTextColor = UIColor.gray
    fileprivate static let WelcomeScreenItemWidth = 170
}

class TopSitesPanel: UIViewController {
    weak var homePanelDelegate: HomePanelDelegate?
    fileprivate lazy var emptyStateOverlayView: UIView = self.createEmptyStateOverlayView()
    fileprivate var collection: TopSitesCollectionView? = nil
    fileprivate lazy var dataSource: TopSitesDataSource = {
        return TopSitesDataSource(profile: self.profile)
    }()
    fileprivate lazy var layout: TopSitesLayout = { return TopSitesLayout() }()

    fileprivate lazy var maxFrecencyLimit: Int = {
        return max(
            self.calculateApproxThumbnailCountForOrientation(UIInterfaceOrientation.landscapeLeft),
            self.calculateApproxThumbnailCountForOrientation(UIInterfaceOrientation.portrait)
        )
    }()

    var editingThumbnails: Bool = false {
        didSet {
            if editingThumbnails != oldValue {
                dataSource.editingThumbnails = editingThumbnails

                if editingThumbnails {
                    homePanelDelegate?.homePanelWillEnterEditingMode?(self)
                }

                updateAllRemoveButtonStates()
            }
        }
    }

    let profile: Profile

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { context in
            self.collection?.reloadData()
        }, completion: nil)
    }

    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.allButUpsideDown
    }

    init(profile: Profile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationFirefoxAccountChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NSNotification.Name(rawValue: NotificationProfileDidFinishSyncing), object: nil)
        NotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationPrivateDataClearedHistory, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NSNotification.Name(rawValue: NotificationDynamicFontChanged), object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let collection = TopSitesCollectionView(frame: self.view.frame, collectionViewLayout: layout)
        collection.backgroundColor = BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
        collection.delegate = self
        collection.dataSource = dataSource
        collection.register(ThumbnailCell.self, forCellWithReuseIdentifier: ThumbnailIdentifier)
        collection.keyboardDismissMode = .onDrag
        collection.accessibilityIdentifier = "Top Sites View"
        view.addSubview(collection)
        collection.snp_makeConstraints { make in
            make.edges.equalTo(self.view)
        }
        self.collection = collection

        self.dataSource.collectionView = self.collection
        succeed().upon { _ in // move sync call off-main
            self.profile.history.setTopSitesCacheSize(Int32(self.maxFrecencyLimit))
            postAsyncToMain(0) { // back to main
                self.refreshTopSites(self.maxFrecencyLimit)
                self.updateEmptyPanelState()
            }
        }
    }

    deinit {
        NotificationCenter.defaultCenter().removeObserver(self, name: NotificationFirefoxAccountChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NotificationProfileDidFinishSyncing), object: nil)
        NotificationCenter.defaultCenter().removeObserver(self, name: NotificationPrivateDataClearedHistory, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NotificationDynamicFontChanged), object: nil)
    }

    func notificationReceived(_ notification: Notification) {
        switch notification.name {
        case NotificationFirefoxAccountChanged, NotificationProfileDidFinishSyncing, NotificationPrivateDataClearedHistory, NotificationDynamicFontChanged:
            refreshTopSites(maxFrecencyLimit)
            break
        default:
            // no need to do anything at all
            log.warning("Received unexpected notification \(notification.name)")
            break
        }
    }

    fileprivate func createEmptyStateOverlayView() -> UIView {
        let overlayView = UIView()
        overlayView.backgroundColor = UIColor.white

        let descriptionLabel = UILabel()
        descriptionLabel.text = Strings.TopSitesEmptyStateDescription
        descriptionLabel.textAlignment = NSTextAlignment.center
        descriptionLabel.font = DynamicFontHelper.defaultHelper.DeviceFontLight
        descriptionLabel.textColor = TopSitesPanelUX.WelcomeScreenItemTextColor
        descriptionLabel.numberOfLines = 2
        descriptionLabel.adjustsFontSizeToFitWidth = true
        overlayView.addSubview(descriptionLabel)

        descriptionLabel.snp_makeConstraints { make in
            make.center.equalTo(overlayView)
            make.width.equalTo(TopSitesPanelUX.WelcomeScreenItemWidth)
        }

        return overlayView
    }

    fileprivate func updateEmptyPanelState() {
        if dataSource.count() == 0 {
            if self.emptyStateOverlayView.superview == nil {
                self.view.addSubview(self.emptyStateOverlayView)
                self.emptyStateOverlayView.snp_makeConstraints { make -> Void in
                    make.edges.equalTo(self.view)
                }
            }
        } else {
            self.emptyStateOverlayView.removeFromSuperview()
        }
    }

    //MARK: Private Helpers
    fileprivate func updateDataSourceWithSites(_ result: Maybe<Cursor<Site>>) {
        if let data = result.successValue {
            self.dataSource.setHistorySites(data.asArray())
            self.dataSource.profile = self.profile
            self.updateEmptyPanelState()
        }
    }

    fileprivate func updateAllRemoveButtonStates() {
        collection?.indexPathsForVisibleItems.forEach(updateRemoveButtonStateForIndexPath)
    }

    fileprivate func deleteTileForSuggestedSite(_ site: SuggestedSite) -> Success {
        var deletedSuggestedSites = profile.prefs.arrayForKey("topSites.deletedSuggestedSites") as! [String]
        deletedSuggestedSites.append(site.url)
        profile.prefs.setObject(deletedSuggestedSites, forKey: "topSites.deletedSuggestedSites")
        return succeed()
    }

    fileprivate func deleteHistoryTileForSite(_ site: Site, atIndexPath indexPath: IndexPath) {
        collection?.isUserInteractionEnabled = false

        if site is SuggestedSite {
            deleteTileForSuggestedSite(site as! SuggestedSite)
        }

        succeed().upon() { _ in // move off main thread
            getApp().profile?.history.removeSiteFromTopSites(site).uponQueue(DispatchQueue.main) { result in
                guard result.isSuccess else { return }

                // Remove the site from the current data source. Don't requery yet
                // since a Sync or location change may have changed the data under us.
                self.dataSource.sites = self.dataSource.sites.filter { $0 !== site }

                // Update the UICollectionView.
                self.deleteOrUpdateSites(indexPath) >>> {
                    // Finally, requery to pull in the latest sites.
                    self.profile.history.getTopSitesWithLimit(self.maxFrecencyLimit).uponQueue(dispatch_get_main_queue()) { result in
                        self.updateDataSourceWithSites(result)
                        self.collection?.userInteractionEnabled = true
                    }
                }
            }
        }
    }

    fileprivate func updateRemoveButtonStateForIndexPath(_ indexPath: IndexPath) {
        // If we have a cell passed in, use it. If not, then use the indexPath to get it.
        guard let cell = collection?.cellForItem(at: indexPath) as? ThumbnailCell else {
            return
        }

        cell.toggleRemoveButton(editingThumbnails)
    }

    fileprivate func refreshTopSites(_ frecencyLimit: Int) {
        DispatchQueue.main.async {
            // Don't allow Sync or other notifications to change the data source if we're deleting a thumbnail.
            if !(self.collection?.isUserInteractionEnabled ?? true) {
                return
            }

            // Reload right away with whatever is in the cache, then check to see if the cache is invalid.
            // If it's invalid, invalidate the cache and requery. This allows us to always show results
            // immediately while also loading up-to-date results asynchronously if needed.
            self.reloadTopSitesWithLimit(frecencyLimit) >>> {
                self.profile.history.updateTopSitesCacheIfInvalidated() >>== { dirty in
                    if dirty {
                        self.dataSource.sitesInvalidated = true
                        self.reloadTopSitesWithLimit(frecencyLimit)
                    }
                }
            }
        }
    }

    fileprivate func reloadTopSitesWithLimit(_ limit: Int) -> Success {
        return self.profile.history.getTopSitesWithLimit(limit).bindQueue(dispatch_get_main_queue()) { result in
            self.updateDataSourceWithSites(result)
            self.collection?.reloadData()
            return succeed()
        }
    }

    fileprivate func deleteOrUpdateSites(_ indexPath: NSIndexPath) -> Success {
        guard let collection = self.collection else { return succeed() }

        let result = Success()

        collection.performBatchUpdates({
            collection.deleteItemsAtIndexPaths([indexPath])

            // If we have more items in our data source, replace the deleted site with a new one.
            let count = collection.numberOfItems(inSection: 0) - 1
            if count < self.dataSource.count() {
                collection.insertItems(at: [ IndexPath(item: count, section: 0) ])
            }
        }, completion: { _ in
            self.updateAllRemoveButtonStates()
            result.fill(Maybe(success: ()))
        })

        return result
    }

    /**
    Calculates an approximation of the number of tiles we want to display for the given orientation. This
    method uses the screen's size as it's basis for the calculation instead of the collectionView's since the 
    collectionView's bounds is determined until the next layout pass.

    - parameter orientation: Orientation to calculate number of tiles for

    - returns: Rough tile count we will be displaying for the passed in orientation
    */
    fileprivate func calculateApproxThumbnailCountForOrientation(_ orientation: UIInterfaceOrientation) -> Int {
        let size = UIScreen.main.bounds.size
        let portraitSize = CGSize(width: min(size.width, size.height), height: max(size.width, size.height))

        func calculateRowsForSize(_ size: CGSize, columns: Int) -> Int {
            let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
                traitCollection:  traitCollection)
            let thumbnailWidth = (size.width - insets.left - insets.right) / CGFloat(columns)
            let thumbnailHeight = thumbnailWidth / CGFloat(ThumbnailCellUX.ImageAspectRatio)
            return max(2, Int(size.height / thumbnailHeight))
        }

        let numberOfColumns: Int
        let numberOfRows: Int

        if UIInterfaceOrientationIsLandscape(orientation) {
            numberOfColumns = 5
            numberOfRows = calculateRowsForSize(CGSize(width: portraitSize.height, height: portraitSize.width), columns: numberOfColumns)
        } else {
            numberOfColumns = 4
            numberOfRows = calculateRowsForSize(portraitSize, columns: numberOfColumns)
        }

        return numberOfColumns * numberOfRows
    }
}

extension TopSitesPanel: HomePanel {
    func endEditing() {
        editingThumbnails = false
        collection?.reloadData()
    }
}

extension TopSitesPanel: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if editingThumbnails {
            return
        }

        if let site = dataSource[indexPath.item] {
            // We're gonna call Top Sites bookmarks for now.
            let visitType = VisitType.Bookmark
            let urlString = "\(URL(string: site.url)?.scheme ?? "")://\(URL(string: site.url)?.host ?? "")"
            homePanelDelegate?.homePanel(self, didSelectURL: URL(string: urlString) ?? site.tileURL, visitType: visitType)
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let thumbnailCell = cell as? ThumbnailCell {
            thumbnailCell.delegate = self
            if editingThumbnails && (indexPath as NSIndexPath).item < dataSource.count() && thumbnailCell.removeButton.isHidden {
                thumbnailCell.removeButton.isHidden = false
            }
        }
    }
}

extension TopSitesPanel: ThumbnailCellDelegate {
    func didRemoveThumbnail(_ thumbnailCell: ThumbnailCell) {
        guard let indexPath = collection?.indexPath(for: thumbnailCell),
              let site = dataSource[indexPath.item] else { return }

        self.deleteHistoryTileForSite(site, atIndexPath: indexPath)
    }

    func didLongPressThumbnail(_ thumbnailCell: ThumbnailCell) {
        editingThumbnails = true
        (view.window as! BraveMainWindow).addTouchFilter(self)
    }
}

private class TopSitesCollectionView: UICollectionView {
    fileprivate override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Hide the keyboard if this view is touched.
        window?.rootViewController?.view.endEditing(true)
        super.touchesBegan(touches, with: event)
    }
}

class TopSitesLayout: UICollectionViewLayout {

    var thumbnailCount: Int {
        assertIsMainThread("layout.thumbnailCount interacts with UIKit components - cannot call from background thread.")
        return thumbnailRows * thumbnailCols
    }

    fileprivate var thumbnailRows: Int {
        assert(Thread.isMainThread, "Interacts with UIKit components - not thread-safe.")
        return 2 // max(2, Int((self.collectionView?.frame.height ?? self.thumbnailHeight) / self.thumbnailHeight))
    }

    fileprivate var thumbnailCols: Int {
        assert(Thread.isMainThread, "Interacts with UIKit components - not thread-safe.")

        let size = collectionView?.bounds.size ?? CGSize.zero
        let traitCollection = collectionView!.traitCollection
        var cols = 0
        if traitCollection.horizontalSizeClass == .compact {
            // Landscape iPhone
            if traitCollection.verticalSizeClass == .compact {
                cols = 5
            }
            // Split screen iPad width
            else if size.widthLargerOrEqualThanHalfIPad() ?? false {
                cols = 4
            }
            // iPhone portrait
            else {
                cols = 3
            }
        } else {
            // Portrait iPad
            if size.height > size.width {
                cols = 4;
            }
            // Landscape iPad
            else {
                cols = 5;
            }
        }
        return cols + 1
    }

    fileprivate var width: CGFloat {
        assertIsMainThread("layout.width interacts with UIKit components - cannot call from background thread.")
        return self.collectionView?.frame.width ?? 0
    }

    // The width and height of the thumbnail here are the width and height of the tile itself, not the image inside the tile.
    fileprivate var thumbnailWidth: CGFloat {
        assertIsMainThread("layout.thumbnailWidth interacts with UIKit components - cannot call from background thread.")

        let size = collectionView?.bounds.size ?? CGSize.zero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
            traitCollection:  collectionView!.traitCollection)

        return floor(width - insets.left - insets.right) / CGFloat(thumbnailCols)
    }
    // The tile's height is determined the aspect ratio of the thumbnails width. We also take into account
    // some padding between the title and the image.
    fileprivate var thumbnailHeight: CGFloat {
        assertIsMainThread("layout.thumbnailHeight interacts with UIKit components - cannot call from background thread.")

        return floor(thumbnailWidth / CGFloat(ThumbnailCellUX.ImageAspectRatio))
    }

    // Used to calculate the height of the list.
    fileprivate var count: Int {
        if let dataSource = self.collectionView?.dataSource as? TopSitesDataSource {
            return dataSource.collectionView(self.collectionView!, numberOfItemsInSection: 0)
        }
        return 0
    }

    fileprivate var topSectionHeight: CGFloat {
        let maxRows = ceil(Float(count) / Float(thumbnailCols))
        let rows = min(Int(maxRows), thumbnailRows)
        let size = collectionView?.bounds.size ?? CGSize.zero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
            traitCollection:  collectionView!.traitCollection)
        return thumbnailHeight * CGFloat(rows) + insets.top + insets.bottom
    }

    fileprivate func getIndexAtPosition(_ y: CGFloat) -> Int {
        if y < topSectionHeight {
            let row = Int(y / thumbnailHeight)
            return min(count - 1, max(0, row * thumbnailCols))
        }
        return min(count - 1, max(0, Int((y - topSectionHeight) / UIConstants.DefaultRowHeight + CGFloat(thumbnailCount))))
    }

    override var collectionViewContentSize : CGSize {
        if count <= thumbnailCount {
            return CGSize(width: width, height: topSectionHeight)
        }

        let bottomSectionHeight = CGFloat(count - thumbnailCount) * UIConstants.DefaultRowHeight
        return CGSize(width: width, height: topSectionHeight + bottomSectionHeight)
    }

    fileprivate var layoutAttributes:[UICollectionViewLayoutAttributes]?

    override func prepare() {
        var layoutAttributes = [UICollectionViewLayoutAttributes]()
        for section in 0..<(self.collectionView?.numberOfSections ?? 0) {
            for item in 0..<(self.collectionView?.numberOfItems(inSection: section) ?? 0) {
                let indexPath = IndexPath(item: item, section: section)
                guard let attrs = self.layoutAttributesForItem(at: indexPath) else { continue }
                layoutAttributes.append(attrs)
            }
        }
        self.layoutAttributes = layoutAttributes
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attrs = [UICollectionViewLayoutAttributes]()
        if let layoutAttributes = self.layoutAttributes {
            for attr in layoutAttributes {
                if rect.intersects(attr.frame) {
                    attrs.append(attr)
                }
            }
        }

        return attrs
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attr = UICollectionViewLayoutAttributes(forCellWith: indexPath)

        // Set the top thumbnail frames.
        let row = floor(Double((indexPath as NSIndexPath).item / thumbnailCols))
        let col = (indexPath as NSIndexPath).item % thumbnailCols
        let size = collectionView?.bounds.size ?? CGSize.zero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
            traitCollection:  collectionView!.traitCollection)
        let x = insets.left + thumbnailWidth * CGFloat(col)
        let y = insets.top + CGFloat(row) * thumbnailHeight
        attr.frame = CGRect(x: ceil(x), y: ceil(y), width: thumbnailWidth, height: thumbnailHeight)

        return attr
    }
}

private class TopSitesDataSource: NSObject, UICollectionViewDataSource {
    var profile: Profile
    var editingThumbnails: Bool = false
    var suggestedSites = [SuggestedSite]()
    var sites = [Site]()
    fileprivate var sitesInvalidated = true

    weak var collectionView: UICollectionView?

    fileprivate let blurQueue = DispatchQueue(label: "FaviconBlurQueue", attributes: DispatchQueue.Attributes.concurrent)
    fileprivate let BackgroundFadeInDuration: TimeInterval = 0.3

    init(profile: Profile) {
        self.profile = profile
        if profile.prefs.arrayForKey("topSites.deletedSuggestedSites") == nil {
            profile.prefs.setObject([], forKey: "topSites.deletedSuggestedSites")
        }
        super.init()
    }

    @objc func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // If there aren't enough data items to fill the grid, look for items in suggested sites.
        if let layout = collectionView.collectionViewLayout as? TopSitesLayout {
            return min(count(), layout.thumbnailCount)
        }

        return 0
    }

    fileprivate func setDefaultThumbnailBackgroundForCell(_ cell: ThumbnailCell) {
        cell.imageView.image = UIImage(named: "defaultTopSiteIcon")!
        cell.imageView.contentMode = UIViewContentMode.center
    }

    fileprivate func setBlurredBackground(_ image: UIImage, withURL url: URL, forCell cell: ThumbnailCell) {
        let blurredKey = "\(url.absoluteString)!blurred"
        if let blurredImage = SDImageCache.shared().imageFromMemoryCache(forKey: blurredKey) {
            cell.backgroundImage.image = blurredImage
        } else {
            let blurredImage = image.applyLightEffect()
            SDImageCache.shared().store(blurredImage, forKey: blurredKey, toDisk: false)
            cell.backgroundImage.alpha = 0
            cell.backgroundImage.image = blurredImage
            UIView.animate(withDuration: self.BackgroundFadeInDuration, animations: {
                cell.backgroundImage.alpha = 1
            }) 
        }
    }

    fileprivate func downloadFaviconsAndUpdateForSite(_ site: Site) {
        guard let siteURL = site.url.asURL else { return }

        FaviconFetcher.getForURL(siteURL, profile: profile).uponQueue(DispatchQueue.main) { result in
            guard let favicons = result.successValue , favicons.count > 0,
                  let url = favicons.first?.url.asURL,
                  let indexOfSite = (self.sites.indexOf { $0 == site }) else {
                return
            }

            let indexPathToUpdate = NSIndexPath(forItem: indexOfSite, inSection: 0)
            guard let cell = self.collectionView?.cellForItemAtIndexPath(indexPathToUpdate) as? ThumbnailCell else { return }
            cell.imageView.sd_setImageWithURL(url) { (img, err, type, url) -> Void in
                guard let img = img else {
                    self.setDefaultThumbnailBackgroundForCell(cell)
                    return
                }
                cell.image = img
                self.setBlurredBackground(img, withURL: url, forCell: cell)
            }
        }
    }

    fileprivate func configureCell(_ cell: ThumbnailCell, forSite site: Site, isEditing editing: Bool, profile: Profile) {

        // We always want to show the domain URL, not the title.
        //
        // Eventually we can do something more sophisticated — e.g., if the site only consists of one
        // history item, show it, and otherwise use the longest common sub-URL (and take its title
        // if you visited that exact URL), etc. etc. — but not yet.
        //
        // The obvious solution here and in collectionView:didSelectItemAtIndexPath: is for the cursor
        // to return domain sites, not history sites -- that is, with the right icon, title, and URL --
        // and for this code to just use what it gets.
        //
        // Instead we'll painstakingly re-extract those things here.

        let domainURL = extractDomainURL(site.url)
        cell.textLabel.text = domainURL
        cell.accessibilityLabel = cell.textLabel.text
        cell.removeButton.isHidden = !editing

        guard let icon = site.icon else {
            setDefaultThumbnailBackgroundForCell(cell)
            downloadFaviconsAndUpdateForSite(site)
            return
        }

        // We've looked before recently and didn't find a favicon
        switch icon.type {
        case .NoneFound where Date().timeIntervalSinceDate(icon.date) < FaviconFetcher.ExpirationTime:
            self.setDefaultThumbnailBackgroundForCell(cell)
        default:
            cell.imageView.sd_setImageWithURL(icon.url.asURL, completed: { (img, err, type, url) -> Void in
                if let img = img {
                    cell.image = img
                    self.setBlurredBackground(img, withURL: url, forCell: cell)
                } else {
                    self.setDefaultThumbnailBackgroundForCell(cell)
                    self.downloadFaviconsAndUpdateForSite(site)
                }
            })
        }
    }

    fileprivate func configureCell(_ cell: ThumbnailCell, forSuggestedSite site: SuggestedSite) {
        cell.textLabel.text = site.title.isEmpty ? URL(string: site.url)?.normalizedHostAndPath() : site.title
        cell.imageWrapper.backgroundColor = site.backgroundColor
        cell.imageView.contentMode = .scaleAspectFit
        cell.imageView.layer.minificationFilter = kCAFilterTrilinear
        cell.accessibilityLabel = cell.textLabel.text

        guard let icon = site.wordmark.url.asURL,
            let host = icon.host else {
                self.setDefaultThumbnailBackgroundForCell(cell)
                return
        }

        if icon.scheme == "asset" {
            if let image = UIImage(named: host) {
                // Brave hack. The images are too close to the top edge
                UIGraphicsBeginImageContextWithOptions(image.size, false, 0)
                image.drawInRect(CGRect(origin: CGPoint(x: 3, y: 6), size: CGSize(width: image.size.width - 6, height: image.size.height - 6)))
                let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                cell.imageView.image = scaledImage
            }

        } else {
            cell.imageView.sd_setImageWithURL(icon, completed: { img, err, type, key in
                if img == nil {
                    self.setDefaultThumbnailBackgroundForCell(cell)
                }
            })
        }
    }

    fileprivate func setHistorySites(_ historySites: [Site]) {
        // Sites are invalidated and we have a new data set, so do a replace.
        if (sitesInvalidated) {
            self.sites = []
        }

        // We requery every time we do a deletion. If the query contains a top site that's
        // bubbled up that wasn't there previously (e.g., a page just finished loading
        // in the background), it will change the index of any following site currently
        // displayed. This, in turn, would cause sites to shuffle around, and we would
        // possibly have duplicates if a site that's already visible has been reindexed
        // to a newly added position, post-deletion.
        //
        // The fix? Go through our existing set of sites on an update and append new sites
        // to the end. This preserves the ordering of existing sites, meaning the last
        // index, post-deletion, will always be a new site. Of course, this is temporary;
        // whenever the panel is reloaded, our transient, ordered state will be lost. But
        // that's OK: top sites change frequently anyway.
        var historySites: [Site] = historySites
        self.sites = self.sites.filter { site in
            if let index = historySites.indexOf({ extractDomainURL($0.url) == extractDomainURL(site.url) }) {
                historySites.removeAtIndex(index)
                return true
            }

            return site is SuggestedSite
        }

        self.sites += historySites

        // Since future updates to history sites will append to the previous result set,
        // including suggested sites, we only need to do this once.
        if sitesInvalidated {
            sitesInvalidated = false
            mergeSuggestedSites()
        }
    }

    fileprivate func mergeSuggestedSites() {
        suggestedSites = SuggestedSites.asArray()
        if let deleted = profile.prefs.arrayForKey("topSites.deletedSuggestedSites") as? [String] {
            for url in deleted {
                suggestedSites = suggestedSites.filter { extractDomainURL($0.url) != extractDomainURL(url) }
            }
        }

        sites = sites.map { site in
            let domainURL = extractDomainURL(site.url)
            if let index = (suggestedSites.indexOf { extractDomainURL($0.url) == domainURL }) {
                let suggestedSite = suggestedSites[index]
                suggestedSites.removeAtIndex(index)
                return suggestedSite
            }
            return site
        }

        sites += suggestedSites as [Site]
    }

    subscript(index: Int) -> Site? {
        if count() == 0 {
            return nil
        }

        return self.sites[index] as Site?
    }

    fileprivate func count() -> Int {
        return sites.count
    }

    fileprivate func extractDomainURL(_ url: String) -> String {
        return URL(string: url)?.normalizedHost() ?? url
    }

    @objc func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // Cells for the top site thumbnails.
        let site = self[indexPath.item]!
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ThumbnailIdentifier, for: indexPath) as! ThumbnailCell

        let traitCollection = collectionView.traitCollection

        if let site = site as? SuggestedSite {
            configureCell(cell, forSuggestedSite: site)
            cell.updateLayoutForCollectionViewSize(collectionView.bounds.size, traitCollection: traitCollection, forSuggestedSite: true)
            return cell
        }

        configureCell(cell, forSite: site, isEditing: editingThumbnails, profile: profile)
        cell.updateLayoutForCollectionViewSize(collectionView.bounds.size, traitCollection: traitCollection, forSuggestedSite: false)
        return cell
    }
}

#if BRAVE
extension TopSitesPanel : WindowTouchFilter {
    func filterTouch(touch: UITouch) -> Bool {
        if (touch.view as? UIButton) == nil && touch.phase == .Began {
            self.endEditing()
            return true
        }
        return false
    }
}
#endif
