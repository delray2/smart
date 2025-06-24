import Foundation
import simd
import SwiftUI

// MARK: - Smart Device
struct SmartDevice: Identifiable, Codable {
    var id = UUID()
    var name: String
    var type: DeviceType
    var position: SIMD3<Float>
    var platform: SmartHomePlatform?
    var isOnline: Bool
    var isOn: Bool
    var properties: [String: String]
    var lastUpdated: Date
    
    init(name: String, type: DeviceType, position: SIMD3<Float>) {
        self.name = name
        self.type = type
        self.position = position
        self.isOnline = true
        self.isOn = false
        self.properties = [:]
        self.lastUpdated = Date()
    }
}

// MARK: - Device Types
enum DeviceType: String, Codable, CaseIterable {
    case lifxBulb = "lifx_bulb"
    case smartTV = "smart_tv"
    case robotVacuum = "robot_vacuum"
    case smartThingsDevice = "smartthings_device"
    case smartSpeaker = "smart_speaker"
    case smartThermostat = "smart_thermostat"
    case smartLock = "smart_lock"
    case smartCamera = "smart_camera"
    
    var displayName: String {
        switch self {
        case .lifxBulb: return "LIFX Bulb"
        case .smartTV: return "Smart TV"
        case .robotVacuum: return "Robot Vacuum"
        case .smartThingsDevice: return "SmartThings Device"
        case .smartSpeaker: return "Smart Speaker"
        case .smartThermostat: return "Smart Thermostat"
        case .smartLock: return "Smart Lock"
        case .smartCamera: return "Smart Camera"
        }
    }
    
    var iconName: String {
        switch self {
        case .lifxBulb: return "lightbulb.fill"
        case .smartTV: return "tv.fill"
        case .robotVacuum: return "vacuum.fill"
        case .smartThingsDevice: return "gearshape.fill"
        case .smartSpeaker: return "speaker.wave.3.fill"
        case .smartThermostat: return "thermometer"
        case .smartLock: return "lock.fill"
        case .smartCamera: return "camera.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .lifxBulb: return .yellow
        case .smartTV: return .blue
        case .robotVacuum: return .gray
        case .smartThingsDevice: return .green
        case .smartSpeaker: return .purple
        case .smartThermostat: return .orange
        case .smartLock: return .red
        case .smartCamera: return .black
        }
    }
}

// MARK: - Device Configuration
struct DeviceConfiguration: Codable {
    var name: String
    var type: DeviceType
    var position: SIMD3<Float>
    var apiKey: String?
    var deviceId: String?
    var roomId: String?
    var customProperties: [String: String]
    
    init(name: String, type: DeviceType, position: SIMD3<Float>) {
        self.name = name
        self.type = type
        self.position = position
        self.apiKey = nil
        self.deviceId = nil
        self.roomId = nil
        self.customProperties = [:]
    }
} 