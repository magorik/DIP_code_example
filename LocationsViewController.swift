//
//  LocationsViewController.swift
//
//
//  Created by Efimenko George on 12/20/17.
//  Copyright © 2017 Efimenko George. All rights reserved.
//

import UIKit

import RxSwift
import RxAppState

class LocationsViewController: WCOViewController {
    
    override var prefersStatusBarHidden: Bool {
        return false
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }
    
    // MARK: Interface Builder Properties
    
    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var tableViewModel: LocationsTableViewModel!
    
    // MARK: Private Properties
    
    private let refreshControl = UIRefreshControl()
    private weak var emptyView: EmptyPlaceholderView?
    private let disposeBag = DisposeBag()
    
    private var loginService: LoginService!
    private var permissionsService: PermissionsService!
    private var locationService: LocationsService!
    private var callService: CallService!
    private var streamingService: StreamingService!

    private var launched = false
    private var needRefreshing = false
    
    // MARK: Init Methods & Superclass Overriders
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureTableView()
        subscribeForUpdates()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
                
        configureNavigationBar()
        
        if !launched {
            launched = true
            refreshControl.beginRefreshing()
            locationService.requestLocations()
        }

        if needRefreshing {
            tableView.contentOffset = CGPoint(x: 0, y: 0)
            refreshControl.beginRefreshing()
            tableView.contentOffset = CGPoint(x: 0, y: -refreshControl.bounds.size.height)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if refreshControl.isRefreshing == true {
            needRefreshing = true
            refreshControl.endRefreshing()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        emptyView?.frame = CGRect(x: 0.0, y: 0.0, width: view.bounds.width, height: view.bounds.height)
        tableViewModel.configure(withBackgroundColor: view.backgroundColor)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func inject(propertiesWithAssembly assembly: AssemblyManager) {
        loginService = assembly.loginService
        permissionsService = assembly.permissionsService
        locationService = assembly.locationService
        callService = assembly.callService
        streamingService = assembly.streamingService
    }
    
    // MARK: Reactive Properties
    
    private func subscribeForUpdates() {
        UIApplication.shared.rx.applicationDidBecomeActive.subscribe(onNext: { [weak self] _ in
            self?.checkForwardRequest()
        }).disposed(by: disposeBag)
        
          _ = locationService.connected.asObservable().subscribe(onNext: { [weak self] connected in
            guard let strongSelf = self else {
                return
            }
            switch connected {
                case true:
                    strongSelf.locationService.requestLocations()
                case false:
                    strongSelf.hideIncomingCallRequestView()
            }
            }).disposed(by: disposeBag)
        
        _ = locationService.locations.asObservable().subscribe(onNext: { [weak self] locations in
            guard let strongSelf = self else {
                return
            }
            if let locationModels = locations, strongSelf.locationService.serverReachable() {
                DispatchQueue.main.async {
                    strongSelf.tableViewModel.locations = locationModels
                    strongSelf.configureEmptyView(hidden: (locationModels.count > 0))
                }
            }
        }).disposed(by: disposeBag)
        
        _ = locationService.requestError.asObservable().subscribe(onNext: { [weak self] requestError in
            DispatchQueue.main.async {
                guard let message = requestError else {
                    return
                }
                
                if let alert = self?.alert(withTitle: AppTexts.Errors.Titles.errorOccurred(), message: message), (self?.isViewLoaded ?? false) && self?.view.window != nil {
                    self?.presentAlert(alert)
                } else {
                    self?.refreshControl.endRefreshing()
                    self?.needRefreshing = false
                    self?.configureEmptyView(hidden: (self?.tableViewModel.locations.count != 0))
                }
            }
        }).disposed(by: disposeBag)
        
        _ = locationService.userForScreen.asObservable().subscribe(onNext: { [weak self] userForScreen in
            if let users = userForScreen {
                DispatchQueue.main.async {
                    self?.tableViewModel.userForScreen = users
                    self?.checkForwardRequest()
                }
            }
        }).disposed(by: disposeBag)
        
        _ = locationService.requestedUserForScreen.asObservable().subscribe(onNext: { [weak self] requestedUserForScreen in
            if let users = requestedUserForScreen {
                DispatchQueue.main.async {
                    self?.refreshControl.perform(#selector(UIRefreshControl.endRefreshing), with: nil, afterDelay: 0)
                    self?.needRefreshing = false
                    self?.tableViewModel.requestedUserForScreen = users
                }
            }
        }).disposed(by: disposeBag)
        
        _ = tableViewModel?.selectedElements.asObservable().subscribe(onNext: { [weak self] selectedElements in
            if let location = selectedElements?.location, let screen = selectedElements?.screen, let user = selectedElements?.locationUser, let status = selectedElements?.screenStatus {
                DispatchQueue.main.async {
                    self?.checkConsultationPossible(location: location, screen: screen, user: user, screenStatus: status)
                }
            }
        }).disposed(by: disposeBag)
        
        _ = callService.forwardRequest.asObservable().subscribe(onNext: { [weak self] tuple in
            if tuple != nil {
                DispatchQueue.main.async {
                    self?.hideIncomingCallRequestView()
                }
            }
        }).disposed(by: disposeBag)
        
        _ = locationService.forwardRequest.asObservable().subscribe(onNext: { [weak self] tuple in
            DispatchQueue.main.async {
                if let properties = tuple, self?.callService.forwardRequest.value == nil {
                    if let callAvailable = self?.checkAvailabilityOfIncomingCall(), callAvailable == true {
                        self?.forwardRequestArrived(forward: properties.forward, forwardUser: properties.forwardUser, userName: properties.forwardUserName, screenName: properties.forwardScreenName)
                    } else {
                        self?.declineForward(forward: properties.forward, forwardUser: properties.forwardUser)
                    }
                } else {
                    self?.hideIncomingCallRequestView()
                }
            }
        }).disposed(by: disposeBag)
        
        _ = locationService.callRequest.asObservable().subscribe(onNext: { [weak self] tuple in
            DispatchQueue.main.async {
                if let properties = tuple {
                    if let callAvailable = self?.checkAvailabilityOfIncomingCall(), callAvailable == true {
                        self?.callRequestArrived(callUser: properties.callUser, userName: properties.callUserName)
                    } else {
                        self?.declineCall(callUser: properties.callUser)
                    }
                } else {
                    self?.hideIncomingCallRequestView()
                }
            }
        }).disposed(by: disposeBag)
        
        _ = streamingService.outgoingCallDeclined.asObservable().subscribe(onNext: { [weak self] user in
            if user != nil {
                self?.hideIncomingCallRequestView()
            }
        }).disposed(by: disposeBag)
    }
    
    // MARK: Configure Views
    
    private func configureTableView() {
        tableViewModel.configure(withBackgroundColor: view.backgroundColor)
        tableView.addSubview(refreshControl)
        
        refreshControl.addTarget(self, action:#selector(handleRefresh(_:)), for: UIControlEvents.valueChanged)
        refreshControl.tintColor = AppColors.Backgrounds.darkColor()
    }
    
    private func configureNavigationBar() {
        navigationItem.title = AppTexts.TitleTexts.locationsTitle()
        
        navigationController?.navigationBar.titleTextAttributes = AppFonts.Texts.navigationBarFontAttributes()
        navigationController?.setNavigationBarHidden(false, animated: true)
    }
    
    private func configureEmptyView(hidden: Bool) {
        if let emptyLocationView = emptyView {
            emptyLocationView.removeFromSuperview()
        }
        
        if !hidden {
            let emptyLocationView = EmptyPlaceholderView(frame: CGRect(x: 0.0, y: 0.0, width: view.bounds.width, height: view.bounds.height))
            emptyLocationView.configureForLocations(withUserRole: loginService.loadUserModel()?.userRole)
            view.addSubview(emptyLocationView)
            emptyView = emptyLocationView
            refreshControl.endRefreshing()
            needRefreshing = false
        }
    }
    
    // MARK: Forward
    
    private func checkForwardRequest() {
        if let forwardRequest = callService.forwardRequest.value {
            acceptForward(forward: forwardRequest.forward, forwardUser: forwardRequest.forwardUser)
            callService.forwardRequest.value = nil
        }
    }
    
    private func checkForwardPossible(forward: ForwardModel, forwardUser: LocationUserModel) {
        if locationService.serverReachable() {
            hideIncomingCallRequestView()
            showConsultation(forward: forward, user: forwardUser)
        } else {
            if let alert = alert(withTitle: AppTexts.Errors.Titles.errorOccurred(), message: AppTexts.Errors.Texts.internetNotReachable()) {
                presentAlert(alert)
            }
        }
    }
    
    private func checkCallPossible(callUser: LocationUserModel) {
        if locationService.serverReachable() {
            hideIncomingCallRequestView()
            showCall(user: callUser)
        } else {
            if let alert = alert(withTitle: AppTexts.Errors.Titles.errorOccurred(), message: AppTexts.Errors.Texts.internetNotReachable()) {
                presentAlert(alert)
            }
        }
    }
    
    private func acceptForward(forward: ForwardModel, forwardUser: LocationUserModel) {
        checkMediaPermissions { [weak self] (granted) in
            if granted {
                self?.checkForwardPossible(forward: forward, forwardUser: forwardUser)
            } else {
                self?.showPermissionAlert()
            }
        }
    }
    
    private func acceptCall(callUser: LocationUserModel) {
        checkMediaPermissions { [weak self] (granted) in
            if granted {
                self?.checkCallPossible(callUser: callUser)
            } else {
                self?.showPermissionAlert()
            }
        }
    }
    
    private func declineForward(forward: ForwardModel, forwardUser: LocationUserModel) {
        if locationService.serverReachable() {
            hideIncomingCallRequestView()
            locationService.declineForward(forward: forward)
        } else {
            if let alert = alert(withTitle: AppTexts.Errors.Titles.errorOccurred(), message: AppTexts.Errors.Texts.internetNotReachable()) {
                presentAlert(alert)
            }
        }
    }
    
    private func declineCall(callUser: LocationUserModel) {
        if locationService.serverReachable() {
            hideIncomingCallRequestView()
            if let _ = callUser.roomIdentifier {
                locationService.declineCall(callUser: callUser)
            }
        } else {
            if let alert = alert(withTitle: AppTexts.Errors.Titles.errorOccurred(), message: AppTexts.Errors.Texts.internetNotReachable()) {
                presentAlert(alert)
            }
        }
    }
    
    // Return false if consulation is started, means that you can't accept incoming call or forward
    private func checkAvailabilityOfIncomingCall() -> Bool {
        switch streamingService.streamingState.value {
        case .finished, .unknown:
            return true
        default:
            return false
        }
    }
    
    private func forwardRequestArrived(forward: ForwardModel, forwardUser: LocationUserModel, userName: String?, screenName: String) {
        showIncomingCallRequestView(from: userName, roomName: screenName, cancelAction: { [weak self] in
            self?.declineForward(forward: forward, forwardUser: forwardUser)
            }, answerAction: { [weak self] in
                self?.acceptForward(forward: forward, forwardUser: forwardUser)
        })
    }
    
    private func callRequestArrived(callUser: LocationUserModel, userName: String?) {
        showIncomingCallRequestView(from: callUser.userInfo?.userName(), roomName: " ", isForward: false, cancelAction: { [weak self] in
            self?.declineCall(callUser: callUser)
        }, answerAction: { [weak self] in
            self?.acceptCall(callUser: callUser)
        })
    }
    
    // MARK: Consultation
    
    private func checkConsultationPossible(location: LocationModel, screen: ScreenModel, user: LocationUserModel, screenStatus: ScreenStatus) {
        if (screenStatus == .online && locationService.consultationInitiationPossible()) || (screenStatus == .calling) {
            checkMediaPermissions { [weak self] (granted) in
                if granted {
                    self?.showConsultation(location: location, screen: screen, user: user)
                } else {
                    self?.showPermissionAlert()
                }
            }
        }
    }
    
    private func showConsultation(forward: ForwardModel, user: LocationUserModel) {
        guard let router = router as? ScreensRouterInput else {
            fatalError("\(self) router isn't ScreensRouter")
        }
        
        router.showConsultationViewController(forward: forward, user: user)
    }
    
    private func showCall(user: LocationUserModel) {
        guard let router = router as? ScreensRouterInput else {
            fatalError("\(self) router isn't ScreensRouter")
        }
        
        router.showConsultationViewController(user: user)
    }
    
    private func showConsultation(location: LocationModel, screen: ScreenModel, user: LocationUserModel) {
        guard let router = router as? ScreensRouterInput else {
            fatalError("\(self) router isn't ScreensRouter")
        }
        
        router.showConsultationViewController(location: location, screen: screen, user: user)
    }
    
    // MARK: Other Methods
    
    private func presentAlert(_ alert: UIAlertController) {
        present(alert, animated: true, completion: {
            self.refreshControl.endRefreshing()
            self.needRefreshing = false
            self.configureEmptyView(hidden: (self.tableViewModel.locations.count != 0))
        })
    }
    
    private func checkMediaPermissions(_ completion: ((_ granted: Bool) -> ())?) {
        if let permissionsService = permissionsService {
            permissionsService.requestCameraPermission({ (granted) in
                if granted {
                    permissionsService.requestMicrophonePermission({ (granted) in
                        completion?(granted)
                    })
                } else {
                    completion?(false)
                }
            })
        } else {
            completion?(false)
        }
    }
    
    private func showPermissionAlert() {
        let microphonePermitted = permissionsService?.checkMicrophonePermission() ?? false
        let cameraPermitted = permissionsService?.checkCameraPermission() ?? false
        let title = AppTexts.Errors.Titles.mediaPermissionsDenied(microphonePermitted: microphonePermitted, cameraPermitted: cameraPermitted)
        let message = AppTexts.Errors.Texts.mediaPermissionsDenied(microphonePermitted: microphonePermitted, cameraPermitted: cameraPermitted)
        let openSettings = UIAlertAction(title: AppTexts.Buttons.openSettings(), style: .default) { (action) in
            if let settingsURL = URL(string: UIApplicationOpenSettingsURLString), UIApplication.shared.canOpenURL(settingsURL) {
                if #available(iOS 10.0, *) {
                    UIApplication.shared.open(settingsURL, completionHandler: nil)
                } else {
                    UIApplication.shared.openURL(settingsURL)
                }
            }
        }
        
        if let alert = alert(withTitle: title, message: message) {
            alert.addAction(openSettings)
            presentAlert(alert)
        }
    }
    
    // MARK: Controls Actions
    
    @objc private func handleRefresh(_ refreshControl: UIRefreshControl) {
        refreshControl.beginRefreshing()
        tableViewModel.tableReloaded = false
        let deadlineTime = DispatchTime.now() + .milliseconds(300)
        DispatchQueue.global().asyncAfter(deadline: deadlineTime) {
            self.locationService.requestLocations()
        }
    }
}

