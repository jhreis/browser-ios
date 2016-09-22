/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

extension UIView {
    /**
     * Takes a screenshot of the view with the given size.
     */
    func screenshot(_ size: CGSize, offset: CGPoint? = nil, quality: CGFloat = 1) -> UIImage? {
        assert(0...1 ~= quality)

        if size.width < 1 || size.height < 1 || superview == nil {
            return nil
        }

        let offset = offset ?? CGPoint(x: 0, y: 0)
        UIGraphicsBeginImageContextWithOptions(size, true, UIScreen.main.scale * quality)
        drawHierarchy(in: CGRect(origin: offset, size: frame.size), afterScreenUpdates: false)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image

        // Migrate to use this alternate method which is 3x faster, but returns UIViews
        //        let startTime = CFAbsoluteTimeGetCurrent()
        //        let snap = snapshotViewAfterScreenUpdates(false)
        //        addSubview(snap)
        //        snap.frame = CGRectMake(0, 0, 200, 200)
        //
        //        UIGraphicsBeginImageContext(snap.frame.size)
        //        snap.layer.renderInContext(UIGraphicsGetCurrentContext()!)
        //        let image = UIGraphicsGetImageFromCurrentImageContext()
        //        UIGraphicsEndImageContext()
        //
        //        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        //        print("Time elapsed for screenshot: \(timeElapsed) s")
        //        return image
    }

    /**
     * Takes a screenshot of the view with the given aspect ratio.
     * An aspect ratio of 0 means capture the entire view.
     * Quality of zero means to use built in default, which adjusts based on the device capabilities
     */
    func screenshot(_ aspectRatio: CGFloat = 0, offset: CGPoint? = nil, quality _quality: CGFloat = 0) -> UIImage? {
        assert(aspectRatio >= 0)

        let quality = _quality != 0 ? _quality : ( DeviceInfo.isBlurSupported() ? 0.5 : 0.2 )

        var size: CGSize
        if aspectRatio > 0 {
            size = CGSize()
            let viewAspectRatio = frame.width / frame.height
            if viewAspectRatio > aspectRatio {
                size.height = frame.height
                size.width = size.height * aspectRatio
            } else {
                size.width = frame.width
                size.height = size.width / aspectRatio
            }
        } else {
            size = frame.size
        }

        let image = screenshot(size, offset: offset, quality: quality)
        return image
    }

    /* 
     * Performs a deep copy of the view. Does not copy constraints.
     */
    func clone() -> UIView {
        let data = NSKeyedArchiver.archivedData(withRootObject: self)
        return NSKeyedUnarchiver.unarchiveObject(with: data) as! UIView
    }
}
