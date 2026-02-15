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
        guard let sdk = ZoomVideoSDK.shareInstance(),
              sdk.getSession() != nil,
              let user = user,
              user.getName() != nil,
              let videoCanvas = user.getVideoCanvas() else {
            return
        }
        
        videoCanvas.subscribe(with: uiView, aspectMode: videoAspect, andResolution: ._Auto)
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
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
        guard let sdk = ZoomVideoSDK.shareInstance(),
              let session = sdk.getSession(),
              let myUser = session.getMySelf(),
              let videoCanvas = myUser.getVideoCanvas() else {
            return
        }
        
        videoCanvas.subscribe(with: uiView, aspectMode: .panAndScan, andResolution: ._Auto)
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
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
        guard let sdk = ZoomVideoSDK.shareInstance(),
              sdk.getSession() != nil,
              let user = user,
              let shareActions = user.getShareActionList(),
              let firstShareAction = shareActions.first,
              let shareCanvas = firstShareAction.getShareCanvas() else {
            return
        }
        
        shareCanvas.subscribe(with: uiView, aspectMode: .panAndScan, andResolution: ._Auto)
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
    }
}
