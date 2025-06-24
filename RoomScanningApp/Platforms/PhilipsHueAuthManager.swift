import Foundation
import Network

// MARK: - Philips Hue Authentication Manager
class PhilipsHueAuthManager: ObservableObject, PlatformAuthManager {
    private let bridgeDiscoveryURL = "https://discovery.meethue.com/"
    private let bridgePort: UInt16 = 80
    
    @Published var isAuthenticated = false
    @Published var bridgeIP: String?
    @Published var username: String?
    
    func authenticate() async throws -> PlatformCredentials {
        // Step 1: Discover Hue Bridge on local network
        let bridgeIP = try await discoverBridge()
        self.bridgeIP = bridgeIP
        
        // Step 2: Create username (API key) by pressing the link button
        let username = try await createUsername(bridgeIP: bridgeIP)
        self.username = username
        self.isAuthenticated = true
        
        return PlatformCredentials(
            platform: .philipsHue,
            accessToken: username, // Hue uses username as the access token
            refreshToken: nil,
            expiresAt: nil
        )
    }
    
    private func discoverBridge() async throws -> String {
        // First try cloud discovery
        do {
            let bridges = try await discoverBridgesFromCloud()
            if let firstBridge = bridges.first {
                return firstBridge.internalIPAddress
            }
        } catch {
            print("Cloud discovery failed, trying local network discovery")
        }
        
        // Fallback to local network discovery
        return try await discoverBridgeOnLocalNetwork()
    }
    
    private func discoverBridgesFromCloud() async throws -> [HueBridge] {
        guard let url = URL(string: bridgeDiscoveryURL) else {
            throw PlatformError.authenticationFailed("Invalid discovery URL")
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.authenticationFailed("Bridge discovery failed")
        }
        
        let bridges = try JSONDecoder().decode([HueBridge].self, from: data)
        return bridges
    }
    
    private func discoverBridgeOnLocalNetwork() async throws -> String {
        // Use Network framework to discover Hue Bridge on local network
        // Hue Bridge typically responds to SSDP or can be found via mDNS
        // For simplicity, we'll try common IP ranges where Hue Bridge might be
        
        let commonIPRanges = [
            "192.168.1.2", "192.168.1.3", "192.168.1.4", "192.168.1.5",
            "192.168.0.2", "192.168.0.3", "192.168.0.4", "192.168.0.5"
        ]
        
        for ip in commonIPRanges {
            if await isHueBridge(at: ip) {
                return ip
            }
        }
        
        throw PlatformError.authenticationFailed("No Hue Bridge found on local network")
    }
    
