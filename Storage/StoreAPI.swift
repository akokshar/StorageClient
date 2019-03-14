//
//  StorageConnection.swift
//  StorageClient
//
//  Created by Koksharov Alexandr on 17/01/2019.
//  Copyright © 2019 Koksharov Alexandr. All rights reserved.
//

import Foundation
import MobileCoreServices

struct StoreAPIError: Error, Codable {
    let errorDescription: String
    
    init(description: String) {
        self.errorDescription = description
    }

    var localizedDescription: String {
        return errorDescription
    }
}

struct FileItemInfo: Codable {
    let id: Int64
    let name: String
    let ctype: String
    let size: Int64
    let mdate: Int64
    let cdate: Int64
    
    var identifier: String {
        return String(id)
    }
    
    var uti: String {
        if ctype.lowercased() == "folder"  {
            return kUTTypeFolder as String
        }
        guard let uti = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassMIMEType,
            NSString(string: ctype), nil)?.takeUnretainedValue() else {
                return kUTTypeData as String
        }
        if UTTypeIsDynamic(uti) {
            return kUTTypeData as String
        }
        return uti as String
    }

    var modificationDate: Date {
        return Date(timeIntervalSince1970: TimeInterval(mdate))
    }
    
    var createDate: Date {
        return Date(timeIntervalSince1970: TimeInterval(cdate))
    }
    
    var isDirectory: Bool {
        return uti == kUTTypeFolder as String
    }
}

struct DirectoryChanges: Codable {
    let new: [FileItemInfo]
    let erase: [Int64]
    let anchor: Int64
    let remain: Int
    let size: Int64
}

private class StoreServer {
    private let url: URL
    
    static let server: StoreServer = {
        return StoreServer()
    }()
    
    private init() {
        // get url from shared config
        self.url = URL(string: "http://localhost:8080/store/")!
    }
 
    func urlRequest(_ method: String = "GET", withQueryItems queryItems: [URLQueryItem] = []) -> URLRequest {
        // optional unwrap should not fail, assuming that correct URL was set in init()
        var urlComponents = URLComponents(url: self.url, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = queryItems
        
        // same as above, should not fail
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = method
        return request
    }
    
    func decodeJsonResponse<T: Codable>(data: Data?, httpResponse: HTTPURLResponse, completion: (T?, StoreAPIError?)->Void) {
        var result: T? = nil
        var resultError: StoreAPIError? = nil
        defer {
            completion(result, resultError)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            resultError = StoreAPIError(description: "Received '\(httpResponse.statusCode)' error code")
            return
        }
        guard let data = data else {
            resultError = StoreAPIError(description: "Received empty data")
            return
        }
        let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
        guard contentType == "application/json" else {
            resultError = StoreAPIError(description: "Unsupported content-type")
            return
        }
        do {
            result = try JSONDecoder().decode(T.self, from: data)
        } catch {
            resultError = StoreAPIError(description: "JSON decode fail")
        }
    }
}

class StoreAPI {
    private let server = StoreServer.server
    private let urlSession: URLSession
    private let sessionOperationOueue: OperationQueue
    
