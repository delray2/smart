import Foundation
import Network

// MARK: - Hubitat Authentication Manager
class HubitatAuthManager: ObservableObject, PlatformAuthManager {
    private let baseURL = "http://localhost:8080" // Default Hubitat URL
    private let apiEndpoint = "/apps/api"
    
    @Published var isAuthenticated = false
    @Published var hubIP: String?
    @Published var apiToken: String?
    
    func authenticate() async throws -> PlatformCredentials {
        // Hubitat requires local network discovery and API token
        // First, discover the Hubitat hub on the local network
        let hubIP = try await discoverHubitatHub()
        self.hubIP = hubIP
        
        // User needs to provide API token from Hubitat Maker API
        throw PlatformError.authenticationFailed("Please provide your Hubitat API token. You can generate one in the Hubitat Maker API app.")
    }
    
    func authenticate(with hubToken: String? = nil, hubIP: String? = nil) async throws -> PlatformCredentials {
        var finalHubIP: String
        if let hubIP = hubIP {
            finalHubIP = hubIP
        } else if let selfHubIP = self.hubIP {
            finalHubIP = selfHubIP
        } else {
            finalHubIP = try await discoverHubitatHub()
        }
        
        let credentials = PlatformCredentials(
            platform: .hubitat,
            accessToken: hubToken ?? self.apiToken ?? "",
            refreshToken: nil,
            expiresAt: nil
        )
        self.hubIP = finalHubIP
        self.apiToken = credentials.accessToken
        self.isAuthenticated = true
        return credentials
    }
    
    func authenticate(with apiKey: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("API key authentication not supported for Hubitat.")
    }
    
    func authenticate(with token: String, hubIP: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("Token/hubIP authentication not supported for Hubitat.")
    }
    
    private func discoverHubitatHub() async throws -> String {
        // Hubitat hubs typically run on port 8080
        // We'll try common IP ranges and the default Hubitat URL
        
        let commonIPRanges = [
            "192.168.1.100", "192.168.1.101", "192.168.1.102", "192.168.1.103",
            "192.168.0.100", "192.168.0.101", "192.168.0.102", "192.168.0.103",
            "10.0.0.100", "10.0.0.101", "10.0.0.102", "10.0.0.103"
        ]
        
        // First try the default localhost URL
        if await isHubitatHub(at: "localhost") {
            return "localhost"
        }
        
        // Then try common IP ranges
        for ip in commonIPRanges {
            if await isHubitatHub(at: ip) {
                return ip
            }
        }
        
        throw PlatformError.authenticationFailed("No Hubitat hub found on local network. Please provide the hub IP address manually.")
    }
    
    private func isHubitatHub(at ip: String) async -> Bool {
        guard let url = URL(string: "http://\(ip):8080/hub/status") else {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    private func validateAPIToken(_ apiToken: String, hubIP: String) async throws {
        guard let url = URL(string: "http://\(hubIP):8080\(apiEndpoint)/\(apiToken)/devices") else {
            throw PlatformError.authenticationFailed("Invalid URL")
        }
        
        let (_, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.authenticationFailed("Invalid response")
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw PlatformError.authenticationFailed("Invalid API token")
        } else if httpResponse.statusCode != 200 {
            throw PlatformError.authenticationFailed("API token validation failed")
        }
    }
    
    func discoverDevices(credentials: PlatformCredentials) async throws -> [PlatformDevice] {
        guard let apiToken = credentials.accessToken,
              let hubIP = self.hubIP else {
            throw PlatformError.authenticationFailed("Missing API token or hub IP")
        }
        
        guard let url = URL(string: "http://\(hubIP):8080\(apiEndpoint)/\(apiToken)/devices") else {
            throw PlatformError.deviceDiscoveryFailed("Invalid URL")
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to discover devices")
        }
        
        let devices = try JSONDecoder().decode([HubitatDevice].self, from: data)
        
        return devices.map { device in
            PlatformDevice(
                id: device.id,
                name: device.label,
                type: .smartThingsDevice,
                platform: .hubitat,
                capabilities: buildCapabilities(from: device),
                isOnline: device.healthStatus == "ONLINE"
            )
        }
    }
    
    private func buildCapabilities(from device: HubitatDevice) -> [String] {
        return device.attributes.map { $0.name }
    }
    
    func executeAction(_ action: DeviceAction, on device: PlatformDevice, credentials: PlatformCredentials, parameters: [String: Any]?) async throws {
        guard let apiToken = credentials.accessToken,
              let hubIP = self.hubIP else {
            throw PlatformError.authenticationFailed("Missing API token or hub IP")
        }
        
        let command = buildHubitatCommand(action: action, parameters: parameters)
        guard let url = URL(string: "http://\(hubIP):8080\(apiEndpoint)/\(apiToken)/devices/\(device.id)/\(command)") else {
            throw PlatformError.actionFailed("Invalid command URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.actionFailed("Failed to execute action")
        }
    }
    
    private func buildHubitatCommand(action: DeviceAction, parameters: [String: Any]?) -> [String: Any] {
        switch action {
        case .turnOn:
            return ["command": "on"]
        case .turnOff:
            return ["command": "off"]
        case .setBrightness:
            if let brightness = parameters?["brightness"] as? Int {
                return ["command": "setLevel", "value": brightness]
            }
        default:
            break
        }
        return [:]
    }
    
    func getDeviceStatus(_ device: PlatformDevice, credentials: PlatformCredentials) async throws -> DeviceStatus {
        guard let hubIP = self.hubIP else {
            throw PlatformError.authenticationFailed("Missing hub IP")
        }
        guard let url = URL(string: "http://\(hubIP)/apps/api/devices/\(device.id)?access_token=\(credentials.accessToken ?? "")") else {
            throw PlatformError.deviceStatusFailed("Invalid device status URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.deviceStatusFailed("Failed to get device status")
        }
        let deviceInfo = try JSONDecoder().decode(HubitatDevice.self, from: data)
        var status = DeviceStatus()
        status.isOnline = deviceInfo.healthStatus == "ONLINE"
        status.isOn = deviceInfo.attributes.first { $0.name == "switch" }?.currentValue == "on"
        if let levelStr = deviceInfo.attributes.first(where: { $0.name == "level" })?.currentValue, let levelInt = Int(levelStr) {
            status.brightness = levelInt
        } else {
            status.brightness = nil
        }
        return status
    }
    
    func discoverDevices() async throws -> [SmartDevice] {
        // For now, return empty array since we need proper authentication
        // This method should be called after authenticate() has been called
        guard isAuthenticated, let apiToken = self.apiToken else {
            throw PlatformError.authenticationFailed("Not authenticated. Please authenticate first.")
        }
        
        let credentials = PlatformCredentials(
            platform: .hubitat,
            accessToken: apiToken,
            refreshToken: nil,
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

// MARK: - Hubitat API Models
struct HubitatDevice: Codable {
    let id: String
    let name: String
    let label: String
    let type: String
    let healthStatus: String
    let capabilities: [String]
    let attributes: [HubitatAttribute]
    
    enum CodingKeys: String, CodingKey {
        case id, name, label, type, capabilities, attributes
        case healthStatus = "healthStatus"
    }
}

struct HubitatAttribute: Codable {
    let name: String
    let currentValue: String
    let dataType: String
    
    enum CodingKeys: String, CodingKey {
        case name, dataType
        case currentValue = "currentValue"
    }
} 