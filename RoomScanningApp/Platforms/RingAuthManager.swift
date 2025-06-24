import Foundation
import AuthenticationServices

// MARK: - Ring Authentication Manager
class RingAuthManager: ObservableObject, PlatformAuthManager {
    private let authURL = "https://oauth.ring.com/oauth/authorize"
    private let tokenURL = "https://oauth.ring.com/oauth/token"
    private let baseURL = "https://api.ring.com/clients_api"
    
    // TODO: Replace with your actual credentials from Ring Developer Portal
    private let clientId = "YOUR_RING_CLIENT_ID"
    private let clientSecret = "YOUR_RING_CLIENT_SECRET"
    private let redirectURI = "roomscanningapp://oauth/ring"
    private let scope = "client"
    
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var refreshToken: String?
    
    func authenticate() async throws -> PlatformCredentials {
        let state = UUID().uuidString
        
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state)
        ]
        
        guard let authURL = components.url else {
            throw PlatformError.authenticationFailed("Invalid authorization URL")
        }
        
        // Use ASWebAuthenticationSession for OAuth flow
        let authCode = try await performOAuthFlow(authURL: authURL, redirectURI: redirectURI)
        
        // Exchange authorization code for tokens
        let tokens = try await exchangeCodeForTokens(authCode: authCode)
        
        self.accessToken = tokens.accessToken
        self.refreshToken = tokens.refreshToken
        self.isAuthenticated = true
        
        return PlatformCredentials(
            platform: .ring,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt
        )
    }
    
    private func performOAuthFlow(authURL: URL, redirectURI: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "roomscanningapp") { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: PlatformError.authenticationFailed(error.localizedDescription))
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "code" })?
                        .value else {
                    continuation.resume(throwing: PlatformError.authenticationFailed("No authorization code received"))
                    return
                }
                
                continuation.resume(returning: code)
            }
            
            session.presentationContextProvider = nil
            session.start()
        }
    }
    
    private func exchangeCodeForTokens(authCode: String) async throws -> (accessToken: String, refreshToken: String, expiresAt: Date) {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": authCode,
            "redirect_uri": redirectURI
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.authenticationFailed("Token exchange failed")
        }
        
        let tokenResponse = try JSONDecoder().decode(RingTokenResponse.self, from: data)
        
        return (
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        )
    }
    
    func discoverDevices(credentials: PlatformCredentials) async throws -> [PlatformDevice] {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        guard let url = URL(string: "\(baseURL)/ring_devices") else {
            throw PlatformError.deviceDiscoveryFailed("Invalid devices URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to discover devices")
        }
        
        let devicesResponse = try JSONDecoder().decode(RingDevicesResponse.self, from: data)
        
        var allDevices: [PlatformDevice] = []
        
        // Add doorbells
        allDevices.append(contentsOf: devicesResponse.doorbots.map { doorbell in
            PlatformDevice(
                id: doorbell.id,
                name: doorbell.description,
                type: .smartCamera,
                platform: .ring,
                capabilities: buildDoorbellCapabilities(from: doorbell),
                isOnline: doorbell.alerts?.connection == "online"
            )
        })
        
        // Add cameras
        allDevices.append(contentsOf: devicesResponse.stickupCams.map { camera in
            PlatformDevice(
                id: camera.id,
                name: camera.description,
                type: .smartCamera,
                platform: .ring,
                capabilities: buildCameraCapabilities(from: camera),
                isOnline: camera.alerts?.connection == "online"
            )
        })
        
        // Add chimes
        allDevices.append(contentsOf: devicesResponse.chimes.map { chime in
            PlatformDevice(
                id: chime.id,
                name: chime.description,
                type: .smartSpeaker,
                platform: .ring,
                capabilities: ["audio", "notifications"],
                isOnline: chime.alerts?.connection == "online"
            )
        })
        
        return allDevices
    }
    
    private func buildDoorbellCapabilities(from doorbell: RingDoorbell) -> [String] {
        var capabilities: [String] = ["camera", "motionDetection", "doorbell", "twoWayAudio"]
        
        if doorbell.features?.motionDetection == true {
            capabilities.append("motionDetection")
        }
        
        if doorbell.features?.videoRecording == true {
            capabilities.append("videoRecording")
        }
        
        if doorbell.features?.nightVision == true {
            capabilities.append("nightVision")
        }
        
        return capabilities
    }
    
    private func buildCameraCapabilities(from camera: RingStickupCam) -> [String] {
        var capabilities: [String] = ["camera", "motionDetection", "twoWayAudio"]
        
        if camera.features?.motionDetection == true {
            capabilities.append("motionDetection")
        }
        
        if camera.features?.videoRecording == true {
            capabilities.append("videoRecording")
        }
        
        if camera.features?.nightVision == true {
            capabilities.append("nightVision")
        }
        
        return capabilities
    }
    
    func executeAction(_ action: DeviceAction, on device: PlatformDevice, credentials: PlatformCredentials, parameters: [String: Any]?) async throws {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        let endpoint = buildActionEndpoint(action: action, deviceId: device.id)
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw PlatformError.actionFailed("Invalid action URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = buildActionBody(action: action, parameters: parameters)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.actionFailed("Failed to execute action")
        }
    }
    
    private func buildActionEndpoint(action: DeviceAction, deviceId: String) -> String {
        switch action {
        case .takePhoto:
            return "devices/\(deviceId)/take_photo"
        case .startRecording:
            return "devices/\(deviceId)/recording_status"
        case .stopRecording:
            return "devices/\(deviceId)/recording_status"
        default:
            return "devices/\(deviceId)/status"
        }
    }
    
    private func buildActionBody(action: DeviceAction, parameters: [String: Any]?) -> [String: Any] {
        switch action {
        case .takePhoto:
            // Implementation needed
            return [:]
        case .startRecording:
            return ["recording_status": "start"]
        case .stopRecording:
            return ["recording_status": "stop"]
        default:
            break
        }
        
        return [:]
    }
    
    func getDeviceStatus(_ device: PlatformDevice, credentials: PlatformCredentials) async throws -> DeviceStatus {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        guard let url = URL(string: "\(baseURL)/devices/\(device.id)") else {
            throw PlatformError.deviceStatusFailed("Invalid device URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceStatusFailed("Failed to get device status")
        }
        
        // Parse device status based on device type
        let deviceData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        var status = DeviceStatus()
        status.isOnline = deviceData?["connection"] as? String == "online"
        status.isOn = true // Ring devices are always "on" when online
        // Set other properties as needed
        return status
    }
    
    func authenticate(with apiKey: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("API key authentication not supported for Ring.")
    }
    
    func authenticate(with token: String, hubIP: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("Token/hubIP authentication not supported for Ring.")
    }
    
    func discoverDevices() async throws -> [SmartDevice] {
        // For now, return empty array since we need proper authentication
        // This method should be called after authenticate() has been called
        guard isAuthenticated, let accessToken = accessToken else {
            throw PlatformError.authenticationFailed("Not authenticated. Please authenticate first.")
        }
        
        let credentials = PlatformCredentials(
            platform: .ring,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: nil
        )
        
        let platformDevices = try await discoverDevices(credentials: credentials)
        
        // Convert PlatformDevice to SmartDevice
        return platformDevices.map { platformDevice in
            SmartDevice(
                name: platformDevice.name,
                type: platformDevice.type,
                position: SIMD3<Float>(0, 0, 0) // Default position, will be set when placed in room
            )
        }
    }
}

