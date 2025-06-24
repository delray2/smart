//
//  RoomScanningAppApp.swift
//  RoomScanningApp
//
//  Created by Jake Delvoye on 6/20/25.
//

import SwiftUI
import RoomPlan
import RealityKit
import ARKit

@main
struct RoomScanningAppApp: App {
    @StateObject private var roomStorage = RoomStorage()
    @StateObject private var deviceController = DeviceController()
    
    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environmentObject(roomStorage)
                .environmentObject(deviceController)
        }
    }
}
