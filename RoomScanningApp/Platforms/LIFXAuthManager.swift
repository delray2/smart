import Foundation

// MARK: - LIFX Authentication Manager
class LIFXAuthManager: ObservableObject, PlatformAuthManager {
    private let baseURL = "https://api.lifx.com/v1"
    
    @Published var isAuthenticated = false
    @Published var apiKey: String?
    
    func authenticate() async throws -> PlatformCredentials {
        // LIFX uses API key authentication
        // User needs to generate an API key from their LIFX account
        // For now, we'll throw an error asking for the API key
        // In a real app, you'd have a UI to input the API key
        
        throw PlatformError.authenticationFailed("Please provide your LIFX API key. You can generate one at https://cloud.lifx.com/settings/tokens")
    }
    
    func authenticate(with apiKey: String) async throws -> PlatformCredentials {
        // Validate the API key by making a test request
        try await validateAPIKey(apiKey)
        
        self.apiKey = apiKey
        self.isAuthenticated = true
        
        return PlatformCredentials(
            platform: .lifx,
            accessToken: apiKey,
            refreshToken: nil,
            expiresAt: nil
        )
    }
    
    func authenticate(with token: String, hubIP: String) async throws -> PlatformCredentials {
        throw PlatformError.authenticationFailed("Token/hubIP authentication not supported for LIFX.")
    }
    
    func discoverDevices() async throws -> [SmartDevice] {
        // Use stored API key if available
        guard let apiKey = self.apiKey else {
            throw PlatformError.authenticationFailed("No API key available. Please authenticate first.")
        }
        
        let credentials = PlatformCredentials(
            platform: .lifx,
            accessToken: apiKey,
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
    
    private func validateAPIKey(_ apiKey: String) async throws {
        guard let url = URL(string: "\(baseURL)/lights") else {
            throw PlatformError.authenticationFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.authenticationFailed("Invalid response")
        }
        
        if httpResponse.statusCode == 401 {
            throw PlatformError.authenticationFailed("Invalid API key")
        } else if httpResponse.statusCode != 200 {
            throw PlatformError.authenticationFailed("API key validation failed")
        }
    }
    
    func discoverDevices(credentials: PlatformCredentials) async throws -> [PlatformDevice] {
        guard let apiKey = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No API key available")
        }
        
        guard let url = URL(string: "\(baseURL)/lights") else {
            throw PlatformError.deviceDiscoveryFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceDiscoveryFailed("Failed to discover lights")
        }
        
        let lights = try JSONDecoder().decode([LIFXLight].self, from: data)
        
        return lights.map { light in
            PlatformDevice(
                id: light.id,
                name: light.label,
                type: .lifxBulb,
                platform: .lifx,
                capabilities: buildCapabilities(from: light),
                isOnline: light.connected
            )
        }
    }
    
    private func buildCapabilities(from light: LIFXLight) -> [String] {
        var capabilities: [String] = ["on", "brightness"]
        
        if light.product.capabilities.has_color {
            capabilities.append("color")
        }
        
        if light.product.capabilities.has_variable_color_temp {
            capabilities.append("colorTemperature")
        }
        
        if light.product.capabilities.has_ir {
            capabilities.append("infrared")
        }
        
        if light.product.capabilities.has_multizone {
            capabilities.append("multizone")
        }
        
        return capabilities
    }
    
    func executeAction(_ action: DeviceAction, on device: PlatformDevice, credentials: PlatformCredentials, parameters: [String: Any]?) async throws {
        guard let apiKey = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No API key available")
        }
        
        let endpoint = buildActionEndpoint(action: action, deviceId: device.id)
        guard let url = URL(string: "\(baseURL)/lights/\(endpoint)") else {
            throw PlatformError.actionFailed("Invalid action URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = buildActionBody(action: action, parameters: parameters)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 207 else { // LIFX returns 207 for multi-status
            throw PlatformError.actionFailed("Failed to execute action")
        }
    }
    
    private func buildActionEndpoint(action: DeviceAction, deviceId: String) -> String {
        switch action {
        case .turnOn, .turnOff, .setBrightness, .setColor:
            return "id:\(deviceId)/state"
        default:
            return "id:\(deviceId)/state"
        }
    }
    
    private func buildActionBody(action: DeviceAction, parameters: [String: Any]?) -> [String: Any] {
        var body: [String: Any] = [:]
        
        switch action {
        case .turnOn:
            body["power"] = "on"
        case .turnOff:
            body["power"] = "off"
        case .setBrightness:
            if let brightness = parameters?["brightness"] as? Double {
                body["brightness"] = brightness
            }
        case .setColor:
            if let color = parameters?["color"] as? String {
                body["color"] = color
            }
        default:
            break
        }
        
        return body
    }
    
    func getDeviceStatus(_ device: PlatformDevice, credentials: PlatformCredentials) async throws -> DeviceStatus {
        guard let apiKey = credentials.accessToken else {
            throw PlatformError.authenticationFailed("No API key available")
        }
        
        guard let url = URL(string: "\(baseURL)/lights/id:\(device.id)") else {
            throw PlatformError.deviceStatusFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlatformError.deviceStatusFailed("Failed to get device status")
        }
        
        let lights = try JSONDecoder().decode([LIFXLight].self, from: data)
        guard let light = lights.first else {
            throw PlatformError.deviceStatusFailed("Device not found")
        }
        
        var status = DeviceStatus()
        status.isOnline = light.connected
        status.isOn = light.power == "on"
        status.brightness = Int(light.brightness * 100)
        return status
    }
}

// MARK: - LIFX API Models
struct LIFXLight: Codable {
    let id: String
    let uuid: String
    let label: String
    let connected: Bool
    let power: String
    let color: LIFXColor?
    let brightness: Double
    let effect: String?
    let group: LIFXGroup
    let location: LIFXLocation
    let product: LIFXProduct
    let lastSeen: String?
    let secondsSinceSeen: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, uuid, label, connected, power, color, brightness, effect, group, location, product
        case lastSeen = "last_seen"
        case secondsSinceSeen = "seconds_since_seen"
    }
}

struct LIFXColor: Codable {
    let hue: Double
    let saturation: Double
    let kelvin: Int
    
    var hex: String {
        // Convert HSL to hex
        let h = hue / 360.0
        let s = saturation / 100.0
        let l = 0.5 // Assuming lightness of 50% for simplicity
        
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        
        var r: Double, g: Double, b: Double
        
        switch Int(h * 6) {
        case 0:
            r = c; g = x; b = 0
        case 1:
            r = x; g = c; b = 0
        case 2:
            r = 0; g = c; b = x
        case 3:
            r = 0; g = x; b = c
        case 4:
            r = x; g = 0; b = c
        case 5:
            r = c; g = 0; b = x
        default:
            r = 0; g = 0; b = 0
        }
        
        let red = Int((r + m) * 255)
        let green = Int((g + m) * 255)
        let blue = Int((b + m) * 255)
        
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

struct LIFXGroup: Codable {
    let id: String
    let name: String
}

struct LIFXLocation: Codable {
    let id: String
    let name: String
}

struct LIFXProduct: Codable {
    let name: String
    let identifier: String
    let company: String
    let capabilities: LIFXCapabilities
    
    enum CodingKeys: String, CodingKey {
        case name, identifier, company, capabilities
    }
}

struct LIFXCapabilities: Codable {
    let has_color: Bool
    let has_variable_color_temp: Bool
    let has_ir: Bool
    let has_multizone: Bool
    let has_chain: Bool
    let has_matrix: Bool
    let min_kelvin: Int?
    let max_kelvin: Int?
} 
