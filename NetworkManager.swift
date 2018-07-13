//
//  NetworkService.swift
//  workerclicks-operatorapp
//
//  Created by Admin on 12/18/17.
//  Copyright © 2017 ForaSoft. All rights reserved.
//

import Alamofire
import SwiftyJSON

class NetworkManager: RequestAdapter {
    
    typealias NetworkCompletion = ((_ cancelled: Bool, _ error: String?, _ response: [String:Any]?) -> ())
    
    let postQueue = DispatchQueue(label: "", qos: .utility, attributes: [.concurrent])
    let getQueue = DispatchQueue(label: "", qos: .utility, attributes: [.concurrent])
    
    private struct Keys {
        static let apiSecurityToken = ""
        static let userAccessToken = ""
        
        static let error = ""
        static let result = ""
        static let code = ""
        static let message = ""
        
        static let identifier = ""
        static let userIdentifier = ""
        static let roomIdentifier = ""

        static let login = ""
        static let password = ""
        
        static let platform = ""
        static let pushToken = ""
        static let voipToken = ""
    }
    
    private struct Paths {
        struct POST {
            static let login = ""
            static let logout = ""

            static let pushToken = ""
            static let voipPushToken = ""
            
            static let locations = "s"
            static let members = ""
            static let company = ""
            static let info = "
            
            static let declineForward = ""
        }
    }
    
    // MARK: Private Properties
    
    private let infoPlistService = InfoPlistService()
    private let reachability = Reachability()
    
    // MARK: Init Methods & Superclass Overriders
    
    static let shared = NetworkManager()
    
    /// Creates network manager instance with default session setups.
    init() {
        SessionManager.default.session.configuration.requestCachePolicy = .reloadIgnoringCacheData
        SessionManager.default.session.configuration.urlCache = nil
        SessionManager.default.adapter = self
    }
    
    // MARK: Public Methods
    
    func isReachable() -> Bool {
        let status = reachability?.connection
        return (status != Reachability.Connection.none)
    }
    
    // MARK: Login Service
    
    func login(withEmail email: String, password: String, completion: @escaping NetworkCompletion) {
        let parameters: [String : Any] = [Keys.login : email,
                                          Keys.password : password]
        
        _ = postRequest(withMethod: Paths.POST.login, parameters: parameters, accessToken: nil, completion: completion)
    }
    
    func logout(withToken token: String, completion: @escaping NetworkCompletion) {
        let parameters: [String : Any] = [:]
        
        _ = postRequest(withMethod: Paths.POST.logout, parameters: parameters, accessToken: token, completion: completion)
    }
    
    // MARK: Account Methods
    
    func updateAccountInfo(withAccessToken accessToken: String?, completion: @escaping NetworkCompletion) {
        let parameters: [String : Any] = [:]
        
        _ = postRequest(withMethod: Paths.POST.info, parameters: parameters, accessToken: accessToken, completion: completion)
    }
    
    // MARK: Locations Service
    
    func loadLocations(withAccessToken accessToken: String?, completion: @escaping NetworkCompletion) -> URLSessionTask? {
        let parameters: [String : Any] = [:]
        
        return postRequest(withMethod: Paths.POST.locations, parameters: parameters, accessToken: accessToken, completion: completion)
    }
    
    func loadMembers(withAccessToken accessToken: String?, completion: @escaping NetworkCompletion) -> URLSessionTask? {
        let parameters: [String : Any] = [:]
        
        return postRequest(withMethod: Paths.POST.members, parameters: parameters, accessToken: accessToken, completion: completion)
    }
    
    func loadCompany(withAccessToken accessToken: String?, completion: @escaping NetworkCompletion) -> URLSessionTask? {
        let parameters: [String : Any] = [:]
        
        return postRequest(withMethod: Paths.POST.company, parameters: parameters, accessToken: accessToken, completion: completion)
    }
    
    // MARK: Push Notifications Service
    
    func updatePushToken(withAccessToken accessToken: String?, pushToken: String, voipToken: String, completion: @escaping NetworkCompletion) -> URLSessionTask? {
        let parameters: [String : Any] = [Keys.pushToken : pushToken,
                                          Keys.voipToken : voipToken,
                                          Keys.platform : "ios"]
        
        return postRequest(withMethod: Paths.POST.pushToken, parameters: parameters, accessToken: accessToken, completion: completion)
    }
    
