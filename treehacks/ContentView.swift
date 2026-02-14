//
//  ContentView.swift
//  treehacks
//
//  Created by Dylan Tran on 2/13/26.
//

import SwiftUI
import SwiftData

/// Root view with tab-based navigation.
/// Designed with large, clear icons and labels for accessibility.
struct ContentView: View {

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var faceRecognitionService = FaceRecognitionService()
    @StateObject private var clipManager = ClipManager()
    @StateObject private var fallDetectionService = FallDetectionService()
    @State private var recordingManager: RecordingManager?

    var body: some View {
        Group {
            if let recordingManager = recordingManager {
                TabView {
                    // Camera Tab
                    MainCameraView(
                        cameraManager: cameraManager,
                        recordingManager: recordingManager,
                        faceRecognitionService: faceRecognitionService,
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

                    // People Tab
                    PeopleListView(cameraManager: cameraManager)
                        .tabItem {
                            Image(systemName: "person.2.fill")
                            Text("People")
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
            } else {
                ProgressView("Setting up...")
                    .onAppear {
                        recordingManager = RecordingManager(cameraManager: cameraManager)
                    }
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var fallDetectionService: FallDetectionService
    @AppStorage("recordingDuration") private var maxRecordingMinutes: Double = 5
    @AppStorage("faceMatchSensitivity") private var matchSensitivity: Double = 0.35
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
                } header: {
                    Text("Safety")
                } footer: {
                    Text("When enabled, the app will send a notification if it detects a sudden fall.")
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Match Sensitivity")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            Text(sensitivityLabel)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $matchSensitivity, in: 0.1...0.6, step: 0.05)
                            .tint(.blue)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Face Recognition")
                } footer: {
                    Text("Higher sensitivity means stricter matching (fewer false positives). Lower means more lenient (may match incorrectly).")
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

                        Label("Face Recognition", systemImage: "person.viewfinder")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Register friends and family in the People tab. When the camera sees them, their name will appear above their head.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        Label("Fall Detection", systemImage: "figure.fall")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Enable fall detection in Safety settings. If the phone detects a sudden drop and impact, you'll receive an alert notification.")
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

    private var sensitivityLabel: String {
        if matchSensitivity < 0.2 { return "Very Lenient" }
        if matchSensitivity < 0.3 { return "Lenient" }
        if matchSensitivity < 0.4 { return "Normal" }
        if matchSensitivity < 0.5 { return "Strict" }
        return "Very Strict"
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Person.self, inMemory: true)
}
