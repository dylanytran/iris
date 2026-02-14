//
//  FallDetectionService.swift
//  treehacks
//
//  Fall detection using Core Motion accelerometer data.
//  Detects sudden drops (free-fall) followed by impact.
//

import Foundation
import CoreMotion
import UserNotifications
import Combine

/// Service that monitors device motion to detect potential falls.
/// When a fall is detected, it sends a local push notification.
class FallDetectionService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isMonitoring = false
    @Published var lastFallDetected: Date?
    @Published var fallCount = 0
    @Published var isCallingEmergency = false
    
    // MARK: - Private Properties
    
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    
    /// Threshold for detecting free-fall (low acceleration magnitude).
    /// During free-fall, acceleration approaches 0g.
    /// Lower value = stricter detection (must be more "weightless")
    private let freeFallThreshold: Double = 0.2
    
    /// Threshold for detecting impact (high acceleration magnitude).
    /// Impact typically shows 2-3g or more.
    /// Higher value = stricter detection (must be harder impact)
    private let impactThreshold: Double = 3.5
    
    /// Time window to detect impact after free-fall (in seconds).
    private let impactWindowDuration: TimeInterval = 0.5
    
    /// Cooldown period between fall detections to prevent spam.
    private let fallCooldown: TimeInterval = 10.0
    
    /// Tracks when free-fall was detected.
    private var freeFallStartTime: Date?
    
    /// Tracks the last time a fall was reported.
    private var lastFallReportTime: Date?
    
    // MARK: - Initialization
    
    init() {
        motionQueue.name = "com.treehacks.falldetection"
        motionQueue.maxConcurrentOperationCount = 1
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Request notification permissions for fall alerts.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("FallDetection: Notification permission error: \(error.localizedDescription)")
            } else {
                print("FallDetection: Notification permission granted: \(granted)")
            }
        }
    }
    
    /// Start monitoring for falls.
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        guard motionManager.isAccelerometerAvailable else {
            print("FallDetection: Accelerometer not available")
            return
        }
        
        // Set update interval to 100Hz for responsive detection
        motionManager.accelerometerUpdateInterval = 0.01
        
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            self.processAccelerometerData(data)
        }
        
        DispatchQueue.main.async {
            self.isMonitoring = true
        }
        
        print("FallDetection: Started monitoring")
    }
    
    /// Stop monitoring for falls.
    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
        
        DispatchQueue.main.async {
            self.isMonitoring = false
        }
        
        freeFallStartTime = nil
        print("FallDetection: Stopped monitoring")
    }
    
    // MARK: - Private Methods
    
    private func processAccelerometerData(_ data: CMAccelerometerData) {
        // Calculate total acceleration magnitude
        // At rest, this is ~1g (gravity). During free-fall, it approaches 0.
        let acceleration = data.acceleration
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        
        let now = Date()
        
        // Phase 1: Detect free-fall (very low acceleration)
        if magnitude < freeFallThreshold {
            if freeFallStartTime == nil {
                freeFallStartTime = now
                print("FallDetection: Free-fall detected at magnitude \(magnitude)")
            }
        }
        // Phase 2: Detect impact (high acceleration after free-fall)
        else if magnitude > impactThreshold {
            if let fallStart = freeFallStartTime {
                let timeSinceFreeFall = now.timeIntervalSince(fallStart)
                
                // Impact must occur within the time window after free-fall
                if timeSinceFreeFall < impactWindowDuration {
                    // Check cooldown to prevent duplicate alerts
                    let shouldReport = lastFallReportTime == nil ||
                        now.timeIntervalSince(lastFallReportTime!) > fallCooldown
                    
                    if shouldReport {
                        print("FallDetection: FALL DETECTED! Impact magnitude: \(magnitude)")
                        lastFallReportTime = now
                        onFallDetected()
                    }
                }
                
                freeFallStartTime = nil
            }
        }
        // Reset free-fall detection if neither condition is met and too much time passed
        else if let fallStart = freeFallStartTime {
            if now.timeIntervalSince(fallStart) > impactWindowDuration {
                freeFallStartTime = nil
            }
        }
    }
    
    private func onFallDetected() {
        DispatchQueue.main.async {
            self.lastFallDetected = Date()
            self.fallCount += 1
            self.triggerEmergencyCall()
        }
        
        sendFallNotification()
    }
    
    // MARK: - Emergency Call
    
    /// Simulate a fall for testing purposes
    func simulateFall() {
        print("FallDetection: Simulating fall for testing")
        DispatchQueue.main.async {
            self.lastFallDetected = Date()
            self.fallCount += 1
            self.triggerEmergencyCall()
        }
    }
    
    /// Immediately trigger emergency call via VAPI
    private func triggerEmergencyCall() {
        isCallingEmergency = true
        
        print("FallDetection: Triggering emergency call via VAPI immediately")
        
        // Call VAPI service
        VAPIService.shared.makeEmergencyCall { [weak self] success in
            DispatchQueue.main.async {
                self?.isCallingEmergency = false
                if success {
                    print("FallDetection: Emergency call initiated successfully")
                } else {
                    print("FallDetection: Failed to initiate emergency call")
                }
            }
        }
    }
    
    private func sendFallNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Fall Detected - Calling Emergency Contact"
        content.body = "A fall was detected. An emergency call is being placed to your contact."
        content.sound = .defaultCritical
        
        // Deliver immediately
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("FallDetection: Failed to send notification: \(error.localizedDescription)")
            } else {
                print("FallDetection: Notification sent successfully")
            }
        }
    }
}