    private func isHueBridge(at ip: String) async -> Bool {
        guard let url = URL(string: "http://\(ip)/api/config") else {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    private func createUsername(bridgeIP: String) async throws -> String {
        // Philips Hue requires the user to press the link button on the bridge
        // Then we can create a username (API key)
        
        guard let url = URL(string: "http://\(bridgeIP)/api") else {
            throw PlatformError.authenticationFailed("Invalid bridge URL")
        }
        
        let createUserRequest = HueCreateUserRequest(
            devicetype: "RoomScanningApp#iPhone",
            generateclientkey: true
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode([createUserRequest])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.authenticationFailed("Failed to create username. Make sure the link button is pressed.")
        }
        
        let responses = try JSONDecoder().decode([HueCreateUserResponse].self, from: data)
        
        guard let firstResponse = responses.first,
              let success = firstResponse.success,
              let username = success.username else {
            if let error = responses.first?.error {
                throw PlatformError.authenticationFailed("Hue Bridge error: \(error.description)")
            }
            throw PlatformError.authenticationFailed("Failed to create username")
        }
        
        return username
    }
    
    func discoverDevices(credentials: PlatformCredentials) async throws -> [PlatformDevice] {
        guard let bridgeIP = credentials.accessToken,
              let username = credentials.refreshToken else {
            throw PlatformError.authenticationFailed("Missing bridge IP or username")
        }
        
        guard let url = URL(string: "http://\(username)/api/\(bridgeIP)/lights") else {
            throw PlatformError.deviceDiscoveryFailed("Invalid lights URL")
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to discover lights")
        }
        
        let lights = try JSONDecoder().decode([String: HueLight].self, from: data)
        
        return lights.map { (id, light) in
            PlatformDevice(
                id: id,
                name: light.name,
                type: .lifxBulb,
                platform: .philipsHue,
                capabilities: buildCapabilities(from: light),
                isOnline: light.state.reachable
            )
        }
    }
    
    private func buildCapabilities(from light: HueLight) -> [String] {
        var capabilities: [String] = []
        
        if light.state.on {
            capabilities.append("on")
        }
        if light.state.bri != nil {
            capabilities.append("brightness")
        }
        if light.state.hue != nil && light.state.sat != nil {
            capabilities.append("color")
            capabilities.append("hue")
            capabilities.append("sat")
        }
        if light.state.ct != nil {
            capabilities.append("colorTemperature")
        }
        if light.state.xy != nil {
            capabilities.append("xy")
        }
        
        return capabilities
    }
    
    func executeAction(_ action: DeviceAction, on device: PlatformDevice, credentials: PlatformCredentials, parameters: [String: Any]?) async throws {
        guard let bridgeIP = credentials.accessToken,
              let username = credentials.refreshToken else {
            throw PlatformError.authenticationFailed("Missing bridge IP or username")
        }
        
        guard let url = URL(string: "http://\(username)/api/\(bridgeIP)/lights/\(device.id)/state") else {
            throw PlatformError.actionFailed("Invalid state URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let state = buildHueCommand(action: action, parameters: parameters)
        request.httpBody = try JSONSerialization.data(withJSONObject: state)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.actionFailed("Failed to execute action")
        }
    }
    
    private func buildHueCommand(action: DeviceAction, parameters: [String: Any]?) -> [String: Any] {
        switch action {
        case .turnOn:
            return ["on": true]
        case .turnOff:
            return ["on": false]
        case .setBrightness:
            if let brightness = parameters?["brightness"] as? Int {
                return ["bri": brightness]
            }
        case .setColor:
            if let color = parameters?["color"] as? String {
                return ["xy": color]
            }
        default:
            break
        }
        return [:]
    }
    
    func getDeviceStatus(_ device: PlatformDevice, credentials: PlatformCredentials) async throws -> DeviceStatus {
        guard let bridgeIP = credentials.accessToken,
              let username = credentials.refreshToken else {
            throw PlatformError.authenticationFailed("Missing bridge IP or username")
        }
        
        guard let url = URL(string: "http://\(username)/api/\(bridgeIP)/lights/\(device.id)") else {
            throw PlatformError.deviceDiscoveryFailed("Invalid device status URL")
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to get device status")
        }
        
        let light = try JSONDecoder().decode(HueLight.self, from: data)
        
        var status = DeviceStatus()
        status.isOnline = light.state.reachable
        status.isOn = light.state.on
        status.brightness = light.state.bri
        return status
    }
    
    func authenticate(with apiKey: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("API key authentication not supported for Philips Hue.")
    }
    
    func authenticate(with token: String, hubIP: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("Token/hubIP authentication not supported for Philips Hue.")
    }
    
    func discoverDevices() async throws -> [SmartDevice] {
        // For now, return empty array since we need proper authentication
        // This method should be called after authenticate() has been called
        guard isAuthenticated, let username = self.username, let bridgeIP = self.bridgeIP else {
            throw PlatformError.authenticationFailed("Not authenticated. Please authenticate first.")
        }
        
        let credentials = PlatformCredentials(
            platform: .philipsHue,
            accessToken: bridgeIP,
            refreshToken: username,
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

// MARK: - Philips Hue API Models
struct HueBridge: Codable {
    let id: String
    let internalIPAddress: String
    let macAddress: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case internalIPAddress = "internalipaddress"
        case macAddress = "macaddress"
        case name
    }
}

struct HueCreateUserRequest: Codable {
    let devicetype: String
    let generateclientkey: Bool
}

struct HueCreateUserResponse: Codable {
    let success: HueSuccess?
    let error: HueError?
}

struct HueSuccess: Codable {
    let username: String?
    let clientkey: String?
}

struct HueError: Codable {
    let type: Int
    let address: String
    let description: String
}

struct HueLight: Codable {
    let name: String
    let state: HueLightState
    let type: String
    let modelid: String
}

struct HueLightState: Codable {
    let on: Bool
    let bri: Int?
    let hue: Int?
    let sat: Int?
    let xy: [Double]?
    let ct: Int?
    let reachable: Bool
} 