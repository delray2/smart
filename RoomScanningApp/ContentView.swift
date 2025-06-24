import SwiftUI
import RoomPlan
import RealityKit

struct ContentView: View {
    @AppStorage("selectedTab") private var selectedTab = 0
    @State private var showingRoomCapture = false
    @EnvironmentObject var roomStorage: RoomStorage
    @EnvironmentObject var deviceController: DeviceController
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            HomeView(showingRoomCapture: $showingRoomCapture)
                .tabItem {
                    Image(systemName: "house")
                    Text("Home")
                }
                .tag(0)
            
            // Scan Tab - Direct to room capture
            RoomCaptureScreen()
                .tabItem {
                    Image(systemName: "camera.viewfinder")
                    Text("Scan")
                }
                .tag(1)
            
            // Devices Tab
            DeviceDiscoveryView()
                .environmentObject(deviceController)
                .tabItem {
                    Image(systemName: "wifi")
                    Text("Devices")
                }
                .tag(2)
            
            // Settings Tab
            SettingsView(deviceController: deviceController)
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(3)
        }
        .sheet(isPresented: $showingRoomCapture) {
            RoomCaptureScreen()
                .environmentObject(roomStorage)
                .environmentObject(deviceController)
        }
    }
}

// MARK: - Device Indicator View
struct DeviceIndicatorView: View {
    let devices: [SmartDevice]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(devices.prefix(3)) { device in
                Circle()
                    .fill(device.type.color)
                    .frame(width: 8, height: 8)
            }
            
            if devices.count > 3 {
                Text("+\(devices.count - 3)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - Filter Button
struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Add Room View
struct AddRoomView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var roomStorage: RoomStorage
    @State private var roomName = ""
    @State private var roomType = RoomType.livingRoom
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
                    
                    TextField("Description (Optional)", text: $roomDescription)
                }
                
                Section(header: Text("Room Type Description")) {
                    Text(roomType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Room")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    saveRoom()
                }
                .disabled(roomName.isEmpty)
            )
        }
    }
    
    private func saveRoom() {
        let newRoom = Room(
            name: roomName,
            type: roomType,
            description: roomDescription.isEmpty ? nil : roomDescription
        )
        roomStorage.addRoom(newRoom)
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Room Filter
enum RoomFilter: String, CaseIterable {
    case all = "all"
    case withDevices = "with_devices"
    case scanned = "scanned"
    case recent = "recent"
    
    var displayTitle: String {
        switch self {
        case .all: return "All"
        case .withDevices: return "With Devices"
        case .scanned: return "Scanned"
        case .recent: return "Recent"
        }
    }
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.blue)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
} 