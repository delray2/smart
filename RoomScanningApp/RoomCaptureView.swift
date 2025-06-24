import SwiftUI
import RoomPlan
import ARKit
import RealityKit
import SceneKit
import AVFoundation

// MARK: - Scan Status
enum ScanStatus {
    case ready
    case scanning
    case processing
    case completed
    case error
}

// MARK: - Wall Color Model
struct WallColor: Codable, Identifiable {
    let id = UUID()
    let name: String
    let color: UIColor
    
    enum CodingKeys: String, CodingKey {
        case name, color
    }
    
    init(name: String, color: UIColor) {
        self.name = name
        self.color = color
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        
        let hexString = try container.decode(String.self, forKey: .color)
        color = UIColor(hex: hexString) ?? .systemGray
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(color.toHex(), forKey: .color)
    }
}

// MARK: - UIColor Extensions
extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let rgb: Int = (Int)(r * 255) << 16 | (Int)(g * 255) << 8 | (Int)(b * 255) << 0
        
        return String(format: "#%06x", rgb)
    }
}

// MARK: - Room Capture Coordinator
class RoomCaptureCoordinator: NSObject, ObservableObject, RoomCaptureSessionDelegate {
    // MARK: - Published Properties
    @Published var scanStatus: ScanStatus = .ready
    @Published var instructionMessage: String = "Move slowly to scan the room"
    @Published var scanStatistics: String = ""
    @Published var showCoachingOverlay = true
    @Published var isExporting = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    var roomCaptureSession: RoomCaptureSession?
    var roomCaptureView: RoomPlan.RoomCaptureView?
    private var capturedRoom: CapturedRoom?
    private var scanStartTime: Date?
    private var colorArray: [WallColor] = []
    private var colorsURL: URL?
    
    private let minimumScanDuration: TimeInterval = 30.0 // 30 seconds minimum
    
    // MARK: - Computed Properties
    var hasActiveSession: Bool {
        roomCaptureSession != nil
    }
    
    var canDoMore: Bool {
        scanStatus == .scanning || scanStatus == .processing
    }
    
    var isScanning: Bool {
        scanStatus == .scanning
    }
    
    var isProcessing: Bool {
        scanStatus == .processing
    }
    
    // MARK: - Public Methods
    func startScanning() {
        scanStatus = .scanning
        scanStartTime = Date()
        errorMessage = nil
        instructionMessage = "Start scanning the room"
        
        // Start the room capture session
        roomCaptureSession?.run(configuration: RoomCaptureSession.Configuration())
    }
    
    func stopScanning() {
        scanStatus = .ready
        roomCaptureSession?.stop()
        instructionMessage = "Scanning stopped"
    }
    
    func saveScan(name: String) {
        guard let capturedRoom = capturedRoom else {
            errorMessage = "No room data to save"
            return
        }
        
        guard validateScanDuration() else {
            errorMessage = "Scan duration too short (minimum 30 seconds)"
            return
        }
        
        print("Saving scan: \(name)")
        
        let room = Room(
            name: name,
            type: .other,
            description: "Scanned room"
        )
        
        Task {
            do {
                let usdzPath = try await exportUSDZ(from: capturedRoom, roomName: name)
                
                await MainActor.run {
                    var scanData = RoomScanData(from: capturedRoom)
                    scanData.usdzFilePath = usdzPath
                    var updatedRoom = room
                    updatedRoom.scanData = scanData
                    updatedRoom.description = "Scanned room with \(scanData.walls.count) walls and \(scanData.objects.count) objects"
                    
                    RoomStorage.shared.addRoom(updatedRoom)
                    scanStatus = .completed
                    
                    print("Room saved successfully: \(updatedRoom.name) with scan data: \(updatedRoom.scanData != nil)")
                    print("USDZ file saved at: \(usdzPath)")
                }
            } catch {
                await MainActor.run {
                    print("Failed to export USDZ: \(error)")
                    let scanData = RoomScanData(from: capturedRoom)
                    var updatedRoom = room
                    updatedRoom.scanData = scanData
                    updatedRoom.description = "Scanned room with \(scanData.walls.count) walls and \(scanData.objects.count) objects"
                    
                    RoomStorage.shared.addRoom(updatedRoom)
                    scanStatus = .completed
                }
            }
        }
    }
    
    func exportResults() async {
        guard let capturedRoom = capturedRoom else {
            errorMessage = "No room data to export"
            return
        }
        
        guard validateScanDuration() else {
            errorMessage = "Scan duration too short"
            return
        }
        
        await MainActor.run {
            isExporting = true
        }
        
        do {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let exportDirectory = documentsDirectory.appendingPathComponent("RoomExports")
            
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: Date())
            let destinationFolderURL = exportDirectory.appendingPathComponent("Room_\(timestamp)")
            
            try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true, attributes: nil)
            
            // Export USDZ
            let usdzURL = destinationFolderURL.appendingPathComponent("Room.usdz")
            try capturedRoom.export(to: usdzURL)
            
            // Export JSON data
            let roomJsonURL = destinationFolderURL.appendingPathComponent("Room.json")
            let roomData = try JSONEncoder().encode(capturedRoom)
            try roomData.write(to: roomJsonURL)
            
            print("Room.json created at: \(roomJsonURL.path)")
            print("Room.usdz created at: \(usdzURL.path)")
            
            try await detectAndExportColors(finalResults: capturedRoom, destinationFolderURL: destinationFolderURL)
            
