/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Deferred
import Foundation
import Shared
import Storage
import Sync

// This is a cut down version of the Profile. 
// This will only ever be used in the NotificationService extension.
// It allows us to customize the SyncDelegate, and later the SyncManager.
class ExtensionProfile: BrowserProfile {
    var syncDelegate: SyncDelegate!

    override var logins: BrowserLogins & SyncableLogins & ResettableSyncStorage {
        get {
            fatalError("Cannot use logins.db in extension")
        }
        set {}
    }

    init(localName: String) {
        super.init(localName: localName, app: nil, clear: false)
        syncManager = ExtensionSyncManager(profile: self)
    }

    override func getSyncDelegate() -> SyncDelegate {
        return syncDelegate
    }
}

fileprivate let extensionSafeNames = Set(["clients"])

class ExtensionSyncManager: BrowserProfile.BrowserSyncManager {

    init(profile: ExtensionProfile) {
        super.init(profile: profile)
    }

    // We don't want to send ping data at all while we're in the extension.
    override func canSendUsageData() -> Bool {
        return false
    }

    // We should probably only want to sync client commands while we're in the extension.
    override func syncNamedCollections(why: SyncReason, names: [String]) -> Success {
        let names = names.filter { extensionSafeNames.contains($0) }
        return super.syncNamedCollections(why: why, names: names)
    }

    override func takeActionsOnEngineStateChanges<T: EngineStateChanges>(_ changes: T) -> Deferred<Maybe<T>> {
        return deferMaybe(changes)
    }
}
