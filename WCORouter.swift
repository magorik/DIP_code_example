//
//  WCORouter.swift
//  workerclicks-operatorapp
//
//  Created by Admin on 12/8/17.
//  Copyright © 2017 ForaSoft. All rights reserved.
//

import UIKit

class WCORouter {
    
    enum RouterError: Error {
        case invalidViewController(storyboardViewController: StoryboardViewController, router: WCORouter)
        case invalidAssembly(router: WCORouter)
        case invalidNavigationController(router: WCORouter)
    }
    
    // MARK: Internal Properties
    
    // Navigation controller for all vc in router.
    internal var rootNavigationController: UINavigationController? {
        didSet {
            
        }
    }
    
    // Router showed by this router will be his child router.
    internal var childRouter: WCORouter?
    
    // Router showing by this router will be his parent router.
    internal weak var parentRouter: WCORouter?
    
    // Assembly. Configures view controllers.
    internal var assemblyManager: AssemblyManager?
    
    // MARK: Init Methods & Superclass Overriders

    init(parentRouter: WCORouter?) {
        self.parentRouter = parentRouter
        rootNavigationController = parentRouter?.rootNavigationController
        assemblyManager = parentRouter?.assemblyManager
    }
    
    convenience init(parentRouter: WCORouter, navigationController: UINavigationController) {
        self.init(parentRouter: parentRouter)
        
        rootNavigationController = navigationController
    }
    
    // MARK: Internal Methods
    
    internal func createViewController(from storyboardViewController: StoryboardViewController) -> UIViewController {
        do {
            let viewController = try self.viewController(withStoryboardViewController: storyboardViewController)
            try self.configureViewControllerWithAssembly(viewController)
            return viewController
        } catch RouterError.invalidViewController(let storyboardViewController, let router) {
            fatalError("\(router) can't create view controller with identifier \(storyboardViewController.identifier) from \(storyboardViewController.storyboardName) storyboard")
        } catch RouterError.invalidAssembly(let router) {
            fatalError("\(router) assembly manager is nil")
        } catch {
            fatalError("\(error)")
        }
    }
    
    internal func navigationController(withRoot root: UIViewController) -> UINavigationController {
        return UINavigationController(rootViewController: root)
    }
    
    internal func showRouter(_ router: WCORouter & InitiallyPresentationRouter) {
        do {
            try self.initiallyShowRouter(router)
        } catch RouterError.invalidNavigationController(let router) {
            fatalError("\(router) root navigation controller is nil")
        } catch {
            fatalError("\(error)")
        }
    }
    
    // MARK: Private Methods
    
    private func viewController(withStoryboardViewController storyboardViewController: StoryboardViewController) throws -> UIViewController {
        do {
            let newViewController = try WCOViewController.create(from: storyboardViewController, router: self)
            return newViewController
        } catch {
            throw(RouterError.invalidViewController(storyboardViewController: storyboardViewController, router: self))
        }
    }
    
    private func initiallyShowRouter(_ router: WCORouter & InitiallyPresentationRouter) throws {
        guard let rootNavigationController = self.rootNavigationController else {
            throw(RouterError.invalidNavigationController(router: self))
        }
        
        DispatchQueue.main.async {
            self.childRouter = router
            router.showInitialViewController(navigationController: rootNavigationController)
        }
    }
    
    private func configureViewControllerWithAssembly(_ viewController: UIViewController) throws {
        guard let assemblyManager = self.assemblyManager else {
            throw(RouterError.invalidAssembly(router: self))
        }
        
        assemblyManager.configure(viewController: viewController)
    }
    
}
