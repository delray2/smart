import Foundation
import SwiftUI
import AuthenticationServices

// MARK: - Smart Home Platform
enum SmartHomePlatform: String, CaseIterable, Identifiable, Codable {
    case lifx = "lifx"
    case smartThings = "smartthings"
    case roborock = "roborock"
    case irobot = "irobot"
    case hubitat = "hubitat"
    case philipsHue = "philips_hue"
    case nest = "nest"
    case ecobee = "ecobee"
    case ring = "ring"
    case wyze = "wyze"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .lifx: return "LIFX"
        case .smartThings: return "SmartThings"
        case .roborock: return "Roborock"
        case .irobot: return "iRobot"
        case .hubitat: return "Hubitat"
        case .philipsHue: return "Philips Hue"
        case .nest: return "Nest"
        case .ecobee: return "Ecobee"
        case .ring: return "Ring"
        case .wyze: return "Wyze"
        }
    }
    
    var iconName: String {
        switch self {
        case .lifx: return "lightbulb.fill"
        case .smartThings: return "gearshape.fill"
        case .roborock: return "house.fill"
        case .irobot: return "house.fill"
        case .hubitat: return "house.fill"
        case .philipsHue: return "lightbulb.fill"
        case .nest: return "thermometer"
        case .ecobee: return "thermometer"
        case .ring: return "camera.fill"
        case .wyze: return "camera.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .lifx: return .purple
        case .smartThings: return .blue
        case .roborock: return .orange
        case .irobot: return .red
        case .hubitat: return .green
        case .philipsHue: return .yellow
        case .nest: return .orange
        case .ecobee: return .blue
        case .ring: return .blue
        case .wyze: return .purple
        }
    }
    
    var description: String {
        switch self {
        case .lifx: return "Smart LED lighting with vibrant colors and effects"
        case .smartThings: return "Samsung's smart home platform for all your devices"
        case .roborock: return "Advanced robot vacuums with smart mapping"
        case .irobot: return "Intelligent cleaning robots for your home"
        case .hubitat: return "Local smart home hub with privacy focus"
        case .philipsHue: return "Smart lighting system with millions of colors"
        case .nest: return "Smart thermostats and home security"
        case .ecobee: return "Smart thermostats with room sensors"
        case .ring: return "Smart doorbells and security cameras"
        case .wyze: return "Affordable smart home devices and cameras"
        }
    }
    
    var authType: AuthType {
        switch self {
        case .lifx: return .apiKey
        case .smartThings: return .oauth2
        case .roborock: return .oauth2
        case .irobot: return .oauth2
        case .hubitat: return .local
        case .philipsHue: return .bridge
        case .nest: return .oauth2
        case .ecobee: return .oauth2
        case .ring: return .oauth2
        case .wyze: return .oauth2
        }
    }
}

// MARK: - Authentication Types
enum AuthType {
    case apiKey
    case oauth2
    case local
    case bridge
}

// MARK: - Platform Auth Manager Protocol
protocol PlatformAuthManager {
    func authenticate() async throws -> PlatformCredentials
    func authenticate(with apiKey: String) async throws -> PlatformCredentials
    func authenticate(with token: String, hubIP: String) async throws -> PlatformCredentials
    func discoverDevices() async throws -> [SmartDevice]
    func discoverDevices(credentials: PlatformCredentials) async throws -> [PlatformDevice]
    func executeAction(_ action: DeviceAction, on device: PlatformDevice, credentials: PlatformCredentials, parameters: [String: Any]?) async throws
    func getDeviceStatus(_ device: PlatformDevice, credentials: PlatformCredentials) async throws -> DeviceStatus
}

// MARK: - Platform Authentication State
enum PlatformAuthState: Equatable {
    case notAuthenticated
    case authenticating
    case authenticated
    case failed(String)
    
