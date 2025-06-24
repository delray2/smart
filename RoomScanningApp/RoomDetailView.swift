import SwiftUI
import SceneKit
import ARKit

// MARK: - Room Detail View
struct RoomDetailView: View {
    @EnvironmentObject var deviceController: DeviceController
    @EnvironmentObject var roomStorage: RoomStorage
    @Environment(\.presentationMode) var presentationMode
    
    let room: Room
    @State private var showingAddDevice = false
    @State private var showingEditRoom = false
    @State private var showing3DView = false
    @State private var selectedDevice: SmartDevice?
    @State private var showingDeviceControl = false
    @State private var viewMode: ViewMode = .overview
    @State private var showingRoomCapture = false
    
    enum ViewMode: String, CaseIterable {
        case overview = "overview"
        case devices = "devices"
        case scan = "scan"
        
        var displayTitle: String {
            switch self {
            case .overview: return "Overview"
            case .devices: return "Devices"
            case .scan: return "3D View"
            }
        }
        
        var icon: String {
            switch self {
            case .overview: return "house"
            case .devices: return "lightbulb"
            case .scan: return "cube.box"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Mode selector
            modeSelectorView
            
            // Content based on selected mode
            switch viewMode {
            case .overview:
                overviewView
            case .devices:
                devicesView
            case .scan:
                scanView
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingAddDevice) {
            AddDeviceToRoomView(room: room)
                .environmentObject(deviceController)
                .environmentObject(roomStorage)
        }
        .sheet(isPresented: $showingEditRoom) {
            EditRoomView(room: room)
        }
        .sheet(isPresented: $showing3DView) {
            if let scanData = room.scanData, let usdzPath = scanData.usdzFilePath {
                // Show USDZ viewer
                NavigationView {
                    USDZViewer(usdzPath: usdzPath)
                        .navigationTitle("3D View")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationBarItems(
                            trailing: Button("Done") {
                                showing3DView = false
                            }
                        )
                }
            } else if room.scanData != nil {
                // Show 3D editor for rooms with scan data but no USDZ
                RoomScanEditorView(room: room, deviceController: deviceController)
                    .environmentObject(roomStorage)
                    .environmentObject(deviceController)
            } else {
                // Show a proper placeholder with option to scan
                Room3DPlaceholderView(room: room) {
                    showingRoomCapture = true
                }
            }
        }
        .sheet(isPresented: $showingDeviceControl) {
            if let device = selectedDevice {
                DeviceControlView(device: device)
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 16) {
            // Top bar
            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text(room.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Menu {
                    Button("Edit Room") {
                        showingEditRoom = true
                    }
                    
                    Button("3D View") {
                        showing3DView = true
                    }
                    
                    Button("Export Data") {
                        exportRoomData()
                    }
                    
                    Divider()
                    
                    Button("Delete Room", role: .destructive) {
                        deleteRoom()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            
            // Room stats
            roomStatsView
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Room Stats View
    private var roomStatsView: some View {
        HStack(spacing: 20) {
            StatCard(
                icon: "lightbulb.fill",
                value: "\(room.devices.count)",
                label: "Devices",
                color: .yellow
            )
            
            StatCard(
                icon: "cube.box.fill",
                value: room.scanData != nil ? "Yes" : "No",
                label: "3D Scan",
                color: room.scanData != nil ? .green : .orange
            )
            
            StatCard(
                icon: "ruler",
                value: room.scanData != nil ? "\(String(format: "%.0f", room.scanData!.dimensions.area)) sq ft" : "N/A",
                label: "Area",
                color: .blue
            )
            
            StatCard(
                icon: "clock",
                value: room.updatedAt.timeAgoDisplay(),
                label: "Updated",
                color: .purple
            )
        }
    }
    
    // MARK: - Mode Selector View
    private var modeSelectorView: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(action: {
                    viewMode = mode
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.title3)
                            .foregroundColor(viewMode == mode ? .blue : .secondary)
                        
                        Text(mode.displayTitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(viewMode == mode ? .blue : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Rectangle()
                            .fill(viewMode == mode ? Color.blue.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Overview View
    private var overviewView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Room preview
                if let scanData = room.scanData {
                    roomPreviewCard(scanData: scanData)
                } else {
                    noScanCard
                }
                
                // Quick actions
                quickActionsView
                
                // Recent activity
                recentActivityView
                
                // Device summary
                deviceSummaryView
            }
            .padding()
        }
    }
    
    // MARK: - Room Preview Card
    private func roomPreviewCard(scanData: RoomScanData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cube.box.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("3D Room Model")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("View Full 3D") {
                    showing3DView = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            // 3D preview placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(height: 200)
                .overlay(
                    VStack {
                        Image(systemName: "view.3d")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("3D Preview")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
            
            // Scan details
            HStack(spacing: 20) {
                DetailItem(
                    icon: "ruler",
                    value: "\(String(format: "%.0f", scanData.dimensions.width))' × \(String(format: "%.0f", scanData.dimensions.length))'",
                    label: "Dimensions"
                )
                
                DetailItem(
                    icon: "square.grid.3x3",
                    value: "\(String(format: "%.0f", scanData.dimensions.area)) sq ft",
                    label: "Area"
                )
                
                DetailItem(
                    icon: "cube",
                    value: "\(scanData.objects.count)",
                    label: "Objects"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - No Scan Card
    private var noScanCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("No 3D Scan Available")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Scan this room to create a 3D model and enable device placement.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Scan Room") {
                // Navigate to scan view
                viewMode = .scan
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Quick Actions View
    private var quickActionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                QuickActionButton(
                    icon: "plus.circle.fill",
                    title: "Add Device",
                    color: .blue
                ) {
                    showingAddDevice = true
                }
                
                QuickActionButton(
                    icon: "camera.viewfinder",
                    title: "Scan Room",
                    color: .green
                ) {
                    viewMode = .scan
                }
                
                QuickActionButton(
                    icon: "cube.box.fill",
                    title: "3D View",
                    color: .purple
                ) {
                    showing3DView = true
                }
                
                QuickActionButton(
                    icon: "gear",
                    title: "Settings",
                    color: .orange
                ) {
                    // Navigate to settings
                }
            }
        }
    }
    
    // MARK: - Recent Activity View
    private var recentActivityView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                ActivityItem(
                    icon: "clock",
                    title: "Room updated",
                    subtitle: room.updatedAt.timeAgoDisplay(),
                    color: .blue
                )
                
                if !room.devices.isEmpty {
                    ActivityItem(
                        icon: "lightbulb.fill",
                        title: "\(room.devices.count) devices connected",
                        subtitle: "Last device added \(room.devices.last?.name ?? "")",
                        color: .yellow
                    )
                }
                
                if room.scanData != nil {
                    ActivityItem(
                        icon: "cube.box.fill",
                        title: "3D scan completed",
                        subtitle: "Room model available",
                        color: .green
                    )
                }
            }
        }
    }
    
    // MARK: - Device Summary View
    private var deviceSummaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Devices")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("View All") {
                    viewMode = .devices
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if room.devices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    
                    Text("No devices yet")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Button("Add Device") {
                        showingAddDevice = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(room.devices.prefix(3)) { device in
                        DeviceSummaryRow(device: device) {
                            selectedDevice = device
                            showingDeviceControl = true
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Devices View
    private var devicesView: some View {
        VStack(spacing: 16) {
            // Device controls
            HStack {
                Text("\(room.devices.count) Devices")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    showingAddDevice = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            if room.devices.isEmpty {
                emptyDevicesView
            } else {
                deviceListView
            }
        }
    }
    
    // MARK: - Empty Devices View
    private var emptyDevicesView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "lightbulb")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Devices Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Add smart devices to control them from this room.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Add Device") {
                showingAddDevice = true
            }
            .buttonStyle(PrimaryButtonStyle())
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Device List View
    private var deviceListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(room.devices) { device in
                    DeviceRowView(device: device) {
                        selectedDevice = device
                        showingDeviceControl = true
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Scan View
    private var scanView: some View {
        VStack(spacing: 20) {
            if let scanData = room.scanData, let usdzPath = scanData.usdzFilePath {
                // Show 3D viewer with USDZ file
                USDZViewer(usdzPath: usdzPath)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if room.scanData != nil {
                // Show 3D editor for rooms with scan data but no USDZ
                RoomScanEditorView(room: room, deviceController: deviceController)
                    .environmentObject(roomStorage)
                    .environmentObject(deviceController)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                noScanAvailableView
            }
        }
    }
    
    private var noScanAvailableView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 80))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("No 3D Scan Available")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create a 3D scan of this room to place and control devices in 3D space.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Start Room Scan") {
                // Navigate to room scan
                showingRoomCapture = true
            }
            .buttonStyle(PrimaryButtonStyle())
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    private func exportRoomData() {
        // Export room data functionality
        print("Exporting room data for: \(room.name)")
    }
    
    private func deleteRoom() {
        roomStorage.deleteRoom(room)
        presentationMode.wrappedValue.dismiss()
    }
}

// The duplicate types have been moved to SmartHomePlatforms.swift and AddDeviceToRoomView.swift

// MARK: - Device Row View (for room detail)
fileprivate struct RoomDetailDeviceRow: View {
    let device: SmartDevice
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: device.type.iconName)
                    .font(.title3)
                    .foregroundColor(device.type.color)
                    .frame(width: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(device.type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status indicators
                HStack(spacing: 8) {
                    if device.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    
                    if device.isOn {
                        Image(systemName: "power")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Room 3D Placeholder View
struct Room3DPlaceholderView: View {
    let room: Room
    let onScanRequested: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()
                
                // 3D placeholder icon
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 200, height: 200)
                    
                    VStack(spacing: 16) {
                        Image(systemName: "cube.box")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("No 3D Scan")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
                
                // Information text
                VStack(spacing: 12) {
                    Text("3D View Unavailable")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("This room hasn't been scanned yet. Create a 3D model of your room to visualize it in 3D space and place devices accurately.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    Button("Scan Room") {
                        presentationMode.wrappedValue.dismiss()
                        onScanRequested()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("3D View")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Button Styles

// MARK: - USDZ Viewer
struct USDZViewer: UIViewRepresentable {
    let usdzPath: String
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = UIColor.systemBackground
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.scene = SCNScene()
        
        // Load USDZ file
        let url = URL(fileURLWithPath: usdzPath)
        do {
            let scene = try SCNScene(url: url, options: nil)
            sceneView.scene = scene
            
            // Set up camera
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(x: 0, y: 5, z: 10)
            scene.rootNode.addChildNode(cameraNode)
            
            // Add ambient light
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.intensity = 100
            scene.rootNode.addChildNode(ambientLight)
            
            // Add directional light
            let directionalLight = SCNNode()
            directionalLight.light = SCNLight()
            directionalLight.light?.type = .directional
            directionalLight.light?.intensity = 800
            directionalLight.position = SCNVector3(x: 5, y: 5, z: 5)
            scene.rootNode.addChildNode(directionalLight)
            
            print("USDZ loaded successfully from: \(usdzPath)")
        } catch {
            print("Failed to load USDZ file: \(error)")
            // Show error placeholder
            showErrorPlaceholder(sceneView: sceneView)
        }
        
        return sceneView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update view if needed
    }
    
    private func showErrorPlaceholder(sceneView: SCNView) {
        let scene = SCNScene()
        
        // Create a simple placeholder geometry
        let box = SCNBox(width: 2, height: 2, length: 2, chamferRadius: 0.1)
        box.firstMaterial?.diffuse.contents = UIColor.systemBlue
        let boxNode = SCNNode(geometry: box)
        scene.rootNode.addChildNode(boxNode)
        
        // Add text
        let text = SCNText(string: "USDZ Load Error", extrusionDepth: 0.1)
        text.firstMaterial?.diffuse.contents = UIColor.systemRed
        let textNode = SCNNode(geometry: text)
        textNode.position = SCNVector3(x: -1, y: 3, z: 0)
        textNode.scale = SCNVector3(x: 0.1, y: 0.1, z: 0.1)
        scene.rootNode.addChildNode(textNode)
        
        sceneView.scene = scene
    }
}
