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
    
    // AR/Immersive UI state
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var pipOffset: CGSize = .zero
    @State private var pipPosition: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 70, y: 80)
    @State private var showTranscript = false
    
    var body: some View {
        Group {
            if zoomService.isInSession && !isLeaving {
                // Immersive full-screen call - no NavigationStack
                immersiveCallView
            } else {
                // Join view or leaving state with navigation
                NavigationStack {
                    VStack(spacing: 0) {
                        if isLeaving {
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
                        } else {
                            joinSessionView
                        }
                    }
                    .navigationTitle("Join Call")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") { dismiss() }
                        }
                    }
                }
            }
        }
        .onAppear {
            zoomService.initializeSDK()
            speechRecognizer.requestPermissions()
            
            if let initialSession = initialSessionName, !initialSession.isEmpty {
                sessionName = initialSession
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if zoomService.isInitialized && !zoomService.isInSession {
                        joinSession()
                    }
                }
            }
        }
        .onChange(of: zoomService.isInSession) { oldValue, newValue in
            if oldValue && !newValue && !isLeavingIntentionally {
                stopTranscription()
                dismiss()
            }
        }
        .alert("Call Ended", isPresented: $showSavedAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("The transcript has been saved to your Instructions.")
        }
    }
    
    // MARK: - Immersive AR-Style Call View
    
    private var immersiveCallView: some View {
        GeometryReader { geometry in
            ZStack {
                // Full-screen background video
                fullScreenVideoBackground
                
                // Floating local video PiP
                floatingPiP(in: geometry)
                
                // Floating transcript bubble
                if showTranscript {
                    floatingTranscript
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Glassmorphism controls overlay
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }
                
                // Screen sharing indicator
                if zoomService.isScreenSharing {
                    screenShareIndicator
                }
            }
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showControls.toggle()
                }
                resetControlsTimer()
            }
        }
        .statusBarHidden(!showControls)
        .confirmationDialog("End Call?", isPresented: $showEndCallConfirmation) {
            Button("End Call & Save Transcript", role: .destructive) { endCallAndSave() }
            Button("End Call Without Saving", role: .destructive) { endCallWithoutSaving() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to save the transcript from this call?")
        }
        .sheet(isPresented: $showShareSheet) {
            let inviteText = sessionPassword.isEmpty 
                ? "Join my video call!\n\nSession: \(zoomService.sessionName)"
                : "Join my video call!\n\nSession: \(zoomService.sessionName)\nPasscode: \(sessionPassword)"
            ShareSheet(items: [inviteText])
        }
        .onAppear { resetControlsTimer() }
    }
    
    // MARK: - Full Screen Video Background
    
    private var fullScreenVideoBackground: some View {
        Group {
            if let shareUser = zoomService.activeShareUser {
                // Someone is sharing their screen
                ZoomShareView(user: shareUser)
            } else if let remoteUser = zoomService.remoteUsers.first {
                // Remote participant video fills screen
                ZoomVideoView(user: remoteUser)
            } else {
                // Waiting for others - ambient background
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.1, green: 0.1, blue: 0.2), Color.black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // Animated particles/orbs for AR feel
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.blue.opacity(0.3), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)
                            .offset(x: CGFloat.random(in: -100...100), y: CGFloat.random(in: -200...200))
                            .blur(radius: 20)
                    }
                    
                    VStack(spacing: 16) {
                        Image(systemName: "waveform.circle")
                            .font(.system(size: 80, weight: .thin))
                            .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .symbolEffect(.pulse, options: .repeating)
                        
                        Text("Waiting for others...")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
    }
    
    // MARK: - Floating PiP
    
    private func floatingPiP(in geometry: GeometryProxy) -> some View {
        let pipSize: CGFloat = 120
        let pipHeight: CGFloat = pipSize * 1.33
        
        return ZStack {
            if !isVideoOff, let localUser = zoomService.localUser {
                ZoomVideoView(user: localUser)
                    .frame(width: pipSize, height: pipHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                    .contentShape(Rectangle())
                    .offset(x: pipOffset.width, y: pipOffset.height)
                    .position(pipPosition)
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                pipOffset = value.translation
                            }
                            .onEnded { value in
                                let newX = pipPosition.x + value.translation.width
                                let newY = pipPosition.y + value.translation.height
                                pipOffset = .zero
                                
                                // Snap to edges
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    let padding: CGFloat = pipSize / 2 + 16
                                    let x = newX < geometry.size.width / 2 ? padding : geometry.size.width - padding
                                    let y = max(100, min(geometry.size.height - 200, newY))
                                    pipPosition = CGPoint(x: x, y: y)
                                }
                            }
                    )
            } else {
                // Video off indicator
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: pipSize, height: pipSize)
                    .overlay(
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.6))
                    )
                    .contentShape(Rectangle())
                    .offset(x: pipOffset.width, y: pipOffset.height)
                    .position(pipPosition)
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                pipOffset = value.translation
                            }
                            .onEnded { value in
                                let newX = pipPosition.x + value.translation.width
                                let newY = pipPosition.y + value.translation.height
                                pipOffset = .zero
                                
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    let padding: CGFloat = pipSize / 2 + 16
                                    let x = newX < geometry.size.width / 2 ? padding : geometry.size.width - padding
                                    let y = max(100, min(geometry.size.height - 200, newY))
                                    pipPosition = CGPoint(x: x, y: y)
                                }
                            }
                    )
            }
        }
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                // Minimize button - dismiss to see tabs, call continues in background
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                
                Spacer()
                
                // Session info
                VStack(spacing: 2) {
                    Text(zoomService.sessionName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("\(zoomService.remoteUsers.count + 1) connected")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                
                Spacer()
                
                // Invite button
                Button(action: { showShareSheet = true }) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            
            Spacer()
            
            // Bottom controls
            VStack(spacing: 20) {
                // Transcript toggle
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showTranscript.toggle()
                    }
                    isTranscribing = showTranscript
                    if showTranscript { startTranscription() }
                    else { stopTranscription() }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: showTranscript ? "text.bubble.fill" : "text.bubble")
                        Text(showTranscript ? "Hide Transcript" : "Show Transcript")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                
                // Main control buttons
                HStack(spacing: 24) {
                    // Mute
                    controlButton(
                        icon: isMuted ? "mic.slash.fill" : "mic.fill",
                        label: isMuted ? "Unmute" : "Mute",
                        isActive: isMuted,
                        action: toggleMute
                    )
                    
                    // Video
                    controlButton(
                        icon: isVideoOff ? "video.slash.fill" : "video.fill",
                        label: isVideoOff ? "Start" : "Stop",
                        isActive: isVideoOff,
                        action: toggleVideo
                    )
                    
                    // Screen Share
                    controlButton(
                        icon: zoomService.isScreenSharing ? "rectangle.on.rectangle.slash.fill" : "rectangle.on.rectangle",
                        label: zoomService.isScreenSharing ? "Stop" : "Share",
                        isActive: zoomService.isScreenSharing,
                        activeColor: .green,
                        action: { zoomService.toggleScreenShare() }
                    )
                    
                    // End call
                    controlButton(
                        icon: "phone.down.fill",
                        label: "End",
                        isActive: true,
                        activeColor: .red,
                        action: { showEndCallConfirmation = true }
                    )
                }
            }
            .padding(.bottom, 100)
        }
    }
    
    private func controlButton(
        icon: String,
        label: String,
        isActive: Bool,
        activeColor: Color = .red,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        isActive 
                            ? AnyShapeStyle(activeColor)
                            : AnyShapeStyle(.ultraThinMaterial)
                    )
                    .clipShape(Circle())
                    .shadow(color: isActive ? activeColor.opacity(0.5) : .clear, radius: 8, x: 0, y: 4)
                
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
    
    // MARK: - Floating Transcript
    
    private var floatingTranscript: some View {
        VStack {
            Spacer()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(isTranscribing ? 1 : 0)
                        Text("Live Transcript")
                            .font(.subheadline.weight(.semibold))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showTranscript = false
                        }
                        stopTranscription()
                        isTranscribing = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                
                ScrollView {
                    Text(zoomService.currentTranscript.isEmpty ? "Listening..." : zoomService.currentTranscript)
                        .font(.system(size: 14))
                        .foregroundColor(zoomService.currentTranscript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, showControls ? 200 : 40)
        }
    }
    
    // MARK: - Screen Share Indicator
    
    private var screenShareIndicator: some View {
        VStack {
            HStack {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                Text("Sharing your screen")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.green, in: Capsule())
            .padding(.top, showControls ? 110 : 60)
            
            Spacer()
        }
    }
    
    // MARK: - Timer for auto-hiding controls
    
    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
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