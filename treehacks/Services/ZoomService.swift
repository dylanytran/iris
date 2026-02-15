//
//  ZoomService.swift
//  treehacks
//
//  Manages Zoom Video SDK integration for video calls with real-time transcription.
//  Stores call transcripts for later reference.
//

import Foundation
import Combine
import AVFoundation
import ZoomVideoSDK

/// Service for managing Zoom Video SDK sessions
class ZoomService: NSObject, ObservableObject, ZoomVideoSDKDelegate {
    
    static let shared = ZoomService()
    
    // MARK: - Published State
    
    @Published var isInitialized = false
    @Published var isInSession = false
    @Published var sessionName: String = ""
    @Published var errorMessage: String?
    @Published var currentTranscript: String = ""
    @Published var participants: [String] = []
    @Published var joinError: String?
    @Published var remoteUsers: [ZoomVideoSDKUser] = []
    @Published var localUser: ZoomVideoSDKUser?
    @Published var activeShareUser: ZoomVideoSDKUser?
    
    // MARK: - Configuration
    
    private var sdkKey: String {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["ZoomSDKKey"] as? String else {
            print("ZoomService: Missing ZoomSDKKey in Secrets.plist")
            return ""
        }
        return key
    }
    
    private var sdkSecret: String {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let secret = dict["ZoomSDKSecret"] as? String else {
            print("ZoomService: Missing ZoomSDKSecret in Secrets.plist")
            return ""
        }
        return secret
    }
    
    // MARK: - Session State
    
    private var sessionStartTime: Date?
    private var transcriptBuilder = ""
    
    private override init() {
        super.init()
    }
    
    // MARK: - SDK Initialization
    
    /// Initialize the Zoom Video SDK
    func initializeSDK() {
        guard !sdkKey.isEmpty && !sdkSecret.isEmpty else {
            errorMessage = "Zoom SDK credentials not configured"
            print("ZoomService: ❌ Missing SDK credentials")
            return
        }
        
        // Check if already initialized
        if isInitialized {
            return
        }
        
        let initParams = ZoomVideoSDKInitParams()
        initParams.domain = "zoom.us"
        initParams.enableLog = true
        
        let sdkInitResult = ZoomVideoSDK.shareInstance()?.initialize(initParams)
        
        if sdkInitResult == .Errors_Success {
            ZoomVideoSDK.shareInstance()?.delegate = self
            isInitialized = true
        } else if sdkInitResult == .Errors_Auth_Error {
            print("ZoomService: ❌ SDK init failed: Auth Error")
            errorMessage = "Zoom SDK authentication failed. Check credentials."
        } else if sdkInitResult == .Errors_Wrong_Usage {
            // May mean already initialized
            ZoomVideoSDK.shareInstance()?.delegate = self
            isInitialized = true
        } else {
            let rawValue = sdkInitResult.map { Int($0.rawValue) } ?? 0
            print("ZoomService: ❌ SDK init failed: \(rawValue)")
            errorMessage = "Failed to initialize Zoom SDK: \(rawValue)"
        }
    }
    
    // MARK: - JWT Token Generation
    
    /// Generate JWT token for session authentication
    func generateJWT(sessionName: String, roleType: Int = 1) -> String {
        // Role: 0 = participant, 1 = host
        let header = ["alg": "HS256", "typ": "JWT"]
        
        let now = Date()
        let expiration = now.addingTimeInterval(3600) // 1 hour
        
        let payload: [String: Any] = [
            "app_key": sdkKey,
            "tpc": sessionName,
            "role_type": roleType,
            "version": 1,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(expiration.timeIntervalSince1970)
        ]
        
        // Encode header and payload
        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            print("ZoomService: Failed to encode JWT components")
            return ""
        }
        
        let headerBase64 = headerData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let signatureInput = "\(headerBase64).\(payloadBase64)"
        
        // Sign with HMAC-SHA256
        guard let signatureData = signatureInput.data(using: .utf8) else { return "" }
        let signature = hmacSHA256(data: signatureData, key: sdkSecret)
        
