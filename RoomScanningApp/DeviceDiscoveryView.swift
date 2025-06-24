import SwiftUI
import SceneKit

// MARK: - Device Discovery View
struct DeviceDiscoveryView: View {
    @EnvironmentObject var deviceController: DeviceController
    @EnvironmentObject var roomStorage: RoomStorage
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedPlatform: SmartHomePlatform?
    @State private var showingPlatformAuth = false
    @State private var showingDevicePlacement = false
    @State private var selectedDevice: SmartDevice?
    @State private var selectedRoom: Room?
    @State private var showingRoomSelection = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Platform selection
                platformSelectionView
                
                // Device list
                deviceListView
            }
            .navigationTitle("Add Devices")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .sheet(isPresented: $showingPlatformAuth) {
                if let platform = selectedPlatform {
                    PlatformAuthView(platform: platform, deviceController: deviceController)
                }
            }
            .sheet(isPresented: $showingDevicePlacement) {
                if let device = selectedDevice, let room = selectedRoom {
                    DevicePlacementView(device: device, room: room, deviceController: deviceController)
                        .environmentObject(roomStorage)
                        .environmentObject(deviceController)
                }
            }
            .sheet(isPresented: $showingRoomSelection) {
                RoomSelectionView(selectedRoom: $selectedRoom, onRoomSelected: { room in
                    selectedRoom = room
                    showingRoomSelection = false
                    if let device = selectedDevice {
                        showingDevicePlacement = true
                    }
                })
            }
        }
        .onAppear {
            // Check for existing devices and platforms on view appear
            checkExistingData()
        }
    }
    
    // MARK: - Platform Selection View
    private var platformSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Smart Home Platforms")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SmartHomePlatform.allCases) { platform in
                        PlatformCardView(
                            platform: platform,
                            authState: deviceController.isPlatformConnected(platform) ? .authenticated : .notAuthenticated
                        ) {
                            selectedPlatform = platform
                            handlePlatformSelection(platform)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Device List View
    private var deviceListView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Available Devices")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal)
            
            if deviceController.connectedPlatforms.isEmpty {
                emptyStateView
            } else {
                deviceListContent
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Connected Platforms")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Connect to your smart home platforms above to discover and add devices to your rooms.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var deviceListContent: some View {
        List {
            ForEach(deviceController.connectedPlatforms, id: \.self) { platform in
                Section(header: Text(platform.displayName)) {
                    let platformDevices = deviceController.getDevices(for: platform)
                    if platformDevices.isEmpty {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Discovering devices...")
                                .foregroundColor(.secondary)
                        }
                        .onAppear {
                            Task {
                                await deviceController.discoverDevices()
                            }
                        }
                    } else {
                        ForEach(platformDevices) { platformDevice in
                            let smartDevice = SmartDevice(
                                name: platformDevice.name,
                                type: platformDevice.type,
                                position: SIMD3<Float>(0, 0, 0)
                            )
                            DeviceRowView(device: smartDevice) {
                                selectedDevice = smartDevice
                                showingRoomSelection = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func checkExistingData() {
        // Check if we already have devices and platforms loaded
        if deviceController.allDevices.isEmpty && !deviceController.connectedPlatforms.isEmpty {
            // We have platforms but no devices, trigger discovery
            Task {
                await deviceController.discoverDevices()
            }
        }
    }
    
    private func handlePlatformSelection(_ platform: SmartHomePlatform) {
        let isConnected = deviceController.isPlatformConnected(platform)
        
        if !isConnected {
            showingPlatformAuth = true
        } else {
            // Platform is already authenticated, refresh devices
            Task {
                await deviceController.discoverDevices()
            }
        }
    }
    
    private func showRoomSelection(for device: SmartDevice) {
        // Get available rooms from storage
        let availableRooms = RoomStorage.shared.rooms
        
        if availableRooms.isEmpty {
            // Create a default room if none exist
            let defaultRoom = Room(name: "Living Room")
            RoomStorage.shared.saveRoom(defaultRoom)
            selectedRoom = defaultRoom
            showingDevicePlacement = true
        } else if availableRooms.count == 1 {
            // Use the only available room
            selectedRoom = availableRooms.first
            showingDevicePlacement = true
        } else {
            // Show room selection
            showingRoomSelection = true
        }
    }
    
    private func addDeviceToRoom(_ device: SmartDevice, room: Room) {
        var updatedRoom = room
        updatedRoom.devices.append(device)
        updatedRoom.updatedAt = Date()
        
        // Save the updated room
        RoomStorage.shared.updateRoom(updatedRoom)
        
        // Add device to controller if not already present
        if !deviceController.allDevices.contains(where: { $0.id == device.id }) {
            deviceController.addDevice(device)
        }
    }
}

// MARK: - Platform Card View
struct PlatformCardView: View {
    let platform: SmartHomePlatform
    let authState: PlatformAuthState
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Platform icon
                ZStack {
                    Circle()
                        .fill(platform.color.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: platform.iconName)
                        .font(.title2)
                        .foregroundColor(platform.color)
                }
                
                // Platform name
                Text(platform.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                // Auth status
                authStatusView
            }
            .frame(width: 100)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(authState == .authenticating)
    }
    
    private var authStatusView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(authStateColor)
                .frame(width: 8, height: 8)
            
            Text(authStateText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var authStateColor: Color {
        switch authState {
        case .notAuthenticated:
            return .gray
        case .authenticating:
            return .orange
        case .authenticated:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var authStateText: String {
        switch authState {
        case .notAuthenticated:
            return "Connect"
        case .authenticating:
            return "Connecting..."
        case .authenticated:
            return "Connected"
        case .failed:
            return "Failed"
        }
    }
}

// MARK: - Platform Device Row View
struct PlatformDeviceRowView: View {
    let device: PlatformDevice
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Device icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(device.platform.color.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: device.type.iconName)
                        .font(.title3)
                        .foregroundColor(device.platform.color)
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
                
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Room Selection View
struct RoomSelectionView: View {
    @Binding var selectedRoom: Room?
    let onRoomSelected: (Room) -> Void
    @StateObject private var roomStorage = RoomStorage.shared
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                ForEach(roomStorage.rooms) { room in
                    Button(action: {
                        onRoomSelected(room)
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(room.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("\(room.devices.count) devices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedRoom?.id == room.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .navigationTitle("Select Room")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Platform Auth View
struct PlatformAuthView: View {
    let platform: SmartHomePlatform
    @ObservedObject var deviceController: DeviceController
    @Environment(\.presentationMode) var presentationMode
    @State private var apiKey = ""
    @State private var showingAPIKeyInput = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Platform info
                platformInfoView
                
                // Auth method
                authMethodView
                
                Spacer()
            }
            .padding()
            .navigationTitle("Connect \(platform.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .sheet(isPresented: $showingAPIKeyInput) {
                APIKeyInputView(platform: platform, apiKey: $apiKey) {
                    authenticateWithAPIKey()
                }
            }
        }
    }
    
    private var platformInfoView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(platform.color.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: platform.iconName)
                    .font(.title)
                    .foregroundColor(platform.color)
            }
            
            Text(platform.displayName)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(platform.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var authMethodView: some View {
        VStack(spacing: 16) {
            switch platform.authType {
            case .apiKey:
                Button("Enter API Key") {
                    showingAPIKeyInput = true
                }
                .buttonStyle(PrimaryButtonStyle())
                
            case .oauth2:
                Button("Sign In with \(platform.displayName)") {
                    authenticateWithOAuth2()
                }
                .buttonStyle(PrimaryButtonStyle())
                
            case .local:
                Button("Discover on Local Network") {
                    authenticateLocally()
                }
                .buttonStyle(PrimaryButtonStyle())
                
            case .bridge:
                Button("Discover Bridge") {
                    authenticateWithBridge()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            
            if deviceController.isLoading {
                ProgressView("Connecting...")
                    .padding()
            }
            
            if let errorMessage = deviceController.errorMessage {
                Text("Connection failed: \(errorMessage)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func authenticateWithAPIKey() {
        Task {
            await deviceController.authenticatePlatform(platform, apiKey: apiKey)
        }
    }
    
    private func authenticateWithOAuth2() {
        Task {
            await deviceController.authenticatePlatform(platform)
        }
    }
    
    private func authenticateLocally() {
        Task {
            await deviceController.authenticatePlatform(platform)
        }
    }
    
    private func authenticateWithBridge() {
        Task {
            await deviceController.authenticatePlatform(platform)
        }
    }
}

// MARK: - API Key Input View
struct APIKeyInputView: View {
    let platform: SmartHomePlatform
    @Binding var apiKey: String
    let onSave: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Enter your \(platform.displayName) API Key")
                    .font(.headline)
                
                Text("You can find your API key in your \(platform.displayName) account settings.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Button("Connect") {
                    onSave()
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(apiKey.isEmpty)
                
                Spacer()
            }
            .padding()
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
} 