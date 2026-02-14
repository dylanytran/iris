//
//  ContentView.swift
//  treehacks
//
//  Created by Dylan Tran on 2/13/26.
//

import SwiftUI

/// Root view with tab-based navigation.
/// Designed with large, clear icons and labels for accessibility.
struct ContentView: View {

    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var clipManager = ClipManager()
    @StateObject private var fallDetectionService = FallDetectionService()
    @State private var recordingManager: RecordingManager?

    var body: some View {
        ZStack {
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

                        // Clips Debug Tab
                        ClipDebugView(clipManager: clipManager)
                            .tabItem {
                                Image(systemName: "film.stack")
                                Text("Clips")
                            }

                        // Contacts tab
                        ContactsView()
                            .tabItem {
                                Image(systemName: "person.3.fill")
                                Text("Contacts")
                            }
                        
                        // Instructions Tab (Zoom Call Transcripts)
                        InstructionsListView()
                            .tabItem {
                                Image(systemName: "doc.text.fill")
                                Text("Instructions")
                            }

                        // Settings Tab
                        SettingsView(fallDetectionService: fallDetectionService)
                            .tabItem {
                                Image(systemName: "gear")
                                Text("Settings")
                            }
                    }
                    .tint(.blue)
                    .onAppear {
                        fallDetectionService.requestNotificationPermission()
                    }
                    .sheet(isPresented: $deepLinkManager.shouldShowZoomCall) {
                        ZoomCallView(initialSessionName: deepLinkManager.pendingSessionName)
                            .onDisappear {
                                deepLinkManager.pendingSessionName = nil
                            }
                    }
                } else {
                    ProgressView("Setting up...")
                        .onAppear {
                            recordingManager = RecordingManager(cameraManager: cameraManager)
                        }
                }
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var fallDetectionService: FallDetectionService
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
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Memory Recall", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                        Text("The app continuously records what you see. Tap \"Recall Memory\" to go back in time and see where you placed something.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)

                        Divider()

                        Label("Voice Query", systemImage: "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Tap \"Ask\" and speak a question like \"Where did I put my keys?\" The app will find and play the most relevant clip from the last 60 seconds.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)

                        Divider()

                        Label("Facial Recognition", systemImage: "faceid")
                            .font(.system(size: 16, weight: .semibold))
                        Text("The camera uses AR and Vision to detect faces in real time. When a face matches a saved contact, their name and relationship appear as a floating label above their head — helping you remember who you're talking to.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)

                        Divider()
                        
                        Label("Fall Detection", systemImage: "figure.fall")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Enable fall detection in Safety settings. If the phone detects a sudden drop and impact, an emergency call will be placed immediately to your contact.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("How It Works")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Built at")
                        Spacer()
                        Text("TreeHacks 2026")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
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
