import Foundation
import RoomPlan
import simd
import os
import SceneKit
import SwiftUI

/// A structure that manages a catalog index. You can create your own model catalog or use the sample project's prepopulated catalog.
struct RoomPlanCatalog: Codable {
    
    /// The name of the catalog file on disk.
    static let catalogIndexFilename = "catalog.plist"
    
    /// A name for an empty file.
    static let emptyFilename = ".empty"
    
    /// An array of categories and attributes that the catalog supports.
    let categoryAttributes: [RoomPlanCatalogCategoryAttribute]
    
    /// Creates a catalog with the given app-supported attributes.
    init(categoryAttributes: [RoomPlanCatalogCategoryAttribute]) {
        self.categoryAttributes = categoryAttributes
    }
    
    /// Creates a catalog.
    init() {
        var categoryAttributes = [RoomPlanCatalogCategoryAttribute]()
        // Iterate through all categories that RoomPlan supports.
        for category in CapturedRoom.Object.Category.allCases {
            let _ = category.supportedAttributeTypes
            
            // Check whether this category has attributes.
            // This isn't mandatory, and you can comment if you want
            // to replace a category without attributes by a model.
          //  guard !attributeTypes.isEmpty else { continue }
            
            categoryAttributes.append(.init(category: category, attributes: []))
            for attributes in category.supportedCombinations {
                categoryAttributes.append(
                    RoomPlanCatalogCategoryAttribute(category: category, attributes: attributes))
            }
        }
        self.init(categoryAttributes: categoryAttributes)
    }
    
    /// Loads a catalog with the given URL.
    static func load(at url: URL) throws -> CapturedRoom.ModelProvider {
        let catalogPListURL = url.appending(path: RoomPlanCatalog.catalogIndexFilename)
        let data = try Data(contentsOf: catalogPListURL)
        let propertyListDecoder = PropertyListDecoder()
        let catalog = try propertyListDecoder.decode(RoomPlanCatalog.self, from: data)
        
        var modelProvider = CapturedRoom.ModelProvider()
        // Iterate through categories/attributes in the catalog.
        for categoryAttribute in catalog.categoryAttributes {
            guard let modelFilename = categoryAttribute.modelFilename else { continue }
            let folderRelativePath = categoryAttribute.folderRelativePath
            let modelURL = url.appending(path: folderRelativePath).appending(path: modelFilename)
            if categoryAttribute.attributes.isEmpty {
                do {
                    try modelProvider.setModelFileURL(modelURL, for: categoryAttribute.category)
                } catch {
                    Logger().warning("Can't add \(modelURL.lastPathComponent) to ModelProvider: \(error.localizedDescription)")
                }
            } else {
                do {
                    try modelProvider.setModelFileURL(modelURL, for: categoryAttribute.attributes)
                } catch {
                    Logger().warning("Can't add \(modelURL.lastPathComponent) to ModelProvider: \(error.localizedDescription)")
                }
            }
        }
        
        return modelProvider
    }
}

/// A structure that holds attributes that the app supports.
struct RoomPlanCatalogCategoryAttribute: Codable {
    enum CodingKeys: String, CodingKey {
        case folderRelativePath
        case category
        case attributes
        case modelFilename
    }
    
    /// A relative path of the folder that contains a 3D model.
    let folderRelativePath: String
    
    /// An object category for a 3D model.
    let category: CapturedRoom.Object.Category

    /// An array of object attributes.
    let attributes: [any CapturedRoomAttribute]
    
    /// A filename for the 3D model.
    private(set) var modelFilename: String? = nil
    
    /// The resources file path component.
    static let resourcesFolderName = "Resources"
    
    /// The default category file path component.
    private static let defaultCategoryAttributeFolderName = "Default"
    
    /// Creates a catalog attributes instance with the given object category and attributes array.
    init(category: CapturedRoom.Object.Category, attributes: [any CapturedRoomAttribute]) {
        self.category = category
        self.attributes = attributes
        self.folderRelativePath = Self.generateFolderRelativePath(category: category, attributes: attributes)
    }
    