    static let session: StoreAPI = {
        return StoreAPI()
    }()
    
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.allowsCellularAccess = true
        config.httpShouldUsePipelining = true
        config.waitsForConnectivity = false
        config.isDiscretionary = false
        self.sessionOperationOueue = OperationQueue()
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: sessionOperationOueue)
    }
    
    private func storeRequestInfo<T: Codable>(withRequest request: URLRequest) throws -> T {
        // [NSProcessInfo performExpiringActivityWithReason:usingBlock:]
        print("URLRequest: '\(request)'")
        var result: T? = nil
        var resultError: StoreAPIError? = nil
        let semaphore = DispatchSemaphore(value: 0)
        let task = urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                resultError = StoreAPIError(description: error.localizedDescription)
                return
            }
            let httpResponse = response as! HTTPURLResponse
            self.server.decodeJsonResponse(data: data, httpResponse: httpResponse) { (obj: T?, error: StoreAPIError?) in
                result = obj
                resultError = error
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        if let error = resultError {
            throw error
        }
        return result!
    }
    
    func storeItemInfo(withIdentifier identifier: String) throws -> FileItemInfo {
        let request = server.urlRequest(withQueryItems: [
            URLQueryItem(name: "id", value: identifier),
            URLQueryItem(name: "cmd", value: "info")
        ])
        do {
            return try storeRequestInfo(withRequest: request)
        } catch let e {
            throw e
        }
    }
    
    func storeEnumerateChangesToContainer(withIdentifier identifier: String, from anchor: Int64 = 0, num count: Int = 128) throws -> DirectoryChanges {
        let request = server.urlRequest(withQueryItems: [
            URLQueryItem(name: "id", value: identifier),
            URLQueryItem(name: "cmd", value: "list"),
            URLQueryItem(name: "anchor", value: String(anchor)),
            URLQueryItem(name: "count", value: String(count))
        ])
        do {
            return try storeRequestInfo(withRequest: request)
        } catch let e {
            throw e
        }
    }
    
    func storeCreateDirectory(withName name: String, parentIdentifier parentId: String) throws -> FileItemInfo {
        let request = server.urlRequest("POST", withQueryItems: [
            URLQueryItem(name: "parentId", value: parentId),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "cmd", value: "createDir"),
        ])
        do {
            return try storeRequestInfo(withRequest: request)
        } catch let e {
            throw e
        }
    }
    
}

class StoreBackgroundSession: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let server: StoreServer = StoreServer.server
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "lex.home.StorageClient")
        config.sharedContainerIdentifier = "group.lex.home.StorageClient"
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private override init() {
        super.init()
    }
    
    public static let backgroundSession = StoreBackgroundSession()
    
    func uploadTask(withId taskId: String, forFileAt fileURL: URL, name: String, parentId: String) -> URLSessionUploadTask {
        let request = server.urlRequest("POST", withQueryItems: [
            URLQueryItem(name: "parentId", value: parentId),
            URLQueryItem(name: "name", value: name)
        ])
        let task = self.session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = taskId
        return task
    }
    
    func dataTask(withId taskId: String, toCreateDirectory name: String, parentId: String, delay: Date? = nil) -> URLSessionDataTask {
        let request = server.urlRequest("POST", withQueryItems: [
            URLQueryItem(name: "cmd", value: "createDir"),
            URLQueryItem(name: "parentId", value: parentId),
            URLQueryItem(name: "name", value: name)
            ])
        
        let task = self.session.dataTask(with: request)
        task.taskDescription = taskId
        task.earliestBeginDate = delay
        return task
    }
    
    func downloadTask(withId taskId: String, forItem itemId: String) -> URLSessionDownloadTask {
        let request = server.urlRequest(withQueryItems: [
            URLQueryItem(name: "id", value: itemId)
            ])
        let task = self.session.downloadTask(with: request)
        task.taskDescription = taskId
        return task
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        NSLog(">>>>>>>>>>>StoreUploadSession.urlSessionDidFinishEvents '\(session.configuration.identifier ?? "*NOID*")")
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let taskId = dataTask.taskDescription else {
            return
        }
        let httpResponse = dataTask.response as! HTTPURLResponse
        server.decodeJsonResponse(data: data, httpResponse: httpResponse) { (itemInfo: FileItemInfo?, error: StoreAPIError?) in
            if let error = error {
                StoreDB.db.uploadTask(withId: taskId, completeWithError: error)
            } else {
                StoreDB.db.uploadTask(withId: taskId, completeWithServerItem: itemInfo!)
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let itemId = downloadTask.taskDescription else {
            return
        }
        
        NSLog(">>>>>>>>>>>didFinishDownloadingTo '\(itemId)")
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else {
            return
        }

        guard let taskId = task.taskDescription else {
            return
        }
        StoreDB.db.uploadTask(withId: taskId, completeWithError: StoreAPIError(description: error.localizedDescription))
    }
}