    static func == (lhs: PlatformAuthState, rhs: PlatformAuthState) -> Bool {
        switch (lhs, rhs) {
        case (.notAuthenticated, .notAuthenticated): return true
        case (.authenticating, .authenticating): return true
        case (.authenticated, .authenticated): return true
        case (.failed(let l), .failed(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - Platform Credentials
struct PlatformCredentials: Codable {
    let platform: SmartHomePlatform
    let accessToken: String?
    let refreshToken: String?
    let apiKey: String?
    let localIP: String?
    let bridgeIP: String?
    let expiresAt: Date?
    let userId: String?
    
    init(platform: SmartHomePlatform, accessToken: String? = nil, refreshToken: String? = nil, 
         apiKey: String? = nil, localIP: String? = nil, bridgeIP: String? = nil, 
         expiresAt: Date? = nil, userId: String? = nil) {
        self.platform = platform
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.apiKey = apiKey
        self.localIP = localIP
        self.bridgeIP = bridgeIP
        self.expiresAt = expiresAt
        self.userId = userId
    }
    
    var isValid: Bool {
        if let expiresAt = expiresAt {
            return expiresAt > Date()
        }
        return accessToken != nil || apiKey != nil || localIP != nil || bridgeIP != nil
    }
}

// MARK: - Platform Device
struct PlatformDevice: Identifiable, Codable {
    let id: String
    let name: String
    let type: DeviceType
    let platform: SmartHomePlatform
    let capabilities: [String]
    let properties: [String: String]
    let isOnline: Bool
    let isOn: Bool
    
    init(id: String, name: String, type: DeviceType, platform: SmartHomePlatform, 
         capabilities: [String] = [], properties: [String: String] = [:], 
         isOnline: Bool = true, isOn: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.platform = platform
        self.capabilities = capabilities
        self.properties = properties
        self.isOnline = isOnline
        self.isOn = isOn
    }
}

// MARK: - Platform Manager
class PlatformManager: ObservableObject {
    @Published var authStates: [SmartHomePlatform: PlatformAuthState] = [:]
    @Published var authenticatedPlatforms: [SmartHomePlatform: PlatformCredentials] = [:]
    @Published var discoveredDevices: [SmartHomePlatform: [PlatformDevice]] = [:]
    
    private let deviceController: DeviceController
    
    init(deviceController: DeviceController = DeviceController()) {
        self.deviceController = deviceController
        setupInitialStates()
    }
    
    private func setupInitialStates() {
        for platform in SmartHomePlatform.allCases {
            authStates[platform] = .notAuthenticated
        }
    }
    
    func authenticatePlatform(_ platform: SmartHomePlatform, apiKey: String? = nil) async {
        await MainActor.run {
            authStates[platform] = .authenticating
        }
        
        do {
            // Simulate authentication
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            let credentials = PlatformCredentials(
                platform: platform,
                accessToken: apiKey ?? "mock_token",
                refreshToken: nil,
                expiresAt: Date().addingTimeInterval(3600)
            )
            
            await MainActor.run {
                authenticatedPlatforms[platform] = credentials
                authStates[platform] = .authenticated
            }
            
            // Discover devices after authentication
            await discoverDevices(for: platform)
        } catch {
            await MainActor.run {
                authStates[platform] = .failed(error.localizedDescription)
            }
        }
    }
    
    func discoverDevices(for platform: SmartHomePlatform) async {
        guard let _ = authenticatedPlatforms[platform] else { return }
        
        // Simulate device discovery
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Create mock devices
        let mockDevices: [PlatformDevice]
        switch platform {
        case .lifx:
            mockDevices = [
                PlatformDevice(id: UUID().uuidString, name: "Living Room Light", type: .lifxBulb, platform: platform, isOnline: true, isOn: false),
                PlatformDevice(id: UUID().uuidString, name: "Bedroom Light", type: .lifxBulb, platform: platform, isOnline: true, isOn: true)
            ]
        case .smartThings:
            mockDevices = [
                PlatformDevice(id: UUID().uuidString, name: "Smart TV", type: .smartTV, platform: platform, isOnline: true, isOn: false),
                PlatformDevice(id: UUID().uuidString, name: "Front Door Lock", type: .smartLock, platform: platform, isOnline: true, isOn: false)
            ]
        case .roborock:
            mockDevices = [
                PlatformDevice(id: UUID().uuidString, name: "Robot Vacuum", type: .robotVacuum, platform: platform, isOnline: true, isOn: false)
            ]
        default:
            mockDevices = []
        }
        
        await MainActor.run {
            discoveredDevices[platform] = mockDevices
        }
    }
}

// MARK: - Credentials Storage
class CredentialsStorage {
    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "platform_credentials_"
    
    func saveCredentials(_ credentials: PlatformCredentials, for platform: SmartHomePlatform) {
        let key = keyPrefix + platform.rawValue
        if let encoded = try? JSONEncoder().encode(credentials) {
            userDefaults.set(encoded, forKey: key)
        }
    }
    
    func getCredentials(for platform: SmartHomePlatform) -> PlatformCredentials? {
        let key = keyPrefix + platform.rawValue
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PlatformCredentials.self, from: data)
    }
    
    func removeCredentials(for platform: SmartHomePlatform) {
        let key = keyPrefix + platform.rawValue
        userDefaults.removeObject(forKey: key)
    }
}

// MARK: - Platform Errors
enum PlatformError: Error, LocalizedError {
    case authenticationFailed(String)
    case networkError
    case invalidCredentials
    case unsupportedAction
    case apiError(String)
    case deviceNotFound
    case deviceDiscoveryFailed(String)
    case actionFailed(String)
    case deviceStatusFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .networkError:
            return "Network error occurred"
        case .invalidCredentials:
            return "Invalid credentials"
        case .unsupportedAction:
            return "This action is not supported for this device"
        case .apiError(let message):
            return "API Error: \(message)"
        case .deviceNotFound:
            return "Device not found"
        case .deviceDiscoveryFailed(let message):
            return "Device discovery failed: \(message)"
        case .actionFailed(let message):
            return "Action failed: \(message)"
        case .deviceStatusFailed(let message):
            return "Device status failed: \(message)"
        }
    }
}

// MARK: - Export Format
enum ExportFormat {
    case usdz, model, floorPlan
}

// WallColor is defined in RoomCaptureView.swift

// MARK: - Helper Structs for UI
struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DetailItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActivityItem: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct DeviceSummaryRow: View {
    let device: SmartDevice
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: device.type.iconName)
                    .foregroundColor(device.type.color)
                    .frame(width: 30)
                
                Text(device.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if device.isOnline {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ModeButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(color)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CircularButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 30)
            .background(Color(.systemGray5))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
    }
}

// MARK: - Device Control View
struct DeviceControlView: View {
    let device: SmartDevice
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Control \(device.name)")
                    .font(.title)
            }
            .navigationTitle("Device Control")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// APIKeyInputView is defined in DeviceDiscoveryView.swift 
