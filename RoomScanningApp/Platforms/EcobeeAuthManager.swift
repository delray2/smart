import Foundation
import AuthenticationServices

// MARK: - Ecobee Authentication Manager
class EcobeeAuthManager: ObservableObject, PlatformAuthManager {
    private let authURL = "https://api.ecobee.com/authorize"
    private let tokenURL = "https://api.ecobee.com/token"
    private let baseURL = "https://api.ecobee.com/1"
    
    // TODO: Replace with your actual credentials from Ecobee Developer Portal
    private let clientId = "YOUR_ECOBEE_CLIENT_ID"
    private let redirectURI = "roomscanningapp://oauth/ecobee"
    private let scope = "smartRead smartWrite"
    
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var refreshToken: String?
    
    func authenticate() async throws -> PlatformCredentials {
        let state = UUID().uuidString
        
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "ecobeePin"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state)
        ]
        
        guard let authURL = components.url else {
            throw PlatformError.authenticationFailed("Invalid authorization URL")
        }
        
        // Ecobee uses a PIN-based authorization flow
        let pinResponse = try await performPinAuthorization(authURL: authURL)
        
        // Wait for user to authorize the PIN
        let tokens = try await waitForAuthorization(pinResponse: pinResponse)
        
        self.accessToken = tokens.accessToken
        self.refreshToken = tokens.refreshToken
        self.isAuthenticated = true
        
        return PlatformCredentials(
            platform: .ecobee,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt
        )
    }
    
    private func performPinAuthorization(authURL: URL) async throws -> EcobeePinResponse {
        let (data, response) = try await URLSession.shared.data(from: authURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.authenticationFailed("PIN authorization failed")
        }
        
        let pinResponse = try JSONDecoder().decode(EcobeePinResponse.self, from: data)
        
        // Show PIN to user
        print("Please go to https://www.ecobee.com/consumerportal/index.html and enter PIN: \(pinResponse.ecobeePin)")
        
        return pinResponse
    }
    
    private func waitForAuthorization(pinResponse: EcobeePinResponse) async throws -> (accessToken: String, refreshToken: String, expiresAt: Date) {
        // Poll for authorization completion
        let maxAttempts = 60 // 5 minutes with 5-second intervals
        var attempts = 0
        
        while attempts < maxAttempts {
            do {
                let tokens = try await exchangePinForTokens(pinResponse: pinResponse)
                return tokens
            } catch {
                attempts += 1
                if attempts >= maxAttempts {
                    throw PlatformError.authenticationFailed("Authorization timeout. Please try again.")
                }
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            }
        }
        
        throw PlatformError.authenticationFailed("Authorization timeout")
    }
    
    private func exchangePinForTokens(pinResponse: EcobeePinResponse) async throws -> (accessToken: String, refreshToken: String, expiresAt: Date) {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "ecobeePin",
            "code": pinResponse.code,
            "client_id": clientId
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.authenticationFailed("Token exchange failed")
        }
        
        let tokenResponse = try JSONDecoder().decode(EcobeeTokenResponse.self, from: data)
        
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
        
        guard let url = URL(string: "\(baseURL)/thermostat") else {
            throw PlatformError.deviceDiscoveryFailed("Invalid thermostat URL")
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "json", value: "{\"selection\":{\"selectionType\":\"registered\",\"selectionMatch\":\"\"}}")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to discover thermostats")
        }
        
        let thermostatsResponse = try JSONDecoder().decode(EcobeeThermostatsResponse.self, from: data)
        
        return thermostatsResponse.thermostatList.map { thermostat in
            PlatformDevice(
                id: thermostat.identifier,
                name: thermostat.name,
                type: .smartThermostat,
                platform: .ecobee,
                capabilities: buildCapabilities(from: thermostat),
                isOnline: thermostat.isConnected
            )
        }
    }
    
    private func buildCapabilities(from thermostat: EcobeeThermostat) -> [String] {
        var capabilities: [String] = ["temperature", "heating", "cooling", "fan"]
        
        if thermostat.settings.hasHeatPump {
            capabilities.append("heatPump")
        }
        
        if thermostat.settings.hasDehumidifier {
            capabilities.append("dehumidifier")
        }
        
        if thermostat.settings.hasHumidifier {
            capabilities.append("humidifier")
        }
        
        if thermostat.settings.hasHrv {
            capabilities.append("hrv")
        }
        
        return capabilities
    }
    
    func executeAction(_ action: DeviceAction, on device: PlatformDevice, credentials: PlatformCredentials, parameters: [String: Any]?) async throws {
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No access token available")
        }
        
        guard let url = URL(string: "\(baseURL)/thermostat") else {
            throw PlatformError.actionFailed("Invalid thermostat URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let command = buildEcobeeCommand(action: action, deviceId: device.id, parameters: parameters)
        request.httpBody = try JSONSerialization.data(withJSONObject: command)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.actionFailed("Failed to execute action")
        }
    }
    
    private func buildEcobeeCommand(action: DeviceAction, deviceId: String, parameters: [String: Any]?) -> [String: Any] {
        switch action {
        case .setTemperature:
            if let temperature = parameters?["temperature"] as? Double {
                return ["command": "setHold", "value": temperature]
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
        
        guard let url = URL(string: "\(baseURL)/thermostatSummary?json={\"selection\":{\"selectionType\":\"devices\",\"selectionMatch\":\"\(device.id)\"}}") else {
            throw PlatformError.deviceStatusFailed("Invalid thermostat summary URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceStatusFailed("Failed to get device status")
        }
        
        let statusResponse = try JSONDecoder().decode(EcobeeThermostatsResponse.self, from: data)
        guard let thermostat = statusResponse.thermostatList.first else {
            throw PlatformError.deviceStatusFailed("Thermostat not found")
        }
        
        var status = DeviceStatus()
        status.isOnline = thermostat.isConnected
        status.isOn = thermostat.runtime?.connected == true
        status.temperature = thermostat.runtime?.actualTemperature.map { Double($0) } ?? 72.0
        status.humidity = thermostat.runtime?.actualHumidity.map { Double($0) }
        return status
    }
    
    func authenticate(with apiKey: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("API key authentication not supported for Ecobee.")
    }
    
    func authenticate(with token: String, hubIP: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("Token/hubIP authentication not supported for Ecobee.")
    }
    
    func discoverDevices() async throws -> [SmartDevice] {
        // For now, return empty array since we need proper authentication
        // This method should be called after authenticate() has been called
        guard isAuthenticated, let accessToken = accessToken else {
            throw PlatformError.authenticationFailed("Not authenticated. Please authenticate first.")
        }
        
        let credentials = PlatformCredentials(
            platform: .ecobee,
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

// MARK: - Ecobee API Models
struct EcobeePinResponse: Codable {
    let ecobeePin: String
    let code: String
    let scope: String
    let expiresIn: Int
    let interval: Int
    
    enum CodingKeys: String, CodingKey {
        case ecobeePin = "ecobeePin"
        case code, scope
        case expiresIn = "expires_in"
        case interval
    }
}

struct EcobeeTokenResponse: Codable {
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

struct EcobeeThermostatsResponse: Codable {
    let thermostatList: [EcobeeThermostat]
    let status: EcobeeStatus
    
    enum CodingKeys: String, CodingKey {
        case thermostatList = "thermostatList"
        case status
    }
}

struct EcobeeThermostat: Codable {
    let identifier: String
    let name: String
    let isConnected: Bool
    let settings: EcobeeSettings
    let runtime: EcobeeRuntime?
    
    enum CodingKeys: String, CodingKey {
        case identifier, name
        case isConnected = "isConnected"
        case settings, runtime
    }
}

struct EcobeeSettings: Codable {
    let hvacMode: String
    let hasHeatPump: Bool
    let hasDehumidifier: Bool
    let hasHumidifier: Bool
    let hasHrv: Bool
    
    enum CodingKeys: String, CodingKey {
        case hvacMode = "hvacMode"
        case hasHeatPump = "hasHeatPump"
        case hasDehumidifier = "hasDehumidifier"
        case hasHumidifier = "hasHumidifier"
        case hasHrv = "hasHrv"
    }
}

struct EcobeeRuntime: Codable {
    let connected: Bool?
    let actualTemperature: Int?
    let actualHumidity: Int?
    let desiredHeat: Int?
    let desiredCool: Int?
    
    enum CodingKeys: String, CodingKey {
        case connected
        case actualTemperature = "actualTemperature"
        case actualHumidity = "actualHumidity"
        case desiredHeat = "desiredHeat"
        case desiredCool = "desiredCool"
    }
}

struct EcobeeStatus: Codable {
    let code: Int
    let message: String
} 