    func declineConsultation(withAccessToken accessToken: String?, fromUserIdentifier: String, toUserIdentifier: String, roomIdentifier: String, message: String) -> URLSessionTask? {
        let parameters: [String : Any] = [Keys.identifier : toUserIdentifier,
                                          Keys.userIdentifier : fromUserIdentifier,
                                          Keys.roomIdentifier : roomIdentifier,
                                          Keys.message: message]
        
        return postRequest(withMethod: Paths.POST.declineForward, parameters: parameters, accessToken: accessToken, completion:{ _,_,_ in })
    }
    
    // MARK: Private Methods
    
    // MARK: Make Request
    
    private func methodPath(withMethod method: String) -> String {
        var urlString = infoPlistService.serverURL() + method
        if method == Paths.POST.declineForward {
            urlString = infoPlistService.serverURL().replacingOccurrences(of: "com/", with: "com:") + infoPlistService.serverPort() + method
        }
        return urlString
    }
    
    private func getRequest(withMethod method: String, parameters: [String : Any], accessToken: String?, completion: @escaping NetworkCompletion) -> URLSessionTask? {
        #if DEBUG
            print("\(Date()) GET \(method) with \(parameters)")
        #endif
        
        return fireRequest(withMethod: method, type: .get, parameters: parameters, accessToken: accessToken, queue: getQueue, completion: completion)
    }
    
    private func postRequest(withMethod method: String, parameters: [String : Any], accessToken: String?, completion: @escaping NetworkCompletion) -> URLSessionTask? {
        #if DEBUG
            print("\(Date()) POST \(method) with \(parameters)")
        #endif
        
        return fireRequest(withMethod: method, type: .post, parameters: parameters, accessToken: accessToken, queue: postQueue, completion: completion)
    }
    
    private func fireRequest(withMethod method: String, type: HTTPMethod, parameters: [String : Any], accessToken: String?, queue: DispatchQueue, completion: @escaping NetworkCompletion) -> URLSessionTask? {
        let urlString = methodPath(withMethod: method)
        let url = URL(string: urlString)
        var headers = [Keys.apiSecurityToken : infoPlistService.securityToken()]
        if let token = accessToken {
            headers[Keys.userAccessToken] = token
        }
        
        let request = Alamofire.request(url!, method: type, parameters: parameters, encoding: JSONEncoding.default, headers: headers).response(queue: queue) { [weak self] (result) in
            self?.perform(completion: completion, data: result.data, response: result.response, error: result.error, method: method)
        }
        return request.task
    }
    
    // MARK: Process Response
    
    private func perform(completion: NetworkCompletion, data: Data?, response: URLResponse?, error: Error?, method: String) {
        #if DEBUG
            print("\(Date()) complete \(method)")
        #endif
        
        let serializedData = self.serializedData(fromData: data)
        let errorMessage = self.errorMessage(withSerializedData: serializedData, response: response, error: error)
        
        var isCancelled = false
        if let errorWithCode = error as NSError? {
            isCancelled = (errorWithCode.code == NSURLErrorCancelled)
        }
        
        completion(isCancelled, errorMessage, serializedData)
    }
    
    private func serializedData(fromData data: Data?) -> [String:Any]? {
        if data != nil {
            if let serializedData = try? JSONSerialization.jsonObject(with: data!, options: []) {
                if let serializedDictionary = serializedData as? [String:Any] {
                    return serializedDictionary
                } else {
                    #if DEBUG
                        print("DEBUG LOG: 'Request response is \(serializedData). Won't be processed.'")
                    #endif
                }
            } else if let serializedString = String.init(data: data!, encoding: .utf8) {
                #if DEBUG
                    print("DEBUG LOG: 'Request response is \(serializedString). Won't be processed.'")
                #endif
            }
        }
        
        return nil
    }
    
    private func errorMessage(withSerializedData serializedData: [String:Any]?, response: URLResponse?, error: Error?) -> String? {
        if !isReachable() {
            return AppTexts.Errors.Texts.internetNotReachable()
        }
        
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 403 {
            return AppTexts.Errors.Texts.accessTokenExpired()
        } else if statusCode == 405 {
            return AppTexts.Errors.Texts.acountDisabled()
        }
        
        if let code = serializedData?[Keys.code] as? Int, code >= 300, let message = serializedData?[Keys.message] as? String, !message.isEmpty {
            return message
        }
        
        if statusCode >= 300 {
            return AppTexts.Errors.Texts.requestTimedOut()
        } else {
            return nil
        }
    }
    
    // MARK: Protocols Implementation
    
    // MARK: RequestAdapter
    
    internal func adapt(_ urlRequest: URLRequest) throws -> URLRequest {
        var request = urlRequest
        request.cachePolicy = .reloadIgnoringCacheData
        request.timeoutInterval = 30.0
        return request
    }
    
}