    /// Creates a catalog attributes instance by deserializing the given decoder.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderRelativePath = try container.decode(String.self, forKey: .folderRelativePath)
        category = try container.decode(CapturedRoom.Object.Category.self, forKey: .category)
        let attributesCodableRepresentation = try container.decode(
            CapturedRoom.AttributesCodableRepresentation.self, forKey: .attributes)
        attributes = attributesCodableRepresentation.attributes
        modelFilename = try? container.decode(String.self, forKey: .modelFilename)
    }

    /// Serializes a catalog attributes instance to the given encoder.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.folderRelativePath, forKey: .folderRelativePath)
        try container.encode(self.category, forKey: .category)
        let attributesCodableRepresentation = CapturedRoom.AttributesCodableRepresentation(
            attributes: attributes)
        try container.encode(attributesCodableRepresentation, forKey: .attributes)
        try container.encode(self.modelFilename, forKey: .modelFilename)
    }
    
    /// Sets the 3D model filename.
    mutating func addModelFilename(_ modelFilename: String) {
        self.modelFilename = modelFilename
    }
    
    /// Returns a complete file path on disk for the given category and attributes array.
    private static func generateFolderRelativePath(category: CapturedRoom.Object.Category,
                                                   attributes: [any CapturedRoomAttribute]) -> String {
        let path = "\(resourcesFolderName)/\(String(describing: category).capitalized)"
        if attributes.isEmpty {
            return "\(path)/\(defaultCategoryAttributeFolderName)"
        }
        var attributesPaths = [String]()
        for attribute in attributes {
            attributesPaths.append(attribute.shortIdentifier)
        }
        var attributePath = attributesPaths.joined(separator: "_")
        attributePath = attributePath.prefix(1).capitalized + attributePath.dropFirst(1)
        return "\(path)/\(attributePath)"
    }
}

// MARK: - Furniture Catalog Manager
class FurnitureCatalogManager: ObservableObject {
    static let shared = FurnitureCatalogManager()
    
    @Published var furnitureCategories: [FurnitureCategory] = []
    @Published var selectedCategory: FurnitureCategory?
    @Published var selectedFurniture: FurnitureItem?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var furnitureItems: [FurnitureCategory: [FurnitureItem]] = [:]
    private let bundle = Bundle.main
    
    private init() {
        loadFurnitureCatalog()
    }
    
    // MARK: - Furniture Categories
    enum FurnitureCategory: String, CaseIterable, Identifiable, Codable {
        case chair = "Chair"
        case sofa = "Sofa"
        case table = "Table"
        case storage = "Storage"
        case bed = "Bed"
        case lighting = "Lighting"
        case decor = "Decor"
        
        var id: String { rawValue }
        
        var displayName: String {
            return rawValue
        }
        
        var icon: String {
            switch self {
            case .chair: return "chair"
            case .sofa: return "sofa"
            case .table: return "table"
            case .storage: return "cabinet"
            case .bed: return "bed.double"
            case .lighting: return "lightbulb"
            case .decor: return "photo"
            }
        }
        
        var color: Color {
            switch self {
            case .chair: return .blue
            case .sofa: return .green
            case .table: return .orange
            case .storage: return .purple
            case .bed: return .pink
            case .lighting: return .yellow
            case .decor: return .red
            }
        }
        
        var description: String {
            switch self {
            case .chair: return "Seating furniture for individual use"
            case .sofa: return "Comfortable seating for multiple people"
            case .table: return "Surfaces for dining, work, or display"
            case .storage: return "Cabinets, shelves, and storage solutions"
            case .bed: return "Sleeping furniture and bedroom items"
            case .lighting: return "Lamps, fixtures, and lighting elements"
            case .decor: return "Decorative items and accessories"
            }
        }
    }
    
    // MARK: - Furniture Item
    struct FurnitureItem: Identifiable, Codable {
        var id = UUID()
        let name: String
        let category: FurnitureCategory
        let modelPath: String
        let thumbnailPath: String?
        let dimensions: SIMD3<Float>
        let price: Double?
        let description: String
        let tags: [String]
        let isPremium: Bool
        
        var displayName: String {
            return name
        }
        
        var displayPrice: String {
            if let price = price {
                return String(format: "$%.2f", price)
            }
            return "Free"
        }
        
        var displayDimensions: String {
            return "\(String(format: "%.1f", dimensions.x))' × \(String(format: "%.1f", dimensions.y))' × \(String(format: "%.1f", dimensions.z))'"
        }
    }
    
