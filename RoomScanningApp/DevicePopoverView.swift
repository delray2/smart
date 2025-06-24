import SwiftUI

// MARK: - Device Popover View
struct DevicePopoverView: View {
    let device: SmartDevice
    @ObservedObject var deviceController: DeviceController
    @Environment(\.presentationMode) var presentationMode
    @State private var showingDeviceDetail = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Device header
                deviceHeaderView
                
                // Quick controls
                quickControlsView
                
                // Device-specific controls
                deviceSpecificControlsView
                
                Spacer()
                
                // Action buttons
                actionButtonsView
            }
            .padding()
            .navigationTitle(device.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .sheet(isPresented: $showingDeviceDetail) {
                DeviceDetailView(device: device, deviceController: deviceController)
            }
        }
    }
    
    // MARK: - Device Header View
    private var deviceHeaderView: some View {
        VStack(spacing: 16) {
            // Device icon and status
            ZStack {
                Circle()
                    .fill(device.type.color.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: device.type.iconName)
                    .font(.title)
                    .foregroundColor(device.type.color)
                
                // Online status indicator
                Circle()
                    .fill(device.isOnline ? Color.green : Color.red)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .offset(x: 25, y: -25)
            }
            
            // Device info
            VStack(spacing: 4) {
                Text(device.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(device.type.displayName)
                    .font(.body)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(device.isOnline ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Quick Controls View
    private var quickControlsView: some View {
        VStack(spacing: 16) {
            Text("Quick Controls")
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                // Power toggle
                Button(action: {
                    Task {
                        await deviceController.executeAction(.toggle, on: device)
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: device.isOn ? "power" : "power")
                            .font(.title2)
                            .foregroundColor(device.isOn ? .green : .gray)
                        
                        Text(device.isOn ? "On" : "Off")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Brightness (for lights)
                if device.type == .lifxBulb {
                    Button(action: {
                        // Quick brightness adjustment
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "sun.max")
                                .font(.title2)
                                .foregroundColor(.orange)
                            
                            Text("Brightness")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Device Specific Controls View
    private var deviceSpecificControlsView: some View {
        VStack(spacing: 16) {
            Text("Device Controls")
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            switch device.type {
            case .lifxBulb:
                LightControlsView(device: device, deviceController: deviceController)
            case .smartTV:
                TVControlsView(device: device, deviceController: deviceController)
            case .robotVacuum:
                VacuumControlsView(device: device, deviceController: deviceController)
            case .smartSpeaker:
                SpeakerControlsView(device: device, deviceController: deviceController)
            case .smartThermostat:
                ThermostatControlsView(device: device, deviceController: deviceController)
            default:
                GenericControlsView(device: device, deviceController: deviceController)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            Button("View Details") {
                showingDeviceDetail = true
            }
            .buttonStyle(PrimaryButtonStyle())
            
            Button("Remove from Room") {
                // Handle device removal
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

// MARK: - Light Controls View
struct LightControlsView: View {
    let device: SmartDevice
    @ObservedObject var deviceController: DeviceController
    @State private var brightness: Double = 50
    @State private var color: Color = .white
    
    var body: some View {
        VStack(spacing: 16) {
            // Brightness slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sun.min")
                        .foregroundColor(.orange)
                    
                    Text("Brightness")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(Int(brightness))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $brightness, in: 0...100, step: 5)
                    .onChange(of: brightness) { newValue in
                        Task {
                            await deviceController.executeAction(.setBrightness, on: device, parameters: ["brightness": Int(newValue)])
                        }
                    }
            }
            
            // Color picker (simplified)
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 12) {
                    ForEach([Color.white, .red, .green, .blue, .yellow, .purple], id: \.self) { colorOption in
                        Button(action: {
                            color = colorOption
                            // Set color on device
                        }) {
                            Circle()
                                .fill(colorOption)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(color == colorOption ? Color.blue : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - TV Controls View
struct TVControlsView: View {
    let device: SmartDevice
    @ObservedObject var deviceController: DeviceController
    @State private var volume: Double = 50
    
    var body: some View {
        VStack(spacing: 16) {
            // Volume control
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "speaker.wave.1")
                        .foregroundColor(.blue)
                    
                    Text("Volume")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(Int(volume))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $volume, in: 0...100, step: 5)
                    .onChange(of: volume) { newValue in
                        Task {
                            await deviceController.executeAction(.setVolume, on: device, parameters: ["volume": Int(newValue)])
                        }
                    }
            }
            
            // Media controls
            HStack(spacing: 16) {
                ActionButton(title: "Play", icon: "play.fill", color: .green) {
                    Task {
                        await deviceController.executeAction(.play, on: device)
                    }
                }
                
                ActionButton(title: "Pause", icon: "pause.fill", color: .orange) {
                    Task {
                        await deviceController.executeAction(.pause, on: device)
                    }
                }
                
                ActionButton(title: "Stop", icon: "stop.fill", color: .red) {
                    Task {
                        await deviceController.executeAction(.stop, on: device)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Vacuum Controls View
struct VacuumControlsView: View {
    let device: SmartDevice
    @ObservedObject var deviceController: DeviceController
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ActionButton(title: "Start", icon: "play.circle.fill", color: .green) {
                    Task {
                        await deviceController.executeAction(.startCleaning, on: device)
                    }
                }
                
                ActionButton(title: "Stop", icon: "stop.circle.fill", color: .red) {
                    Task {
                        await deviceController.executeAction(.stopCleaning, on: device)
                    }
                }
            }
            
            HStack(spacing: 16) {
                ActionButton(title: "Home", icon: "house.circle.fill", color: .blue) {
                    Task {
                        await deviceController.executeAction(.returnToBase, on: device)
                    }
                }
                
                ActionButton(title: "Spot", icon: "target", color: .purple) {
                    Task {
                        await deviceController.executeAction(.spotClean, on: device)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Speaker Controls View
struct SpeakerControlsView: View {
    let device: SmartDevice
    @ObservedObject var deviceController: DeviceController
    @State private var volume: Double = 50
    
    var body: some View {
        VStack(spacing: 16) {
            // Volume control
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "speaker.wave.3")
                        .foregroundColor(.blue)
                    
                    Text("Volume")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(Int(volume))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $volume, in: 0...100, step: 5)
                    .onChange(of: volume) { newValue in
                        Task {
                            await deviceController.executeAction(.setVolume, on: device, parameters: ["volume": Int(newValue)])
                        }
                    }
            }
            
            // Playback controls
            HStack(spacing: 16) {
                ActionButton(title: "Previous", icon: "backward.fill", color: .blue) {
                    Task {
                        await deviceController.executeAction(.previous, on: device)
                    }
                }
                
                ActionButton(title: "Play/Pause", icon: "playpause.fill", color: .green) {
                    Task {
                        await deviceController.executeAction(.toggle, on: device)
                    }
                }
                
                ActionButton(title: "Next", icon: "forward.fill", color: .blue) {
                    Task {
                        await deviceController.executeAction(.next, on: device)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Thermostat Controls View
struct ThermostatControlsView: View {
    let device: SmartDevice
    @ObservedObject var deviceController: DeviceController
    @State private var temperature: Double = 72
    
    var body: some View {
        VStack(spacing: 16) {
            // Temperature control
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "thermometer")
                        .foregroundColor(.orange)
                    
                    Text("Temperature")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(Int(temperature))°F")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $temperature, in: 60...85, step: 1)
                    .onChange(of: temperature) { newValue in
                        Task {
                            await deviceController.executeAction(.setTemperature, on: device, parameters: ["temperature": Int(newValue)])
                        }
                    }
            }
            
            // Mode controls
            HStack(spacing: 16) {
                ActionButton(title: "Heat", icon: "flame.fill", color: .red) {
                    Task {
                        await deviceController.executeAction(.setMode, on: device, parameters: ["mode": "heat"])
                    }
                }
                
                ActionButton(title: "Cool", icon: "snowflake", color: .blue) {
                    Task {
                        await deviceController.executeAction(.setMode, on: device, parameters: ["mode": "cool"])
                    }
                }
                
                ActionButton(title: "Auto", icon: "thermometer.sun.fill", color: .orange) {
                    Task {
                        await deviceController.executeAction(.setMode, on: device, parameters: ["mode": "auto"])
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Generic Controls View
struct GenericControlsView: View {
    let device: SmartDevice
    @ObservedObject var deviceController: DeviceController
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ActionButton(title: "On", icon: "power", color: .green) {
                    Task {
                        await deviceController.executeAction(.turnOn, on: device)
                    }
                }
                
                ActionButton(title: "Off", icon: "power", color: .red) {
                    Task {
                        await deviceController.executeAction(.turnOff, on: device)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Device Detail View
struct DeviceDetailView: View {
    let device: SmartDevice
    @ObservedObject var deviceController: DeviceController
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Device info
                    deviceInfoSection
                    
                    // Device status
                    deviceStatusSection
                    
                    // Device history
                    deviceHistorySection
                }
                .padding()
            }
            .navigationTitle("Device Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    private var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Information")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                InfoRow(label: "Name", value: device.name)
                InfoRow(label: "Type", value: device.type.displayName)
                InfoRow(label: "Platform", value: device.platform?.displayName ?? "Unknown")
                InfoRow(label: "ID", value: device.id.uuidString.prefix(8).description)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var deviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                InfoRow(label: "Online", value: device.isOnline ? "Yes" : "No")
                InfoRow(label: "Power", value: device.isOn ? "On" : "Off")
                InfoRow(label: "Last Updated", value: "Just now")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var deviceHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("No recent activity")
                .font(.body)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
    }
} 