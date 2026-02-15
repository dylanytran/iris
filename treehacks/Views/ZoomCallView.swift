//
//  ZoomCallView.swift
//  treehacks
//
//  Video call interface with real-time transcription.
//  Uses Zoom Video SDK for video and iOS Speech framework for transcription.
//

import SwiftUI
import SwiftData

struct ZoomCallView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var zoomService = ZoomService.shared
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    // Optional initial session name from deep link
    var initialSessionName: String?
    
    @State private var sessionName: String = ""
    @State private var sessionPassword: String = ""
    @State private var userName: String = "User"
    @State private var isTranscribing = false
    @State private var showEndCallConfirmation = false
    @State private var isMuted = false
    @State private var isVideoOff = false
    @State private var showSavedAlert = false
    @State private var showShareSheet = false
    @State private var isLeavingIntentionally = false
    @State private var isLeaving = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLeaving {
                    // Show nothing while leaving to prevent SDK access
                    VStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Ending call...")
                            .foregroundColor(.white)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
                } else if zoomService.isInSession {
                    // In-call view
                    inCallView
                } else {
                    // Join session view
                    joinSessionView
                }
            }
            .navigationTitle(isLeaving ? "Ending..." : (zoomService.isInSession ? "In Call" : "Join Call"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !zoomService.isInSession && !isLeaving {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                zoomService.initializeSDK()
                speechRecognizer.requestPermissions()
                
                // Auto-fill and optionally auto-join from deep link
                if let initialSession = initialSessionName, !initialSession.isEmpty {
                    sessionName = initialSession
                    // Auto-join after a brief delay to allow SDK initialization
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if zoomService.isInitialized && !zoomService.isInSession {
                            joinSession()
                        }
                    }
                }
            }
            .onChange(of: zoomService.isInSession) { oldValue, newValue in
                // Handle when session ends remotely (e.g., host ended for all)
                // Don't dismiss if we're leaving intentionally (we handle that ourselves)
                if oldValue && !newValue && !isLeavingIntentionally {
                    print("ZoomCallView: Session ended remotely, dismissing view")
                    stopTranscription()
                    dismiss()
                }
            }
            .alert("Call Ended", isPresented: $showSavedAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("The transcript has been saved to your Instructions.")
            }
        }
    }
    
    // MARK: - Join Session View
    
    private var joinSessionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "video.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Join Video Call")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                TextField("Session Name", text: $sessionName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                
                SecureField("Passcode (optional)", text: $sessionPassword)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Your Name", text: $userName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 40)
            
            Button(action: joinSession) {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Join Session")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(sessionName.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(sessionName.isEmpty)
            .padding(.horizontal, 40)
            
            // Error display
            if let error = zoomService.joinError {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Text("Real-time transcription will be enabled during the call.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
    }
    
    // MARK: - In-Call View
    
    private var inCallView: some View {
        VStack(spacing: 0) {
            // Video area
            ZStack {
                Color.black
                
                // Main view - show shared screen if someone is sharing, otherwise show remote video
                if zoomService.isScreenSharing {
                    // I'm sharing my screen - show simple indicator (no complex UIKit views)
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.inset.filled.and.person.filled")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text("Screen Share Active")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        Text("Others can see your app")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        
                        HStack {
                            Image(systemName: "rectangle.on.rectangle.fill")
                                .foregroundColor(.green)
                            Text("Sharing")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.6))
                        .cornerRadius(8)
                    }
                } else if let shareUser = zoomService.activeShareUser {
                    // Someone else is sharing their screen
                    VStack {
                        ZoomShareView(user: shareUser)
                        HStack {
                            Image(systemName: "rectangle.on.rectangle.fill")
                                .foregroundColor(.green)
                            Text("\(shareUser.getName() ?? "Someone") is sharing")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                    }
                } else if let remoteUser = zoomService.remoteUsers.first {
                    ZoomVideoView(user: remoteUser)
                } else {
                    // No remote participants yet
                    VStack {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        Text("Waiting for others to join...")
                            .foregroundColor(.gray)
                    }
                }
                
                // Local video preview (top right)
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            if !isVideoOff, let localUser = zoomService.localUser {
                                ZoomVideoView(user: localUser)
                                    .frame(width: 100, height: 140)
                                    .cornerRadius(8)
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.8))
                                    .frame(width: 100, height: 140)
                                    .overlay(
                                        Image(systemName: "video.slash.fill")
                                            .font(.largeTitle)
                                            .foregroundColor(.white)
                                    )
                            }
                        }
                        .padding()
                    }
                    Spacer()
                }
                
                // Session info overlay
                VStack {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(zoomService.sessionName)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("\(zoomService.participants.count) participant(s)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            if isTranscribing {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("Transcribing")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding()
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(height: 400)
            
            // Transcript area
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Live Transcript")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $isTranscribing)
                        .labelsHidden()
                        .onChange(of: isTranscribing) { _, newValue in
                            if newValue {
                                startTranscription()
                            } else {
                                stopTranscription()
                            }
                        }
                }
                
                ScrollView {
                    Text(zoomService.currentTranscript.isEmpty ? "Transcript will appear here..." : zoomService.currentTranscript)
                        .font(.system(size: 14))
                        .foregroundColor(zoomService.currentTranscript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .padding()
            
            Spacer()
            
            // Call controls
            callControlsView
        }
    }
    
    // MARK: - Call Controls
    
    private var callControlsView: some View {
        VStack(spacing: 16) {
            // Top row - Screen share toggle
            Button(action: { zoomService.toggleScreenShare() }) {
                HStack {
                    Image(systemName: zoomService.isScreenSharing ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle")
                    Text(zoomService.isScreenSharing ? "Stop Sharing Screen" : "Share Screen")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(zoomService.isScreenSharing ? Color.green : Color.blue)
                .cornerRadius(10)
            }
            .padding(.horizontal, 20)
            
            // Show share error if any
            if let shareError = zoomService.shareError {
                Text(shareError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
            }
            // Bottom row - Other controls
            HStack(spacing: 30) {
                // Mute button
                Button(action: toggleMute) {
                    VStack {
                        Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(isMuted ? Color.red : Color.gray.opacity(0.6))
                            .clipShape(Circle())
                        Text(isMuted ? "Unmute" : "Mute")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Video toggle
                Button(action: toggleVideo) {
                    VStack {
                        Image(systemName: isVideoOff ? "video.slash.fill" : "video.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(isVideoOff ? Color.red : Color.gray.opacity(0.6))
                            .clipShape(Circle())
                        Text(isVideoOff ? "Start Video" : "Stop Video")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Share session
                Button(action: { showShareSheet = true }) {
                    VStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                        Text("Invite")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // End call
                Button(action: { showEndCallConfirmation = true }) {
                    VStack {
                        Image(systemName: "phone.down.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.red)
                            .clipShape(Circle())
                        Text("End")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 20)
        .sheet(isPresented: $showShareSheet) {
            let encodedSession = zoomService.sessionName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? zoomService.sessionName
            let inviteText = sessionPassword.isEmpty 
                ? "Join my video call!\n\nSession: \(zoomService.sessionName)"
                : "Join my video call!\n\nSession: \(zoomService.sessionName)\nPasscode: \(sessionPassword)"
            ShareSheet(items: [inviteText])
        }
        .confirmationDialog("End Call?", isPresented: $showEndCallConfirmation) {
            Button("End Call & Save Transcript", role: .destructive) {
                endCallAndSave()
            }
            Button("End Call Without Saving", role: .destructive) {
                endCallWithoutSaving()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to save the transcript from this call?")
        }
    }
    
    // MARK: - Actions
    
    private func joinSession() {
        zoomService.joinSession(sessionName: sessionName, userName: userName, password: sessionPassword)
        
        // Auto-start transcription
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isTranscribing = true
            startTranscription()
        }
    }
    
    private func startTranscription() {
        speechRecognizer.onFinished = { transcript in
            if !transcript.isEmpty {
                zoomService.appendToTranscript(transcript)
            }
            // Restart transcription continuously
            if isTranscribing && zoomService.isInSession {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    speechRecognizer.startListening()
                }
            }
        }
        speechRecognizer.startListening()
    }
    
    private func stopTranscription() {
        speechRecognizer.stopListening()
    }
    
    private func toggleMute() {
        isMuted.toggle()
        zoomService.toggleMute()
    }
    
    private func toggleVideo() {
        isVideoOff.toggle()
        zoomService.toggleVideo()
    }
    
    private func endCallAndSave() {
        isLeavingIntentionally = true
        isLeaving = true
        stopTranscription()
        
        // Small delay to let SwiftUI stop rendering the video views
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let transcriptData = self.zoomService.leaveSession() {
                // Save to SwiftData
                let transcript = MeetingTranscript(
                    title: transcriptData.title,
                    transcript: transcriptData.transcript,
                    date: transcriptData.date,
                    duration: transcriptData.duration,
                    participants: transcriptData.participants
                )
                self.modelContext.insert(transcript)
                self.showSavedAlert = true
            } else {
                self.dismiss()
            }
        }
    }
    
    private func endCallWithoutSaving() {
        isLeavingIntentionally = true
        isLeaving = true
        stopTranscription()
        
        // Small delay to let SwiftUI stop rendering the video views
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            _ = self.zoomService.leaveSession()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.dismiss()
            }
        }
    }
}

#Preview {
    ZoomCallView()
        .modelContainer(for: MeetingTranscript.self, inMemory: true)
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}