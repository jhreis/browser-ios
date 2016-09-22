/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

public func titleForSpecialGUID(_ guid: GUID) -> String? {
    switch guid {
    case BookmarkRoots.RootGUID:
        return "<Root>"
    case BookmarkRoots.MobileFolderGUID:
        return BookmarksFolderTitleMobile
    case BookmarkRoots.ToolbarFolderGUID:
        return BookmarksFolderTitleToolbar
    case BookmarkRoots.MenuFolderGUID:
        return BookmarksFolderTitleMenu
    case BookmarkRoots.UnfiledFolderGUID:
        return BookmarksFolderTitleUnsorted
    default:
        return nil
    }
}

extension SQLiteBookmarks: ShareToDestination {
    public func addToMobileBookmarks(_ url: NSURL, title: String, favicon: Favicon?, folderId:String? = nil, folderTitle:String? = nil) -> Success {
        //default to the right root folder if no folder is passed
        let actualFolderId = folderId ?? BookmarkRoots.MobileFolderGUID // folderId is something like "DgNGLGdYTKdT"
        let actualFolderTitle = folderTitle ?? BookmarksFolderTitleMobile //folderTitle is human-readable eg "my folder"
        return self.insertBookmark(url, title: title, favicon: favicon,
                                   intoFolder: actualFolderId,
                                   withTitle: actualFolderTitle)
    }

    public func shareItem(_ item: ShareItem) {
        // We parse here in anticipation of getting real URLs at some point.
        if let url = item.url.asURL {
            let title = item.title ?? url.absoluteString
            let folderId = item.folderId
            let folderTitle = item.folderTitle
            let v = self.addToMobileBookmarks(url, title: title, favicon: item.favicon, folderId: folderId, folderTitle: folderTitle)
            if let completion = item.completion {
                v.upon { success in
                    if success.isSuccess {
                        dispatch_async(dispatch_get_main_queue()) {
                            completion()
                        }
                    }
                }
            }
            
        }
    }
}
