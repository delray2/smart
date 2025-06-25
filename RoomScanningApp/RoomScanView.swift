import SwiftUI
import RoomPlan
import ARKit
import RealityKit
import SceneKit
import Metal

// MARK: - Room Scan View
struct RoomScanView: View {
    @StateObject private var scanCoordinator = RoomScanViewCoordinator()
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var roomStorage: RoomStorage
    
    @State private var showingInstructions = true
    @State private var showingScanComplete = false
    @State private var scanName = ""
    @State private var showingNamePrompt = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            // Camera view
            RoomCaptureView(coordinator: scanCoordinator)
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
        .onAppear {
            startScanning()
        }
        .onDisappear {
            stopScanning()
        }
        .sheet(isPresented: $showingInstructions) {
            ScanInstructionsView {
                showingInstructions = false
            }
        }
        .sheet(isPresented: $showingNamePrompt) {
            ScanNamePromptView(scanName: $scanName) {
                saveScan()
            }
        }
        .alert("Scan Complete", isPresented: $showingScanComplete) {
            Button("View Room") {
                // Navigate to room detail
                presentationMode.wrappedValue.dismiss()
            }
            Button("Scan Another") {
                resetScan()
            }
        } message: {
            Text("Your room scan has been saved successfully! You can now add devices and customize your room.")
        }
        .alert("Scan Error", isPresented: $showingError) {
            Button("Try Again") {
                resetScan()
            }
            Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Top Controls View
    private var topControlsView: some View {
        VStack(spacing: 12) {
            // Status bar
            HStack {
                // Back button
                Button(action: {
                    if scanCoordinator.scanStatus.isScanning {
                        showingError = true
                        errorMessage = "Are you sure you want to cancel? Your scan progress will be lost."
                    } else {
                        presentationMode.wrappedValue.dismiss()
                    }
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
                    Text(scanCoordinator.scanStatus.displayTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(scanCoordinator.scanStatus.displayMessage)
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
            
            // Scan instructions
            if scanCoordinator.scanStatus.isScanning {
                scanInstructionsView
            }
        }
    }
    
    // MARK: - Scan Instructions View
    private var scanInstructionsView: some View {
        VStack(spacing: 8) {
            Text(scanCoordinator.instructionMessage)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if !scanCoordinator.scanStatistics.isEmpty {
                Text(scanCoordinator.scanStatistics)
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
            // Scan controls
            HStack(spacing: 20) {
                // Start/Stop button
                Button(action: {
                    if scanCoordinator.scanStatus.isScanning {
                        stopScan()
                    } else {
                        startScan()
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: scanCoordinator.scanStatus.isScanning ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(scanCoordinator.scanStatus.isScanning ? .red : .green)
                        
                        Text(scanCoordinator.scanStatus.isScanning ? "Stop Scan" : "Start Scan")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Save button (only when scan is complete)
                if scanCoordinator.scanStatus == .completed {
                    Button(action: {
                        showingNamePrompt = true
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                            
                            Text("Save Scan")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
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
    
    // MARK: - Helper Methods
    private func startScanning() {
        scanCoordinator.startScanning()
    }
    
    private func stopScanning() {
        scanCoordinator.stopScanning()
    }
    
    private func startScan() {
        scanCoordinator.startScanning()
    }

    private func stopScan() {
        scanCoordinator.stopScanning()
    }
    
    private func resetScan() {
        scanCoordinator.resetScan()
    }
    
    private func saveScan() {
        scanCoordinator.saveScan(name: scanName)
        showingScanComplete = true
    }
}

// MARK: - Quality Indicator
struct QualityIndicator: View {
    let title: String
    let value: Double
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
                    .trim(from: 0, to: value)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: value)
                
                Text("\(Int(value * 100))")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Room Scan Coordinator
class RoomScanViewCoordinator: RoomCaptureCoordinator {
    func resetScan() {
        stopScanning()
        scanStatus = .ready
    }
}

// MARK: - Scan Instructions View
struct ScanInstructionsView: View {
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
                        
                        Text("Room Scanning")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Follow these steps to scan your room accurately")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        InstructionStep(
                            number: 1,
                            title: "Clear the Room",
                            description: "Remove any obstacles and ensure good lighting."
                        )
                        
                        InstructionStep(
                            number: 2,
                            title: "Start Scanning",
                            description: "Tap 'Start Scan' and slowly move your device around the room."
                        )
                        
                        InstructionStep(
                            number: 3,
                            title: "Follow the Guide",
                            description: "Keep the camera steady and follow the on-screen guidance."
                        )
                        
                        InstructionStep(
                            number: 4,
                            title: "Complete the Scan",
                            description: "Continue until the scan is 100% complete."
                        )
                    }
                    
                    // Tips
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tips")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            TipRow(icon: "lightbulb", text: "Ensure good lighting for better results")
                            TipRow(icon: "ruler", text: "Move slowly and steadily")
                            TipRow(icon: "arrow.clockwise", text: "You can restart if needed")
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