    // MARK: - Catalog Loading
    private func loadFurnitureCatalog() {
        isLoading = true
        errorMessage = nil
        
        // Load furniture items for each category
        for category in FurnitureCategory.allCases {
            loadFurnitureForCategory(category)
        }
        
        furnitureCategories = FurnitureCategory.allCases
        isLoading = false
    }
    
    private func loadFurnitureForCategory(_ category: FurnitureCategory) {
        var items: [FurnitureItem] = []
        
        switch category {
        case .chair:
            items = loadChairItems()
        case .sofa:
            items = loadSofaItems()
        case .table:
            items = loadTableItems()
        case .storage:
            items = loadStorageItems()
        case .bed:
            items = loadBedItems()
        case .lighting:
            items = loadLightingItems()
        case .decor:
            items = loadDecorItems()
        }
        
        furnitureItems[category] = items
    }
    
    // MARK: - Category-Specific Loading
    private func loadChairItems() -> [FurnitureItem] {
        return [
            FurnitureItem(
                name: "Dining Chair",
                category: .chair,
                modelPath: "Chair/DiningChair_wBack_fourLegs_noArms/DiningChair_wBack_fourLegs_noArms.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(0.5, 0.9, 0.5),
                price: 0.0,
                description: "Classic dining chair with back support",
                tags: ["dining", "back", "four legs"],
                isPremium: false
            ),
            FurnitureItem(
                name: "Office Chair",
                category: .chair,
                modelPath: "Chair/Swivel_wBack_starLegs_wArms/Swivel_wBack_starLegs_wArms.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(0.6, 1.1, 0.6),
                price: 0.0,
                description: "Comfortable office chair with swivel base",
                tags: ["office", "swivel", "arms"],
                isPremium: false
            ),
            FurnitureItem(
                name: "Stool",
                category: .chair,
                modelPath: "Chair/Stool_noBack_fourLegs_noArms/Stool_noBack_fourLegs_noArms.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(0.4, 0.7, 0.4),
                price: 0.0,
                description: "Simple stool for casual seating",
                tags: ["stool", "no back", "simple"],
                isPremium: false
            )
        ]
    }
    
    private func loadSofaItems() -> [FurnitureItem] {
        return [
            FurnitureItem(
                name: "3-Seat Sofa",
                category: .sofa,
                modelPath: "Sofa/Rectangular/Rectangular.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(2.1, 0.8, 0.9),
                price: 0.0,
                description: "Comfortable 3-seat sofa for living room",
                tags: ["sofa", "3-seat", "rectangular"],
                isPremium: false
            ),
            FurnitureItem(
                name: "L-Shaped Sectional",
                category: .sofa,
                modelPath: "Sofa/LShaped/LShaped.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(2.4, 0.8, 1.8),
                price: 0.0,
                description: "Spacious L-shaped sectional sofa",
                tags: ["sectional", "L-shaped", "large"],
                isPremium: false
            ),
            FurnitureItem(
                name: "Single Seat",
                category: .sofa,
                modelPath: "Sofa/SingleSeat/SingleSeat.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(0.8, 0.8, 0.9),
                price: 0.0,
                description: "Single seat chair with sofa styling",
                tags: ["single", "chair", "sofa-style"],
                isPremium: false
            )
        ]
    }
    
    private func loadTableItems() -> [FurnitureItem] {
        return [
            FurnitureItem(
                name: "Dining Table",
                category: .table,
                modelPath: "Table/DiningTable_rectangular/DiningTable_rectangular.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(1.8, 0.8, 0.9),
                price: 0.0,
                description: "Rectangular dining table for meals",
                tags: ["dining", "rectangular", "meals"],
                isPremium: false
            ),
            FurnitureItem(
                name: "Coffee Table",
                category: .table,
                modelPath: "Table/CoffeeTable_rectangular/CoffeeTable_rectangular.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(1.2, 0.5, 0.6),
                price: 0.0,
                description: "Coffee table for living room",
                tags: ["coffee", "living room", "rectangular"],
                isPremium: false
            ),
            FurnitureItem(
                name: "Round Table",
                category: .table,
                modelPath: "Table/CoffeeTable_circularElliptic/CoffeeTable_circularElliptic.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(1.0, 0.5, 1.0),
                price: 0.0,
                description: "Round coffee table",
                tags: ["round", "coffee", "circular"],
                isPremium: false
            )
        ]
    }
    
