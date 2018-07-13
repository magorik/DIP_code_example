//
//  ChatService.swift
//  
//
//  Created by Efimenko George on 1/29/18.
//  Copyright © 2018 Efimenko George. All rights reserved.
//

import Foundation

import RxSwift
import ObjectMapper
import RealmSwift

// MARK: Public Methods Protocols

private protocol PublicMethods {
    func requestUnreadStatus()
    func requestLastMessageWith(completion: @escaping ([String: Any])->())
    func sendMessage(_ userIdentifier: String, text: String)
    func requestMessageWith(userIdentifier: String, completion: @escaping ([MessageModel]?)->())
    func requestMoreMessageWith(userIdentifier: String, completion: @escaping ([MessageModel])->())
    func markReadMessagesWith(identifiers: [String], userIdentifier: String)
    func fetchCachedMessages()
    func isReachable() -> Bool
    
    func updateLastMessages(messages: [String: Any])
}

class ChatService {
    
    private struct Keys {
        static let message = "message"
        static let commonRoomIdentifier = "commonRoom"
        static let roomIdentifier = "roomId"
        static let userIdentifier = "userId"
        static let dialogs = "dialogs"
        static let members = "members"
        static let rooms = "rooms"
    }
    
    // MARK: Public Properties
    
    // Unread count for each chat.
    private(set) var ureadStatus = Variable<[String : Any]>([:])
    
    // Last message for each chat.
    private(set) var lastMessages = Variable<[String : MessageModel]>([:])
    
    // Saved no sended message for each chat.
    private(set) var savedMessages = Variable<[String : String]>([:])
    
    // New message comming for new chat.
    private(set) var newMessage = Variable<[String : MessageModel]>([:])
    
    // All messages for display. Main goal - messages.last <-> last
    private(set) var messages = Variable<[String : [MessageModel]]>([:])
    
    private(set) var roomAdded = Variable<Bool>(false)
    
    // MARK: Private Properties

    private let socketManager = SocketManager.shared
    private let networkManager = NetworkManager.shared
    private let audioManager = AudioManager.shared

    private let streamingService: StreamingService!

    private let disposeBag = DisposeBag()
    private let realm = try! Realm()
    
    private var currentUserIdentifier: String!
    private var currentCompanyIdentifier: String!

    private var isMessageСorresponds: [String: Bool] = [:]
    
    // MARK: Init Methods & Superclass Overriders

    init(identifier: String, companyIdentifier: String, streaming: StreamingService) {
        currentCompanyIdentifier = companyIdentifier
        currentUserIdentifier = identifier
        streamingService = streaming
        
        subscribeToSocketEvents()
    }
    
    deinit {
        clearProperties()
    }
}

// MARK: Public Methods

extension ChatService: PublicMethods {
    
    /// Returns network reachability.
    func isReachable() -> Bool {
        return networkManager.isReachable() && socketManager.isSocketConnected()
    }
    
    /// Request unread status
    func requestUnreadStatus() {
        socketManager.getUnreadMessageStatus(withIdentifier: currentCompanyIdentifier) { [weak self] (data) in
                self?.proceesUnreadStatus(data)
        }
    }

    /// Update last showed message
    func updateLastMessages(messages: [String: Any]) {
        var lastMessage: [String: MessageModel] = [:]
        _ = messages.flatMap({ lastMessage[$0.key] = didReceiveLastMessage(data: $0.value as? [String : Any], userIdentifier: $0.key)})
        
        lastMessages.value = lastMessage
    }
    
    /// Request last message for each chat
    ///
    func requestLastMessageWith(completion: @escaping ([String: Any])->()) {
        socketManager.getLastMessages(currentCompanyIdentifier) { (data) in
            var allMessages: [String: Any] = [:]
            if let data = data?[Keys.dialogs] as? [String: Any]  {
                if let rooms = data[Keys.rooms] as? [String: Any] {
                    allMessages.add(other: rooms)
                }
                if let members = data[Keys.members] as? [String: Any] {
                    allMessages.add(other: members)
                }
            }
            completion(allMessages)
        }
    }
    
    /// Send a message to user
    ///
    /// - Parameters:
    ///   - userIdentifier: user to send
    ///   - text: message
    func sendMessage(_ userIdentifier: String, text: String) {
        let sendKey = userIdentifier == currentCompanyIdentifier ? Keys.roomIdentifier : Keys.userIdentifier
        didReceiveMessage(data: [messageWith(text: text)], userIdentifier: userIdentifier)
        
        socketManager.sendMessage(sendKey, userIdentifier, message: text)
    }
    
