import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var deviceController: DeviceController
    @State private var showingResetAlert = false
    @State private var showingExportData = false
    @State private var showingAbout = false
    
    var body: some View {
        NavigationView {
            List {
                // Account Section
                accountSection
                
                // Smart Home Section
                smartHomeSection
                
                // App Settings Section
                appSettingsSection
                
                // Data & Privacy Section
                dataPrivacySection
                
                // Support Section
                supportSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .alert("Reset All Data", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetAllData()
                }
            } message: {
                Text("This will delete all your room scans and device configurations. This action cannot be undone.")
            }
            .sheet(isPresented: $showingExportData) {
                ExportDataView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }
    
    // MARK: - Account Section
    private var accountSection: some View {
        Section {
            NavigationLink(destination: AccountSettingsView()) {
                SettingsRow(
                    icon: "person.circle",
                    title: "Account",
                    subtitle: "Manage your profile and preferences",
                    color: .blue
                )
            }
            
            NavigationLink(destination: SubscriptionView()) {
                SettingsRow(
                    icon: "star.circle",
                    title: "Premium",
                    subtitle: "Upgrade to unlock advanced features",
                    color: .yellow
                )
            }
        } header: {
            Text("Account")
        }
    }
    
    // MARK: - Smart Home Section
    private var smartHomeSection: some View {
        Section {
            NavigationLink(destination: PlatformSettingsView(deviceController: deviceController)) {
                SettingsRow(
                    icon: "house.circle",
                    title: "Smart Home Platforms",
                    subtitle: "\(deviceController.connectedPlatforms.count) platforms connected",
                    color: .green
                )
            }
            
            NavigationLink(destination: DeviceManagementView(deviceController: deviceController)) {
                SettingsRow(
                    icon: "lightbulb.circle",
                    title: "Device Management",
                    subtitle: "\(deviceController.allDevices.count) devices configured",
                    color: .orange
                )
            }
            
            NavigationLink(destination: AutomationSettingsView()) {
                SettingsRow(
                    icon: "clock.circle",
                    title: "Automations",
                    subtitle: "Set up smart home routines",
                    color: .purple
                )
            }
        } header: {
            Text("Smart Home")
        }
    }
    
    // MARK: - App Settings Section
    private var appSettingsSection: some View {
        Section {
            NavigationLink(destination: ScanSettingsView()) {
                SettingsRow(
                    icon: "camera.circle",
                    title: "Scan Settings",
                    subtitle: "Configure room scanning preferences",
                    color: .blue
                )
            }
            
            NavigationLink(destination: DisplaySettingsView()) {
                SettingsRow(
                    icon: "display",
                    title: "Display",
                    subtitle: "Customize app appearance",
                    color: .indigo
                )
            }
            
            NavigationLink(destination: NotificationSettingsView()) {
                SettingsRow(
                    icon: "bell.circle",
                    title: "Notifications",
                    subtitle: "Manage app notifications",
                    color: .red
                )
            }
        } header: {
            Text("App Settings")
        }
    }
    
    // MARK: - Data & Privacy Section
    private var dataPrivacySection: some View {
        Section {
            Button(action: {
                showingExportData = true
            }) {
                SettingsRow(
                    icon: "square.and.arrow.up",
                    title: "Export Data",
                    subtitle: "Download your room scans and settings",
                    color: .green
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            NavigationLink(destination: PrivacySettingsView()) {
                SettingsRow(
                    icon: "lock.circle",
                    title: "Privacy & Security",
                    subtitle: "Manage data and privacy settings",
                    color: .gray
                )
            }
            
            Button(action: {
                showingResetAlert = true
            }) {
                SettingsRow(
                    icon: "trash.circle",
                    title: "Reset All Data",
                    subtitle: "Delete all scans and configurations",
                    color: .red
                )
            }
            .buttonStyle(PlainButtonStyle())
        } header: {
            Text("Data & Privacy")
        }
    }
    
    // MARK: - Support Section
    private var supportSection: some View {
        Section {
            NavigationLink(destination: HelpCenterView()) {
                SettingsRow(
                    icon: "questionmark.circle",
                    title: "Help Center",
                    subtitle: "Get help and find answers",
                    color: .blue
                )
            }
            
            Button(action: {
                contactSupport()
            }) {
                SettingsRow(
                    icon: "envelope.circle",
                    title: "Contact Support",
                    subtitle: "Get in touch with our team",
                    color: .green
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                showingAbout = true
            }) {
                SettingsRow(
                    icon: "info.circle",
                    title: "About",
                    subtitle: "App version and information",
                    color: .gray
                )
            }
            .buttonStyle(PlainButtonStyle())
        } header: {
            Text("Support")
        }
    }
    
    // MARK: - Helper Methods
    private func resetAllData() {
        // Reset all app data
        deviceController.resetAllData()
    }
    
    private func contactSupport() {
        // Open support contact
        if let url = URL(string: "mailto:support@roomscanningapp.com") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Settings Row
struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Account Settings View
struct AccountSettingsView: View {
    @State private var username = "John Doe"
    @State private var email = "john.doe@example.com"
    @State private var showingEditProfile = false
    
    var body: some View {
        List {
            Section {
                HStack {
                    // Profile image
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(username)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Edit") {
                        showingEditProfile = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.vertical, 8)
            }
            
            Section("Account Information") {
                InfoRow(label: "Username", value: username)
                InfoRow(label: "Email", value: email)
                InfoRow(label: "Member Since", value: "January 2024")
                InfoRow(label: "Account Type", value: "Free")
            }
            
            Section("Security") {
                NavigationLink("Change Password") {
                    ChangePasswordView()
                }
                
                NavigationLink("Two-Factor Authentication") {
                    TwoFactorAuthView()
                }
                
                NavigationLink("Login History") {
                    LoginHistoryView()
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(username: $username, email: $email)
        }
    }
}

// MARK: - Platform Settings View
struct PlatformSettingsView: View {
    @ObservedObject var deviceController: DeviceController
    @State private var showingAddPlatform = false
    
    var body: some View {
        List {
            Section {
                ForEach(deviceController.connectedPlatforms, id: \.self) { platform in
                    PlatformRow(platform: platform, deviceController: deviceController)
                }
                .onDelete(perform: deletePlatform)
                
                Button(action: {
                    showingAddPlatform = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.blue)
                        
                        Text("Add Platform")
                            .foregroundColor(.blue)
                    }
                }
            } header: {
                Text("Connected Platforms")
            }
        }
        .navigationTitle("Smart Home Platforms")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddPlatform) {
            AddPlatformView(deviceController: deviceController)
        }
    }
    
    private func deletePlatform(offsets: IndexSet) {
        // Handle platform deletion
    }
}

// MARK: - Platform Row
struct PlatformRow: View {
    let platform: SmartHomePlatform
    @ObservedObject var deviceController: DeviceController
    @State private var showingPlatformDetails = false
    
    var body: some View {
        HStack {
            // Platform icon
            Image(systemName: platform.iconName)
                .font(.title2)
                .foregroundColor(platform.color)
                .frame(width: 24)
            
            // Platform info
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text("\(deviceController.devicesForPlatform(platform).count) devices")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(deviceController.isPlatformConnected(platform) ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingPlatformDetails = true
        }
        .sheet(isPresented: $showingPlatformDetails) {
            PlatformDetailView(platform: platform, deviceController: deviceController)
        }
    }
}

// MARK: - Device Management View
struct DeviceManagementView: View {
    @ObservedObject var deviceController: DeviceController
    @State private var searchText = ""
    
    var filteredDevices: [SmartDevice] {
        if searchText.isEmpty {
            return deviceController.allDevices
        } else {
            return deviceController.allDevices.filter { device in
                device.name.localizedCaseInsensitiveContains(searchText) ||
                device.type.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredDevices, id: \.id) { device in
                DeviceRow(device: device, deviceController: deviceController)
            }
            .onDelete(perform: deleteDevice)
        }
        .navigationTitle("Device Management")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search devices")
    }
    
    private func deleteDevice(offsets: IndexSet) {
        // Handle device deletion
    }
}

// MARK: - Device Row
struct DeviceRow: View {
    let device: SmartDevice
    @ObservedObject var deviceController: DeviceController
    @State private var showingDeviceDetails = false
    
    var body: some View {
        HStack {
            // Device icon
            Image(systemName: device.type.iconName)
                .font(.title2)
                .foregroundColor(device.type.color)
                .frame(width: 24)
            
            // Device info
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(device.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(device.isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingDeviceDetails = true
        }
        .sheet(isPresented: $showingDeviceDetails) {
            DeviceDetailView(device: device, deviceController: deviceController)
        }
    }
}

// MARK: - Export Data View
struct ExportDataView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedDataTypes: Set<DataType> = [.roomScans, .deviceConfigurations]
    @State private var isExporting = false
    
    enum DataType: String, CaseIterable {
        case roomScans = "Room Scans"
        case deviceConfigurations = "Device Configurations"
        case settings = "App Settings"
        case usageData = "Usage Data"
        
        var icon: String {
            switch self {
            case .roomScans: return "camera"
            case .deviceConfigurations: return "lightbulb"
            case .settings: return "gear"
            case .usageData: return "chart.bar"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Export Data")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Select the data you want to export")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Data type selection
                VStack(alignment: .leading, spacing: 16) {
                    Text("Data Types")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    ForEach(DataType.allCases, id: \.self) { dataType in
                        DataTypeRow(
                            dataType: dataType,
                            isSelected: selectedDataTypes.contains(dataType)
                        ) {
                            if selectedDataTypes.contains(dataType) {
                                selectedDataTypes.remove(dataType)
                            } else {
                                selectedDataTypes.insert(dataType)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button("Export Selected Data") {
                        exportData()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedDataTypes.isEmpty || isExporting)
                    
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding()
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func exportData() {
        isExporting = true
        
        // Simulate export process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isExporting = false
            presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Data Type Row
struct DataTypeRow: View {
    let dataType: ExportDataView.DataType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: dataType.icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                Text(dataType.rawValue)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // App icon and name
                    VStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "house.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.blue)
                            )
                        
                        Text("RoomScanningApp")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Version 1.0.0")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // App description
                    VStack(spacing: 16) {
                        Text("About")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("RoomScanningApp helps you create detailed 3D models of your rooms and integrate them with your smart home devices for a seamless home automation experience.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Features
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Features")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(icon: "camera", text: "3D Room Scanning")
                            FeatureRow(icon: "lightbulb", text: "Smart Device Integration")
                            FeatureRow(icon: "gear", text: "Automation Setup")
                            FeatureRow(icon: "chart.bar", text: "Usage Analytics")
                        }
                    }
                    
                    // Links
                    VStack(spacing: 12) {
                        Link("Privacy Policy", destination: URL(string: "https://roomscanningapp.com/privacy")!)
                            .buttonStyle(SecondaryButtonStyle())
                        
                        Link("Terms of Service", destination: URL(string: "https://roomscanningapp.com/terms")!)
                            .buttonStyle(SecondaryButtonStyle())
                        
                        Link("Website", destination: URL(string: "https://roomscanningapp.com")!)
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
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

// MARK: - Placeholder Views
struct SubscriptionView: View {
    var body: some View {
        Text("Subscription View")
            .navigationTitle("Premium")
    }
}

struct AutomationSettingsView: View {
    var body: some View {
        Text("Automation Settings")
            .navigationTitle("Automations")
    }
}

struct ScanSettingsView: View {
    var body: some View {
        Text("Scan Settings")
            .navigationTitle("Scan Settings")
    }
}

struct DisplaySettingsView: View {
    var body: some View {
        Text("Display Settings")
            .navigationTitle("Display")
    }
}

struct NotificationSettingsView: View {
    var body: some View {
        Text("Notification Settings")
            .navigationTitle("Notifications")
    }
}

struct PrivacySettingsView: View {
    var body: some View {
        Text("Privacy Settings")
            .navigationTitle("Privacy & Security")
    }
}

struct HelpCenterView: View {
    var body: some View {
        Text("Help Center")
            .navigationTitle("Help Center")
    }
}

struct ChangePasswordView: View {
    var body: some View {
        Text("Change Password")
            .navigationTitle("Change Password")
    }
}

struct TwoFactorAuthView: View {
    var body: some View {
        Text("Two-Factor Authentication")
            .navigationTitle("2FA")
    }
}

struct LoginHistoryView: View {
    var body: some View {
        Text("Login History")
            .navigationTitle("Login History")
    }
}

struct EditProfileView: View {
    @Binding var username: String
    @Binding var email: String
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section("Profile Information") {
                    TextField("Username", text: $username)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

struct AddPlatformView: View {
    @ObservedObject var deviceController: DeviceController
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                ForEach(SmartHomePlatform.allCases, id: \.self) { platform in
                    PlatformRow(platform: platform, deviceController: deviceController)
                }
            }
            .navigationTitle("Add Platform")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

struct PlatformDetailView: View {
    let platform: SmartHomePlatform
    @ObservedObject var deviceController: DeviceController
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Platform Information")) {
                    InfoRow(label: "Name", value: platform.displayName)
                    InfoRow(label: "Status", value: deviceController.isPlatformConnected(platform) ? "Connected" : "Disconnected")
                    InfoRow(label: "Devices", value: "\(deviceController.devicesForPlatform(platform).count)")
                }
                
                Section(header: Text("Actions")) {
                    Button("Reconnect") {
                        // Handle reconnection
                    }
                    .foregroundColor(.blue)
                    
                    Button("Disconnect", role: .destructive) {
                        // Handle disconnection
                    }
                }
            }
            .navigationTitle(platform.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
} 