    private func loadStorageItems() -> [FurnitureItem] {
        return [
            FurnitureItem(
                name: "Bookshelf",
                category: .storage,
                modelPath: "Storage/Shelf/shelf_vertical.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(0.8, 2.0, 0.4),
                price: 0.0,
                description: "Vertical bookshelf for storage",
                tags: ["bookshelf", "vertical", "storage"],
                isPremium: false
            ),
            FurnitureItem(
                name: "Cabinet",
                category: .storage,
                modelPath: "Storage/Cabinet/Default/DefaultCabinet.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(1.2, 1.8, 0.6),
                price: 0.0,
                description: "Storage cabinet with doors",
                tags: ["cabinet", "doors", "storage"],
                isPremium: false
            )
        ]
    }
    
    private func loadBedItems() -> [FurnitureItem] {
        return [
            FurnitureItem(
                name: "Queen Bed",
                category: .bed,
                modelPath: "Bed/Queen/QueenBed.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(1.6, 0.6, 2.0),
                price: 0.0,
                description: "Queen size bed frame",
                tags: ["bed", "queen", "sleep"],
                isPremium: false
            ),
            FurnitureItem(
                name: "Nightstand",
                category: .bed,
                modelPath: "Bed/Nightstand/Nightstand.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(0.5, 0.7, 0.4),
                price: 0.0,
                description: "Bedside table",
                tags: ["nightstand", "bedside", "table"],
                isPremium: false
            )
        ]
    }
    
    private func loadLightingItems() -> [FurnitureItem] {
        return [
            FurnitureItem(
                name: "Table Lamp",
                category: .lighting,
                modelPath: "Lighting/TableLamp/TableLamp.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(0.3, 0.6, 0.3),
                price: 0.0,
                description: "Table lamp for ambient lighting",
                tags: ["lamp", "table", "lighting"],
                isPremium: false
            ),
            FurnitureItem(
                name: "Floor Lamp",
                category: .lighting,
                modelPath: "Lighting/FloorLamp/FloorLamp.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(0.4, 1.8, 0.4),
                price: 0.0,
                description: "Floor lamp for room lighting",
                tags: ["lamp", "floor", "lighting"],
                isPremium: false
            )
        ]
    }
    
    private func loadDecorItems() -> [FurnitureItem] {
        return [
            FurnitureItem(
                name: "Plant Pot",
                category: .decor,
                modelPath: "Decor/PlantPot/PlantPot.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(0.4, 0.5, 0.4),
                price: 0.0,
                description: "Decorative plant pot",
                tags: ["plant", "pot", "decor"],
                isPremium: false
            ),
            FurnitureItem(
                name: "Picture Frame",
                category: .decor,
                modelPath: "Decor/PictureFrame/PictureFrame.rooms.usdc",
                thumbnailPath: nil,
                dimensions: SIMD3<Float>(0.6, 0.1, 0.8),
                price: 0.0,
                description: "Wall picture frame",
                tags: ["picture", "frame", "wall"],
                isPremium: false
            )
        ]
    }
    
    // MARK: - Public Methods
    func getFurnitureItems(for category: FurnitureCategory) -> [FurnitureItem] {
        return furnitureItems[category] ?? []
    }
    
