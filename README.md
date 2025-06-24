
# 🛠️ RoomScan App Comprehensive Refactor Instructions for AI Assistant

## 🧠 Project Context
You are assisting in a full-stack SwiftUI + ARKit app refactor for **RoomScan**, a home scanning and smart device placement/control app using Apple RoomPlan. The app supports:
- 3D room scanning
- Smart home device discovery and control
- 3D placement and visualization of devices
- Platform authentication (LIFX, Hue, etc.)

The codebase requires **modern SwiftUI architecture**, **proper state management**, and **persistent storage** for rooms/devices. You will be executing file-by-file refactors based on the table below.

---

## 📁 File-by-File Refactor Table

| File Name | Purpose | Issues | Refactor Instructions |
|-----------|---------|--------|------------------------|
| RoomScanningAppApp.swift | App entry point | Singleton use | Inject RoomStorage and DeviceController via `@EnvironmentObject`. Remove singletons. |
| ContentView.swift | Main tab view | Redundant view structs, no tab persistence | Delete wrapper structs. Use `@AppStorage("selectedTab")` for tab index. |
| HomeView.swift | Room browser | Rooms reset on relaunch | Bind by room ID, not struct. Persist rooms to disk. |
| RoomModel.swift | Room model & storage | No persistence, singleton used | Implement Codable + FileManager for room save/load. Replace singleton with `@EnvironmentObject`. |
| RoomCaptureScreen.swift | Scan onboarding | Does not start scan | Inject RoomCaptureCoordinator. Bind scanning state. |
| RoomCaptureView.swift | ARKit scan UI | Uses hardcoded shared storage | Terminate session on `onDisappear`. Use injected storage. Handle errors. |
| RoomDetailView.swift | Room detail tabs | No device refresh | Lookup rooms dynamically by ID. Add room edit/delete button. |
| RoomScanEditorView.swift | 3D visualization | Device changes not saved | Write changes to RoomStorage on update or exit. |
| DeviceDiscoveryView.swift | Finds devices | No save/feedback | Save discovered devices to RoomStorage. Show result toast. |
| DeviceController.swift | Controls devices | Monolithic, silent errors | Split by platform. Return Result or throw. Show UI feedback. |
| SmartHomePlatforms.swift | Protocol + platform base | No real auth implemented | Implement `PlatformAuthManager` in new platform files using OAuth/device APIs. |
| AddDeviceToRoomView.swift | Device assignment | Devices not saved | On submit, add to Room.devices and save with RoomStorage. |
| DevicePlacementView.swift | 3D placement | Placement not persisted | Save positions per device on move/exit. Add undo/redo. |
| DevicePopoverView.swift | Quick control UI | Doesn't save state | Reflect control changes in RoomStorage. Use DeviceController. |
| SettingsView.swift | App/platform settings | Most actions are placeholders | Implement all actions. Use alerts for confirmation. |
| RoomPlanCatalog.swift | 3D models | Hardcoded, uncached | Move model data to JSON. Cache SCNNode per model name. |
| Info.plist | Permissions | Missing keys | Add photo/tracking permission keys. Document and match UX onboarding. |

---

## 🔁 Global Refactor Tasks

- Replace all singletons with `@EnvironmentObject` and inject properly.
- Implement persistent RoomStorage and DeviceStorage using Codable + FileManager.
- Add undo/redo support where needed (placement).
- Use RoomPlan API per Apple Docs: https://developer.apple.com/documentation/roomplan
- Add alert, toast, or ProgressView feedback in every user flow.
- Make scanning, control, and placement flows fault-tolerant with error handling.
- Add in-app permission rationale dialogs for every plist key.

---

## ✅ Final Integration Checklist

- Ensure all user data persists reliably.
- Use live data binding (`@EnvironmentObject`, `@ObservedObject`) everywhere.
- Confirm RoomPlan sessions are terminated safely on exit.
- Make all destructive or irreversible actions confirmable.
- Ensure UI is responsive and provides clear feedback at all stages.

---

## 🚀 Execution

You may now:
- Apply these changes directly to the codebase.
- Create any needed helper files or view models.
- Return a list of updated files and any edge case corrections made.

