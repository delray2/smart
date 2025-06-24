import SwiftUI
import SceneKit
import ARKit

// MARK: - Device Placement View
struct DevicePlacementView: View {
    let device: SmartDevice
    let room: Room
    @ObservedObject var deviceController: DeviceController
    @EnvironmentObject var roomStorage: RoomStorage
    @Environment(\.presentationMode) var presentationMode
    
    @State private var devicePosition = SIMD3<Float>(0, 1, 0)
    @State private var deviceRotation = Float(0)
    @State private var placementMode: PlacementMode = .move
    @State private var showingConfirmation = false
    
    enum PlacementMode {
        case move, rotate, height
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // 3D Scene View
                DevicePlacementSceneView(
                    device: device,
                    room: room,
                    position: $devicePosition,
                    rotation: $deviceRotation,
                    placementMode: $placementMode
                )
                .ignoresSafeArea()
                
                // Overlay UI
                VStack {
                    // Top bar
                    topBarView
                    
                    Spacer()
                    
                    // Placement controls
                    placementControlsView
                    
                    // Bottom action bar
                    bottomActionBar
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Top Bar View
    private var topBarView: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text("Place Device")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(device.name)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Button("Help") {
                    // Show placement help
                }
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }
            
            // Device info
            HStack {
                Image(systemName: device.type.iconName)
                    .font(.title3)
                    .foregroundColor(device.type.color)
                
                Text(device.type.displayName)
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(room.name)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.7))
                    .background(.ultraThinMaterial)
            )
            .cornerRadius(12)
        }
    }
    
    // MARK: - Placement Controls View
    private var placementControlsView: some View {
        VStack(spacing: 16) {
            // Mode selector
            HStack(spacing: 12) {
                PlacementModeButton(
                    title: "Move",
                    icon: "move.3d",
                    isSelected: placementMode == .move
                ) {
                    placementMode = .move
                }
                
                PlacementModeButton(
                    title: "Rotate",
                    icon: "rotate.3d",
                    isSelected: placementMode == .rotate
                ) {
                    placementMode = .rotate
                }
                
                PlacementModeButton(
                    title: "Height",
                    icon: "arrow.up.and.down",
                    isSelected: placementMode == .height
                ) {
                    placementMode = .height
                }
            }
            
            // Position info
            VStack(spacing: 8) {
                HStack {
                    Text("Position:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("X: \(String(format: "%.1f", devicePosition.x)) Y: \(String(format: "%.1f", devicePosition.y)) Z: \(String(format: "%.1f", devicePosition.z))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                
                HStack {
                    Text("Rotation:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("\(Int(deviceRotation * 180 / .pi))°")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
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
    }
    
    // MARK: - Bottom Action Bar
    private var bottomActionBar: some View {
        HStack(spacing: 16) {
            Button("Reset Position") {
                devicePosition = SIMD3<Float>(0, 1, 0)
                deviceRotation = 0
            }
            .buttonStyle(SecondaryButtonStyle())
            
            Button("Place Device") {
                showingConfirmation = true
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .alert("Confirm Placement", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Place") {
                placeDevice()
            }
        } message: {
            Text("Place \(device.name) at this location in \(room.name)?")
        }
    }
    
    // MARK: - Helper Methods
    private func placeDevice() {
        // Update device position
        var updatedDevice = device
        updatedDevice.position = devicePosition
        
        // Add device to room
        var updatedRoom = room
        updatedRoom.devices.append(updatedDevice)
        updatedRoom.updatedAt = Date()
        
        // Save changes
        roomStorage.updateRoom(updatedRoom)
        deviceController.updateDevice(updatedDevice)
        
        // Dismiss view
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Device Placement Scene View
struct DevicePlacementSceneView: UIViewRepresentable {
    let device: SmartDevice
    let room: Room
    @Binding var position: SIMD3<Float>
    @Binding var rotation: Float
    @Binding var placementMode: DevicePlacementView.PlacementMode
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = createScene()
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = UIColor.systemBackground
        
        // Add gesture recognizers
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        sceneView.addGestureRecognizer(panGesture)
        
        context.coordinator.sceneView = sceneView
        context.coordinator.deviceNode = createDeviceNode()
        sceneView.scene?.rootNode.addChildNode(context.coordinator.deviceNode!)
        
        return sceneView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update device position
        context.coordinator.updateDevicePosition(position, rotation: rotation)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func createScene() -> SCNScene {
        let scene = SCNScene()
        
        // Add room geometry
        if let scanData = room.scanData {
            addRoomGeometry(to: scene, scanData: scanData)
        } else {
            addPlaceholderRoom(to: scene)
        }
        
        // Add lighting
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 0.3
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.intensity = 0.7
        let directionalNode = SCNNode()
        directionalNode.light = directionalLight
        directionalNode.eulerAngles = SCNVector3(x: -.pi/4, y: .pi/4, z: 0)
        scene.rootNode.addChildNode(directionalNode)
        
        return scene
    }
    
    private func addRoomGeometry(to scene: SCNScene, scanData: RoomScanData) {
        // Add walls
        for wall in scanData.walls {
            let wallNode = createWallNode(wall)
            scene.rootNode.addChildNode(wallNode)
        }
        
        // Add floor
        let floorNode = SCNNode(geometry: SCNPlane(width: 10, height: 10))
        floorNode.geometry?.firstMaterial?.diffuse.contents = UIColor.lightGray.withAlphaComponent(0.3)
        floorNode.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(floorNode)
    }
    
    private func addPlaceholderRoom(to scene: SCNScene) {
        // Create a simple room placeholder
        let floorNode = SCNNode(geometry: SCNPlane(width: 10, height: 10))
        floorNode.geometry?.firstMaterial?.diffuse.contents = UIColor.lightGray.withAlphaComponent(0.3)
        floorNode.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(floorNode)
        
        // Add grid
        let gridNode = createGridNode()
        scene.rootNode.addChildNode(gridNode)
    }
    
    private func createWallNode(_ wall: Wall) -> SCNNode {
        let wallGeometry = SCNBox(
            width: CGFloat(wall.dimensions.x),
            height: CGFloat(wall.dimensions.y),
            length: CGFloat(wall.dimensions.z),
            chamferRadius: 0
        )
        
        wallGeometry.firstMaterial?.diffuse.contents = UIColor.lightGray.withAlphaComponent(0.5)
        
        let wallNode = SCNNode(geometry: wallGeometry)
        wallNode.simdTransform = wall.transform
        
        return wallNode
    }
    
    private func createGridNode() -> SCNNode {
        let gridNode = SCNNode()
        
        // Create grid lines
        let lineCount = 21
        let spacing: Float = 0.5
        let halfSize: Float = Float(lineCount - 1) * spacing / 2
        
        for i in 0..<lineCount {
            let offset = Float(i) * spacing - halfSize
            
            // X-axis lines
            let xLine = SCNBox(width: CGFloat(halfSize * 2), height: 0.01, length: 0.01, chamferRadius: 0)
            xLine.firstMaterial?.diffuse.contents = UIColor.lightGray.withAlphaComponent(0.3)
            let xNode = SCNNode(geometry: xLine)
            xNode.position = SCNVector3(0, 0, offset)
            gridNode.addChildNode(xNode)
            
            // Z-axis lines
            let zLine = SCNBox(width: 0.01, height: 0.01, length: CGFloat(halfSize * 2), chamferRadius: 0)
            zLine.firstMaterial?.diffuse.contents = UIColor.lightGray.withAlphaComponent(0.3)
            let zNode = SCNNode(geometry: zLine)
            zNode.position = SCNVector3(offset, 0, 0)
            gridNode.addChildNode(zNode)
        }
        
        return gridNode
    }
    
    private func createDeviceNode() -> SCNNode {
        // Create device geometry based on type
        let geometry: SCNGeometry
        
        switch device.type {
        case .lifxBulb:
            geometry = SCNSphere(radius: 0.1)
        case .smartTV:
            geometry = SCNBox(width: 1.2, height: 0.7, length: 0.05, chamferRadius: 0.01)
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
        deviceNode.position = SCNVector3(position.x, position.y, position.z)
        
        // Add highlight
        let highlightGeometry = geometry.copy() as! SCNGeometry
        highlightGeometry.firstMaterial?.diffuse.contents = UIColor.white
        highlightGeometry.firstMaterial?.transparency = 0.3
        let highlightNode = SCNNode(geometry: highlightGeometry)
        highlightNode.scale = SCNVector3(1.1, 1.1, 1.1)
        deviceNode.addChildNode(highlightNode)
        
        return deviceNode
    }
    
    class Coordinator: NSObject {
        var parent: DevicePlacementSceneView
        var sceneView: SCNView?
        var deviceNode: SCNNode?
        
        init(_ parent: DevicePlacementSceneView) {
            self.parent = parent
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView = sceneView,
                  let deviceNode = deviceNode else { return }
            
            let translation = gesture.translation(in: sceneView)
            
            switch parent.placementMode {
            case .move:
                // Move in X-Z plane
                let deltaX = Float(translation.x) * 0.01
                let deltaZ = Float(translation.y) * 0.01
                parent.position.x += deltaX
                parent.position.z += deltaZ
                
            case .rotate:
                // Rotate around Y axis
                let deltaRotation = Float(translation.x) * 0.01
                parent.rotation += deltaRotation
                
            case .height:
                // Move in Y axis
                let deltaY = -Float(translation.y) * 0.01
                parent.position.y += deltaY
            }
            
            gesture.setTranslation(.zero, in: sceneView)
            updateDevicePosition(parent.position, rotation: parent.rotation)
        }
        
        func updateDevicePosition(_ position: SIMD3<Float>, rotation: Float) {
            deviceNode?.position = SCNVector3(position.x, position.y, position.z)
            deviceNode?.eulerAngles.y = rotation
        }
    }
}

// MARK: - Placement Mode Button
struct PlacementModeButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .white)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .blue : .white)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white : Color.black.opacity(0.6))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Placement Instructions View
struct PlacementInstructionsView: View {
    let onDismiss: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Device Placement")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Position your device in the 3D room view")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        InstructionStep(
                            number: 1,
                            title: "Tap to Position",
                            description: "Tap anywhere in the 3D view to place the device at that location."
                        )
                        
                        InstructionStep(
                            number: 2,
                            title: "Fine-tune with Controls",
                            description: "Use the arrow buttons to adjust the position precisely."
                        )
                        
                        InstructionStep(
                            number: 3,
                            title: "Confirm Placement",
                            description: "Tap 'Confirm Position' when you're happy with the placement."
                        )
                    }
                    
                    // Tips
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tips")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            TipRow(icon: "lightbulb", text: "Place devices where they actually are in your room")
                            TipRow(icon: "ruler", text: "Use the grid as a reference for positioning")
                            TipRow(icon: "arrow.clockwise", text: "Use 'Reset' to start over if needed")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Got it!") {
                    onDismiss()
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Extensions
extension SCNGeometry {
    static func line(from start: SCNVector3, to end: SCNVector3) -> SCNGeometry {
        let vertices: [SCNVector3] = [start, end]
        let data = Data(bytes: vertices, count: vertices.count * MemoryLayout<SCNVector3>.size)
        
        let source = SCNGeometrySource(data: data, semantic: .vertex, vectorCount: vertices.count, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<SCNVector3>.size)
        
        let element = SCNGeometryElement(data: nil, primitiveType: .line, primitiveCount: 1, bytesPerIndex: 0)
        
        return SCNGeometry(sources: [source], elements: [element])
    }
} 