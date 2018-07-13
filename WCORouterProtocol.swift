//
//  WCORouterProtocol.swift
//  workerclicks-operatorapp
//
//  Created by Admin on 12/11/17.
//  Copyright © 2017 ForaSoft. All rights reserved.
//

import UIKit

// MARK: Router Protocols

protocol LaunchRouterInput: LoginableRouter {
    
}

protocol LoginRouterInput: InitiallyPresentationRouter {
    func showAuthRouter()
    func showPinViewController(user: UserModel)
}

protocol AuthRouterInput: LoginableRouter, InitiallyPresentationRouter {
    func configure(screenRouterWith navigationController: UINavigationController, viewController: WCOViewController)
    func configure(messageRouterWith navigationController: UINavigationController, viewController: WCOViewController)
    func configure(profileRouterWith navigationController: UINavigationController, viewController: WCOViewController)
}

protocol ScreensRouterInput {
    func showConsultationViewController(user: LocationUserModel)
    func showConsultationViewController(forward: ForwardModel, user: LocationUserModel)
    func showConsultationViewController(location: LocationModel, screen: ScreenModel, user: LocationUserModel)
    func showForwardViewController(screenIdentifier: String)
}

protocol MessageRouterInput {
    func showChatViewController(chatIdentifier: String, userName: String)
    func showConsultationViewController(user: LocationUserModel)
}

protocol ProfileRouterInput: LoginableRouter {
    func showSettingViewControllerWith(loginService: LoginService)
}

// MARK: Common Protocols

protocol InitiallyPresentationRouter {
    func showInitialViewController(navigationController: UINavigationController)
}

protocol LoginableRouter {
    func showLoginRouter()
}
