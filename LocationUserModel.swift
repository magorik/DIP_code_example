//
//  LocationUserModel.swift
//  workerclicks-operatorapp
//
//  Created by Daniil on 17.01.2018.
//  Copyright © 2018 ForaSoft. All rights reserved.
//

import ObjectMapper
import RealmSwift

enum UserStatus: String {
    case busy
    case offline
    case online
    case calling
}

class LocationUserModel: Object, Mappable {
    
    struct Keys {
        static let identifier = "id"
        static let roomIdentifier = "roomId"
        static let screenIdentifier = "userId"
        static let viewingRoom = "viewingRoom"
        static let busyState = "busyState"
        static let connected = "connected"
        static let broadcasting = "broadcasting"
        static let status = "status"
        static let type = "type"
        static let orientation = "orientation"
        static let consultationRequest = "consultationRequest"
        static let proactiveEngagementPossible = "can_proactive_engagement"
        static let userInfo = "userInfo"
    }
    
    // MARK: Properties
    
    @objc dynamic var identifier: String!
    @objc dynamic var roomIdentifier: String!
    @objc dynamic var screenIdentifier: String!
    
    @objc dynamic var busyState: Int = 0
    @objc dynamic var connected: Int = 0
    @objc dynamic var broadcasting: Int = 0
    @objc dynamic var consultationRequest: Bool = false
    @objc dynamic var viewingRoom: String?

    @objc dynamic var status: String?
    @objc dynamic var type: String?
    @objc dynamic var orientation: String?
    
    @objc dynamic var userInfo: UserModel?

    required convenience init?(map: Map) {
        self.init()
        self.commoninit(map: map)
    }
    
    func poluteFromUser(model: UserModel) {
        identifier = model.userIdentifier
        userInfo = model
    }
    
    // MARK: Mappable
    
    func commoninit(map: Map) {
        guard let id = map.JSON[Keys.identifier] else {
            return
        }

        identifier = "\(id)"
        roomIdentifier <- map[Keys.roomIdentifier]
        screenIdentifier <- map[Keys.screenIdentifier]

        busyState <- map[Keys.busyState]
        connected <- map[Keys.connected]
        broadcasting <- map[Keys.broadcasting]
        consultationRequest = ((map.JSON[Keys.consultationRequest] as? [String:Any]) != nil)
        viewingRoom <- map[Keys.viewingRoom]

        status <- map[Keys.status]
        type <- map[Keys.type]
        orientation <- map[Keys.orientation]

        userInfo <- map[Keys.userInfo]
    }
    
    func mapping(map: Map) {
        if !map.JSON.isEmpty {
            guard let id = map.JSON[Keys.identifier], let roomID = map.JSON[Keys.roomIdentifier], let screenID = map.JSON[Keys.screenIdentifier] else {
                return
            }
            identifier = "\(id)"
            roomIdentifier = "\(roomID)"
            screenIdentifier = "\(screenID)"
        } else {
            identifier <- map[Keys.identifier]
            roomIdentifier <- map[Keys.roomIdentifier]
            screenIdentifier <- map[Keys.screenIdentifier]
        }
        busyState <- map[Keys.busyState]
        connected <- map[Keys.connected]
        broadcasting <- map[Keys.broadcasting]
        consultationRequest = ((map.JSON[Keys.consultationRequest] as? [String:Any]) != nil)
        viewingRoom <- map[Keys.viewingRoom]
        
        status <- map[Keys.status]
        type <- map[Keys.type]
        orientation <- map[Keys.orientation]
        
        userInfo <- map[Keys.userInfo]
    }
}
