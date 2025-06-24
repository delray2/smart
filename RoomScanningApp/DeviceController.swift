import Foundation
import Combine
import SwiftUI

// MARK: - Device Controller Protocol
protocol DeviceControllerProtocol {
    func connect(to device: SmartDevice) async throws
    func disconnect(from device: SmartDevice) async throws
    func executeAction(_ action: DeviceAction, on device: SmartDevice, parameters: [String: Any]?) async throws
    func getStatus(for device: SmartDevice) async throws -> DeviceStatus
    func discoverDevices() async throws -> [SmartDevice]
}

// MARK: - Main Device Controller
class DeviceController: ObservableObject {
    @Published var allDevices: [SmartDevice] = []
    @Published var deviceStatuses: [UUID: DeviceStatus] = [:]
    @Published var connectedPlatforms: [SmartHomePlatform] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private var platformManagers: [SmartHomePlatform: PlatformAuthManager] = [:]
    
    init() {
        setupPlatformManagers()
        loadSavedDevices()
        loadSavedPlatforms()
    }
    
    // MARK: - Platform Management
    private func setupPlatformManagers() {
        for platform in SmartHomePlatform.allCases {
            platformManagers[platform] = createAuthManager(for: platform)
        }
    }
    
    private func createAuthManager(for platform: SmartHomePlatform) -> any PlatformAuthManager {
        switch platform {
        case .lifx:
            return LIFXAuthManager()
        case .philipsHue:
            return PhilipsHueAuthManager()
        case .nest:
            return NestAuthManager()
        case .smartThings:
            return SmartThingsAuthManager()
        case .ecobee:
            return EcobeeAuthManager()
        case .ring:
            return RingAuthManager()
        case .roborock:
            return RoborockAuthManager()
        case .wyze:
            return WyzeAuthManager()
        case .hubitat:
            return HubitatAuthManager()
        case .irobot:
            return IRobotAuthManager()
        }
    }
    
    // MARK: - Device Management
    func addDevice(_ device: SmartDevice) {
        if !allDevices.contains(where: { $0.id == device.id }) {
            allDevices.append(device)
            saveDevices()
        }
    }
    
    func removeDevice(_ device: SmartDevice) {
        allDevices.removeAll { $0.id == device.id }
        deviceStatuses.removeValue(forKey: device.id)
        saveDevices()
    }
    
    func updateDevice(_ device: SmartDevice) {
        if let index = allDevices.firstIndex(where: { $0.id == device.id }) {
            allDevices[index] = device
            saveDevices()
        }
    }
    
    func getDevices(for platform: SmartHomePlatform) -> [SmartDevice] {
        return allDevices.filter { $0.platform == platform }
    }
    
    func getDevices(for room: Room) -> [SmartDevice] {
        return allDevices.filter { device in
            room.devices.contains { $0.id == device.id }
        }
    }
    
    func getDevice(by id: UUID) -> SmartDevice? {
        return allDevices.first { $0.id == id }
    }
    
    func devicesForPlatform(_ platform: SmartHomePlatform) -> [SmartDevice] {
        return allDevices.filter { $0.platform == platform }
    }
    
    func isPlatformConnected(_ platform: SmartHomePlatform) -> Bool {
        return connectedPlatforms.contains(platform)
    }
    
    // MARK: - Device Position Management
    func updateDevicePosition(_ device: SmartDevice, position: SIMD3<Float>) {
        // Update device position in storage
        if let index = allDevices.firstIndex(where: { $0.id == device.id }) {
            allDevices[index].position = position
        }
    }
    
    // MARK: - Device Actions
    func executeAction(_ action: DeviceAction, on device: SmartDevice, parameters: [String: Any] = [:]) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let result = try await performDeviceAction(action, on: device, parameters: parameters)
            
