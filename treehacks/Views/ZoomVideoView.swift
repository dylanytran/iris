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
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Clear any existing video subscriptions
        if let canvas = uiView.layer.sublayers?.first as? CALayer {
            canvas.removeFromSuperlayer()
        }
        
        guard let user = user else {
            print("ZoomVideoView: No user to render")
            return
        }
        
        // Make sure we're still in a session
        guard ZoomVideoSDK.shareInstance()?.getSession() != nil else {
            print("ZoomVideoView: No active session")
            return
        }
        
        // Subscribe to the user's video
        if let videoCanvas = user.getVideoCanvas() {
            let result = videoCanvas.subscribe(with: uiView, aspectMode: videoAspect, andResolution: ._Auto)
            print("ZoomVideoView: Subscribe result for \(user.getName() ?? "unknown"): \(result)")
        } else {
            print("ZoomVideoView: No video canvas for user")
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // Unsubscribe when view is removed
        // The SDK should handle cleanup automatically
    }
}

/// Renders the local user's camera preview
struct ZoomLocalVideoView: UIViewRepresentable {
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .darkGray
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Make sure we're in an active session
        guard let session = ZoomVideoSDK.shareInstance()?.getSession(),
              let myUser = session.getMySelf(),
              let videoCanvas = myUser.getVideoCanvas() else {
            print("ZoomLocalVideoView: Cannot get local video canvas or not in session")
            return
        }
        
        let result = videoCanvas.subscribe(with: uiView, aspectMode: .panAndScan, andResolution: ._Auto)
        print("ZoomLocalVideoView: Local video subscribe result: \(result)")
    }
}

/// Renders shared screen content from a user
struct ZoomShareView: UIViewRepresentable {
    let user: ZoomVideoSDKUser?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        print("ZoomShareView: updateUIView called")
        
        guard let user = user else {
            print("ZoomShareView: No user to render")
            return
        }
        
        print("ZoomShareView: Rendering share for user: \(user.getName() ?? "unknown")")
        
        // Make sure we're still in a session
        guard ZoomVideoSDK.shareInstance()?.getSession() != nil else {
            print("ZoomShareView: No active session")
            return
        }
        
        // Get share canvas from the user's share action list
        guard let shareActions = user.getShareActionList() else {
            print("ZoomShareView: getShareActionList() returned nil")
            return
        }
        
        print("ZoomShareView: Share actions count: \(shareActions.count)")
        
        guard let firstShareAction = shareActions.first else {
            print("ZoomShareView: No first share action")
            return
        }
        
        guard let shareCanvas = firstShareAction.getShareCanvas() else {
            print("ZoomShareView: getShareCanvas() returned nil")
            return
        }
        
        print("ZoomShareView: Got share canvas, subscribing...")
        let result = shareCanvas.subscribe(with: uiView, aspectMode: .panAndScan, andResolution: ._Auto)
        print("ZoomShareView: Subscribe to share result: \(result)")
    }
}

/// Shows a preview when the local user is sharing their screen
struct ZoomLocalSharePreview: UIViewRepresentable {
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
        
        // Add a visual indicator that we're sharing
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        let iconImageView = UIImageView(image: UIImage(systemName: "rectangle.inset.filled.and.person.filled"))
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        
        let label = UILabel()
        label.text = "Screen Share Active"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        
        let subLabel = UILabel()
        subLabel.text = "Others can see your app"
        subLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        subLabel.font = UIFont.systemFont(ofSize: 14)
        
        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(label)
        stackView.addArrangedSubview(subLabel)
        
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Static view, no updates needed
    }
}
