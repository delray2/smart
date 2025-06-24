import SwiftUI

// MARK: - Home View
struct HomeView: View {
    @EnvironmentObject var roomStorage: RoomStorage
    @EnvironmentObject var deviceController: DeviceController
    @Binding var showingRoomCapture: Bool
    @State private var selectedRoom: Room?
    @State private var showingRoomDetail = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if roomStorage.rooms.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(roomStorage.rooms) { room in
                            RoomCardView(room: room) {
                                selectedRoom = room
                                showingRoomDetail = true
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("My Rooms")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingRoomDetail) {
                if let room = selectedRoom {
                    RoomDetailView(room: room)
                        .environmentObject(roomStorage)
                        .environmentObject(deviceController)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "house.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 12) {
                Text("Welcome to RoomScanningApp")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Your scans will be here.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 60)
    }
}

// MARK: - Room Card View
struct RoomCardView: View {
    let room: Room
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Room header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(room.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("Last updated \(room.updatedAt, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Room status indicator
                    ZStack {
                        Circle()
                            .fill(room.scanData != nil ? Color.green : Color.orange)
                            .frame(width: 12, height: 12)
                        
                        if room.scanData != nil {
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    }
                }
                
                // Room preview or placeholder
                if let scanData = room.scanData {
                    roomPreviewView(scanData: scanData)
                } else {
                    roomPlaceholderView
                }
                
                // Room stats
                roomStatsView
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func roomPreviewView(scanData: RoomScanData) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
                .frame(height: 120)
            
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "cube.box.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    Text("3D Model")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(format: "%.0f", scanData.dimensions.area)) sq ft")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("\(scanData.walls.count) walls • \(scanData.objects.count) objects")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private var roomPlaceholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .frame(height: 120)
            
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.title)
                        .foregroundColor(.orange)
                    
                    Text("Scan Needed")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("No 3D model yet")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Tap to scan this room")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private var roomStatsView: some View {
        HStack(spacing: 20) {
            StatItem(
                icon: "lightbulb.fill",
                value: "\(room.devices.count)",
                label: "Devices",
                color: .yellow
            )
            
            if let scanData = room.scanData {
                StatItem(
                    icon: "ruler.fill",
                    value: "\(String(format: "%.0f", scanData.dimensions.width))'",
                    label: "Width",
                    color: .blue
                )
                
                StatItem(
                    icon: "ruler.fill",
                    value: "\(String(format: "%.0f", scanData.dimensions.length))'",
                    label: "Length",
                    color: .blue
                )
            }
            
            Spacer()
        }
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                
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