            await MainActor.run {
                self.updateDeviceStatus(device.id, with: result)
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func performDeviceAction(_ action: DeviceAction, on device: SmartDevice, parameters: [String: Any]) async throws -> DeviceActionResult {
        guard let platform = device.platform,
              let authManager = platformManagers[platform] else {
            throw DeviceError.platformNotSupported
        }
        
        // Perform the action based on device type and action
        switch (device.type, action) {
        case (.lifxBulb, .toggle):
            return try await toggleLight(device, authManager: authManager)
        case (.lifxBulb, .turnOn):
            return try await turnOnLight(device, authManager: authManager)
        case (.lifxBulb, .turnOff):
            return try await turnOffLight(device, authManager: authManager)
        case (.lifxBulb, .setBrightness):
            if let brightness = parameters["brightness"] as? Int {
                return try await setLightBrightness(device, brightness: brightness, authManager: authManager)
            }
        case (.lifxBulb, .setColor):
            if let color = parameters["color"] as? String {
                return try await setLightColor(device, color: color, authManager: authManager)
            }
        case (.smartTV, .setVolume):
            if let volume = parameters["volume"] as? Int {
                return try await setTVVolume(device, volume: volume, authManager: authManager)
            }
        case (.robotVacuum, .startCleaning):
            return try await startVacuumCleaning(device, authManager: authManager)
        case (.robotVacuum, .stopCleaning):
            return try await stopVacuumCleaning(device, authManager: authManager)
        case (.smartThermostat, .setTemperature):
            if let temperature = parameters["temperature"] as? Int {
                return try await setThermostatTemperature(device, temperature: temperature, authManager: authManager)
            }
        default:
            throw DeviceError.actionNotSupported
        }
        
        throw DeviceError.actionNotSupported
    }
    
    // MARK: - Device Discovery
    func discoverDevices() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            var discoveredDevices: [SmartDevice] = []
            
            // Discover devices from all connected platforms
            for platform in connectedPlatforms {
                if let authManager = platformManagers[platform] {
                    let platformDevices = try await authManager.discoverDevices()
                    discoveredDevices.append(contentsOf: platformDevices)
                }
            }
            
            await MainActor.run {
                // Add new devices to the list
                for device in discoveredDevices {
                    if !self.allDevices.contains(where: { $0.id == device.id }) {
                        self.allDevices.append(device)
                    }
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Platform Authentication
    func authenticatePlatform(_ platform: SmartHomePlatform, apiKey: String? = nil) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            guard let authManager = platformManagers[platform] else {
                throw DeviceError.platformNotSupported
            }
            
            // Authenticate with the platform
            if let apiKey = apiKey {
                _ = try await authManager.authenticate(with: apiKey)
            } else {
                _ = try await authManager.authenticate()
            }
            
            await MainActor.run {
                if !self.connectedPlatforms.contains(platform) {
                    self.connectedPlatforms.append(platform)
                }
                self.isLoading = false
                self.savePlatforms()
            }
            
            // Automatically discover devices after successful authentication
            await discoverDevices()
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func disconnectPlatform(_ platform: SmartHomePlatform) {
        // Remove platform from connected platforms
        connectedPlatforms.removeAll { $0 == platform }
        savePlatforms()
        
        // Clear any stored credentials for this platform
        // (You may want to clear persisted credentials in a real app)
    }
    
    // MARK: - Device Status Management
    private func updateDeviceStatus(_ deviceId: UUID, with result: DeviceActionResult) {
        DispatchQueue.main.async {
            var status = self.deviceStatuses[deviceId] ?? DeviceStatus()
            
            switch result {
            case .success(let data):
                status.isOnline = true
                status.lastUpdated = Date()
                
                // Update specific properties based on action result
                if let brightness = data["brightness"] as? Int {
                    status.brightness = brightness
                }
                if let volume = data["volume"] as? Int {
                    status.volume = volume
                }
                if let temperature = data["temperature"] as? Double {
                    status.temperature = temperature
                }
                if let isOn = data["isOn"] as? Bool {
                    status.isOn = isOn
                }
                
            case .failure(let error):
                status.isOnline = false
                status.lastError = error.localizedDescription
                status.lastUpdated = Date()
            }
            
            self.deviceStatuses[deviceId] = status
        }
    }
    
    // MARK: - Data Persistence
    private func saveDevices() {
        // Save devices to UserDefaults or Core Data
        if let data = try? JSONEncoder().encode(allDevices) {
            UserDefaults.standard.set(data, forKey: "savedDevices")
        }
    }
    
    private func savePlatforms() {
        // Save connected platforms to UserDefaults
        let platformStrings = connectedPlatforms.map { $0.rawValue }
        UserDefaults.standard.set(platformStrings, forKey: "connectedPlatforms")
    }
    
    private func loadSavedDevices() {
        guard let data = UserDefaults.standard.data(forKey: "savedDevices"),
              let devices = try? JSONDecoder().decode([SmartDevice].self, from: data) else {
            return
        }
        
        DispatchQueue.main.async {
            self.allDevices = devices
            // Initialize status for all devices
            for device in devices {
                self.deviceStatuses[device.id] = DeviceStatus()
            }
        }
    }
    
    private func loadSavedPlatforms() {
        guard let platformStrings = UserDefaults.standard.stringArray(forKey: "connectedPlatforms") else {
            return
        }
        
        let platforms = platformStrings.compactMap { SmartHomePlatform(rawValue: $0) }
        DispatchQueue.main.async {
            self.connectedPlatforms = platforms
        }
    }
    
    // MARK: - Reset Data
    func resetAllData() {
        DispatchQueue.main.async {
            self.allDevices.removeAll()
            self.deviceStatuses.removeAll()
            self.connectedPlatforms.removeAll()
            self.errorMessage = nil
            
            // Clear saved data
            UserDefaults.standard.removeObject(forKey: "savedDevices")
            
            // Disconnect all platforms
            for platform in SmartHomePlatform.allCases {
                self.disconnectPlatform(platform)
            }
        }
    }
    
    // MARK: - Platform-Specific Action Implementations
    private func toggleLight(_ device: SmartDevice, authManager: PlatformAuthManager) async throws -> DeviceActionResult {
        // Implementation for toggling light
        return .success(["isOn": true])
    }
    
    private func turnOnLight(_ device: SmartDevice, authManager: PlatformAuthManager) async throws -> DeviceActionResult {
        // Implementation for turning on light
        return .success(["isOn": true])
    }
    
    private func turnOffLight(_ device: SmartDevice, authManager: PlatformAuthManager) async throws -> DeviceActionResult {
        // Implementation for turning off light
        return .success(["isOn": false])
    }
    
    private func setLightBrightness(_ device: SmartDevice, brightness: Int, authManager: PlatformAuthManager) async throws -> DeviceActionResult {
        // Implementation for setting light brightness
        return .success(["brightness": brightness])
    }
    
    private func setLightColor(_ device: SmartDevice, color: String, authManager: PlatformAuthManager) async throws -> DeviceActionResult {
        // Implementation for setting light color
        return .success(["color": color])
    }
    
    private func setTVVolume(_ device: SmartDevice, volume: Int, authManager: PlatformAuthManager) async throws -> DeviceActionResult {
        // Implementation for setting TV volume
        return .success(["volume": volume])
    }
    
    private func startVacuumCleaning(_ device: SmartDevice, authManager: PlatformAuthManager) async throws -> DeviceActionResult {
        // Implementation for starting vacuum cleaning
        return .success(["isCleaning": true])
    }
    
    private func stopVacuumCleaning(_ device: SmartDevice, authManager: PlatformAuthManager) async throws -> DeviceActionResult {
        // Implementation for stopping vacuum cleaning
        return .success(["isCleaning": false])
    }
    
    private func setThermostatTemperature(_ device: SmartDevice, temperature: Int, authManager: PlatformAuthManager) async throws -> DeviceActionResult {
        // Implementation for setting thermostat temperature
        return .success(["temperature": Double(temperature)])
    }
}

// MARK: - Device Status
struct DeviceStatus {
    var isOnline: Bool = false
    var isOn: Bool = false
    var brightness: Int? = nil
    var volume: Int = 50
    var temperature: Double = 72.0
    var humidity: Double? = nil
    var isCleaning: Bool = false
    var battery: Int? = nil
    var lastUpdated: Date = Date()
    var lastError: String?
}

// MARK: - Device Action Result
enum DeviceActionResult {
    case success([String: Any])
    case failure(Error)
}

// MARK: - Device Error
enum DeviceError: LocalizedError {
    case platformNotSupported
    case platformNotAuthenticated
    case actionNotSupported
    case deviceNotFound
    case networkError
    case authenticationFailed
    
    var errorDescription: String? {
        switch self {
        case .platformNotSupported:
            return "Platform not supported"
        case .platformNotAuthenticated:
            return "Platform not authenticated"
        case .actionNotSupported:
            return "Action not supported for this device"
        case .deviceNotFound:
            return "Device not found"
        case .networkError:
            return "Network error occurred"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
}

// MARK: - Device Action
enum DeviceAction: CaseIterable {
    case toggle
    case turnOn
    case turnOff
    case setBrightness
    case setColor
    case setVolume
    case play
    case pause
    case stop
    case startCleaning
    case stopCleaning
    case spotClean
    case returnToBase
    case setTemperature
    case setMode
    case lock
    case unlock
    case takePhoto
    case startRecording
    case stopRecording
    case previous
    case next
    
    var displayTitle: String {
        switch self {
        case .toggle: return "Toggle"
        case .turnOn: return "Turn On"
        case .turnOff: return "Turn Off"
        case .setBrightness: return "Set Brightness"
        case .setColor: return "Set Color"
        case .setVolume: return "Set Volume"
        case .play: return "Play"
        case .pause: return "Pause"
        case .stop: return "Stop"
        case .startCleaning: return "Start Cleaning"
        case .stopCleaning: return "Stop Cleaning"
        case .spotClean: return "Spot Clean"
        case .returnToBase: return "Return to Base"
        case .setTemperature: return "Set Temperature"
        case .setMode: return "Set Mode"
        case .lock: return "Lock"
        case .unlock: return "Unlock"
        case .takePhoto: return "Take Photo"
        case .startRecording: return "Start Recording"
        case .stopRecording: return "Stop Recording"
        case .previous: return "Previous"
        case .next: return "Next"
        }
    }
    
    var displayIcon: String {
        switch self {
        case .toggle: return "power"
        case .turnOn: return "power"
        case .turnOff: return "power"
        case .setBrightness: return "sun.max"
        case .setColor: return "paintpalette.fill"
        case .setVolume: return "speaker.wave.3"
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .stop: return "stop.fill"
        case .startCleaning: return "play.circle.fill"
        case .stopCleaning: return "stop.circle.fill"
        case .spotClean: return "play.circle.fill"
        case .returnToBase: return "house.circle.fill"
        case .setTemperature: return "thermometer"
        case .setMode: return "gear"
        case .lock: return "lock.fill"
        case .unlock: return "lock.open.fill"
        case .takePhoto: return "camera.fill"
        case .startRecording: return "record.circle.fill"
        case .stopRecording: return "stop.circle.fill"
        case .previous: return "backward.fill"
        case .next: return "forward.fill"
        }
    }
    
    var displayColor: Color {
        switch self {
        case .toggle: return .blue
        case .turnOn: return .green
        case .turnOff: return .red
        case .setBrightness: return .yellow
        case .setColor: return .blue
        case .setVolume: return .blue
        case .play: return .green
        case .pause: return .orange
        case .stop: return .red
        case .startCleaning: return .green
        case .stopCleaning: return .red
        case .spotClean: return .green
        case .returnToBase: return .blue
        case .setTemperature: return .orange
        case .setMode: return .purple
        case .lock: return .red
        case .unlock: return .green
        case .takePhoto: return .blue
        case .startRecording: return .red
        case .stopRecording: return .gray
        case .previous: return .blue
        case .next: return .blue
        }
    }
    
    func isAvailableFor(_ deviceType: DeviceType) -> Bool {
        switch self {
        case .toggle, .turnOn, .turnOff:
            return true
        case .setBrightness, .setColor:
            return deviceType == .lifxBulb
        case .setVolume, .play, .pause, .stop, .previous, .next:
            return [.smartTV, .smartSpeaker].contains(deviceType)
        case .startCleaning, .stopCleaning, .spotClean, .returnToBase:
            return deviceType == .robotVacuum
        case .setTemperature, .setMode:
            return deviceType == .smartThermostat
        case .lock, .unlock:
            return deviceType == .smartLock
        case .takePhoto, .startRecording, .stopRecording:
            return deviceType == .smartCamera
        }
    }
} 