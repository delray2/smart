import SwiftUI
import SceneKit
import simd

// MARK: - Room Scan Editor View
struct RoomScanEditorView: View {
    let room: Room
    @ObservedObject var deviceController: DeviceController
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedDevice: SmartDevice?
    @State private var showingDeviceControls = false
    @State private var showingAddDevice = false
    @State private var editingMode: EditingMode = .view
    @State private var showingExportOptions = false
    
    enum EditingMode {
        case view, edit, device
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // 3D Scene View
                RoomEditorSceneView(
                    room: room,
                    deviceController: deviceController,
                    selectedDevice: $selectedDevice,
                    editingMode: $editingMode
                )
                
                // Overlay UI
                VStack {
                    // Top toolbar
                    topToolbarView
                    
                    Spacer()
                    
                    // Bottom controls
                    bottomControlsView
                }
                .padding()
            }
            .navigationTitle(room.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: HStack(spacing: 16) {
                    Button("Export") {
                        showingExportOptions = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            )
            .sheet(isPresented: $showingDeviceControls) {
                if let device = selectedDevice {
                    DevicePopoverView(
                        device: device,
                        deviceController: deviceController
                    )
                }
            }
            .sheet(isPresented: $showingAddDevice) {
                DeviceDiscoveryView()
            }
            .actionSheet(isPresented: $showingExportOptions) {
                ActionSheet(
                    title: Text("Export Room"),
                    message: Text("Choose export format"),
                    buttons: [
                        .default(Text("USDZ File")) {
                            exportRoom(format: .usdz)
                        },
                        .default(Text("3D Model")) {
                            exportRoom(format: .model)
                        },
                        .default(Text("Floor Plan")) {
                            exportRoom(format: .floorPlan)
                        },
                        .cancel()
                    ]
                )
            }
        }
    }
    
