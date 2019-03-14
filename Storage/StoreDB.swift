//
//  StoreDB.swift
//  StorageClient
//
//  Created by Koksharov Alexandr on 31/01/2019.
//  Copyright © 2019 Koksharov Alexandr. All rights reserved.
//

import Foundation
import FileProvider
import CoreData
#if os(macOS)
import CoreServices
#else
import MobileCoreServices
#endif

enum SortType: String, Codable {
    case byName = "name"
    case byCreateDate = "cdate"
}

class StoreDB {
    private let sharedGroupName = "group.lex.home.StorageClient"
    
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "StoreDB")

        let description = NSPersistentStoreDescription()
        description.shouldInferMappingModelAutomatically = true
        description.shouldMigrateStoreAutomatically = true
        description.url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedGroupName)!.appendingPathComponent("storedb.sqlite")
        
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })

        container.viewContext.undoManager = nil
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container
    }()
    
    private static let instance: StoreDB = {
        let storeDB = StoreDB()
        
        // Ensure root items exist
        storeDB.performInContextAndWait { (context) in
            StoreDomains.domains.forEach { (key, domain) in
                let request: NSFetchRequest<StoreItem> = StoreItem.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@ and domain == %@", NSFileProviderItemIdentifier.rootContainer.rawValue, domain.identifier)
                guard let result = try? context.fetch(request) else {
                    fatalError("cant initialize store")
                }
                if result.count == 0 {
                    let rootContainerItem = StoreItem(context: context)
                    rootContainerItem.name = domain.fileProviderDomain.displayName
                    rootContainerItem.id = NSFileProviderItemIdentifier.rootContainer.rawValue
                    rootContainerItem.domain = domain.id
                    rootContainerItem.pid = ""
                    rootContainerItem.uti = kUTTypeFolder as String
                    rootContainerItem.size = 0
                    rootContainerItem.cdate = Date(timeIntervalSince1970: 0)
                    rootContainerItem.mdate = Date(timeIntervalSince1970: 0)
                    rootContainerItem.anchor = 0
                    rootContainerItem.downloadState = ItemDownloadState.downloaded
                    rootContainerItem.uploadState = ItemUploadState.uploaded
                }
            }
        }
        return storeDB
    }()
    
    public static let db = StoreDB.instance
    