        let signatureBase64 = signature.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        return "\(headerBase64).\(payloadBase64).\(signatureBase64)"
    }
    
    private func hmacSHA256(data: Data, key: String) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        let keyData = key.data(using: .utf8)!
        
        keyData.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyBytes.baseAddress, keyData.count,
                       dataBytes.baseAddress, data.count,
                       &digest)
            }
        }
        
        return Data(digest)
    }
    
    // MARK: - Session Management
    
    /// Join or create a Zoom session
    func joinSession(sessionName: String, userName: String = "User", password: String = "") {
        guard isInitialized else {
            errorMessage = "SDK not initialized"
            return
        }
        
        // Reset error state
        joinError = nil
        errorMessage = nil
        
        self.sessionName = sessionName
        let jwt = generateJWT(sessionName: sessionName)
        
        let sessionContext = ZoomVideoSDKSessionContext()
        sessionContext.sessionName = sessionName
        sessionContext.userName = userName
        if !password.isEmpty {
            sessionContext.sessionPassword = password
        }
        sessionContext.token = jwt
        
        // Audio and video settings
        let audioOption = ZoomVideoSDKAudioOptions()
        audioOption.connect = true
        audioOption.mute = false
        sessionContext.audioOption = audioOption
        
        let videoOption = ZoomVideoSDKVideoOptions()
        videoOption.localVideoOn = true
        sessionContext.videoOption = videoOption
        
        if let _ = ZoomVideoSDK.shareInstance()?.joinSession(sessionContext) {
            sessionStartTime = Date()
            // Note: isInSession will be set by onSessionJoin delegate
        } else {
            print("ZoomService: ❌ joinSession returned nil")
            errorMessage = "Failed to join session"
            joinError = "Failed to start session"
        }
    }
    
    /// Leave the current session
    func leaveSession() -> MeetingTranscriptData? {
        guard isInSession else { return nil }
        
        // Calculate duration
        let duration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        // Create transcript data before clearing state
        let transcriptData = MeetingTranscriptData(
            title: sessionName,
            transcript: currentTranscript,
            date: sessionStartTime ?? Date(),
            duration: duration,
            participants: participants
        )
        
        // Reset state BEFORE leaving session to prevent UI accessing invalid objects
        localUser = nil
        remoteUsers = []
        activeShareUser = nil
        isInSession = false
        
        // Stop screen sharing if active
        if isScreenSharing {
            ZoomVideoSDK.shareInstance()?.getShareHelper()?.stopShare()
            isScreenSharing = false
        }
        
        // Now leave the session (false = just leave, don't end for everyone)
        ZoomVideoSDK.shareInstance()?.leaveSession(false)
        
        // Reset remaining state
        sessionName = ""
        currentTranscript = ""
        participants = []
        sessionStartTime = nil
        isMuted = false
        isVideoOn = true
        
        return transcriptData
    }
    
    // MARK: - Transcription
    
    /// Append text to the current transcript
    func appendToTranscript(_ text: String, speaker: String = "Speaker") {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let entry = "[\(timestamp)] \(speaker): \(text)\n"
        currentTranscript += entry
    }
    
    // MARK: - Audio/Video Controls
    
    @Published var isMuted = false
    @Published var isVideoOn = true
    
    func toggleMute() {
        guard let audioHelper = ZoomVideoSDK.shareInstance()?.getAudioHelper() else { return }
        
        if isMuted {
            _ = audioHelper.unmuteAudio(localUser)
        } else {
            _ = audioHelper.muteAudio(localUser)
        }
        isMuted.toggle()
    }
    
    func toggleVideo() {
        guard let videoHelper = ZoomVideoSDK.shareInstance()?.getVideoHelper() else { return }
        
        if isVideoOn {
            _ = videoHelper.stopVideo()
        } else {
            _ = videoHelper.startVideo()
        }
        isVideoOn.toggle()
    }
    
    // MARK: - Screen Sharing
    
    @Published var isScreenSharing = false
    @Published var shareError: String?
    
    func startScreenShare() {
        // Must be called on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard let shareHelper = ZoomVideoSDK.shareInstance()?.getShareHelper() else {
                self.shareError = "Share helper not available"
                return
            }
            
            // Check if someone else is already sharing
            if shareHelper.isOtherSharing() {
                self.shareError = "Another user is already sharing"
                return
            }
            
            // Check if already sharing
            if shareHelper.isSharingOut() {
                self.isScreenSharing = true
                return
            }
            
            // Try in-app screen share
            if shareHelper.isSupportInAppScreenShare() {
                let result = shareHelper.startInAppScreenShare()
                
                if result == .Errors_Success {
                    self.isScreenSharing = true
                    self.shareError = nil
                } else {
                    self.shareError = "Failed: \(self.describeError(result))"
                }
            } else {
                self.shareError = "Screen sharing not supported on this device"
            }
        }
    }
    
    func stopScreenShare() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let shareHelper = ZoomVideoSDK.shareInstance()?.getShareHelper() else { return }
            
            _ = shareHelper.stopShare()
            self.isScreenSharing = false
            self.shareError = nil
        }
    }
    
    func toggleScreenShare() {
        guard isInSession else {
            shareError = "Not in a session"
            return
        }
        
        shareError = nil  // Clear previous error
        if isScreenSharing {
            stopScreenShare()
        } else {
            startScreenShare()
        }
    }
    
    // MARK: - ZoomVideoSDKDelegate
    
    func onSessionJoin() {
        DispatchQueue.main.async {
            self.isInSession = true
            self.joinError = nil
            
            // Get local user
            if let session = ZoomVideoSDK.shareInstance()?.getSession(),
               let myUser = session.getMySelf() {
                self.localUser = myUser
                
                // Start local video
                ZoomVideoSDK.shareInstance()?.getVideoHelper()?.startVideo()
            }
            
            // Get existing remote users
            self.updateRemoteUsers()
            
            // Check if anyone is already sharing
            self.checkForActiveShare()
        }
    }
    
    private func updateRemoteUsers() {
        guard let session = ZoomVideoSDK.shareInstance()?.getSession(),
              let allUsers = session.getRemoteUsers() else {
            return
        }
        
        self.remoteUsers = allUsers
    }
    
    private func checkForActiveShare() {
        guard let shareHelper = ZoomVideoSDK.shareInstance()?.getShareHelper() else {
            return
        }
        
        if shareHelper.isOtherSharing() {
            // Find who is sharing
            for user in remoteUsers {
                if let shareActions = user.getShareActionList(), !shareActions.isEmpty {
                    self.activeShareUser = user
                    return
                }
            }
        }
    }
    
    func onSessionLeave() {
        DispatchQueue.main.async {
            // Clear all user references FIRST to prevent UI accessing invalid objects
            self.localUser = nil
            self.remoteUsers = []
            self.activeShareUser = nil
            self.isInSession = false
            self.isScreenSharing = false
            self.sessionName = ""
            self.participants = []
            self.isMuted = false
            self.isVideoOn = true
        }
    }
    
    func onError(_ errorType: ZoomVideoSDKError, detail: Int) {
        DispatchQueue.main.async {
            let errorDescription = self.describeError(errorType)
            print("ZoomService: ❌ Error: \(errorDescription) (detail: \(detail))")
            self.joinError = errorDescription
            self.errorMessage = errorDescription
        }
    }
    
    func onUserJoin(_ helper: ZoomVideoSDKUserHelper?, users: [ZoomVideoSDKUser]?) {
        guard let users = users else { return }
        DispatchQueue.main.async {
            for user in users {
                if let name = user.getName() {
                    if !self.participants.contains(name) {
                        self.participants.append(name)
                    }
                }
            }
            self.updateRemoteUsers()
            
            // Check if any joining user is already sharing
            self.checkForActiveShare()
        }
    }
    
    func onUserLeave(_ helper: ZoomVideoSDKUserHelper?, users: [ZoomVideoSDKUser]?) {
        guard let users = users else { return }
        DispatchQueue.main.async {
            for user in users {
                if let name = user.getName() {
                    self.participants.removeAll { $0 == name }
                }
                // Clear active share user if they left
                if self.activeShareUser?.getID() == user.getID() {
                    self.activeShareUser = nil
                }
            }
            self.updateRemoteUsers()
        }
    }
    
    // MARK: - Share Delegate Methods
    
    func onUserShareStatusChanged(_ helper: ZoomVideoSDKShareHelper?, user: ZoomVideoSDKUser?, status: ZoomVideoSDKReceiveSharingStatus) {
        DispatchQueue.main.async {
            // Check if this is our own share status
            if let session = ZoomVideoSDK.shareInstance()?.getSession(),
               let myUser = session.getMySelf(),
               user?.getID() == myUser.getID() {
                // Our own share status changed
                self.isScreenSharing = (status == .start)
            }
            
            // Track who is sharing for viewing their share
            if status == .start {
                self.activeShareUser = user
            } else if status == .stop {
                // If this user stopped sharing, clear active share user
                if self.activeShareUser?.getID() == user?.getID() {
                    self.activeShareUser = nil
                }
            }
        }
    }
    
    private func describeError(_ error: ZoomVideoSDKError) -> String {
        switch error {
        case .Errors_Success:
            return "Success"
        case .Errors_Wrong_Usage:
            return "Wrong usage"
        case .Errors_Internal_Error:
            return "Internal error"
        case .Errors_Uninitialize:
            return "SDK not initialized"
        case .Errors_Memory_Error:
            return "Memory error"
        case .Errors_Load_Module_Error:
            return "Load module error"
        case .Errors_UnLoad_Module_Error:
            return "Unload module error"
        case .Errors_Auth_Error:
            return "Authentication error - check SDK credentials"
        case .Errors_JoinSession_NoSessionName:
            return "No session name provided"
        case .Errors_JoinSession_NoSessionToken:
            return "No session token"
        case .Errors_JoinSession_NoUserName:
            return "No user name"
        case .Errors_JoinSession_Invalid_SessionName:
            return "Invalid session name"
        case .Errors_JoinSession_Invalid_Password:
            return "Invalid password - passwords must match"
        case .Errors_JoinSession_Invalid_SessionToken:
            return "Invalid session token - check SDK key/secret"
        case .Errors_Session_Not_Started:
            return "Session not started"
        case .Errors_Session_Need_Password:
            return "Session requires a password"
        case .Errors_Session_Password_Wrong:
            return "Wrong password"
        default:
            return "Unknown error: \(error)"
        }
    }
}

// MARK: - Data Transfer Object

struct MeetingTranscriptData {
    let title: String
    let transcript: String
    let date: Date
    let duration: TimeInterval
    let participants: [String]
}

// MARK: - CommonCrypto Import

import CommonCrypto