            await MainActor.run {
                isExporting = false
            }
        } catch {
            await MainActor.run {
                isExporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - RoomCaptureSessionDelegate Methods
    func session(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        DispatchQueue.main.async { [weak self] in
            self?.capturedRoom = room
            self?.scanStatus = .scanning
            self?.updateScanStatistics(room: room)
        }
    }
    
    func session(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        DispatchQueue.main.async { [weak self] in
            switch instruction {
            case .moveCloseToWall:
                self?.instructionMessage = "Move closer to the wall"
            case .moveAwayFromWall:
                self?.instructionMessage = "Move away from the wall"
            case .slowDown:
                self?.instructionMessage = "Slow down your movement"
            case .turnOnLight:
                self?.instructionMessage = "Turn on more lights"
            case .normal:
                self?.instructionMessage = "Continue scanning"
            case .lowTexture:
                self?.instructionMessage = "Point at more textured surfaces"
            @unknown default:
                self?.instructionMessage = "Continue scanning"
            }
        }
    }
    
    func session(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
        DispatchQueue.main.async { [weak self] in
            self?.scanStatus = .scanning
            self?.instructionMessage = "Start scanning the room"
        }
    }
    
    func session(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                self?.scanStatus = .error
                self?.instructionMessage = "Error: \(error.localizedDescription)"
            } else {
                self?.scanStatus = .processing
                self?.instructionMessage = "Processing scan data..."
                
                Task {
                    do {
                        let options = RoomBuilder.ConfigurationOptions()
                        let builder = RoomBuilder(options: options)
                        let capturedRoom = try await builder.capturedRoom(from: data)
                        await MainActor.run {
                            self?.capturedRoom = capturedRoom
                            self?.scanStatus = .completed
                            self?.instructionMessage = "Scan completed successfully"
                            self?.updateScanStatistics(room: capturedRoom)
                        }
                    } catch {
                        await MainActor.run {
                            self?.scanStatus = .error
                            self?.instructionMessage = "Processing failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    func session(_ session: RoomCaptureSession, didFailWith error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.scanStatus = .error
            self?.instructionMessage = "Scan failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    private func updateScanStatistics(room: CapturedRoom) {
        scanStatistics = "Walls: \(room.walls.count) • Objects: \(room.objects.count)"
    }
    
    private func validateScanDuration() -> Bool {
        guard let startTime = scanStartTime else { return false }
        return Date().timeIntervalSince(startTime) >= minimumScanDuration
    }
    
    private func exportUSDZ(from capturedRoom: CapturedRoom, roomName: String) async throws -> String {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportDirectory = documentsDirectory.appendingPathComponent("RoomScans")
        
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true, attributes: nil)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let safeRoomName = roomName.replacingOccurrences(of: " ", with: "_")
        let usdzFileName = "\(safeRoomName)_\(timestamp).usdz"
        let usdzURL = exportDirectory.appendingPathComponent(usdzFileName)
        
        try capturedRoom.export(to: usdzURL)
        
        print("USDZ exported to: \(usdzURL.path)")
        return usdzURL.path
    }
    
    private func detectAndExportColors(finalResults: CapturedRoom, destinationFolderURL: URL) async throws {
        // Simplified color detection for now
        for (index, _) in finalResults.walls.enumerated() {
            let wallColor = WallColor(name: "Wall\(index)", color: .systemGray)
            colorArray.append(wallColor)
        }
        
        // Save color data as JSON
        let colorData = try JSONEncoder().encode(colorArray)
        let colorFileURL = destinationFolderURL.appendingPathComponent("colors.json")
        try colorData.write(to: colorFileURL)
        colorsURL = colorFileURL
        print("Color data saved to: \(colorFileURL.path)")
    }
}

// MARK: - Room Capture View
struct RoomCaptureView: UIViewRepresentable {
    @ObservedObject var coordinator: RoomCaptureCoordinator
    
    func makeUIView(context: Context) -> RoomPlan.RoomCaptureView {
        let captureView = RoomPlan.RoomCaptureView(frame: .zero)
        
        // Set the coordinator as the capture session delegate
        captureView.captureSession.delegate = coordinator
        
        // Store references
        coordinator.roomCaptureSession = captureView.captureSession
        coordinator.roomCaptureView = captureView
        
        // Configure and start the session for camera preview
        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        
        // Start the session immediately to show camera feed
        captureView.captureSession.run(configuration: configuration)
        
        return captureView
    }
    
    func updateUIView(_ captureView: RoomPlan.RoomCaptureView, context: Context) {
        // Update view if needed
    }
    
    func makeCoordinator() -> RoomCaptureCoordinator {
        return coordinator
    }
}

// MARK: - Camera Permission Manager
class CameraPermissionManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    
    init() {
        checkAuthorizationStatus()
    }
    
    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                self?.authorizationStatus = granted ? .authorized : .denied
            }
        }
    }
    
    private func checkAuthorizationStatus() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        isAuthorized = authorizationStatus == .authorized
    }
}

// MARK: - Scan Quality Indicator
struct ScanQualityIndicator: View {
    let quality: Double
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                    .frame(width: 30, height: 30)
                
                Circle()
                    .trim(from: 0, to: quality)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(quality * 100))")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Scan Instructions Overlay
struct ScanInstructionsOverlay: View {
    let instructions: [String]
    
    var body: some View {
        VStack(spacing: 16) {
            ForEach(instructions, id: \.self) { instruction in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    
                    Text(instruction)
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }
        }
        .padding()
    }
} 