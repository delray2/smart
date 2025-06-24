import SwiftUI
import RoomPlan

// MARK: - Room Capture Screen
struct RoomCaptureScreen: View {
    @StateObject private var captureCoordinator = RoomScanCoordinator()
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var roomStorage: RoomStorage
    
    @State private var showingInstructions = true
    @State private var showingScanComplete = false
    @State private var scanName = ""
    @State private var showingNamePrompt = false
    
    var body: some View {
        ZStack {
            // Camera view
            RoomCaptureView(coordinator: captureCoordinator)
                .environmentObject(roomStorage)
                .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top controls
                topControlsView
                
                Spacer()
                
                // Bottom controls
                bottomControlsView
            }
            .padding()
        }
        .navigationBarHidden(true)
        .onAppear {
            startCapture()
        }
        .onDisappear {
            stopCapture()
        }
        .sheet(isPresented: $showingInstructions) {
            CaptureInstructionsView {
                showingInstructions = false
            }
        }
        .sheet(isPresented: $showingNamePrompt) {
            ScanNamePromptView(scanName: $scanName) {
                saveScan()
            }
        }
        .alert("Scan Complete", isPresented: $showingScanComplete) {
            Button("OK") {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("Your room scan has been saved successfully!")
        }
    }
    
    // MARK: - Top Controls View
    private var topControlsView: some View {
        VStack(spacing: 12) {
            // Status bar
            HStack {
                // Back button
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                // Scan status
                VStack(spacing: 4) {
                    Text(captureCoordinator.scanStatus.displayTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(captureCoordinator.scanStatus.displayMessage)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                // Help button
                Button(action: {
                    showingInstructions = true
                }) {
                    Image(systemName: "questionmark")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.7))
                    .background(.ultraThinMaterial)
            )
            .cornerRadius(12)
            
            // Progress indicator
            if captureCoordinator.scanStatus.isScanning {
                progressIndicatorView
            }
        }
    }
    
    // MARK: - Progress Indicator View
    private var progressIndicatorView: some View {
        VStack(spacing: 8) {
            // Instruction message
            Text(captureCoordinator.instructionMessage)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Scan statistics
            if !captureCoordinator.scanStatistics.isEmpty {
                Text(captureCoordinator.scanStatistics)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
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
            // Done button (always visible)
            if captureCoordinator.scanStatus == .scanning || captureCoordinator.scanStatus == .completed {
                Button(action: {
                    if captureCoordinator.scanStatus == .scanning {
                        // Stop scanning first
                        stopScan()
                    }
                    // Show name prompt to save
                    showingNamePrompt = true
                }) {
                    Text("Done")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Scan controls
            HStack(spacing: 20) {
                // Start/Stop button
                if captureCoordinator.scanStatus != .completed {
                    Button(action: {
                        if captureCoordinator.scanStatus.isScanning {
                            stopScan()
                        } else {
                            startScan()
                        }
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: captureCoordinator.scanStatus.isScanning ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(captureCoordinator.scanStatus.isScanning ? .orange : .green)
                            
                            Text(captureCoordinator.scanStatus.isScanning ? "Pause Scan" : "Start Scan")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Instructions
            if captureCoordinator.scanStatus == .ready {
                instructionCardView
            }
        }
    }
    
    // MARK: - Instruction Card View
    private var instructionCardView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(.yellow)
                
                Text("Scanning Tips")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                TipRow(icon: "move.3d", text: "Move slowly around the room")
                TipRow(icon: "eye", text: "Keep the camera pointed at walls and furniture")
                TipRow(icon: "light.max", text: "Ensure good lighting for best results")
                TipRow(icon: "hand.raised", text: "Hold device steady while scanning")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.7))
                .background(.ultraThinMaterial)
        )
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    private func startCapture() {
        captureCoordinator.startCapture()
    }
    
    private func stopCapture() {
        captureCoordinator.stopCapture()
    }
    
    private func startScan() {
        captureCoordinator.startScan()
    }
    
    private func stopScan() {
        captureCoordinator.stopScan()
    }
    
    private func saveScan() {
        guard !scanName.isEmpty else { return }
        
        // Save the scan with the provided name
        captureCoordinator.saveScan(name: scanName)
        
        // Dismiss the name prompt and show completion
        showingNamePrompt = false
        showingScanComplete = true
    }
}

// MARK: - Capture Instructions View
struct CaptureInstructionsView: View {
    let onDismiss: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Room Scanning Guide")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Follow these steps to capture your room accurately")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        InstructionStep(
                            number: 1,
                            title: "Prepare Your Room",
                            description: "Clear any obstacles and ensure good lighting. Close doors and windows to get a complete scan."
                        )
                        
                        InstructionStep(
                            number: 2,
                            title: "Start Scanning",
                            description: "Tap 'Start Scan' and slowly walk around the room, keeping the camera pointed at walls and furniture."
                        )
                        
                        InstructionStep(
                            number: 3,
                            title: "Move Methodically",
                            description: "Move in a systematic pattern, scanning each wall and corner. Take your time for better accuracy."
                        )
                        
                        InstructionStep(
                            number: 4,
                            title: "Complete the Scan",
                            description: "Once you've covered the entire room, tap 'Stop Scan' and save your results."
                        )
                    }
                    
                    // Tips section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pro Tips")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            TipRow(icon: "move.3d", text: "Move at a steady pace - not too fast or slow")
                            TipRow(icon: "eye", text: "Keep the device at chest height for best results")
                            TipRow(icon: "light.max", text: "Avoid direct sunlight and harsh shadows")
                            TipRow(icon: "hand.raised", text: "Hold the device with both hands for stability")
                            TipRow(icon: "arrow.clockwise", text: "You can always restart if you're not satisfied")
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

// MARK: - Scan Name Prompt View
struct ScanNamePromptView: View {
    @Binding var scanName: String
    let onSave: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Save Your Scan")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Give your room scan a name to save it")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Room name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Room Name")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    TextField("e.g., Living Room, Bedroom", text: $scanName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.words)
                }
                
                // Suggestions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggestions")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                        ForEach(["Living Room", "Bedroom", "Kitchen", "Bathroom", "Office", "Dining Room"], id: \.self) { suggestion in
                            Button(action: {
                                scanName = suggestion
                            }) {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button("Save Scan") {
                        onSave()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(scanName.isEmpty)
                    
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding()
            .navigationTitle("Save Scan")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Instruction Step
struct InstructionStep: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Tip Row
struct TipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 16)
            
            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Scan Status Display Helpers
extension ScanStatus {
    var displayTitle: String {
        switch self {
        case .ready: return "Ready"
        case .scanning: return "Scanning"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .error: return "Error"
        }
    }
    var displayMessage: String {
        switch self {
        case .ready: return "Ready to scan."
        case .scanning: return "Scanning in progress..."
        case .processing: return "Processing scan data..."
        case .completed: return "Scan complete."
        case .error: return "An error occurred."
        }
    }
    var isScanning: Bool {
        self == .scanning
    }
} 