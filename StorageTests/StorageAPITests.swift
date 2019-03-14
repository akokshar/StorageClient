//
//  StorageClientTests.swift
//  StorageClientTests
//
//  Created by Koksharov Alexandr on 17/01/2019.
//  Copyright © 2019 Koksharov Alexandr. All rights reserved.
//

import XCTest
//@testable import StorageClient

class StorageAPITests: XCTestCase {
    
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testStoreRoot() {
        do {
            let root: FileItemInfo = try StoreAPI.session.storeItemInfo(withIdentifier:  NSFileProviderItemIdentifier.rootContainer.rawValue)
            print("ROOT: \(root)")
            let dir: FileItemInfo = try StoreAPI.session.storeCreateDirectory(withName: "test2", parentIdentifier: NSFileProviderItemIdentifier.rootContainer.rawValue)
            print("DIR:  \(dir)")
            XCTAssert(true)
        } catch let e {
            print("\(e)")
            XCTAssert(false)
        }
    }
    
    func testStoreItemInfo() {
        do {
            let root: FileItemInfo = try StoreAPI.session.storeItemInfo(withIdentifier:  NSFileProviderItemIdentifier.rootContainer.rawValue)
            print("ROOT: \(root)")
            XCTAssert(true)
        } catch let e {
            print("\(e)")
            XCTAssert(false)
        }
    }

    func testStoreEnumerate() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        do {
            let changes: DirectoryChanges = try StoreAPI.session.storeEnumerateChangesToContainer(withIdentifier: NSFileProviderItemIdentifier.rootContainer.rawValue)
            print("CHANGES: \(changes)")
            XCTAssert(true)
        } catch let e {
            print("\(e)")
            XCTAssert(false)
        }
    }
    

//    func testPerformanceExample() {
//        // This is an example of a performance test case.
//        self.measure {
//            do {
//                let dir = try StoreAPI.session.storeItemInfo(withIdentifier: "11")
//                let items = try StoreAPI.session.storeEnumerateItem(withIdentifier: "11", start: 0, num: Int(dir.size))
//                print("\(items.count)")
//                // Put the code you want to measure the time of here.
//                XCTAssert(true)
//            } catch let e {
//                print("\(e)")
//                XCTAssert(false)
//            }
//        }
//    }

}
