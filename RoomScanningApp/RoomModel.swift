import Foundation
import RoomPlan
import SceneKit
import simd
import SwiftUI

// MARK: - Room Model
struct Room: Identifiable, Codable {
    var id = UUID()
    var name: String
    var type: RoomType
    var description: String?
    var scanData: RoomScanData?
    var devices: [SmartDevice]
    var createdAt: Date
    var updatedAt: Date
    
    init(name: String, type: RoomType = .other, description: String? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.devices = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Room Storage
class RoomStorage: ObservableObject {
    static let shared = RoomStorage()
    
    @Published var rooms: [Room] = []
    private let userDefaults = UserDefaults.standard
    private let roomsKey = "saved_rooms"
    
    init() {
        loadRooms()
    }
    
    func saveRoom(_ room: Room) {
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[index] = room
        } else {
            rooms.append(room)
        }
        persistRooms()
    }
    
    func addRoom(_ room: Room) {
        rooms.append(room)
        persistRooms()
    }
    
    func deleteRoom(_ room: Room) {
        rooms.removeAll { $0.id == room.id }
        persistRooms()
    }
    
    func updateRoom(_ room: Room) {
        saveRoom(room)
    }
    
    private func loadRooms() {
        if let data = userDefaults.data(forKey: roomsKey),
           let decodedRooms = try? JSONDecoder().decode([Room].self, from: data) {
            rooms = decodedRooms
        }
    }
    
    private func persistRooms() {
        if let encoded = try? JSONEncoder().encode(rooms) {
            userDefaults.set(encoded, forKey: roomsKey)
        }
    }
}

// MARK: - Room Scan Data
struct RoomScanData: Codable {
    var walls: [Wall]
    var openings: [Opening]
    var objects: [FurnitureObject]
    let dimensions: RoomDimensions
    var usdzFilePath: String?
    
    init(from capturedRoom: CapturedRoom) {
        self.walls = capturedRoom.walls.map { Wall(from: $0) }
        self.openings = capturedRoom.openings.map { Opening(from: $0) }
        self.objects = capturedRoom.objects.map { FurnitureObject(from: $0) }
        self.dimensions = RoomDimensions(from: capturedRoom)
        self.usdzFilePath = nil
    }
}

// MARK: - Wall
struct Wall: Codable {
    let position: SIMD3<Float>
    let dimensions: SIMD3<Float>
    let category: WallCategory
    let transform: simd_float4x4

    init(from surface: CapturedRoom.Surface) {
        self.position = surface.transform.columns.3.xyz
        self.dimensions = surface.dimensions
        self.transform = surface.transform
        self.category = WallCategory(from: surface.category)
    }
}

enum WallCategory: String, Codable, CaseIterable {
    case interior = "interior"
    case exterior = "exterior"
    case door = "door"
    case window = "window"

    init(from surfaceCategory: CapturedRoom.Surface.Category) {
        switch surfaceCategory {
        case .door:
            self = .door
        case .opening: // Openings can be treated as a type of wall for this model
            self = .interior
        case .wall:
            self = .interior
        case .window:
            self = .window
        case .floor:
            self = .interior
        @unknown default:
            self = .interior
        }
    }
}

// MARK: - Opening
struct Opening: Codable {
    let position: SIMD3<Float>
    let dimensions: SIMD3<Float>
    let category: OpeningCategory
    let transform: simd_float4x4
    
    init(from surface: CapturedRoom.Surface) {
        self.position = surface.transform.columns.3.xyz
        self.dimensions = surface.dimensions
        self.transform = surface.transform
        self.category = OpeningCategory(from: surface.category)
    }
}

enum OpeningCategory: String, Codable, CaseIterable {
    case door = "door"
    case window = "window"
    case arch = "arch"
    
    init(from surfaceCategory: CapturedRoom.Surface.Category) {
        switch surfaceCategory {
        case .door:
            self = .door
        case .opening:
            self = .arch
        case .window:
            self = .window
        case .wall:
            self = .arch // Treat walls as arches if they end up here
        case .floor:
            self = .arch
        @unknown default:
            self = .arch
        }
    }
}

// MARK: - Furniture Object
struct FurnitureObject: Codable {
    let id = UUID()
    let position: SIMD3<Float>
    let dimensions: SIMD3<Float>
    var category: FurnitureCat
    let transform: simd_float4x4
    var modelPath: String?
    var name: String?
    
    init(from object: CapturedRoom.Object) {
        self.position = object.transform.columns.3.xyz
        self.dimensions = object.dimensions
        self.transform = object.transform
        self.category = FurnitureCat(from: object.category)
        self.modelPath = nil
        self.name = nil
    }
}

enum FurnitureCat: String, Codable, CaseIterable {
    case table = "table"
    case chair = "chair"
    case bed = "bed"
    case sofa = "sofa"
    case cabinet = "cabinet"
    case shelf = "shelf"
    case other = "other"

    var color: Color {
        switch self {
        case .table: return .orange
        case .chair: return .blue
        case .bed: return .pink
        case .sofa: return .green
        case .cabinet: return .purple
        case .shelf: return .gray
        case .other: return .secondary
        }
    }

