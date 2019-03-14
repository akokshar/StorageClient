//
//  StoreItem+CoreDataClass.swift
//  StorageClient
//
//  Created by Koksharov Alexandr on 03/02/2019.
//  Copyright © 2019 Koksharov Alexandr. All rights reserved.
//
//

import Foundation
import CoreData
import MobileCoreServices
import FileProvider

public enum ItemDownloadState: Int16 {
    case notStarted = 0
    case downloading = 1
    case downloaded = 2
    case deleteLocal = 3
}

public enum ItemUploadState: Int16 {
    case notStarted = 0
    case uploading = 1
    case uploaded = 2
}

@objc(StoreItem)
public class StoreItem: NSManagedObject, NSFileProviderItem {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<StoreItem> {
        return NSFetchRequest<StoreItem>(entityName: "StoreItem")
    }
    
    @NSManaged public var id: String
    @NSManaged public var pid: String
    @NSManaged public var name: String
    @NSManaged public var domain: Int16
    @NSManaged public var cdate: Date
    @NSManaged public var uti: String
    @NSManaged public var mdate: Date
    @NSManaged public var anchor: Int64
    @NSManaged public var size: Int64
    @NSManaged private var uploadingState: Int16
    @NSManaged public var uploadError: String?
    @NSManaged private var downloadingState: Int16
    @NSManaged public var downloadError: String?
    @NSManaged public var children: NSSet?
    @NSManaged public var parent: StoreItem?
    
    // TODO: implement an initializer to create an item from your extension's backing model

    convenience init(asChildOf parent: StoreItem) {
        self.init(entity: parent.entity, insertInto: parent.managedObjectContext)
        self.parent = parent
        self.domain = parent.domain
        self.anchor = 0
        self.downloadingState = ItemDownloadState.notStarted.rawValue
        self.downloadError = nil
        self.uploadingState = ItemUploadState.notStarted.rawValue
        self.uploadError = nil
    }
    
    // TODO: implement the accessors to return the values from your extension's backing model
    
    public var itemIdentifier: NSFileProviderItemIdentifier {
        return NSFileProviderItemIdentifier(rawValue: self.id)
    }
    
    public var parentItemIdentifier: NSFileProviderItemIdentifier {
        if let parentItem = self.parent {
            return parentItem.itemIdentifier
        }
        return NSFileProviderItemIdentifier.rootContainer
    }
    
    public var capabilities: NSFileProviderItemCapabilities {
        if self.isDirectory {
            return  [ .allowsAddingSubItems, .allowsContentEnumerating, .allowsReading, .allowsDeleting ]
        }
        return [ .allowsReading, .allowsDeleting ]
    }
    
    public var childItemCount: NSNumber? {
        if isDirectory {
            return NSNumber(value: self.size)
        }
        return nil
    }
    
    public var isDirectory: Bool {
        return (self.uti == kUTTypeFolder as String)
    }
    
    public var isNotDirectory: Bool {
        return !self.isDirectory
    }
    
    public var documentSize: NSNumber? {
        return NSNumber(value: self.size)
    }
    
    public var filename: String {
        return self.name
    }
    
    public var typeIdentifier: String {
        return self.uti
    }
    
    public var uploadState: ItemUploadState {
        get {
            return ItemUploadState(rawValue: self.uploadingState)!
        }
        set (newState) {
            self.uploadingState = newState.rawValue
        }
    }
    
    public var isUploading: Bool {
        return self.uploadingState == ItemUploadState.uploading.rawValue
    }

    public var isUploaded: Bool {
        return self.uploadingState == ItemUploadState.uploaded.rawValue
    }

    public var uploadingError: Error? {
        if let uploadError = self.uploadError {
            return StoreAPIError(description: uploadError)
        }
        return nil
    }
    
    public var downloadState: ItemDownloadState {
        get {
            return ItemDownloadState(rawValue: self.downloadingState)!
        }
        set (newState) {
            self.downloadingState = newState.rawValue
        }
    }

    public var isDownloading: Bool {
        return self.downloadingState == ItemDownloadState.downloading.rawValue
    }
    
    public var isDownloaded: Bool {
        return self.downloadingState == ItemDownloadState.downloaded.rawValue
    }
    
    public var downloadingError: Error? {
        if let downloadError = self.downloadError {
            return StoreAPIError(description: downloadError)
        }
        return nil
    }
    
}

// MARK: Generated accessors for children
extension StoreItem {
    
    @objc(addChildrenObject:)
    @NSManaged public func addToChildren(_ value: StoreItem)
    
    @objc(removeChildrenObject:)
    @NSManaged public func removeFromChildren(_ value: StoreItem)
    
    @objc(addChildren:)
    @NSManaged public func addToChildren(_ values: NSSet)
    
    @objc(removeChildren:)
    @NSManaged public func removeFromChildren(_ values: NSSet)
    
}
