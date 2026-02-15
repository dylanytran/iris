//
//  ContentView.swift
//  treehacks
//
//  Created by Dylan Tran on 2/13/26.
//

import SwiftUI
import ZoomVideoSDK

/// Root view with tab-based navigation.
/// Designed with large, clear icons and labels for accessibility.
struct ContentView: View {

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var clipManager = ClipManager()
    @StateObject private var fallDetectionService = FallDetectionService()
    @ObservedObject private var zoomService = ZoomService.shared
    @State private var recordingManager: RecordingManager?
    @State private var showFullCallView = false
    @State private var showMiniControls = true

    var body: some View {
        Group {
            if let recordingManager = recordingManager {
                TabView {
                    // Camera Tab
                    MainCameraView(
                        cameraManager: cameraManager,
                        recordingManager: recordingManager,
                        clipManager: clipManager
                    )
                    .tabItem {
                        Image(systemName: "camera.fill")
                        Text("Camera")
                    }

                    // Contacts tab
                    ContactsView()
                        .tabItem {
                            Image(systemName: "person.3.fill")
                            Text("Contacts")
                        }
                    
                    // Tasks Tab
                    TasksListView()
                        .tabItem {
                            Image(systemName: "checklist")
                            Text("Tasks")
                        }

                    // Settings Tab
                    SettingsView(fallDetectionService: fallDetectionService, clipManager: clipManager, onStartZoomCall: {
                        showFullCallView = true
                    })
                        .tabItem {
                            Image(systemName: "gear")
                            Text("Settings")
                        }
                }
                .tint(.blue)
                .onAppear {
                    fallDetectionService.requestNotificationPermission()
                }
                .overlay(alignment: .bottom) {
                    // Global floating call overlay when in Zoom session but minimized
                    if zoomService.isInSession && !showFullCallView {
                        floatingCallOverlay
                            .padding(.bottom, 90) // Above tab bar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: zoomService.isInSession)
            } else {
                ProgressView("Setting up...")
                    .onAppear {
                        recordingManager = RecordingManager(cameraManager: cameraManager)
                    }
            }
        }
        .fullScreenCover(isPresented: $showFullCallView) {
            ZoomCallView()
        }
    }
    
    // MARK: - Floating Call Overlay
    
    private var floatingCallOverlay: some View {
        HStack(spacing: 12) {
            // Remote video thumbnail
            if let remoteUser = zoomService.remoteUsers.first {
                ZoomVideoView(user: remoteUser)
                    .frame(width: 60, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 80)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.white.opacity(0.6))
                    )
            }
            
            // Call info and expand button
            VStack(alignment: .leading, spacing: 4) {
                Text(zoomService.sessionName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("In Call")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer(minLength: 8)
            
            // Quick controls
            if showMiniControls {
                HStack(spacing: 8) {
                    miniControlButton(icon: zoomService.isMuted ? "mic.slash.fill" : "mic.fill", isActive: zoomService.isMuted) {
                        zoomService.toggleMute()
                    }
                    
                    miniControlButton(icon: "arrow.up.left.and.arrow.down.right", isActive: false) {
                        showFullCallView = true
                    }
                    
                    miniControlButton(icon: "phone.down.fill", isActive: true, activeColor: .red) {
                        _ = zoomService.leaveSession()
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 16)
        .fixedSize(horizontal: false, vertical: true)
        .onTapGesture {
            showFullCallView = true
        }
    }
    
    private func miniControlButton(icon: String, isActive: Bool, activeColor: Color = .red, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(isActive ? activeColor : Color.white.opacity(0.2), in: Circle())
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var fallDetectionService: FallDetectionService
    @ObservedObject var clipManager: ClipManager
    var onStartZoomCall: () -> Void
    @AppStorage("recordingDuration") private var maxRecordingMinutes: Double = 5
    @AppStorage("fallDetectionEnabled") private var fallDetectionEnabled: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $fallDetectionEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fall Detection")
                                .font(.system(size: 16, weight: .medium))
                            if fallDetectionService.isMonitoring {
                                Text("Monitoring active")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .onChange(of: fallDetectionEnabled) { _, newValue in
                        if newValue {
                            fallDetectionService.startMonitoring()
                        } else {
                            fallDetectionService.stopMonitoring()
                        }
                    }
                    
                    if fallDetectionService.fallCount > 0 {
                        HStack {
                            Text("Falls detected")
                            Spacer()
                            Text("\(fallDetectionService.fallCount)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Test button for development
                    Button(action: {
                        fallDetectionService.simulateFall()
                    }) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                            Text("Test Fall Alert")
                        }
                        .foregroundColor(.orange)
                    }
                } header: {
                    Text("Safety")
                } footer: {
                    Text("When a fall is detected, an emergency call will be made immediately to your contact via VAPI.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keep recordings for")
                            .font(.system(size: 16, weight: .medium))
                        Picker("Duration", selection: $maxRecordingMinutes) {
                            Text("2 minutes").tag(2.0)
                            Text("5 minutes").tag(5.0)
                            Text("10 minutes").tag(10.0)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Memory Recording")
                } footer: {
                    Text("Longer durations use more storage space.")
                }

                Section {
                    NavigationLink {
                        ClipDebugView(clipManager: clipManager)
                    } label: {
                        HStack {
                            Image(systemName: "film.stack")
                                .foregroundColor(.blue)
                            Text("Clips Debug")
                        }
                    }
                    
                    Button(action: onStartZoomCall) {
                        HStack {
                            Image(systemName: "video.fill")
                                .foregroundColor(.green)
                            Text("Zoom Call")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Debug")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                // Resume monitoring if it was previously enabled
                if fallDetectionEnabled && !fallDetectionService.isMonitoring {
                    fallDetectionService.startMonitoring()
                }
            }
        }
    }

}

#Preview {
    ContentView()
}