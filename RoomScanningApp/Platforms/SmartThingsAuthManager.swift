import Foundation
import AuthenticationServices

// MARK: - SmartThings Authentication Manager
class SmartThingsAuthManager: ObservableObject, PlatformAuthManager {
    private let authURL = "https://auth-global.api.smartthings.com/oauth/authorize"
    private let tokenURL = "https://auth-global.api.smartthings.com/oauth/token"
    private let baseURL = "https://api.smartthings.com/v1"
    
    // TODO: Replace with your actual credentials from SmartThings Developer Workspace
    private let clientId = "YOUR_SMARTTHINGS_CLIENT_ID"
    private let clientSecret = "YOUR_SMARTTHINGS_CLIENT_SECRET"
    private let redirectURI = "roomscanningapp://oauth/smartthings"
    private let scope = "r:devices:* r:locations:* r:scenes:* x:devices:*"
    
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
            platform: .smartThings,
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
        
        let tokenResponse = try JSONDecoder().decode(SmartThingsTokenResponse.self, from: data)
        
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
        
        var request = URLRequest(url: URL(string: "\(baseURL)/devices")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to discover devices")
        }
        
        let devicesResponse = try JSONDecoder().decode(SmartThingsDevicesResponse.self, from: data)
        
        return devicesResponse.items.map { device in
            PlatformDevice(
                id: device.deviceId,
                name: device.name,
                type: mapDeviceType(from: device),
                platform: .smartThings,
                capabilities: device.components.flatMap { $0.capabilities },
                isOnline: device.healthState == "ONLINE"
            )
        }
    }
    
    private func mapDeviceType(from device: SmartThingsDevice) -> DeviceType {
        // Map SmartThings device types to our DeviceType enum
        if device.components.contains(where: { $0.capabilities.contains("switch") }) {
            return .smartThingsDevice
        } else if device.components.contains(where: { $0.capabilities.contains("light") }) {
            return .lifxBulb
        } else if device.components.contains(where: { $0.capabilities.contains("thermostat") }) {
            return .smartThermostat
        } else if device.components.contains(where: { $0.capabilities.contains("lock") }) {
            return .smartLock
        } else {
            return .smartThingsDevice
        }
    }
    
    func authenticate(with apiKey: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("API key authentication not supported for SmartThings.")
    }
    
    func authenticate(with token: String, hubIP: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("Token/hubIP authentication not supported for SmartThings.")
    }
    
    func executeAction(_ action: DeviceAction, on device: PlatformDevice, credentials: PlatformCredentials, parameters: [String: Any]?) async throws {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/devices/\(device.id)/commands")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build command based on action
        let command = buildCommand(for: action, parameters: parameters)
        request.httpBody = try JSONSerialization.data(withJSONObject: command)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.actionFailed("Failed to execute action")
        }
    }
    
    func getDeviceStatus(_ device: PlatformDevice, credentials: PlatformCredentials) async throws -> DeviceStatus {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/devices/\(device.id)/status")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to get device status")
        }
        
        // Parse device status from response
        let statusData = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        return DeviceStatus(
            isOnline: device.isOnline,
            isOn: statusData["on"] as? Bool ?? false,
            brightness: statusData["brightness"] as? Int,
            temperature: statusData["temperature"] as? Double ?? 72.0
        )
    }
    
    private func buildCommand(for action: DeviceAction, parameters: [String: Any]?) -> [String: Any] {
        switch action {
        case .turnOn:
            return [
                "commands": [
                    [
                        "component": "main",
                        "capability": "switch",
                        "command": "on"
                    ]
                ]
            ]
        case .turnOff:
            return [
                "commands": [
                    [
                        "component": "main",
                        "capability": "switch",
                        "command": "off"
                    ]
                ]
            ]
        case .setBrightness:
            let brightness = parameters?["brightness"] as? Double ?? 50.0
            return [
                "commands": [
                    [
                        "component": "main",
                        "capability": "switchLevel",
                        "command": "setLevel",
                        "arguments": [Int(brightness)]
                    ]
                ]
            ]
        case .setColor:
            let hue = parameters?["hue"] as? Double ?? 0.0
            let saturation = parameters?["saturation"] as? Double ?? 100.0
            return [
                "commands": [
                    [
                        "component": "main",
                        "capability": "colorControl",
                        "command": "setColor",
                        "arguments": [
                            "hue": hue,
                            "saturation": saturation
                        ]
                    ]
                ]
            ]
        case .setTemperature:
            let temperature = parameters?["temperature"] as? Double ?? 72.0
            return [
                "commands": [
                    [
                        "component": "main",
                        "capability": "thermostatSetpoint",
                        "command": "setHeatingSetpoint",
                        "arguments": [temperature]
                    ]
                ]
            ]
        case .toggle, .setVolume, .play, .pause, .stop, .startCleaning, .stopCleaning, .spotClean, .returnToBase, .setMode, .lock, .unlock, .takePhoto, .startRecording, .stopRecording, .previous, .next:
            // For unsupported actions, return a basic command
            return [
                "commands": [
                    [
                        "component": "main",
                        "capability": "switch",
                        "command": "on"
                    ]
                ]
            ]
        }
    }
    
    func discoverDevices() async throws -> [SmartDevice] {
        // For now, return empty array since we need proper authentication
        // This method should be called after authenticate() has been called
        guard isAuthenticated, let accessToken = accessToken else {
            throw PlatformError.authenticationFailed("Not authenticated. Please authenticate first.")
        }
        
        let credentials = PlatformCredentials(
            platform: .smartThings,
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

// MARK: - SmartThings API Models
struct SmartThingsTokenResponse: Codable {
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

struct SmartThingsDevicesResponse: Codable {
    let items: [SmartThingsDevice]
}

struct SmartThingsDevice: Codable {
    let deviceId: String
    let name: String
    let type: String
    let healthState: String
    let components: [SmartThingsComponent]
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case name = "name"
        case type = "type"
        case healthState = "healthState"
        case components = "components"
    }
}

struct SmartThingsComponent: Codable {
    let capabilities: [String]
} 