    // MARK: - Top Toolbar View
    private var topToolbarView: some View {
        VStack(spacing: 12) {
            // Mode selector
            HStack(spacing: 16) {
                ModeButton(
                    title: "View",
                    icon: "eye",
                    isSelected: editingMode == .view
                ) {
                    editingMode = .view
                }
                
                ModeButton(
                    title: "Edit",
                    icon: "pencil",
                    isSelected: editingMode == .edit
                ) {
                    editingMode = .edit
                }
                
                ModeButton(
                    title: "Devices",
                    icon: "lightbulb",
                    isSelected: editingMode == .device
                ) {
                    editingMode = .device
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.7))
                    .background(.ultraThinMaterial)
            )
            .cornerRadius(12)
            
            // Device info (when device is selected)
            if let device = selectedDevice {
                deviceInfoCard(device)
            }
        }
    }
    
    // MARK: - Device Info Card
    private func deviceInfoCard(_ device: SmartDevice) -> some View {
        HStack {
            // Device icon
            ZStack {
                Circle()
                    .fill(device.type.color.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: device.type.iconName)
                    .font(.title3)
                    .foregroundColor(device.type.color)
            }
            
            // Device info
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(device.type.displayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            // Quick actions
            HStack(spacing: 12) {
                Button(action: {
                    showingDeviceControls = true
                }) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.white)
                }
                .buttonStyle(CircularButtonStyle())
                
                Button(action: {
                    selectedDevice = nil
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                }
                .buttonStyle(CircularButtonStyle())
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
                .background(.ultraThinMaterial)
        )
        .cornerRadius(12)
    }
    
    // MARK: - Bottom Controls View
    private var bottomControlsView: some View {
        VStack(spacing: 16) {
            // Mode-specific controls
            switch editingMode {
            case .view:
                viewModeControls
            case .edit:
                editModeControls
            case .device:
                deviceModeControls
            }
        }
    }
    
    // MARK: - View Mode Controls
    private var viewModeControls: some View {
        VStack(spacing: 12) {
            Text("View Mode")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                ActionButton(title: "Reset View", icon: "arrow.clockwise", color: .blue) {
                    // Reset camera view
                }
                
                ActionButton(title: "Take Screenshot", icon: "camera", color: .green) {
                    // Take screenshot
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
                .background(.ultraThinMaterial)
        )
        .cornerRadius(12)
    }
    
    // MARK: - Edit Mode Controls
    private var editModeControls: some View {
        VStack(spacing: 12) {
            Text("Edit Mode")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                ActionButton(title: "Undo", icon: "arrow.uturn.backward", color: .orange) {
                    // Undo last action
                }
                
                ActionButton(title: "Redo", icon: "arrow.uturn.forward", color: .blue) {
                    // Redo last action
                }
                
                ActionButton(title: "Reset", icon: "arrow.clockwise", color: .red) {
                    // Reset all changes
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
                .background(.ultraThinMaterial)
        )
        .cornerRadius(12)
    }
    
    // MARK: - Device Mode Controls
    private var deviceModeControls: some View {
        VStack(spacing: 12) {
            Text("Device Management")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                ActionButton(title: "Add Device", icon: "plus.circle", color: .green) {
                    showingAddDevice = true
                }
                
                ActionButton(title: "Select All", icon: "checkmark.circle", color: .blue) {
                    // Select all devices
                }
                
                ActionButton(title: "Remove All", icon: "trash", color: .red) {
                    // Remove all devices
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
                .background(.ultraThinMaterial)
        )
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    private func exportRoom(format: ExportFormat) {
        // Handle room export
        print("Exporting room in \(format) format")
    }
}

// MARK: - Room Editor Scene View
struct RoomEditorSceneView: UIViewRepresentable {
    let room: Room
    @ObservedObject var deviceController: DeviceController
    @Binding var selectedDevice: SmartDevice?
    @Binding var editingMode: RoomScanEditorView.EditingMode
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = createScene()
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = UIColor.systemBackground
        
        // Add tap gesture for device selection
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
        
        context.coordinator.sceneView = sceneView
        context.coordinator.selectedDevice = $selectedDevice
        context.coordinator.editingMode = $editingMode
        
        return sceneView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update scene based on mode changes
        context.coordinator.updateScene()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func createScene() -> SCNScene {
        let scene = SCNScene()
        
        // Try to load USDZ file first if available
        if let scanData = room.scanData, let usdzPath = scanData.usdzFilePath {
            do {
                let usdzURL = URL(fileURLWithPath: usdzPath)
                let usdzScene = try SCNScene(url: usdzURL, options: nil)
                
                // Copy all nodes from USDZ scene to our scene
                for childNode in usdzScene.rootNode.childNodes {
                    scene.rootNode.addChildNode(childNode)
                }
                
                print("Loaded USDZ scene from: \(usdzPath)")
            } catch {
                print("Failed to load USDZ file: \(error), falling back to generated geometry")
                // Fall back to generated geometry
                addRoomGeometry(to: scene)
            }
        } else {
            // No USDZ file, use generated geometry
            addRoomGeometry(to: scene)
        }
        
        // Add devices on top of the scene
        addDevices(to: scene)
        
        return scene
    }
    
    private func addRoomGeometry(to scene: SCNScene) {
        guard let scanData = room.scanData else {
            // Show proper error state instead of placeholder
            addErrorState(to: scene)
            return
        }
        
        // Add walls
        for wall in scanData.walls {
            let wallNode = createWallNode(wall)
            scene.rootNode.addChildNode(wallNode)
        }
        
        // Add openings
        for opening in scanData.openings {
            let openingNode = createOpeningNode(opening)
            scene.rootNode.addChildNode(openingNode)
        }
        
        // Add furniture objects
        for object in scanData.objects {
            let objectNode = createFurnitureNode(object)
            scene.rootNode.addChildNode(objectNode)
        }
    }
    
    private func addErrorState(to scene: SCNScene) {
        // Create a simple error indicator
        let errorNode = SCNNode()
        
        // Add a text geometry to show error
        let textGeometry = SCNText(string: "No Scan Data", extrusionDepth: 0.1)
        textGeometry.font = UIFont.systemFont(ofSize: 0.5)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.red
        
        let textNode = SCNNode(geometry: textGeometry)
        textNode.position = SCNVector3(0, 0, 0)
        errorNode.addChildNode(textNode)
        
        scene.rootNode.addChildNode(errorNode)
    }
    
    private func createWallNode(_ wall: Wall) -> SCNNode {
        let wallGeometry = SCNBox(
            width: CGFloat(wall.dimensions.x),
            height: CGFloat(wall.dimensions.y),
            length: CGFloat(wall.dimensions.z),
            chamferRadius: 0
        )
        
        wallGeometry.firstMaterial?.diffuse.contents = UIColor.lightGray
        wallGeometry.firstMaterial?.transparency = 0.8
        
        let wallNode = SCNNode(geometry: wallGeometry)
        wallNode.simdTransform = wall.transform
        
        return wallNode
    }
    
    private func createOpeningNode(_ opening: Opening) -> SCNNode {
        let openingGeometry = SCNBox(
            width: CGFloat(opening.dimensions.x),
            height: CGFloat(opening.dimensions.y),
            length: CGFloat(opening.dimensions.z),
            chamferRadius: 0
        )
        
        openingGeometry.firstMaterial?.diffuse.contents = UIColor.blue
        openingGeometry.firstMaterial?.transparency = 0.6
        
        let openingNode = SCNNode(geometry: openingGeometry)
        openingNode.simdTransform = opening.transform
        
        return openingNode
    }
    
    private func createFurnitureNode(_ object: FurnitureObject) -> SCNNode {
        let furnitureGeometry = SCNBox(
            width: CGFloat(object.dimensions.x),
            height: CGFloat(object.dimensions.y),
            length: CGFloat(object.dimensions.z),
            chamferRadius: 0.02
        )
        
        furnitureGeometry.firstMaterial?.diffuse.contents = UIColor.brown
        furnitureGeometry.firstMaterial?.transparency = 0.9
        
        let furnitureNode = SCNNode(geometry: furnitureGeometry)
        furnitureNode.position = SCNVector3(object.position.x, object.position.y, object.position.z)
        
        return furnitureNode
    }
    
    private func addDevices(to scene: SCNScene) {
        for device in room.devices {
            let deviceNode = createDeviceNode(device)
            scene.rootNode.addChildNode(deviceNode)
        }
    }
    
    private func createDeviceNode(_ device: SmartDevice) -> SCNNode {
        // Create device geometry based on type
        let geometry: SCNGeometry
        
        switch device.type {
        case .lifxBulb:
            geometry = SCNSphere(radius: 0.1)
        case .smartTV:
            geometry = SCNBox(width: 0.8, height: 0.5, length: 0.05, chamferRadius: 0.01)
        case .robotVacuum:
            geometry = SCNCylinder(radius: 0.15, height: 0.1)
        case .smartSpeaker:
            geometry = SCNCylinder(radius: 0.08, height: 0.2)
        case .smartThermostat:
            geometry = SCNBox(width: 0.1, height: 0.15, length: 0.02, chamferRadius: 0.01)
        case .smartLock:
            geometry = SCNBox(width: 0.05, height: 0.1, length: 0.02, chamferRadius: 0.005)
        case .smartCamera:
            geometry = SCNBox(width: 0.08, height: 0.08, length: 0.05, chamferRadius: 0.01)
        default:
            geometry = SCNSphere(radius: 0.05)
        }
        
        // Set material
        let material = SCNMaterial()
        material.diffuse.contents = device.type.color
        material.transparency = 0.8
        geometry.materials = [material]
        
        let deviceNode = SCNNode(geometry: geometry)
        deviceNode.position = SCNVector3(device.position.x, device.position.y, device.position.z)
        deviceNode.name = device.id.uuidString
        
        // Add device name label
        let textGeometry = SCNText(string: device.name, extrusionDepth: 0.01)
        textGeometry.font = UIFont.systemFont(ofSize: 0.05)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.black
        
        let textNode = SCNNode(geometry: textGeometry)
        textNode.position = SCNVector3(0, 0.2, 0)
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)
        deviceNode.addChildNode(textNode)
        
        return deviceNode
    }
    
    class Coordinator: NSObject {
        var parent: RoomEditorSceneView
        var sceneView: SCNView?
        var selectedDevice: Binding<SmartDevice?>
        var editingMode: Binding<RoomScanEditorView.EditingMode>
        
        init(_ parent: RoomEditorSceneView) {
            self.parent = parent
            self.selectedDevice = parent.$selectedDevice
            self.editingMode = parent.$editingMode
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView = sceneView else { return }
            
            let location = gesture.location(in: sceneView)
            let hitResults = sceneView.hitTest(location, options: [:])
            
            if let hitResult = hitResults.first,
               let nodeName = hitResult.node.name,
               let deviceId = UUID(uuidString: nodeName),
               let device = parent.room.devices.first(where: { $0.id == deviceId }) {
                selectedDevice.wrappedValue = device
            } else {
                selectedDevice.wrappedValue = nil
            }
        }
        
        func updateScene() {
            // Update scene based on editing mode
            // This could include showing/hiding selection indicators, etc.
        }
    }
}

// ModeButton, ActionButton, and CircularButtonStyle are defined in SmartHomePlatforms.swift

// Export format is defined in SmartHomePlatforms.swift 