import SwiftUI

// MARK: - Add Device to Room View
struct AddDeviceToRoomView: View {
    let room: Room
    @EnvironmentObject var deviceController: DeviceController
    @EnvironmentObject var roomStorage: RoomStorage
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedPlatform: SmartHomePlatform?
    @State private var showingDeviceDiscovery = false
    @State private var selectedDevice: SmartDevice?
    @State private var showingDevicePlacement = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Room info header
                roomInfoHeader
                
                if room.scanData != nil {
                    // Device selection list
                    deviceSelectionList
                } else {
                    // No scan available message
                    noScanMessage
                }
            }
            .navigationTitle("Add Device to \(room.name)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Discover New") {
                    showingDeviceDiscovery = true
                }
                .disabled(room.scanData == nil)
            )
            .sheet(isPresented: $showingDeviceDiscovery) {
                DeviceDiscoveryView()
                    .environmentObject(deviceController)
            }
            .sheet(isPresented: $showingDevicePlacement) {
                if let device = selectedDevice {
                    DevicePlacementView(
                        device: device,
                        room: room,
                        deviceController: deviceController
                    )
                    .environmentObject(roomStorage)
                }
            }
        }
    }
    
    // MARK: - Room Info Header
    private var roomInfoHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("\(room.devices.count) devices installed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if room.scanData != nil {
                Label("3D Scan Available", systemImage: "cube.box.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Device Selection List
    private var deviceSelectionList: some View {
        List {
            // Available devices section
            Section(header: Text("Available Devices")) {
                let availableDevices = deviceController.allDevices.filter { device in
                    !room.devices.contains { $0.id == device.id }
                }
                
                if availableDevices.isEmpty {
                    HStack {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.secondary)
                        Text("No devices discovered yet")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(availableDevices) { device in
                        DeviceRowView(device: device) {
                            selectedDevice = device
                            showingDevicePlacement = true
                        }
                    }
                }
            }
            
            // Installed devices section
            if !room.devices.isEmpty {
                Section(header: Text("Already in Room")) {
                    ForEach(room.devices) { device in
                        HStack {
                            Image(systemName: device.type.iconName)
                                .foregroundColor(device.type.color)
                                .frame(width: 30)
                            
                            Text(device.name)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear {
            // Check if we need to discover devices
            if deviceController.allDevices.isEmpty && !deviceController.connectedPlatforms.isEmpty {
                Task {
                    await deviceController.discoverDevices()
                }
            }
        }
    }
    
    // MARK: - No Scan Message
    private var noScanMessage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 80))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Room Scan Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("You need to scan this room before you can place devices in 3D space.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Scan Room") {
                presentationMode.wrappedValue.dismiss()
                // The parent view should handle navigation to scan
            }
            .buttonStyle(PrimaryButtonStyle())
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Device Row View
struct DeviceRowView: View {
    let device: SmartDevice
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Device icon
                ZStack {
                    Circle()
                        .fill(device.type.color.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: device.type.iconName)
                        .font(.title3)
                        .foregroundColor(device.type.color)
                }
                
                // Device info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(device.type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Circle()
                            .fill(device.isOnline ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        
                        Text(device.isOnline ? "Online" : "Offline")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Edit Room View
struct EditRoomView: View {
    let room: Room
    @Environment(\.presentationMode) var presentationMode
    @State private var roomName = ""
    @State private var roomType: RoomType = .other
    @State private var roomDescription = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Room Details")) {
                    TextField("Room Name", text: $roomName)
                    
                    Picker("Room Type", selection: $roomType) {
                        ForEach(RoomType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    TextField("Description", text: $roomDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section(header: Text("Room Statistics")) {
                    HStack {
                        Text("Devices")
                        Spacer()
                        Text("\(room.devices.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("3D Scan")
                        Spacer()
                        Text(room.scanData != nil ? "Available" : "Not Available")
                            .foregroundColor(room.scanData != nil ? .green : .orange)
                    }
                    
                    if let scanData = room.scanData {
                        HStack {
                            Text("Room Size")
                            Spacer()
                            Text("\(String(format: "%.0f", scanData.dimensions.area)) sq ft")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Edit Room")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    saveChanges()
                }
            )
            .onAppear {
                roomName = room.name
                roomType = room.type
                roomDescription = room.description ?? ""
            }
        }
    }
    
    private func saveChanges() {
        var updatedRoom = room
        updatedRoom.name = roomName
        updatedRoom.type = roomType
        updatedRoom.description = roomDescription.isEmpty ? nil : roomDescription
        updatedRoom.updatedAt = Date()
        
        RoomStorage.shared.updateRoom(updatedRoom)
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Room 3D View (for rooms without scan data)
struct Room3DView: View {
    let room: Room
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                if room.scanData != nil {
                    Text("3D View Available")
                        .font(.title)
                } else {
                    VStack(spacing: 24) {
                        Image(systemName: "cube.box")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary)
                        
                        Text("No 3D Model")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("This room hasn't been scanned yet.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("\(room.name) - 3D View")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
} 
