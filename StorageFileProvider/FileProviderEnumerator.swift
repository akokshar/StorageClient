//
//  FileProviderEnumerator.swift
//  StorageFileProvider
//
//  Created by Koksharov Alexandr on 28/01/2019.
//  Copyright © 2019 Koksharov Alexandr. All rights reserved.
//

import FileProvider

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    
    struct PageData: Codable {
        var ascending: Bool
        var sortKey: SortType
        var offset: Int
        let batchSize: Int = 128
    }
    
    struct SyncAnchorData: Codable {
        var anchor: Int64
    }
    
//    var enumeratedItemIdentifier: NSFileProviderItemIdentifier
    var enumeratedItemIdentifier: String
    var domainIdentifier: String

    init(enumeratedItemIdentifier: String, domain: String) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        self.domainIdentifier = domain
        super.init()
    }

    func invalidate() {
        // TODO: perform invalidation of server connection if necessary
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        /* TODO:
         - inspect the page to determine whether this is an initial or a follow-up request
         
         If this is an enumerator for a directory, the root container or all directories:
         - perform a server request to fetch directory contents
         If this is an enumerator for the active set:
         - perform a server request to update your local database
         - fetch the active set from your local database
         
         - inform the observer about the items returned by the server (possibly multiple times)
         - inform the observer that you are finished with this page
         */
        print("enumerate items for \(self.enumeratedItemIdentifier)")
        var pageData: PageData = {
            if let pd = try? PropertyListDecoder().decode(PageData.self, from: page.rawValue) {
                return pd
            }
//            if page ==  NSFileProviderPage.initialPageSortedByName as NSFileProviderPage {
//                return PageData(ascending: false, sortKey: "name", offset: 0)
//            }
            if page ==  NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage {
                return PageData(ascending: false, sortKey: .byCreateDate, offset: 0)
            }
            return PageData(ascending: false, sortKey: .byName, offset: 0)
        }()
        
        let items = StoreDB.db.enumerate(childrenOf: self.enumeratedItemIdentifier, inDomain: self.domainIdentifier, startAt: pageData.offset, atLeast: pageData.batchSize, sortBy: pageData.sortKey)
        
//        let items = StoreDB.perform { (db) in
////            return db.enumerate(childrenOf: self.enumeratedItemIdentifier.rawValue, startAt: pageData.offset, atLeast: pageData.batchSize, sortBy: pageData.sortKey)
//            return db.enumerate(childrenOf: self.enumeratedItemIdentifier, inDomain: self.domainIdentifier, startAt: pageData.offset, atLeast: pageData.batchSize, sortBy: pageData.sortKey)
//        }
        
        if items.count > 0 {
            observer.didEnumerate(items)
        }
        
        guard items.count >= pageData.batchSize  else {
            observer.finishEnumerating(upTo: nil)
            // if we got the last page - less them requested, them check whether there are changes on the server
            // by triggerig enumerateDhanges
//            StoreDB.perform { (db) in
//                db.checkSyncStatusForItem(withIdentifier: self.enumeratedItemIdentifier.rawValue) { (status) in
//                    print("signaling ennumerator for \(self.enumeratedItemIdentifier)")
//                    NSFileProviderManager.default.signalEnumerator(for: self.enumeratedItemIdentifier) { (error) in }
//                }
//            }
            return
        }
        
        pageData.offset += items.count
        let nextPage = try! PropertyListEncoder().encode(pageData)
        observer.finishEnumerating(upTo: NSFileProviderPage(nextPage))
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        /* TODO:
         - query the server for updates since the passed-in sync anchor
         
         If this is an enumerator for the active set:
         - note the changes in your local database
         
         - inform the observer about item deletions and updates (modifications + insertions)
         - inform the observer when you have finished enumerating up to a subsequent sync anchor
         */
        
        print("enumerate changes for \(self.enumeratedItemIdentifier)")
        var anchorData: SyncAnchorData = {
            if let sd = try? PropertyListDecoder().decode(SyncAnchorData.self, from: anchor.rawValue) {
                return sd
            }
            return SyncAnchorData(anchor: 0)
        }()
        
        StoreDB.db.syncChangesForItem(withIdentifier: self.enumeratedItemIdentifier, inDomain: self.domainIdentifier, from: anchorData.anchor, batchSize: 3) { (newItems, deletedItems, nextAnchorValue, hasMore) in
            if deletedItems.count > 0 {
                observer.didDeleteItems(withIdentifiers: deletedItems.map{ (id) -> NSFileProviderItemIdentifier in
                    return NSFileProviderItemIdentifier(id)
                })
            }
            if newItems.count > 0 {
                observer.didUpdate(newItems)
            }
        
            anchorData.anchor = nextAnchorValue
            let nextAnchor = try! PropertyListEncoder().encode(anchorData)
            observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(nextAnchor), moreComing: hasMore)
        }
    }
    

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        print("syncAnchor for \(self.enumeratedItemIdentifier)")
        let currentAnchorValue = StoreDB.db.syncAnchorForItem(withIdentifier: self.enumeratedItemIdentifier, inDimain: self.domainIdentifier)
        let anchorData = SyncAnchorData(anchor: currentAnchorValue)
        let anchor =  try! PropertyListEncoder().encode(anchorData)
        completionHandler(NSFileProviderSyncAnchor(anchor))
    }

}