    func searchFurniture(query: String) -> [FurnitureItem] {
        let allItems = furnitureItems.values.flatMap { $0 }
        
        if query.isEmpty {
            return allItems
        }
        
        return allItems.filter { item in
            item.name.localizedCaseInsensitiveContains(query) ||
            item.description.localizedCaseInsensitiveContains(query) ||
            item.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
    
    func loadUSDZModel(for item: FurnitureItem) -> SCNNode? {
        guard let url = bundle.url(forResource: item.modelPath, withExtension: nil) else {
            print("Could not find model at path: \(item.modelPath)")
            return nil
        }
        
        do {
            let scene = try SCNScene(url: url, options: nil)
            return scene.rootNode
        } catch {
            print("Error loading USDZ model: \(error)")
            return nil
        }
    }
    
    func getFurniturePreview(for item: FurnitureItem) -> some View {
        // Create a preview of the furniture item
        return FurniturePreviewView(item: item)
    }
    
    func replaceFurniture(_ oldFurniture: FurnitureObject, with newItem: FurnitureItem, in room: Room) -> Room {
        var updatedRoom = room
        
        // Find and replace the furniture object
        if let index = updatedRoom.scanData?.objects.firstIndex(where: { $0.id == oldFurniture.id }) {
            var newFurniture = oldFurniture
            // Map FurnitureCatalogManager.FurnitureCategory to FurnitureCat
            newFurniture.category = mapFurnitureCategory(from: newItem.category)
            newFurniture.modelPath = newItem.modelPath
            newFurniture.name = newItem.name
            
            updatedRoom.scanData?.objects[index] = newFurniture
        }
        
        return updatedRoom
    }
    
    private func mapFurnitureCategory(from catalogCategory: FurnitureCatalogManager.FurnitureCategory) -> FurnitureCat {
        switch catalogCategory {
        case .chair:
            return .chair
        case .sofa:
            return .sofa
        case .table:
            return .table
        case .storage:
            return .cabinet
        case .bed:
            return .bed
        case .lighting, .decor:
            return .other
        }
    }
    
    func getRecommendedFurniture(for room: Room) -> [FurnitureItem] {
        var recommendations: [FurnitureItem] = []
        
        // Analyze room and recommend furniture based on:
        // - Room type (bedroom, living room, etc.)
        // - Available space
        // - Existing furniture
        // - Room dimensions
        
        if room.name.localizedCaseInsensitiveContains("bedroom") {
            recommendations.append(contentsOf: getFurnitureItems(for: .bed))
        }
        
        if room.name.localizedCaseInsensitiveContains("living") {
            recommendations.append(contentsOf: getFurnitureItems(for: .sofa))
            recommendations.append(contentsOf: getFurnitureItems(for: .table))
        }
        
        if room.name.localizedCaseInsensitiveContains("dining") {
            recommendations.append(contentsOf: getFurnitureItems(for: .table))
            recommendations.append(contentsOf: getFurnitureItems(for: .chair))
        }
        
        return recommendations
    }
}

// MARK: - Furniture Preview View
struct FurniturePreviewView: View {
    let item: FurnitureCatalogManager.FurnitureItem
    @State private var sceneNode: SCNNode?
    
    var body: some View {
        ZStack {
            if let node = sceneNode {
                SceneView(scene: createScene(with: node), options: [.allowsCameraControl, .autoenablesDefaultLighting])
                    .frame(height: 200)
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(height: 200)
                    .overlay(
                        VStack {
                            Image(systemName: item.category.icon)
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            
                            Text("Loading...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .onAppear {
            loadModel()
        }
    }
    
    private func loadModel() {
        sceneNode = FurnitureCatalogManager.shared.loadUSDZModel(for: item)
    }
    
    private func createScene(with node: SCNNode) -> SCNScene {
        let scene = SCNScene()
        scene.rootNode.addChildNode(node)
        
        // Add lighting
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        scene.rootNode.addChildNode(lightNode)
        
        // Add ambient light
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        return scene
    }
}

// MARK: - Furniture Catalog View
struct FurnitureCatalogView: View {
    @ObservedObject var catalog = FurnitureCatalogManager.shared
    @State private var searchText = ""
    @State private var selectedCategory: FurnitureCatalogManager.FurnitureCategory?
    
    var filteredItems: [FurnitureCatalogManager.FurnitureItem] {
        if let category = selectedCategory {
            return catalog.getFurnitureItems(for: category)
        } else {
            return catalog.searchFurniture(query: searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            // Category filter
            categoryFilter
            
            // Furniture grid
            furnitureGrid
        }
        .navigationTitle("Furniture Catalog")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search furniture...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
    }
    
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FurnitureCatalogManager.FurnitureCategory.allCases) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category,
                        action: {
                            if selectedCategory == category {
                                selectedCategory = nil
                            } else {
                                selectedCategory = category
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var furnitureGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                ForEach(filteredItems) { item in
                    FurnitureItemCard(item: item)
                }
            }
            .padding()
        }
    }
}

// MARK: - Category Button
struct CategoryButton: View {
    let category: FurnitureCatalogManager.FurnitureCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .white : category.color)
                
                Text(category.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? category.color : Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Furniture Item Card
struct FurnitureItemCard: View {
    let item: FurnitureCatalogManager.FurnitureItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Preview
            FurniturePreviewView(item: item)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Text(item.displayDimensions)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(item.displayPrice)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(item.isPremium ? .orange : .green)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