// MARK: - Ring API Models
struct RingTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct RingDevicesResponse: Codable {
    let doorbots: [RingDoorbell]
    let stickupCams: [RingStickupCam]
    let chimes: [RingChime]
    
    enum CodingKeys: String, CodingKey {
        case doorbots = "doorbots"
        case stickupCams = "stickup_cams"
        case chimes = "chimes"
    }
}

struct RingDoorbell: Codable {
    let id: String
    let description: String
    let alerts: RingAlerts?
    let features: RingFeatures?
    
    enum CodingKeys: String, CodingKey {
        case id, description, alerts, features
    }
}

struct RingStickupCam: Codable {
    let id: String
    let description: String
    let alerts: RingAlerts?
    let features: RingFeatures?
    
    enum CodingKeys: String, CodingKey {
        case id, description, alerts, features
    }
}

struct RingChime: Codable {
    let id: String
    let description: String
    let alerts: RingAlerts?
    
    enum CodingKeys: String, CodingKey {
        case id, description, alerts
    }
}

struct RingAlerts: Codable {
    let connection: String?
    
    enum CodingKeys: String, CodingKey {
        case connection
    }
}

struct RingFeatures: Codable {
    let motionDetection: Bool?
    let videoRecording: Bool?
    let nightVision: Bool?
    
    enum CodingKeys: String, CodingKey {
        case motionDetection = "motion_detection"
        case videoRecording = "video_recording"
        case nightVision = "night_vision"
    }
} 