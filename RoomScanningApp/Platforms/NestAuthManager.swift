import Foundation
import AuthenticationServices

// MARK: - Nest Authentication Manager
class NestAuthManager: ObservableObject, PlatformAuthManager {
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let baseURL = "https://smartdevicemanagement.googleapis.com/v1"
    
    // TODO: Replace with your actual credentials from Google Cloud Console
    private let clientId = "YOUR_GOOGLE_CLIENT_ID"
    private let clientSecret = "YOUR_GOOGLE_CLIENT_SECRET"
    private let redirectURI = "roomscanningapp://oauth/nest"
    private let scope = "https://www.googleapis.com/auth/sdm.service"
    
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var refreshToken: String?
    @Published var expiresAt: Date?
    
    func authenticate() async throws -> PlatformCredentials {
        let state = UUID().uuidString
        
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
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
        self.expiresAt = tokens.expiresAt
        self.isAuthenticated = true
        
        return PlatformCredentials(
            platform: .nest,
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
        
        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        
        return (
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        )
    }
    
    func discoverDevices(credentials: PlatformCredentials) async throws -> [PlatformDevice] {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        // First, get the enterprise
        let enterprise = try await getEnterprise(accessToken: accessToken)
        
        // Then get devices in the enterprise
        guard let url = URL(string: "\(baseURL)/enterprises/\(enterprise)/devices") else {
            throw PlatformError.deviceDiscoveryFailed("Invalid devices URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to discover devices")
        }
        
        let devicesResponse = try JSONDecoder().decode(NestDevicesResponse.self, from: data)
        
        return devicesResponse.devices.map { device in
            PlatformDevice(
                id: device.name,
                name: device.traits?.info?.customName ?? device.name,
                type: mapDeviceType(device.type),
                platform: .nest,
                capabilities: buildCapabilities(from: device),
                isOnline: device.traits?.connectivity?.status == "ONLINE"
            )
        }
    }
    
    private func getEnterprise(accessToken: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/enterprises") else {
            throw PlatformError.deviceDiscoveryFailed("Invalid enterprises URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to get enterprise")
        }
        
        let enterprisesResponse = try JSONDecoder().decode(NestEnterprisesResponse.self, from: data)
        
        guard let enterprise = enterprisesResponse.enterprises.first else {
            throw PlatformError.deviceDiscoveryFailed("No enterprise found")
        }
        
        return enterprise.name
    }
    
    private func mapDeviceType(_ nestType: String) -> DeviceType {
        switch nestType.lowercased() {
        case "sdm.devices.types.thermostat":
            return .smartThermostat
        case "sdm.devices.types.camera":
            return .smartCamera
        case "sdm.devices.types.doorbell":
            return .smartCamera
        case "sdm.devices.types.display":
            return .smartSpeaker
        default:
            return .smartThermostat
        }
    }
    
    private func buildCapabilities(from device: NestDevice) -> [String] {
        var capabilities: [String] = []
        
        if device.traits?.thermostatHvac != nil {
            capabilities.append(contentsOf: ["temperature", "heating", "cooling", "fan"])
        }
        
        if device.traits?.cameraLiveStream != nil {
            capabilities.append("camera")
        }
        
        if device.traits?.cameraEventImage != nil {
            capabilities.append("motionDetection")
        }
        
        return capabilities
    }
    
    func executeAction(_ action: DeviceAction, on device: PlatformDevice, credentials: PlatformCredentials, parameters: [String: Any]?) async throws {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        guard let url = URL(string: "\(baseURL)/\(device.id):executeCommand") else {
            throw PlatformError.actionFailed("Invalid command URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let command = buildNestCommand(action: action, parameters: parameters)
        request.httpBody = try JSONSerialization.data(withJSONObject: command)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.actionFailed("Failed to execute action")
        }
    }
    
    private func buildNestCommand(action: DeviceAction, parameters: [String: Any]?) -> [String: Any] {
        switch action {
        case .setTemperature:
            if let temperature = parameters?["temperature"] as? Double {
                return [
                    "command": "sdm.devices.commands.ThermostatTemperatureSetpoint.SetHeat",
                    "params": [
                        "heatCelsius": temperature
                    ]
                ]
            }
        default:
            break
        }
        
        return [:]
    }
    
    func getTokens() -> (accessToken: String, refreshToken: String, expiresAt: Date) {
        let accessTokenValue = accessToken ?? ""
        let refreshTokenValue = refreshToken ?? ""
        let expiresAtValue = expiresAt ?? Date()
        return (accessToken: accessTokenValue, refreshToken: refreshTokenValue, expiresAt: expiresAtValue)
    }
    
    func getDeviceStatus(_ device: PlatformDevice, credentials: PlatformCredentials) async throws -> DeviceStatus {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        // Fetch device info from the API (pseudo-code, adjust endpoint as needed)
        guard let url = URL(string: "\(baseURL)/devices/\(device.id)") else {
            throw PlatformError.deviceStatusFailed("Invalid device info URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.deviceStatusFailed("Failed to get device status")
        }
        let deviceInfo = try JSONDecoder().decode(NestDevice.self, from: data)
        var status = DeviceStatus()
        status.isOnline = deviceInfo.traits?.connectivity?.status == "ONLINE"
        status.isOn = true // Assume Nest devices are "on" if online
        // Set other properties as needed
        return status
    }
    
    func authenticate(with apiKey: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("API key authentication not supported for Nest.")
    }
    
    func authenticate(with token: String, hubIP: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("Token/hubIP authentication not supported for Nest.")
    }
    
    func discoverDevices() async throws -> [SmartDevice] {
        // For now, return empty array since we need proper authentication
        // This method should be called after authenticate() has been called
        guard isAuthenticated, let accessToken = accessToken else {
            throw PlatformError.authenticationFailed("Not authenticated. Please authenticate first.")
        }
        
        let credentials = PlatformCredentials(
            platform: .nest,
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

// MARK: - Nest API Models
struct GoogleTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct NestEnterprisesResponse: Codable {
    let enterprises: [NestEnterprise]
}

struct NestEnterprise: Codable {
    let name: String
    let displayName: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "displayName"
    }
}

struct NestDevicesResponse: Codable {
    let devices: [NestDevice]
}

struct NestDevice: Codable {
    let name: String
    let type: String
    let traits: NestTraits?
}

struct NestTraits: Codable {
    let info: NestInfo?
    let connectivity: NestConnectivity?
    let thermostatHvac: NestThermostatHvac?
    let cameraLiveStream: NestCameraLiveStream?
    let cameraEventImage: NestCameraEventImage?
}

struct NestInfo: Codable {
    let customName: String?
    
    enum CodingKeys: String, CodingKey {
        case customName = "customName"
    }
}

struct NestConnectivity: Codable {
    let status: String
}

struct NestThermostatHvac: Codable {
    let status: String
}

struct NestCameraLiveStream: Codable {
    let maxVideoResolution: NestVideoResolution?
    
    enum CodingKeys: String, CodingKey {
        case maxVideoResolution = "maxVideoResolution"
    }
}

struct NestVideoResolution: Codable {
    let width: Int
    let height: Int
}

struct NestCameraEventImage: Codable {
    let maxImageResolution: NestImageResolution?
    
    enum CodingKeys: String, CodingKey {
        case maxImageResolution = "maxImageResolution"
    }
}

struct NestImageResolution: Codable {
    let width: Int
    let height: Int
} 