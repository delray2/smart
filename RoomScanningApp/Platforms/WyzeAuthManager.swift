import Foundation
import AuthenticationServices

// MARK: - Wyze Authentication Manager
class WyzeAuthManager: ObservableObject, PlatformAuthManager {
    private let authURL = "https://auth-prod.api.wyze.com/oauth2/authorize"
    private let tokenURL = "https://auth-prod.api.wyze.com/oauth2/token"
    private let baseURL = "https://api.wyze.com/v2"
    
    // TODO: Replace with your actual credentials from Wyze Developer Portal
    private let clientId = "YOUR_WYZE_CLIENT_ID"
    private let clientSecret = "YOUR_WYZE_CLIENT_SECRET"
    private let redirectURI = "roomscanningapp://oauth/wyze"
    private let scope = "read write"
    
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
            platform: .wyze,
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
        
        let tokenResponse = try JSONDecoder().decode(WyzeTokenResponse.self, from: data)
        
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
        
        guard let url = URL(string: "\(baseURL)/device/list") else {
            throw PlatformError.deviceDiscoveryFailed("Invalid devices URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["app_id": "com.hualai.WyzeCam"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to discover devices")
        }
        
        let devicesResponse = try JSONDecoder().decode(WyzeDevicesResponse.self, from: data)
        
        return devicesResponse.data.map { device in
            PlatformDevice(
                id: device.mac,
                name: device.nickname,
                type: mapDeviceType(from: device),
                platform: .wyze,
                capabilities: buildCapabilities(from: device),
                isOnline: device.isOnline
            )
        }
    }
    
    private func mapDeviceType(from device: WyzeDevice) -> DeviceType {
        if device.productModel == "bulb" {
            return .lifxBulb
        } else if device.productModel == "lock" {
            return .smartLock
        } else if device.productModel == "camera" {
            return .smartCamera
        } else if device.productModel == "plug" {
            return .smartThingsDevice
        } else {
            return .smartThingsDevice
        }
    }
    
    private func buildCapabilities(from device: WyzeDevice) -> [String] {
        var capabilities: [String] = []
        
        switch device.productModel.lowercased() {
        case "wcv2", "wcv3", "wcv4":
            capabilities.append(contentsOf: ["camera", "motionDetection", "nightVision", "twoWayAudio"])
        case "wbs1", "wbs2":
            capabilities.append(contentsOf: ["on", "brightness", "color", "colorTemperature"])
        case "wss1", "wss2":
            capabilities.append(contentsOf: ["on", "brightness"])
        case "wop1", "wop2":
            capabilities.append(contentsOf: ["on", "powerMonitoring"])
        case "wsp1", "wsp2":
            capabilities.append(contentsOf: ["audio", "notifications"])
        default:
            capabilities.append("on")
        }
        
        return capabilities
    }
    
    func executeAction(_ action: DeviceAction, on device: PlatformDevice, credentials: PlatformCredentials, parameters: [String: Any]?) async throws {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        guard let url = URL(string: "\(baseURL)/device/control") else {
            throw PlatformError.actionFailed("Invalid control URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let command = buildWyzeCommand(action: action, parameters: parameters)
        request.httpBody = try JSONSerialization.data(withJSONObject: command)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.actionFailed("Failed to execute action")
        }
    }
    
    private func buildWyzeCommand(action: DeviceAction, parameters: [String: Any]?) -> [String: Any] {
        switch action {
        case .turnOn:
            return ["action": "power_on"]
        case .turnOff:
            return ["action": "power_off"]
        case .setBrightness:
            if let brightness = parameters?["brightness"] as? Int {
                return ["action": "set_brightness", "value": brightness]
            }
        default:
            break
        }
        return [:]
    }
    
    func getDeviceStatus(_ device: PlatformDevice, credentials: PlatformCredentials) async throws -> DeviceStatus {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        guard let url = URL(string: "\(baseURL)/device/info") else {
            throw PlatformError.deviceStatusFailed("Invalid device info URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["device_mac": device.id]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceStatusFailed("Failed to get device status")
        }
        
        let deviceInfo = try JSONDecoder().decode(WyzeDeviceInfo.self, from: data)
        
        var status = DeviceStatus()
        status.isOnline = deviceInfo.data.isOnline
        status.isOn = deviceInfo.data.switchStatus == "1"
        status.brightness = deviceInfo.data.brightness
        status.battery = deviceInfo.data.battery
        status.temperature = deviceInfo.data.temperature ?? 72.0
        return status
    }
    
    func authenticate(with apiKey: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("API key authentication not supported for Wyze.")
    }
    
    func authenticate(with token: String, hubIP: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("Token/hubIP authentication not supported for Wyze.")
    }
    
    func discoverDevices() async throws -> [SmartDevice] {
        // For now, return empty array since we need proper authentication
        // This method should be called after authenticate() has been called
        guard isAuthenticated, let accessToken = accessToken else {
            throw PlatformError.authenticationFailed("Not authenticated. Please authenticate first.")
        }
        
        let credentials = PlatformCredentials(
            platform: .wyze,
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

// MARK: - Wyze API Models
struct WyzeTokenResponse: Codable {
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

struct WyzeDevicesResponse: Codable {
    let code: Int
    let message: String
    let data: [WyzeDevice]
}

struct WyzeDevice: Codable {
    let mac: String
    let nickname: String
    let productModel: String
    let isOnline: Bool
    
    enum CodingKeys: String, CodingKey {
        case mac, nickname
        case productModel = "product_model"
        case isOnline = "is_online"
    }
}

struct WyzeDeviceInfo: Codable {
    let code: Int
    let message: String
    let data: WyzeDeviceData
}

struct WyzeDeviceData: Codable {
    let isOnline: Bool
    let switchStatus: String
    let brightness: Int?
    let color: String?
    let battery: Int?
    let signal: Int?
    let temperature: Double?
    
    enum CodingKeys: String, CodingKey {
        case isOnline = "is_online"
        case switchStatus = "switch_status"
        case brightness, color, battery, signal, temperature
    }
} 