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
    @Published var latestCaption: String = ""  // For live captions display
    @Published var isLiveTranscriptionActive = false
    @Published var joinError: String?
    @Published var remoteUsers: [ZoomVideoSDKUser] = []
    @Published var localUser: ZoomVideoSDKUser?
    @Published var activeShareUser: ZoomVideoSDKUser? {
        didSet {
            activeShareUserId = Int(activeShareUser?.getID() ?? 0)
        }
    }
    @Published var activeShareUserId: Int = 0  // Tracks share user changes for SwiftUI
    
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
            print("ZoomService: SDK already initialized, skipping")
            return
        }
        
        print("ZoomService: Initializing SDK...")
        print("ZoomService: SDK Key: \(sdkKey.prefix(8))...")
        
        let initParams = ZoomVideoSDKInitParams()
        initParams.domain = "zoom.us"
        initParams.enableLog = true
        
        let sdkInitResult = ZoomVideoSDK.shareInstance()?.initialize(initParams)
        
        if sdkInitResult == .Errors_Success {
            print("ZoomService: ✅ SDK initialized successfully")
            ZoomVideoSDK.shareInstance()?.delegate = self
            isInitialized = true
        } else if sdkInitResult == .Errors_Auth_Error {
            print("ZoomService: ❌ SDK initialization failed: Auth Error - Check SDK credentials")
            errorMessage = "Zoom SDK authentication failed. Check credentials."
        } else if sdkInitResult == .Errors_Wrong_Usage {
            // May mean already initialized
            print("ZoomService: SDK may already be initialized, setting delegate")
            ZoomVideoSDK.shareInstance()?.delegate = self
            isInitialized = true
        } else {
            let rawValue = sdkInitResult.map { Int($0.rawValue) } ?? 0
            print("ZoomService: ❌ SDK initialization failed: \(String(describing: sdkInitResult)) rawValue: \(rawValue)")
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
        
        print("ZoomService: Joining session '\(sessionName)'")
        print("ZoomService: Password: '\(password.isEmpty ? "(none)" : "***")'")
        print("ZoomService: JWT generated: \(jwt.prefix(50))...")
        
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
        
        if let session = ZoomVideoSDK.shareInstance()?.joinSession(sessionContext) {
            print("ZoomService: joinSession called - waiting for delegate callback")
            sessionStartTime = Date()
            AppSpeechManager.shared.speak("Starting Zoom Call")
        } else {
            print("ZoomService: ❌ Failed to join session - joinSession returned nil")
            errorMessage = "Failed to join session"
            joinError = "Failed to start session"
            AppSpeechManager.shared.speak("Failed to start session")
        }
    }
    
    /// Leave the current session
    func leaveSession() -> MeetingTranscriptData? {
        guard isInSession else { return nil }
        
        print("ZoomService: Leaving session '\(sessionName)'")
        
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
        activeShareUser = nil
        
        print("ZoomService: ✅ Left session, transcript saved")
        return transcriptData
    }
    
    // MARK: - Transcription
    
    /// Append text to the current transcript
    func appendToTranscript(_ text: String, speaker: String = "Speaker") {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let entry = "[\(timestamp)] \(speaker): \(text)\n"
        currentTranscript += entry
        print("ZoomService: Transcript += \"\(text.prefix(50))...\"")
    }
    
    // MARK: - Audio/Video Controls
    
    @Published var isMuted = false
    @Published var isVideoOn = true
    
    func toggleMute() {
        guard let audioHelper = ZoomVideoSDK.shareInstance()?.getAudioHelper() else {
            print("ZoomService: No audio helper available")
            return
        }
        
        if isMuted {
            let result = audioHelper.unmuteAudio(localUser)
            print("ZoomService: Unmute result: \(result)")
        } else {
            let result = audioHelper.muteAudio(localUser)
            print("ZoomService: Mute result: \(result)")
        }
        isMuted.toggle()
    }
    
    func toggleVideo() {
        guard let videoHelper = ZoomVideoSDK.shareInstance()?.getVideoHelper() else {
            print("ZoomService: No video helper available")
            return
        }
        
        if isVideoOn {
            let result = videoHelper.stopVideo()
            print("ZoomService: Stop video result: \(result)")
        } else {
            let result = videoHelper.startVideo()
            print("ZoomService: Start video result: \(result)")
        }
        isVideoOn.toggle()
    }
    
    // MARK: - Screen Sharing
    
    @Published var isScreenSharing = false
    @Published var shareError: String?
    
    func startScreenShare() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard self.isInSession else {
                self.shareError = "Not in a session"
                return
            }
            
            guard let shareHelper = ZoomVideoSDK.shareInstance()?.getShareHelper() else {
                print("ZoomService: ❌ No share helper available")
                self.shareError = "Share helper not available"
                return
            }
            
            if shareHelper.isOtherSharing() {
                print("ZoomService: ❌ Another user is already sharing")
                self.shareError = "Another user is already sharing"
                return
            }
            
            if shareHelper.isSharingOut() {
                print("ZoomService: Already sharing")
                self.isScreenSharing = true
                return
            }
            
            if shareHelper.isSupportInAppScreenShare() {
                let result = shareHelper.startInAppScreenShare()
                print("ZoomService: startInAppScreenShare result: \(result)")
                if result == .Errors_Success {
                    self.isScreenSharing = true
                    self.shareError = nil
                    print("ZoomService: ✅ Screen sharing started")
                } else {
                    self.shareError = "Failed: \(self.describeError(result))"
                    print("ZoomService: ❌ Failed to start screen share")
                }
            } else {
                self.shareError = "Screen sharing not supported"
            }
        }
    }
    
    func stopScreenShare() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard let shareHelper = ZoomVideoSDK.shareInstance()?.getShareHelper() else {
                return
            }
            
            let result = shareHelper.stopShare()
            print("ZoomService: Stop screen share result: \(result)")
            self.isScreenSharing = false
            self.shareError = nil
        }
    }
    
    func toggleScreenShare() {
        guard isInSession else {
            print("ZoomService: Cannot toggle screen share - not in session")
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
            print("ZoomService: ✅ onSessionJoin - Successfully joined session")
            self.isInSession = true
            self.joinError = nil
            
            // Get local user
            if let session = ZoomVideoSDK.shareInstance()?.getSession(),
               let myUser = session.getMySelf() {
                self.localUser = myUser
                print("ZoomService: Local user set: \(myUser.getName() ?? "unknown")")
                
                // Start local video
                ZoomVideoSDK.shareInstance()?.getVideoHelper()?.startVideo()
                
                // Start audio - this is required to activate the microphone
                if let audioHelper = ZoomVideoSDK.shareInstance()?.getAudioHelper() {
                    let audioResult = audioHelper.startAudio()
                    print("ZoomService: startAudio result: \(audioResult.rawValue)")
                    
                    // Ensure we're unmuted
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if !self.isMuted {
                            let unmuteResult = audioHelper.unmuteAudio(myUser)
                            print("ZoomService: Initial unmute result: \(unmuteResult.rawValue)")
                        }
                    }
                }
            }
            
            // Get existing remote users
            self.updateRemoteUsers()
            
            // Check if anyone is already sharing
            self.checkForActiveShare()
            
            // Start live transcription
            self.startLiveTranscription()
        }
    }
    
    // MARK: - Live Transcription
    
    func startLiveTranscription() {
        guard let helper = ZoomVideoSDK.shareInstance()?.getLiveTranscriptionHelper() else {
            print("ZoomService: ❌ Live transcription helper not available")
            return
        }
        
        // Check if we can start
        let canStart = helper.canStartLiveTranscription()
        print("ZoomService: Can start live transcription: \(canStart)")
        
        let status = helper.getLiveTranscriptionStatus()
        print("ZoomService: Current transcription status: \(status.rawValue) (0=stop, 1=start)")
        
        // IMPORTANT: Start transcription FIRST, then set language
        if canStart && status == .stop {
            let result = helper.startLiveTranscription()
            print("ZoomService: Start live transcription result: \(result.rawValue) (0=success)")
            
            if result == .Errors_Success {
                // Now set speaking language AFTER transcription has started
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.configureLiveTranscriptionLanguage()
                }
            }
        } else if status == .start {
            // Already started, just configure language
            configureLiveTranscriptionLanguage()
        }
    }
    
    private func configureLiveTranscriptionLanguage() {
        guard let helper = ZoomVideoSDK.shareInstance()?.getLiveTranscriptionHelper() else { return }
        
        // Enable receiving original content
        let enableResult = helper.enableReceiveSpokenLanguageContent(true)
        print("ZoomService: enableReceiveSpokenLanguageContent result: \(enableResult.rawValue)")
        
        // Check available spoken languages
        if let languages = helper.getAvailableSpokenLanguages() {
            print("ZoomService: Available spoken languages: \(languages.count)")
            for lang in languages {
                print("ZoomService:   - \(lang.languageName ?? "unknown") (ID: \(lang.languageID))")
            }
            
            // Set spoken language to English (usually ID 0 or first available)
            if let englishLang = languages.first(where: { ($0.languageName ?? "").lowercased().contains("english") }) {
                let setResult = helper.setSpokenLanguage(englishLang.languageID)
                print("ZoomService: Set spoken language to English, result: \(setResult.rawValue)")
            } else if let firstLang = languages.first {
                let setResult = helper.setSpokenLanguage(firstLang.languageID)
                print("ZoomService: Set spoken language to \(firstLang.languageName ?? "first"), result: \(setResult.rawValue)")
            }
        } else {
            print("ZoomService: ⚠️ No spoken languages available")
        }
    }
    
    func onLiveTranscriptionStatus(_ status: ZoomVideoSDKLiveTranscriptionStatus) {
        DispatchQueue.main.async {
            print("ZoomService: Live transcription status changed: \(status.rawValue)")
            self.isLiveTranscriptionActive = (status == .start)
        }
    }
    
    func onLiveTranscriptionMsgReceived(_ messageInfo: ZoomVideoSDKLiveTranscriptionMessageInfo?) {
        guard let info = messageInfo,
              let message = info.messageContent, !message.isEmpty else { return }
        
        DispatchQueue.main.async {
            let speakerName = info.speakerName ?? "Unknown"
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            
            // Update live caption display
            self.latestCaption = "\(speakerName): \(message)"
            
            // Append to full transcript
            let entry = "[\(timestamp)] \(speakerName): \(message)\n"
            self.currentTranscript += entry
            
            print("ZoomService: [Transcription] \(speakerName): \(message)")
        }
    }
    
    func onOriginalLanguageMsgReceived(_ messageInfo: ZoomVideoSDKLiveTranscriptionMessageInfo?) {
        // Also handle original language messages (same as above)
        guard let info = messageInfo,
              let message = info.messageContent, !message.isEmpty else { return }
        
        DispatchQueue.main.async {
            let speakerName = info.speakerName ?? "Unknown"
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            
            self.latestCaption = "\(speakerName): \(message)"
            let entry = "[\(timestamp)] \(speakerName): \(message)\n"
            self.currentTranscript += entry
            
            print("ZoomService: [Original] \(speakerName): \(message)")
        }
    }
    
    private func updateRemoteUsers() {
        guard let session = ZoomVideoSDK.shareInstance()?.getSession(),
              let allUsers = session.getRemoteUsers() else {
            return
        }
        
        self.remoteUsers = allUsers
        print("ZoomService: Remote users count: \(allUsers.count)")
    }
    
    private func checkForActiveShare() {
        guard let shareHelper = ZoomVideoSDK.shareInstance()?.getShareHelper() else {
            return
        }
        
        print("ZoomService: Checking for active shares...")
        print("ZoomService: isOtherSharing = \(shareHelper.isOtherSharing())")
        
        if shareHelper.isOtherSharing() {
            // Find who is sharing
            for user in remoteUsers {
                if let shareActions = user.getShareActionList(), !shareActions.isEmpty {
                    print("ZoomService: Found active share from: \(user.getName() ?? "unknown")")
                    self.activeShareUser = user
                    return
                }
            }
        }
    }
    
    func onSessionLeave() {
        DispatchQueue.main.async {
            print("ZoomService: onSessionLeave - Left session")
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
            AppSpeechManager.shared.speak(errorDescription)
        }
    }
    
    func onUserJoin(_ helper: ZoomVideoSDKUserHelper?, users: [ZoomVideoSDKUser]?) {
        guard let users = users else { return }
        DispatchQueue.main.async {
            for user in users {
                if let name = user.getName() {
                    print("ZoomService: User joined: \(name)")
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
                    print("ZoomService: User left: \(name)")
                    self.participants.removeAll { $0 == name }
                }
                // Clear active share user if they left
                if self.activeShareUser?.getID() == user.getID() {
                    print("ZoomService: Active share user left, clearing")
                    self.activeShareUser = nil
                }
            }
            self.updateRemoteUsers()
        }
    }
    
    // MARK: - Share Delegate Methods
    
    func onUserShareStatusChanged(_ helper: ZoomVideoSDKShareHelper?, user: ZoomVideoSDKUser?, shareAction: ZoomVideoSDKShareAction?) {
        DispatchQueue.main.async {
            let userName = user?.getName() ?? "Unknown"
            let userId = user?.getID() ?? 0
            let status = shareAction?.getShareStatus() ?? .stop
            print("ZoomService: ===== SHARE STATUS CHANGED =====")
            print("ZoomService: User: \(userName) (ID: \(userId)), Status: \(status.rawValue)")
            print("ZoomService: isOtherSharing: \(helper?.isOtherSharing() ?? false)")
            print("ZoomService: isSharingOut: \(helper?.isSharingOut() ?? false)")
            print("ZoomService: Share actions count: \(user?.getShareActionList()?.count ?? 0)")
            
            // Check if this is our own share status
            if let session = ZoomVideoSDK.shareInstance()?.getSession(),
               let myUser = session.getMySelf() {
                let isMyShare = user?.getID() == myUser.getID()
                print("ZoomService: My ID: \(myUser.getID()), Is my share: \(isMyShare)")
                
                if isMyShare {
                    // Our own share status changed
                    self.isScreenSharing = (status == .start)
                    print("ZoomService: My own share status changed to: \(self.isScreenSharing)")
                }
            }
            
            // Track who is sharing for viewing their share
            if status == .start {
                print("ZoomService: Setting activeShareUser to: \(userName) (ID: \(userId))")
                self.activeShareUser = user
                print("ZoomService: activeShareUserId is now: \(self.activeShareUserId)")
            } else if status == .stop {
                // If this user stopped sharing, clear active share user
                if self.activeShareUser?.getID() == user?.getID() {
                    print("ZoomService: Clearing activeShareUser")
                    self.activeShareUser = nil
                }
            }
            
            // Force objectWillChange to ensure SwiftUI updates
            self.objectWillChange.send()
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