    /// Request messages from one user
    ///
    /// - Parameters:
    ///   - userIdentifier: user from
    ///   - completion: array of messagemodel
    func requestMessageWith(userIdentifier: String, completion: @escaping ([MessageModel]?)->()) {
        let sendKey = userIdentifier == currentCompanyIdentifier ? Keys.roomIdentifier : Keys.userIdentifier
        computeMessageCorresponding(userIdentifier: userIdentifier)
        
        // Messages no maching -> update messages
        socketManager.getMessages(sendKey, userIdentifier, limit: 45) { [weak self] (data) in
            self?.didReceiveMessages(data: data, userIdentifier: userIdentifier, completion: completion)
        }
        
        // Pollute with olderst value
        completion(messages.value[userIdentifier])
    }
    
    /// Request more message when top is reached
    ///
    /// - Parameters:
    ///   - userIdentifier: user from
    ///   - completion: array of messagemodel
    func requestMoreMessageWith(userIdentifier: String , completion: @escaping ([MessageModel])->()) {
        let sendKey = userIdentifier == currentCompanyIdentifier ? Keys.roomIdentifier : Keys.userIdentifier
        let timeStamp = messages.value[userIdentifier]?.last?.timestamp
        
        socketManager.getMessages(sendKey, userIdentifier, limit: 45, lastTime: timeStamp) { [weak self] (data) in
            self?.didReceiveMoreMessages(data: data, userIdentifier: userIdentifier, completion: completion)
        }
    }
    
    /// Mark messages readed
    ///
    /// - Parameters:
    ///   - identifiers: messages identifiers
    ///   - userIdentifier: user
    func markReadMessagesWith(identifiers: [String], userIdentifier: String) {
        socketManager.markReaded(messageIdentifiers: identifiers)
        restoreUnreadStatusFor(userIdentifier: userIdentifier)
        requestUnreadStatus()
    }
    
    /// Get cashed messages
    func fetchCachedMessages() {
        fetchCached()
    }
}

// MARK: Sockets Methods

private extension ChatService {
    func subscribeToSocketEvents() {
        _ = socketManager.roomAdded.asObservable().subscribe(onNext: { [weak self] connected in
            if connected {
                self?.requestUnreadStatus()
            }
        })
        
        _ = socketManager.textMessageDidRecieve.asObservable().subscribe({ [weak self] data in
            guard let strongSelf = self else {
                return
            }
            if let responseModel = data.element {
                let dataModel = Mapper<MessageModel>().map(JSONObject: responseModel)
                
                if let userIdentifier = dataModel?.sender?.screenIdentifier, dataModel?.receiver != nil  {
                    strongSelf.didReceiveMessage(data: [(dataModel?.toJSON())!], userIdentifier: userIdentifier)
                    strongSelf.requestUnreadStatus()
                } else {
                    strongSelf.didReceiveMessage(data: [(dataModel?.toJSON())!], userIdentifier: strongSelf.currentCompanyIdentifier)
                    strongSelf.requestUnreadStatus()
                }
                switch strongSelf.streamingService.streamingState.value {
                case .finished, .error(_), .unknown:
                    strongSelf.audioManager.playMessageSound()
                    break
                case .started, .initiated:
                    return
                }
            }
        }).disposed(by: disposeBag)
        
        _ = socketManager.roomAdded.asObservable().bind(to: roomAdded)
    }
}

// MARK: Support Methods

private extension ChatService {
    func computeMessageCorresponding(userIdentifier: String) {
        var corresponds = false
        // Count > 8 - Fix situation:
        // User dont have cached messages and have messages in server
        // Recevie message from server
        // Open chat -> timestams is equal, but history don't load
        if let count = messages.value[userIdentifier]?.count, count > 8 {
            if let lastMessage = lastMessages.value[userIdentifier], let message = messages.value[userIdentifier]?.first {
                if lastMessage.timestamp == message.timestamp {
                    corresponds = true
                }
            }
        }
        
        isMessageСorresponds[userIdentifier] = corresponds
    }
    
    func clearProperties() {
        ureadStatus.value.removeAll()
        messages.value.removeAll()
        lastMessages.value.removeAll()
    }
    
    func messageWith(text: String) -> [String : Any] {
        return [
            MessageModel.Keys.messageIdentifier : currentUserIdentifier,
            MessageModel.Keys.message : text,
            MessageModel.Keys.timestamp : Date().timeIntervalSince1970*1000,
            MessageModel.Keys.sender : [
                LocationUserModel.Keys.identifier : currentUserIdentifier,
                LocationUserModel.Keys.screenIdentifier : currentUserIdentifier
                ]
            ]
    }
    
    func proceesUnreadStatus(_ data: [String : Any]?) {
        guard var dataModel = data else {
            return
        }
        
        if let commonUnread = dataModel[Keys.commonRoomIdentifier] as? Int, commonUnread > 0 {
            dataModel.removeValue(forKey: Keys.commonRoomIdentifier)
            dataModel[currentCompanyIdentifier] = commonUnread
        }
        
        ureadStatus.value = dataModel
    }
    