//    public static func perform<T>(block: (StoreDB) -> T) -> T {
//        return block(StoreDB.instance)
//    }
    
    private init() { }
    
    private func performInContextAndWait(block: @escaping (NSManagedObjectContext) -> Void) {
        let context = persistentContainer.newBackgroundContext()
        context.undoManager = nil
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        block(context)
        self.saveContext(context)
    }
    
    private func saveContext(_ context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
            } catch let e {
                print("Save context error: '\(e)'")
            }
        }
    }
    
    private func item(withIdentifier identifier: String, inContext context: NSManagedObjectContext, inDomain domainIdentifier: String) -> StoreItem? {
        guard let domain = StoreDomains.domains[domainIdentifier] else {
            return nil
        }
        
        let request: NSFetchRequest<StoreItem> = StoreItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ and domain == %@", identifier, String(domain.id))
        guard let result = try? context.fetch(request), result.count > 0 else {
            return nil
        }
        
        return result[0]
    }
    
    func item(withIdentifier identifier: String, inDomain domainIdentifier: String) -> StoreItem? {
        return item(withIdentifier: identifier, inContext: self.persistentContainer.viewContext, inDomain: domainIdentifier)
    }
    
    private func item(withName name: String, childOf parent: StoreItem) -> StoreItem? {
        if let context = parent.managedObjectContext {
            let request: NSFetchRequest<StoreItem> = StoreItem.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@ and parent == %@", name, parent)
            guard let result = try? context.fetch(request), result.count > 0 else {
                return nil
            }
            return result[0]
        }
        return nil
    }

    func syncAnchorForItem(withIdentifier identifier: String, inDimain domainIdentifier: String) -> Int64 {
        guard let item = self.item(withIdentifier: identifier, inDomain: domainIdentifier) else {
            return 0
        }
        return item.anchor
    }
    
    func enumerate(childrenOf identifier: String, inDomain domainIdentifier: String, startAt offset: Int, atLeast count: Int = 128, sortBy sortby: SortType = .byName) -> [StoreItem] {
        guard let domain = StoreDomains.domains[domainIdentifier] else {
            return []
        }
        // retrive items from database
        let request: NSFetchRequest<StoreItem> = StoreItem.fetchRequest()
        request.predicate = NSPredicate(format: "parent.id == %@ and parent.domain == %@", identifier, String(domain.id))
        request.sortDescriptors = [NSSortDescriptor(key: sortby.rawValue, ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))]
        request.fetchOffset = offset
        request.fetchLimit = count
        request.fetchBatchSize = count
        guard let result = try? self.persistentContainer.viewContext.fetch(request) else {
            return []
        }
        return result
    }
    
    func syncChangesForItem(withIdentifier identifier: String, inDomain domainIdentifier: String, from anchor: Int64, batchSize count: Int, handler: ([StoreItem], [String], Int64, Bool)->Void) {
        print("syncChanges for \(identifier)")
        
        guard
            let changes = try? StoreAPI.session.storeEnumerateChangesToContainer(withIdentifier: identifier, from: anchor, num: count),
            anchor < changes.anchor
        else {
            handler([], [], anchor, false)
            return
        }
        
        var deletedIdentifiers: [String] = []
        print("got \(changes.new.count) new items")
        
        self.performInContextAndWait { (context) in
            guard let parent = self.item(withIdentifier: identifier, inContext: context, inDomain: domainIdentifier) else {
                return
            }
            for itemInfo in changes.new {
                // check if the object with same pid,name pair already exists
                // if so (local object must be a temporary one created by importFile/createDirectory)
                let item: StoreItem
                if let storeItem = self.item(withName: itemInfo.name, childOf: parent) {
                    deletedIdentifiers.append(storeItem.id)
                    item = storeItem
                } else {
                    item = StoreItem(asChildOf: parent)
                }
                item.id = itemInfo.identifier
                item.pid = identifier
                item.name = itemInfo.name
                item.size = itemInfo.size
                item.uti = itemInfo.uti
                item.mdate = itemInfo.modificationDate
                item.cdate = itemInfo.createDate
                item.anchor = 0
                item.uploadState = ItemUploadState.uploaded
            }
            for rawId in changes.erase {
                let id = String(rawId)
                if let item = self.item(withIdentifier: id, inContext: context, inDomain: domainIdentifier) {
                    context.delete(item)
                }
            }
            parent.anchor = changes.anchor
            parent.size = changes.size
        }
        
        let newItems: [StoreItem] = changes.new.map { (itemInfo) -> StoreItem? in
            return self.item(withIdentifier: itemInfo.identifier, inDomain: domainIdentifier)
        }.filter { (item) -> Bool in
            return item != nil
        }.map { (item) -> StoreItem in
            return item!
        }
        
        deletedIdentifiers.append(contentsOf: changes.erase.map{ (rawId) -> String in
            return String(rawId)
        })

        handler(newItems, deletedIdentifiers, changes.anchor, changes.remain > 0)
    }
    
    func createDirectory(withName name: String, parentIdentifier parentId: String, inDomain domainIdentifier: String, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
        let tmpID = UUID().uuidString
        self.performInContextAndWait { (context) in
            guard let parent = self.item(withIdentifier: parentId, inContext: context, inDomain: domainIdentifier), parent.isDirectory else {
                return
            }
            let dirItem = StoreItem(asChildOf: parent)
            dirItem.id = tmpID
            dirItem.pid = parentId
            dirItem.name = name
            dirItem.uti = kUTTypeFolder as String
            dirItem.size = 0
            dirItem.cdate = Date()
            dirItem.mdate = Date()
            dirItem.anchor = 0
            dirItem.downloadState = ItemDownloadState.downloaded
            dirItem.uploadState = ItemUploadState.uploading
            
            parent.size += 1
        }
        
        guard let item = self.item(withIdentifier: tmpID, inDomain: domainIdentifier) else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return
        }
        
        completionHandler(item, nil)
        
        DispatchQueue.global().async {
            let taskId = "\(domainIdentifier)/\(item.id)"
            let task = StoreBackgroundSession.backgroundSession.dataTask(withId: taskId, toCreateDirectory: item.name, parentId: parentId)
            if let fileManager = StoreDomains.domains[domainIdentifier]?.fileProviderManager {
                fileManager.register(task, forItemWithIdentifier: item.itemIdentifier) { (error) in
                    task.resume()
                }
                return
            }
            task.resume()
        }
    }
    
    func importFile(at fileURL: URL, parentIdentifier parentId: String, inDomain domainIdentifier: String, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
        guard
            let parent = self.item(withIdentifier: parentId, inDomain: domainIdentifier),
            parent.isDirectory,
            fileURL.startAccessingSecurityScopedResource() == true,
            let resourceValues = try? fileURL.resourceValues(forKeys: [.typeIdentifierKey, .isDirectoryKey, .nameKey, .creationDateKey, .contentModificationDateKey, .totalFileSizeKey]),
            resourceValues.isDirectory! == false
        else {
            fileURL.stopAccessingSecurityScopedResource()
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return
        }
        
        // TODO: make check case insensitive
        if let child = self.item(withName: resourceValues.name!, childOf: parent) {
            completionHandler(nil, NSError.fileProviderErrorForCollision(with: child))
            return
        }
        
        let tmpID = UUID().uuidString
        
        let itemTmpDir = NSFileProviderManager.default.documentStorageURL.appendingPathComponent(tmpID, isDirectory: true)
        let tmpFilePath = itemTmpDir.appendingPathComponent(resourceValues.name!, isDirectory: false)
        
        // move file to shared container storage to tmpID directory
        var copyNSError: NSError? = nil
        var copyError: Error? = nil
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: .forUploading, error: &copyNSError) { (url) in
            do {
                try FileManager.default.createDirectory(at: itemTmpDir, withIntermediateDirectories: true, attributes: nil)
                try FileManager.default.moveItem(at: url, to: tmpFilePath)
            } catch let e {
                copyError = e
            }
        }
        
        guard copyError == nil && copyNSError == nil else {
            try? FileManager.default.removeItem(at: itemTmpDir)
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return
        }
        
        fileURL.stopAccessingSecurityScopedResource()
        
        // create object un a background context and save it
        self.performInContextAndWait { (context) in
            guard let parent = self.item(withIdentifier: parentId, inContext: context, inDomain: domainIdentifier) else {
                return
            }
            let item = StoreItem(asChildOf: parent)
            item.id = tmpID
            item.pid = parentId
            item.name = resourceValues.name!
            item.uti = resourceValues.typeIdentifier!
            item.cdate = resourceValues.creationDate!
            item.mdate = resourceValues.contentModificationDate!
            item.size = Int64(resourceValues.totalFileSize!)
            item.downloadState = ItemDownloadState.notStarted
            item.uploadState = ItemUploadState.uploading
            
            parent.size += 1
        }
        
        guard let item = self.item(withIdentifier: tmpID, inDomain: domainIdentifier) else {
            try? FileManager.default.removeItem(at: itemTmpDir)
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return
        }
        
        completionHandler(item, nil)
        
        // dispatch async file upload subsequent update from server have to move tmp item to proper directory
        //uploadFile(atUrl: tmpFilePath, forItemWithId: item.id)
        DispatchQueue.global().async {
            let taskId = "\(domainIdentifier)/\(item.id)"
            let task = StoreBackgroundSession.backgroundSession.uploadTask(withId: taskId, forFileAt: tmpFilePath, name: item.name, parentId: parent.id)
            if let fileManager = StoreDomains.domains[domainIdentifier]?.fileProviderManager {
                fileManager.register(task, forItemWithIdentifier: item.itemIdentifier) { (error) in
                    task.resume()
                }
                return
            }
            task.resume()
        }
    }
    
    public func downloadFileForItem(withIdentifier identifier: String, inDomain domainIdentifier: String, completionHandler: (_ error: Error?) -> Void) {
        
    }
    
     // MARK: StoreAPI handlers
    
    func uploadTask(withId taskId: String, completeWithError error: StoreAPIError) {
        let taskIdComponents = taskId.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard taskIdComponents.count == 2 else {
            return
        }
        
        let domainIdentifier = String(taskIdComponents[0])
        let itemId = String(taskIdComponents[1])
        
        self.performInContextAndWait { (context) in
            guard let item = self.item(withIdentifier: itemId, inContext: context, inDomain: domainIdentifier) else {
                return
            }
            item.uploadState = .notStarted
            item.uploadError = error.localizedDescription
        }
        
        // TODO: Reschedule upload
        // TODO: distinguish from permanent and temporary errors
    }
    
    func uploadTask(withId taskId: String, completeWithServerItem itemInfo: FileItemInfo) {
        let taskIdComponents = taskId.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard taskIdComponents.count == 2 else {
            return
        }
        
        let domainIdentifier = String(taskIdComponents[0])
        let itemId = String(taskIdComponents[1])
        
        var parentId: NSFileProviderItemIdentifier? = nil
        self.performInContextAndWait { (context) in
            guard let item = self.item(withIdentifier: itemId, inContext: context, inDomain: domainIdentifier), let parent = item.parent else {
                return
            }
            item.uploadState = .uploaded
            item.uploadError = nil
            
            // delete temporary item on next sync
            item.downloadState = .deleteLocal
            
            parentId = parent.itemIdentifier
            print("item \(item.name) uploaded")
            if item.isDirectory {
                return
            }
            
            // remove temporary files
            let itemTmpDir = NSFileProviderManager.default.documentStorageURL.appendingPathComponent(itemId, isDirectory: true)
            NSFileCoordinator().coordinate(with: [NSFileAccessIntent.writingIntent(with: itemTmpDir, options: .forDeleting)], queue: OperationQueue()) { (error) in
                if let error = error {
                    NSLog("Cant coordiname delete operation of \(itemTmpDir) due to \(error)")
                    return
                }
                do {
                    try FileManager.default.removeItem(at: itemTmpDir)
                } catch let e {
                    NSLog("Cant delete \(itemTmpDir) due to \(e)")
                }
            }
        }
        if let parentId = parentId, let domain = StoreDomains.domains[domainIdentifier] {
                domain.fileProviderManager?.signalEnumerator (for: parentId) { (error) in
                    //print("signalEnumerator for \(parentId) error \(error.debugDescription)")
                }
        }
    }
}
