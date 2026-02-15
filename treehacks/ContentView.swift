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
                        SettingsView(fallDetectionService: fallDetectionService, clipManager: clipManager)
                            .tabItem {
                                Image(systemName: "gear")
                                Text("Settings")
                            }
                    }
                    .tint(.blue)
                    .onAppear {
                        fallDetectionService.requestNotificationPermission()
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
    @ObservedObject var clipManager: ClipManager
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
                    
                    NavigationLink {
                        ZoomCallView()
                    } label: {
                        HStack {
                            Image(systemName: "video.fill")
                                .foregroundColor(.green)
                            Text("Zoom Call")
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