    func prepareMessages(data: [[String : Any]], userIdentifier: String) -> [MessageModel] {
        let messagesModel = Mapper<MessageModel>().mapArray(JSONArray: data)
        
        let filterMessages = messagesModel.filter({$0.room == nil || $0.room?.identifier == userIdentifier})
        _ = filterMessages.map({$0.isOutgoing = ($0.sender?.screenIdentifier == currentUserIdentifier)})
        
        return filterMessages
    }
    
    func didReceiveLastMessage(data: [String :Any]?, userIdentifier: String) -> MessageModel? {
        if let dataModel = data {
            let filterMessages = prepareMessages(data: [dataModel], userIdentifier: userIdentifier)
            
            if let lastMessage = filterMessages.first {
                //lastMessages.value[userIdentifier] = lastMessage
                computeMessageCorresponding(userIdentifier: userIdentifier)
                return lastMessage
            } 
        }
        return nil
    }
    
    func didReceiveMessages(data: [[String :Any]]?, userIdentifier: String, completion: ([MessageModel])->()) {
        if let dataModel = data {
            let filterMessages = prepareMessages(data: dataModel, userIdentifier: userIdentifier)
            let messagesForSave = prepareMessages(data: dataModel, userIdentifier: userIdentifier)

            completion(filterMessages)
            messages.value[userIdentifier] = filterMessages
            computeMessageCorresponding(userIdentifier: userIdentifier)
            _ = messagesForSave.flatMap({$0.readed = 1})
            save(messagesModel: messagesForSave.flatMap({$0.toJSON()}), userIdentifier)
        }
    }
    
    func didReceiveMoreMessages(data: [[String :Any]]?, userIdentifier: String, completion: ([MessageModel])->()) {
        if let dataModel = data {
            let filterMessages = prepareMessages(data: dataModel, userIdentifier: userIdentifier)
            
           
            if var existMessages = messages.value[userIdentifier] {
                existMessages += filterMessages
                messages.value[userIdentifier] = existMessages
                completion(existMessages)
            } else {
                completion([])
            }
        }
    }
    
    func didReceiveMessage(data: [[String :Any]]?, userIdentifier: String) {
        if let dataModel = data {
            let filterMessages = prepareMessages(data: dataModel, userIdentifier: userIdentifier)

            if let lastMessage = filterMessages.first {
                newMessage.value = [userIdentifier : lastMessage]
                newMessage.value = [:]
                if var existMessages = messages.value[userIdentifier] {
                    existMessages.insert(lastMessage, at: 0)
                    messages.value[userIdentifier] = existMessages
                } else {
                    messages.value[userIdentifier] = [lastMessage]
                }
                
                lastMessages.value[userIdentifier] = lastMessage
                computeMessageCorresponding(userIdentifier: userIdentifier)
            }
        }
    }
}

//MARK: Realm Methods

private extension ChatService {
    func restoreUnreadStatusFor(userIdentifier: String) {
        if let messageObject = self.realm.objects(MessageRealmModel.self).filter({$0.chatIdentifier == userIdentifier}).first {
            try! realm.write {
                messageObject.unreadCount = 0
            }
        }
    }
    
    func save(messagesModel: [[String :Any]], _ userIdentifier: String) {
        let maxIndex = messagesModel.count > 45 ? 45 : messagesModel.count
        
        let realmMessage = MessageRealmModel(JSON: [
            MessageRealmModel.Keys.chatIdentifier : userIdentifier,
            MessageRealmModel.Keys.message : Array(messagesModel[..<maxIndex]),
            MessageRealmModel.Keys.unreadCount : ureadStatus.value[userIdentifier] ?? 0,
            MessageRealmModel.Keys.lastMessage : lastMessages.value[userIdentifier]?.toJSON() ?? [:]
            ])
        
        try! self.realm.write {
            self.realm.delete(self.realm.objects(MessageRealmModel.self).filter({$0.chatIdentifier == userIdentifier}))
        }
        try! self.realm.write {
            self.realm.add(realmMessage!)
        }
    }
    
    func fetchCached() {
        DispatchQueue.main.async {
            let cachedMessages = self.realm.objects(MessageRealmModel.self)

            try! self.realm.write {
                var lastObject: [String: MessageModel] = [:]
                var unread: [String: Any] = [:]
                for object in Array(cachedMessages) {
                    let json = object.toJSON()
                    if let messageModel = json[MessageRealmModel.Keys.message] as? [[String : Any]] {
                        let mappedObjects = Mapper<MessageModel>().mapArray(JSONArray: messageModel)
                        _ = mappedObjects.map({$0.isOutgoing = ($0.sender?.screenIdentifier == self.currentUserIdentifier)})
                        
                        self.messages.value[object.chatIdentifier] = mappedObjects
                    }
                   unread[object.chatIdentifier] = object.unreadCount
                    
                    if let last = json[MessageRealmModel.Keys.lastMessage] as? [String : Any] {
                         lastObject[object.chatIdentifier] = Mapper<MessageModel>().map(JSON: last)
                    }
                }
            }
        }
    }
}
