//
//  ZoomVideoView.swift
//  treehacks
//
//  UIViewRepresentable wrapper for Zoom Video SDK video rendering.
//

import SwiftUI
import ZoomVideoSDK

/// Renders video from a Zoom Video SDK user
struct ZoomVideoView: UIViewRepresentable {
    let user: ZoomVideoSDKUser?
    let videoAspect: ZoomVideoSDKVideoAspect
    
    init(user: ZoomVideoSDKUser?, videoAspect: ZoomVideoSDKVideoAspect = .panAndScan) {
        self.user = user
        self.videoAspect = videoAspect
    }
    
    class Coordinator {
        var subscribedUser: ZoomVideoSDKUser?
        var subscribedView: UIView?
        
        func unsubscribe() {
            guard let user = subscribedUser, let view = subscribedView else { return }
            user.getVideoCanvas()?.unSubscribe(with: view)
            subscribedUser = nil
            subscribedView = nil
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        
        guard let user = user else {
            coordinator.unsubscribe()
            return
        }
        
        // Make sure we're still in a session
        guard ZoomVideoSDK.shareInstance()?.getSession() != nil else {
            return
        }
        
        // Only resubscribe if user changed or view changed
        if coordinator.subscribedUser?.getID() != user.getID() || coordinator.subscribedView !== uiView {
            coordinator.unsubscribe()
            
            // Subscribe to the user's video
            if let videoCanvas = user.getVideoCanvas() {
                let result = videoCanvas.subscribe(with: uiView, aspectMode: videoAspect, andResolution: ._Auto)
                if result == .Errors_Success {
                    coordinator.subscribedUser = user
                    coordinator.subscribedView = uiView
                }
            }
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // Properly unsubscribe when view is removed
        coordinator.unsubscribe()
    }
}

/// Renders the local user's camera preview
struct ZoomLocalVideoView: UIViewRepresentable {
    
    class Coordinator {
        var subscribedUser: ZoomVideoSDKUser?
        var subscribedView: UIView?
        
        func unsubscribe() {
            guard let user = subscribedUser, let view = subscribedView else { return }
            user.getVideoCanvas()?.unSubscribe(with: view)
            subscribedUser = nil
            subscribedView = nil
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .darkGray
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        
        // Make sure we're in an active session
        guard let session = ZoomVideoSDK.shareInstance()?.getSession(),
              let myUser = session.getMySelf(),
              let videoCanvas = myUser.getVideoCanvas() else {
            return
        }
        
        // Only resubscribe if user changed or view changed
        if coordinator.subscribedUser?.getID() != myUser.getID() || coordinator.subscribedView !== uiView {
            coordinator.unsubscribe()
            
            let result = videoCanvas.subscribe(with: uiView, aspectMode: .panAndScan, andResolution: ._Auto)
            if result == .Errors_Success {
                coordinator.subscribedUser = myUser
                coordinator.subscribedView = uiView
            }
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.unsubscribe()
    }
}

/// Renders shared screen content from a user
struct ZoomShareView: UIViewRepresentable {
    let user: ZoomVideoSDKUser?
    
    class Coordinator {
        var isSubscribed = false
        var subscribedView: UIView?
        var subscribedUserId: Int = -1
        var retryTimer: Timer?
        
        func markUnsubscribed() {
            isSubscribed = false
            subscribedView = nil
            subscribedUserId = -1
            retryTimer?.invalidate()
            retryTimer = nil
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        
        guard let user = user else {
            coordinator.markUnsubscribed()
            return
        }
        
        // Make sure we're still in a session
        guard ZoomVideoSDK.shareInstance()?.getSession() != nil else {
            return
        }
        
        let userId = user.getID()
        
        // If already subscribed to this user on this view, skip
        if coordinator.isSubscribed && coordinator.subscribedView === uiView && coordinator.subscribedUserId == Int(userId) {
            return
        }
        
        // Try to subscribe
        Self.trySubscribe(user: user, view: uiView, coordinator: coordinator, retryCount: 0)
    }
    
    private static func trySubscribe(user: ZoomVideoSDKUser, view: UIView, coordinator: Coordinator, retryCount: Int) {
        print("ZoomShareView: trySubscribe attempt \(retryCount + 1) for user \(user.getName() ?? "unknown")")
        
        // Get share canvas from the user's share action list
        guard let shareActions = user.getShareActionList() else {
            print("ZoomShareView: getShareActionList() returned nil")
            retryIfNeeded(user: user, view: view, coordinator: coordinator, retryCount: retryCount)
            return
        }
        
        print("ZoomShareView: Share actions count: \(shareActions.count)")
        
        guard let firstShareAction = shareActions.first else {
            print("ZoomShareView: No first share action")
            retryIfNeeded(user: user, view: view, coordinator: coordinator, retryCount: retryCount)
            return
        }
        
        guard let shareCanvas = firstShareAction.getShareCanvas() else {
            print("ZoomShareView: getShareCanvas() returned nil")
            retryIfNeeded(user: user, view: view, coordinator: coordinator, retryCount: retryCount)
            return
        }
        
        coordinator.retryTimer?.invalidate()
        
        let result = shareCanvas.subscribe(with: view, aspectMode: .panAndScan, andResolution: ._Auto)
        print("ZoomShareView: subscribe result: \(result.rawValue)")
        
        if result == .Errors_Success {
            coordinator.isSubscribed = true
            coordinator.subscribedView = view
            coordinator.subscribedUserId = Int(user.getID())
            print("ZoomShareView: ✅ Successfully subscribed to share")
        } else {
            print("ZoomShareView: ❌ Failed to subscribe: \(result.rawValue)")
        }
    }
    
    private static func retryIfNeeded(user: ZoomVideoSDKUser, view: UIView, coordinator: Coordinator, retryCount: Int) {
        if retryCount < 5 {
            coordinator.retryTimer?.invalidate()
            coordinator.retryTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                DispatchQueue.main.async {
                    Self.trySubscribe(user: user, view: view, coordinator: coordinator, retryCount: retryCount + 1)
                }
            }
        } else {
            print("ZoomShareView: ❌ Max retries reached, giving up")
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.markUnsubscribed()
    }
}