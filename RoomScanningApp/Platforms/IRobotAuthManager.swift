import Foundation
import AuthenticationServices

// MARK: - iRobot Authentication Manager
class IRobotAuthManager: ObservableObject, PlatformAuthManager {
    private let authURL = "https://portal.irobot.com/oauth2/authorize"
    private let tokenURL = "https://portal.irobot.com/oauth2/token"
    private let baseURL = "https://api.irobot.com/v1"
    
    // TODO: Replace with your actual credentials from iRobot Developer Portal
    private let clientId = "YOUR_IROBOT_CLIENT_ID"
    private let clientSecret = "YOUR_IROBOT_CLIENT_SECRET"
    private let redirectURI = "roomscanningapp://oauth/irobot"
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
            platform: .irobot,
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
        
        let tokenResponse = try JSONDecoder().decode(IRobotTokenResponse.self, from: data)
        
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
        
        guard let url = URL(string: "\(baseURL)/robots") else {
            throw PlatformError.deviceDiscoveryFailed("Invalid robots URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to discover robots")
        }
        
        let robotsResponse = try JSONDecoder().decode(IRobotRobotsResponse.self, from: data)
        
        return robotsResponse.robots.map { robot in
            PlatformDevice(
                id: robot.serialNumber,
                name: robot.name,
                type: .robotVacuum,
                platform: .irobot,
                capabilities: buildCapabilities(from: robot),
                isOnline: robot.isOnline
            )
        }
    }
    
    private func buildCapabilities(from robot: IRobotRobot) -> [String] {
        var capabilities: [String] = ["vacuum", "navigation", "mapping"]
        
        if robot.capabilities.contains("mop") {
            capabilities.append("mop")
        }
        
        if robot.capabilities.contains("selfEmpty") {
            capabilities.append("selfEmpty")
        }
        
        if robot.capabilities.contains("selfWash") {
            capabilities.append("selfWash")
        }
        
        if robot.capabilities.contains("camera") {
            capabilities.append("camera")
        }
        
        return capabilities
    }
    
    func executeAction(_ action: DeviceAction, on device: PlatformDevice, credentials: PlatformCredentials, parameters: [String: Any]?) async throws {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        guard let url = URL(string: "\(baseURL)/robots/\(device.id)/commands") else {
            throw PlatformError.actionFailed("Invalid commands URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let command = buildIRobotCommand(action: action, parameters: parameters)
        request.httpBody = try JSONSerialization.data(withJSONObject: command)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.actionFailed("Failed to execute action")
        }
    }
    
    private func buildIRobotCommand(action: DeviceAction, parameters: [String: Any]?) -> [String: Any] {
        switch action {
        case .startCleaning:
            return [
                "command": "start",
                "initiator": "localApp"
            ]
        case .stopCleaning:
            return [
                "command": "stop",
                "initiator": "localApp"
            ]
        case .returnToBase:
            return [
                "command": "dock",
                "initiator": "localApp"
            ]
        default:
            break
        }
        
        return [:]
    }
    
    func getDeviceStatus(_ device: PlatformDevice, credentials: PlatformCredentials) async throws -> DeviceStatus {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        guard let url = URL(string: "\(baseURL)/robots/\(device.id)/status") else {
            throw PlatformError.deviceStatusFailed("Invalid status URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceStatusFailed("Failed to get device status")
        }
        
        let statusResponse = try JSONDecoder().decode(IRobotStatusResponse.self, from: data)
        
        var status = DeviceStatus()
        status.isOnline = statusResponse.status.isOnline
        status.isOn = statusResponse.status.state != "idle"
        status.isCleaning = statusResponse.status.state == "cleaning"
        return status
    }
    
    func authenticate(with apiKey: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("API key authentication not supported for iRobot.")
    }
    
    func authenticate(with token: String, hubIP: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("Token/hubIP authentication not supported for iRobot.")
    }
    
    func discoverDevices() async throws -> [SmartDevice] {
        // For now, return empty array since we need proper authentication
        // This method should be called after authenticate() has been called
        guard isAuthenticated, let accessToken = accessToken else {
            throw PlatformError.authenticationFailed("Not authenticated. Please authenticate first.")
        }
        
        let credentials = PlatformCredentials(
            platform: .irobot,
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

// MARK: - iRobot API Models
struct IRobotTokenResponse: Codable {
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

struct IRobotRobotsResponse: Codable {
    let robots: [IRobotRobot]
}

struct IRobotRobot: Codable {
    let serialNumber: String
    let name: String
    let model: String
    let isOnline: Bool
    let capabilities: [String]
    
    enum CodingKeys: String, CodingKey {
        case serialNumber = "serial_number"
        case name, model
        case isOnline = "is_online"
        case capabilities
    }
}

struct IRobotStatusResponse: Codable {
    let status: IRobotStatus
}

struct IRobotStatus: Codable {
    let isOnline: Bool
    let state: String
    let phase: String?
    let battery: Int?
    let cleaningArea: Double?
    let cleaningTime: Int?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case isOnline = "is_online"
        case state, phase, battery
        case cleaningArea = "cleaning_area"
        case cleaningTime = "cleaning_time"
        case error
    }
} 