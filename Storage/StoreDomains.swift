//
//  StoreDomain.swift
//  StorageClient
//
//  Created by Koksharov Alexandr on 09/03/2019.
//  Copyright © 2019 Koksharov Alexandr. All rights reserved.
//

import Foundation
import FileProvider

struct StoreDomain {
    let id: Int16
    let identifier: String
    let fileProviderDomain: NSFileProviderDomain
    let fileProviderManager: NSFileProviderManager?
}

class StoreDomains: Sequence {
    private let filesFileProviderDomain: NSFileProviderDomain
    private let filesFileProviderManager: NSFileProviderManager?
    
    private let photosFileProviderDomain: NSFileProviderDomain
    private let photosFileProviderManager: NSFileProviderManager?
    
    private let storeDomains: [String: StoreDomain]
    
    private init() {
        let filesDomainIdentifierKey = "files"
        self.filesFileProviderDomain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: filesDomainIdentifierKey),
            displayName: "Files",
            pathRelativeToDocumentStorage: "/files"
        )
        self.filesFileProviderManager = NSFileProviderManager(for: self.filesFileProviderDomain)
        
        let photosDomainIdentifierKey = "photos"
        self.photosFileProviderDomain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: photosDomainIdentifierKey),
            displayName: "Photos",
            pathRelativeToDocumentStorage: "/photos"
        )
        self.photosFileProviderManager = NSFileProviderManager(for: self.photosFileProviderDomain)
     
        self.storeDomains = [
            filesDomainIdentifierKey: StoreDomain(
                id: 1,
                identifier: filesDomainIdentifierKey,
                fileProviderDomain: self.filesFileProviderDomain,
                fileProviderManager: self.filesFileProviderManager
            ),
            photosDomainIdentifierKey: StoreDomain(
                id: 2,
                identifier: photosDomainIdentifierKey,
                fileProviderDomain: self.photosFileProviderDomain,
                fileProviderManager: self.photosFileProviderManager
            )
        ]
    }
    
    static var domains = {
        return StoreDomains()
    }()
    
    subscript(identifier: String) -> StoreDomain? {
        return self.storeDomains[identifier]
    }
    
    func makeIterator() -> DictionaryIterator<String,StoreDomain> {
        return storeDomains.makeIterator()
    }
    
    static func register() {
        NSFileProviderManager.getDomainsWithCompletionHandler { (domains, error) in
            StoreDomains.domains.storeDomains.forEach { (key, storeDomain) in
                let doesExist = domains.reduce(false) { (result, providerDomain) -> Bool in
                    return result || providerDomain.identifier.rawValue == key
                }
                if !doesExist {
                    NSFileProviderManager.add(storeDomain.fileProviderDomain) { (error) in }
                }
            }
        }

    }
}
