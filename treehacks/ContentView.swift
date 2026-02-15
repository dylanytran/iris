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
    @State private var selectedTab = 0
    @State private var cameraTabBarExpanded = false
    
    // Draggable floating call overlay state
    @State private var floatingCallOffset: CGSize = .zero
    @State private var floatingCallPosition: CGPoint = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height - 180)

    var body: some View {
        Group {
            if let recordingManager = recordingManager {
                TabView(selection: $selectedTab) {
                    // Camera Tab
                    MainCameraView(
                        cameraManager: cameraManager,
                        recordingManager: recordingManager,
                        clipManager: clipManager
                    )
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem {
                        Image(systemName: "camera.fill")
                        Text("Camera")
                    }
                    .tag(0)

                    // Contacts tab
                    ContactsView()
                        .tabItem {
                            Image(systemName: "person.3.fill")
                            Text("Contacts")
                        }
                        .tag(1)
                    
                    // Tasks Tab
                    TasksListView()
                        .tabItem {
                            Image(systemName: "checklist")
                            Text("Tasks")
                        }
                        .tag(2)

                    // Settings Tab
                    SettingsView(fallDetectionService: fallDetectionService, clipManager: clipManager, onStartZoomCall: {
                        showFullCallView = true
                    })
                        .tabItem {
                            Image(systemName: "gear")
                            Text("Settings")
                        }
                        .tag(3)
                }
                .tint(.blue)
                .overlay {
                    if selectedTab == 0 {
                        VStack {
                            Spacer()
                            if cameraTabBarExpanded {
                                expandedCameraTabBar
                            } else {
                                HStack {
                                    Spacer()
                                    collapsedCameraTabButton
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.bottom, 16)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: cameraTabBarExpanded)
                    }
                }
                .onChange(of: selectedTab) { _, newTab in
                    if newTab != 0 {
                        cameraTabBarExpanded = false
                    }
                }
                .onAppear {
                    fallDetectionService.requestNotificationPermission()
                }
                .overlay {
                    // Global floating call overlay when in Zoom session but minimized
                    if zoomService.isInSession && !showFullCallView {
                        GeometryReader { geometry in
                            floatingCallOverlay(in: geometry)
                        }
                        .transition(.opacity)
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
    
    // MARK: - Custom Camera Tab Bar
    
    private var expandedCameraTabBar: some View {
        HStack(spacing: 2) {
            cameraTabItem(icon: "camera.fill", label: "Camera", tag: 0)
            cameraTabItem(icon: "person.3.fill", label: "Contacts", tag: 1)
            cameraTabItem(icon: "checklist", label: "Tasks", tag: 2)
            cameraTabItem(icon: "gear", label: "Settings", tag: 3)
            
            // Collapse button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    cameraTabBarExpanded = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(.horizontal, 20)
        .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
    }
    
    private var collapsedCameraTabButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                cameraTabBarExpanded = true
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        }
        .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
    }
    
    private func cameraTabItem(icon: String, label: String, tag: Int) -> some View {
        Button {
            if tag == 0 {
                // Already on camera, just collapse
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    cameraTabBarExpanded = false
                }
            } else {
                selectedTab = tag
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(tag == 0 ? .blue : .white.opacity(0.75))
            .frame(width: 62, height: 44)
        }
    }
    
    // MARK: - Floating Call Overlay
    
    private func floatingCallOverlay(in geometry: GeometryProxy) -> some View {
        HStack(spacing: 12) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.4))
                .frame(width: 4, height: 30)
            
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
        .fixedSize(horizontal: false, vertical: true)
        .offset(x: floatingCallOffset.width, y: floatingCallOffset.height)
        .position(floatingCallPosition)
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    floatingCallOffset = value.translation
                }
                .onEnded { value in
                    let newX = floatingCallPosition.x + value.translation.width
                    let newY = floatingCallPosition.y + value.translation.height
                    floatingCallOffset = .zero
                    
                    withAnimation(.interpolatingSpring(stiffness: 200, damping: 25)) {
                        let padding: CGFloat = 100
                        let x = max(padding, min(geometry.size.width - padding, newX))
                        let y = max(120, min(geometry.size.height - 120, newY))
                        floatingCallPosition = CGPoint(x: x, y: y)
                    }
                }
        )
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
                                .foregroundColor(.blue)
                            Text("Zoom Call")
                                .foregroundColor(.primary)
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