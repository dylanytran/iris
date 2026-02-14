//
//  VAPIService.swift
//  treehacks
//
//  Service to make emergency calls via VAPI (Voice AI Platform).
//  When a fall is detected and user doesn't respond, this initiates an AI-assisted call.
//

import Foundation

/// Service for making emergency calls through VAPI
class VAPIService {
    
    static let shared = VAPIService()
    
    // MARK: - Configuration
    
    /// VAPI API endpoint for outbound calls
    private let vapiBaseURL = "https://api.vapi.ai/call/phone"
    
    /// Riley Fall Detection Assistant ID
    private let assistantId = "788457f4-6bf9-44c8-86d0-62ab2421778f"
    
    /// VAPI Phone Number ID for outbound calls
    private let phoneNumberId = "e6906873-4d47-4206-8295-b4df863f28f2"
    
    /// Your VAPI API key - should be stored in Secrets.plist
    private var apiKey: String {
        print("VAPIService: Looking for Secrets.plist...")
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist") else {
            print("VAPIService: ❌ Secrets.plist file not found in bundle")
            return ""
        }
        print("VAPIService: Found Secrets.plist at: \(path)")
        
        guard let dict = NSDictionary(contentsOfFile: path) else {
            print("VAPIService: ❌ Could not read Secrets.plist as dictionary")
            return ""
        }
        print("VAPIService: Secrets.plist keys: \(dict.allKeys)")
        
        guard let key = dict["VAPIAPIKey"] as? String else {
            print("VAPIService: ❌ VAPIAPIKey not found in Secrets.plist")
            return ""
        }
        print("VAPIService: ✅ Found VAPIAPIKey: \(key.prefix(8))...")
        return key
    }
    
    /// Emergency contact phone number
    private let emergencyPhoneNumber = "+17734318347"
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Make an emergency call to the configured contact
    /// - Parameter completion: Called with success/failure status
    func makeEmergencyCall(completion: @escaping (Bool) -> Void) {
        print("VAPIService: ======== makeEmergencyCall() CALLED ========")
        
        guard !apiKey.isEmpty else {
            print("VAPIService: ❌ No API key configured - aborting call")
            completion(false)
            return
        }
        
        // Build the VAPI call request
        guard let url = URL(string: vapiBaseURL) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Call payload for VAPI outbound call
        let payload: [String: Any] = [
            "assistantId": assistantId,
            "phoneNumberId": phoneNumberId,
            "customer": [
                "number": emergencyPhoneNumber
            ]
        ]
        
        // Log the payload for debugging
        print("VAPIService: === OUTBOUND CALL REQUEST ===")
        print("VAPIService: URL: \(vapiBaseURL)")
        print("VAPIService: Assistant ID: \(assistantId)")
        print("VAPIService: Phone Number ID: \(phoneNumberId)")
        print("VAPIService: Customer Number: \(emergencyPhoneNumber)")
        if let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let payloadString = String(data: payloadData, encoding: .utf8) {
            print("VAPIService: Payload JSON:\n\(payloadString)")
        }
        print("VAPIService: =============================")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("VAPIService: Failed to serialize request: \(error)")
            completion(false)
            return
        }
        
        print("VAPIService: Initiating emergency call to \(emergencyPhoneNumber)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("VAPIService: ❌ Network error: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("VAPIService: ❌ No HTTP response received")
                completion(false)
                return
            }
            
            print("VAPIService: HTTP Status Code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                print("VAPIService: ✅ Emergency call initiated successfully")
                
                // Log response for debugging
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("VAPIService: Response:\n\(responseString)")
                }
                
                completion(true)
            } else {
                print("VAPIService: ❌ Call failed with status \(httpResponse.statusCode)")
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    print("VAPIService: Error Response:\n\(errorString)")
                }
                // Log response headers for debugging
                print("VAPIService: Response Headers: \(httpResponse.allHeaderFields)")
                completion(false)
            }
        }.resume()
    }
    
    // MARK: - Configuration Helpers
    
    /// Check if VAPI is properly configured
    var isConfigured: Bool {
        !apiKey.isEmpty
    }
}