    init(from objectCategory: CapturedRoom.Object.Category) {
        switch objectCategory {
        case .storage, .refrigerator, .stove, .dishwasher, .sink:
            self = .cabinet
        case .bed:
            self = .bed
        case .chair:
            self = .chair
        case .sofa:
            self = .sofa
        case .table:
            self = .table
        case .washerDryer, .toilet, .bathtub, .oven, .fireplace, .television, .stairs:
            self = .other
        @unknown default:
            self = .other
        }
    }
}

// MARK: - Room Type
enum RoomType: String, CaseIterable, Codable {
    case livingRoom = "living_room"
    case bedroom = "bedroom"
    case kitchen = "kitchen"
    case bathroom = "bathroom"
    case diningRoom = "dining_room"
    case office = "office"
    case garage = "garage"
    case basement = "basement"
    case attic = "attic"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .livingRoom: return "Living Room"
        case .bedroom: return "Bedroom"
        case .kitchen: return "Kitchen"
        case .bathroom: return "Bathroom"
        case .diningRoom: return "Dining Room"
        case .office: return "Office"
        case .garage: return "Garage"
        case .basement: return "Basement"
        case .attic: return "Attic"
        case .other: return "Other"
        }
    }
    
    var description: String {
        switch self {
        case .livingRoom: return "Main living area for relaxation and entertainment"
        case .bedroom: return "Sleeping quarters and personal space"
        case .kitchen: return "Food preparation and cooking area"
        case .bathroom: return "Personal hygiene and bathing facilities"
        case .diningRoom: return "Dedicated space for meals and dining"
        case .office: return "Work space and productivity area"
        case .garage: return "Vehicle storage and workshop space"
        case .basement: return "Lower level storage and utility space"
        case .attic: return "Upper level storage and potential living space"
        case .other: return "Custom or specialized room type"
        }
    }
}

// MARK: - Room Dimensions
struct RoomDimensions: Codable {
    let width: Float
    let length: Float
    let height: Float
    let area: Float
    
    init(from capturedRoom: CapturedRoom) {
        // Calculate room dimensions from walls
        let xCoords = capturedRoom.walls.flatMap { [$0.transform.columns.3.x - $0.dimensions.x / 2, $0.transform.columns.3.x + $0.dimensions.x / 2] }
        let zCoords = capturedRoom.walls.flatMap { [$0.transform.columns.3.z - $0.dimensions.z / 2, $0.transform.columns.3.z + $0.dimensions.z / 2] }
        let yCoords = capturedRoom.walls.map { $0.dimensions.y }
        
        self.width = (xCoords.max() ?? 0) - (xCoords.min() ?? 0)
        self.length = (zCoords.max() ?? 0) - (zCoords.min() ?? 0)
        self.height = yCoords.max() ?? 0
        self.area = width * length
    }
}

extension SIMD4 {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x as! Float, y as! Float, z as! Float)
    }
}

// MARK: - simd_float4x4 Extension for Codable
extension simd_float4x4: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let columns = try container.decode([SIMD4<Float>].self, forKey: .columns)
        self.init(columns[0], columns[1], columns[2], columns[3])
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([columns.0, columns.1, columns.2, columns.3], forKey: .columns)
    }
    
    private enum CodingKeys: String, CodingKey {
        case columns
    }
}

// MARK: - Simple Room Model for Scanning
struct RoomModel: Identifiable, Codable {
    var id = UUID()
    let name: String
    let usdzPath: String
    let createdAt: Date
    let wallCount: Int
    let objectCount: Int
    
    init(name: String, usdzPath: String, createdAt: Date, wallCount: Int, objectCount: Int) {
        self.name = name
        self.usdzPath = usdzPath
        self.createdAt = createdAt
        self.wallCount = wallCount
        self.objectCount = objectCount
    }
}

// MARK: - 3D Room Viewer
struct Room3DViewer: View {
    let roomModel: RoomModel
    @Environment(\.presentationMode) var presentationMode
    @State private var sceneView: SCNView?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            // SceneKit View
            SceneKitViewRepresentable(sceneView: $sceneView, usdzPath: roomModel.usdzPath)
                .ignoresSafeArea()
            
            // Loading overlay
            if isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    
                    Text("Loading 3D Room...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
            }
            
            // Error overlay
            if let errorMessage = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    
                    Text("Error Loading Room")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
            }
            
            // Top bar
            VStack {
                HStack {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    Text(roomModel.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    Button("Reset View") {
                        resetCamera()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                }
                .padding()
                
                Spacer()
            }
        }
        .onAppear {
            loadUSDZScene()
        }
    }
    
    private func loadUSDZScene() {
        let fileURL = URL(fileURLWithPath: roomModel.usdzPath)
        
        guard FileManager.default.fileExists(atPath: roomModel.usdzPath) else {
            errorMessage = "USDZ file not found"
            return
        }
        
        do {
            let scene = try SCNScene(url: fileURL, options: nil)
            
            // Configure the scene
            scene.background.contents = UIColor.systemBackground
            
            // Set up lighting
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
            
            // Set the scene on the view
            sceneView?.scene = scene
            
            // Set up camera
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(x: 0, y: 5, z: 10)
            cameraNode.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(cameraNode)
            
            // Configure camera controls
            sceneView?.allowsCameraControl = true
            sceneView?.autoenablesDefaultLighting = true
            sceneView?.backgroundColor = UIColor.systemBackground
            
            isLoading = false
            
        } catch {
            print("Failed to load USDZ scene: \(error)")
            errorMessage = "Failed to load 3D room: \(error.localizedDescription)"
        }
    }
    
    private func resetCamera() {
        guard let sceneView = sceneView else { return }
        
        // Reset camera to default position
        let cameraNode = sceneView.scene?.rootNode.childNode(withName: "camera", recursively: true)
        cameraNode?.position = SCNVector3(x: 0, y: 5, z: 10)
        cameraNode?.look(at: SCNVector3(0, 0, 0))
    }
}

// MARK: - SceneKit View Representable
struct SceneKitViewRepresentable: UIViewRepresentable {
    @Binding var sceneView: SCNView?
    let usdzPath: String
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = UIColor.systemBackground
        view.antialiasingMode = .multisampling4X
        
        // Enable physics debugging (optional)
        view.showsStatistics = false
        
        return view
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update the binding
        sceneView = uiView
    }
} 
